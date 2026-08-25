import ActivityKit
import Foundation
import UserNotifications

@MainActor
final class LiveActivityController: ObservableObject {
    private static let layoutVersionKey = "CodeIslandLiveActivityLayoutVersion"
    private static let currentLayoutVersion = "2026-07-17-private-lifecycle-v4"
    private static let followedTaskKey = RemoteHostScopedArtifactStore.followedTaskIDKey

    @Published private(set) var activityID: String?
    @Published private(set) var lastError: String?
    @Published private(set) var existingActivityCount = 0
    @Published private(set) var followedTaskID: UUID?

    private var activity: Activity<CodeIslandActivityAttributes>?
    private var lastContentState: CodeIslandActivityAttributes.ContentState?
    private var lifecycleCursor: LiveActivityLifecycleCursor?
    private var activityStateTask: Task<Void, Never>?
    private var activityPushTokenTask: Task<Void, Never>?
    private var activityPushTokenPollingTask: Task<Void, Never>?
    private var activityDiscoveryTask: Task<Void, Never>?
    private var pushToStartTokenTask: Task<Void, Never>?
    private var hostLossNotified = false
    private var pairingIdentity: LiveActivityPairingIdentity
    private var pairingGeneration: UInt64 = 0

    var isRunning: Bool {
        activity != nil
    }

    deinit {
        activityStateTask?.cancel()
        activityPushTokenTask?.cancel()
        activityPushTokenPollingTask?.cancel()
        activityDiscoveryTask?.cancel()
        pushToStartTokenTask?.cancel()
    }

    init(pairingIdentity: LiveActivityPairingIdentity = .unpaired) {
        self.pairingIdentity = pairingIdentity
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-CodeIslandCompanionResetFollowedTask") {
            UserDefaults.standard.removeObject(forKey: Self.followedTaskKey)
        }
#endif
        followedTaskID = UserDefaults.standard.string(forKey: Self.followedTaskKey).flatMap(UUID.init(uuidString:))
        observeRemoteStartTokens()
        observeActivitiesStartedByPush()
        let initialScope = currentPairingScope
        Task {
            await migrateLiveActivityLayoutIfNeeded(scope: initialScope)
            guard self.isCurrent(initialScope) else { return }
            await recoverExistingActivity(endingDuplicates: false, scope: initialScope)
            guard self.isCurrent(initialScope) else { return }
            LiveActivityTokenMailbox.storeSnapshot(pairingIdentity: initialScope.identity)
        }
    }

    /// Completes the privacy boundary before the new pairing can register APNs
    /// routes. Cancellation and local state reset happen synchronously on the
    /// main actor; ActivityKit retirement is awaited by the caller.
    func pairingIdentityDidChange(to pairingIdentity: LiveActivityPairingIdentity) async {
        pairingGeneration &+= 1
        self.pairingIdentity = pairingIdentity
        let transitionScope = currentPairingScope
        cancelCurrentActivityObservers(includeDiscovery: true)
        followedTaskID = nil
        UserDefaults.standard.removeObject(forKey: Self.followedTaskKey)
        hostLossNotified = false
        LiveActivityTokenMailbox.clearHostScopedArtifacts()

        let activities = Activity<CodeIslandActivityAttributes>.activities
        for existing in activities {
            await existing.end(nil, dismissalPolicy: .immediate)
            guard isCurrent(transitionScope) else { return }
        }
        activity = nil
        activityID = nil
        lastContentState = nil
        lifecycleCursor = nil
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.filter(isInCurrentPairingScope).count
        observeActivitiesStartedByPush()
        await recoverExistingActivity(endingDuplicates: true, scope: transitionScope)
        guard isCurrent(transitionScope) else { return }
        LiveActivityTokenMailbox.storeSnapshot(pairingIdentity: pairingIdentity)
    }

    func updateFromNearbyIfRunning(with payload: CompanionStatePayload) {
        guard let scope = LocalTransportLiveActivityScope.capture(
            generation: pairingGeneration,
            identity: pairingIdentity
        ) else { return }
        updateIfRunning(with: payload, scope: scope)
    }

    private func updateIfRunning(
        with payload: CompanionStatePayload,
        scope: PairingIdentityGenerationScope
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard followedTaskID == nil else { return }

        Task {
            let shouldRecreate = await migrateLiveActivityLayoutIfNeeded(scope: scope)
            guard self.isCurrent(scope) else { return }
            await recoverExistingActivity(endingDuplicates: true, scope: scope)
            guard self.isCurrent(scope) else { return }
            guard activity != nil || shouldRecreate else { return }
            await apply(
                payload,
                createIfNeeded: shouldRecreate,
                allowIdleCreation: false,
                scope: scope
            )
        }
    }

    /// Remote attention should appear on the Lock Screen and Dynamic Island
    /// without requiring Buddy to already be open. Non-actionable snapshots
    /// only update or end an activity that is already running.
    func syncAttention(with payload: CompanionStatePayload) {
        let scope = currentPairingScope
        if Self.shouldAutoStart(for: payload.status) {
            startOrUpdate(with: payload, scope: scope)
        } else {
            updateIfRunning(with: payload, scope: scope)
        }
    }

    func isFollowing(taskID: UUID) -> Bool {
        followedTaskID == taskID
    }

    func follow(_ task: RemoteTaskSummary) {
        followedTaskID = task.id
        UserDefaults.standard.set(task.id.uuidString.lowercased(), forKey: Self.followedTaskKey)
        let scope = currentPairingScope
        Task { await applyTask(task, createIfNeeded: true, scope: scope) }
    }

    func unfollowTask() {
        followedTaskID = nil
        UserDefaults.standard.removeObject(forKey: Self.followedTaskKey)
        stopAll()
    }

    func syncRemoteTasks(_ tasks: [RemoteTaskSummary]) {
        guard let followedTaskID else { return }
        guard let task = tasks.first(where: { $0.id == followedTaskID }) else {
            unfollowTask()
            return
        }
        let scope = currentPairingScope
        Task {
            await applyTask(task, createIfNeeded: true, scope: scope)
            guard self.isCurrent(scope) else { return }
            if task.state.isTerminal {
                try? await Task.sleep(for: .seconds(8))
                guard self.isCurrent(scope), self.followedTaskID == task.id else { return }
                self.followedTaskID = nil
                UserDefaults.standard.removeObject(forKey: Self.followedTaskKey)
                self.stopAll()
            }
        }
    }

    func hostAvailabilityChanged(isAvailable: Bool) {
        if isAvailable {
            hostLossNotified = false
            return
        }
        guard followedTaskID != nil, !hostLossNotified else { return }
        hostLossNotified = true
        if var state = lastContentState, state.taskID != nil {
            state.status = "taskWaiting"
            state.taskState = RemoteTaskState.waitingForMac.rawValue
            state.message = "Waiting for your Mac to reconnect"
            state.updatedAt = Date()
            lastContentState = state
            let scope = currentPairingScope
            Task {
                guard self.isCurrent(scope) else { return }
                if let activity,
                   self.isInPairingScope(activity, identity: scope.identity) {
                    await activity.update(ActivityContent(
                        state: state,
                        staleDate: Date().addingTimeInterval(300),
                        relevanceScore: 1
                    ))
                }
            }
        }
        let content = UNMutableNotificationContent()
        content.title = "CodeIsland lost your Mac"
        content.body = "Open Buddy to reconnect the followed coding task."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "codeisland.followed-task.host-loss",
            content: content,
            trigger: nil
        )
        let notificationScope = currentPairingScope
        Task {
            guard self.isCurrent(notificationScope) else { return }
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static func shouldAutoStart(for status: CompanionStatus) -> Bool {
        status == .waitingApproval || status == .waitingQuestion
    }

    func startOrUpdateFromNearby(with payload: CompanionStatePayload) {
        guard let scope = LocalTransportLiveActivityScope.capture(
            generation: pairingGeneration,
            identity: pairingIdentity
        ) else { return }
        startOrUpdate(with: payload, scope: scope)
    }

    private func startOrUpdate(
        with payload: CompanionStatePayload,
        scope: PairingIdentityGenerationScope
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "This iPhone doesn't have Live Activities enabled."
            return
        }

        Task {
            await migrateLiveActivityLayoutIfNeeded(scope: scope)
            guard self.isCurrent(scope) else { return }
            await recoverExistingActivity(endingDuplicates: true, scope: scope)
            guard self.isCurrent(scope) else { return }
            if activity == nil {
                // An explicit user start is a fresh lifecycle even when the
                // latest synchronized payload has not changed.
                lifecycleCursor = nil
            }
            await apply(
                payload,
                createIfNeeded: true,
                allowIdleCreation: true,
                scope: scope
            )
        }
    }

    func stop() {
        followedTaskID = nil
        UserDefaults.standard.removeObject(forKey: Self.followedTaskKey)
        stopAll()
    }

    func stopAll() {
        let scope = currentPairingScope
        Task {
            for activity in Activity<CodeIslandActivityAttributes>.activities
                where self.isInPairingScope(activity, identity: scope.identity) {
                await activity.end(nil, dismissalPolicy: .immediate)
                guard self.isCurrent(scope) else { return }
            }
            guard self.isCurrent(scope) else { return }
            clearActivity(id: activityID, resetCursor: true)
            existingActivityCount = 0
            lastError = nil
        }
    }

    private func applyTask(
        _ task: RemoteTaskSummary,
        createIfNeeded: Bool,
        scope: PairingIdentityGenerationScope
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "This iPhone doesn't have Live Activities enabled."
            return
        }
        guard isCurrent(scope), scope.identity.canCreateOwnedActivity else { return }
        do {
            await recoverExistingActivity(endingDuplicates: true, scope: scope)
            guard isCurrent(scope) else { return }
            let taskID = task.id.uuidString.lowercased()
            if let activity, activity.attributes.sessionId != taskID {
                await activity.end(nil, dismissalPolicy: .immediate)
                guard isCurrent(scope) else { return }
                clearActivity(id: activity.id, resetCursor: true)
            }
            let contentState = CodeIslandActivityAttributes.ContentState(
                sequence: task.lastReceiptSequence,
                source: task.provider == .auto ? "codeisland" : task.provider.rawValue,
                status: Self.activityStatus(for: task.state),
                toolName: nil,
                workspaceName: task.workspaceName,
                message: Self.taskSummary(for: task.state),
                pendingAction: task.state == .needsYou ? RemoteAttentionKind.task.rawValue : nil,
                taskID: taskID,
                taskState: task.state.rawValue,
                questionText: nil,
                questionHeader: nil,
                questionProgress: nil,
                sessions: [],
                updatedAt: task.updatedAt
            )
            let content = ActivityContent(
                state: contentState,
                staleDate: Date().addingTimeInterval(180),
                relevanceScore: task.state == .needsYou || task.state == .failed ? 1 : 0.75
            )
            if let activity {
                await activity.update(content)
                guard isCurrent(scope) else { return }
            } else if createIfNeeded {
                guard isCurrent(scope) else { return }
                let attributes = CodeIslandActivityAttributes(
                    sessionId: taskID,
                    pairingDeviceID: scope.identity.pairingDeviceID
                )
                let created: Activity<CodeIslandActivityAttributes>
                do {
                    created = try Activity.request(attributes: attributes, content: content, pushType: .token)
                } catch {
                    created = try Activity.request(attributes: attributes, content: content, pushType: nil)
                }
                guard isCurrent(scope) else {
                    await created.end(nil, dismissalPolicy: .immediate)
                    return
                }
                activity = created
                activityID = created.id
                observeState(of: created)
                observePushToken(of: created)
            }
            lastContentState = contentState
            existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.filter {
                isInPairingScope($0, identity: scope.identity)
            }.count
            lastError = nil
        } catch {
            guard isCurrent(scope) else { return }
            lastError = error.localizedDescription
        }
    }

    private static func activityStatus(for state: RemoteTaskState) -> String {
        switch state {
        case .waitingForMac: return "taskWaiting"
        case .queued: return "processing"
        case .working: return "running"
        case .needsYou: return "waitingApproval"
        case .verified: return "taskVerified"
        case .failed: return "taskFailed"
        case .cancelled: return "idle"
        }
    }

    private static func taskSummary(for state: RemoteTaskState) -> String {
        switch state {
        case .waitingForMac: return "Waiting for your Mac to reconnect"
        case .queued: return "Queued on your Mac"
        case .working: return "Editing and running checks"
        case .needsYou: return "A decision is waiting in Buddy"
        case .verified: return "Reported checks passed"
        case .failed: return "Review the failure in Buddy"
        case .cancelled: return "Task cancelled"
        }
    }

    private func recoverExistingActivity(
        endingDuplicates: Bool,
        scope expectedScope: PairingIdentityGenerationScope? = nil
    ) async {
        let scope = expectedScope ?? currentPairingScope
        guard isCurrent(scope) else { return }
        let activities = Activity<CodeIslandActivityAttributes>.activities
        for existing in activities where !isInPairingScope(existing, identity: scope.identity) {
            await existing.end(nil, dismissalPolicy: .immediate)
            guard isCurrent(scope) else { return }
        }
        existingActivityCount = activities.filter {
            isInPairingScope($0, identity: scope.identity)
        }.count
        guard let existing = newestExistingActivity(identity: scope.identity) else {
            if activity != nil {
                clearActivity(id: activityID)
            }
            return
        }

        if activityID != existing.id {
            activity = existing
            activityID = existing.id
            lastContentState = existing.content.state
            lifecycleCursor = LiveActivityLifecycleCursor(
                sequence: existing.content.state.sequence,
                updatedAt: existing.content.state.updatedAt
            )
            observeState(of: existing)
            observePushToken(of: existing)
        }

        guard endingDuplicates else { return }
        for duplicate in Activity<CodeIslandActivityAttributes>.activities
            where isInPairingScope(duplicate, identity: scope.identity) && duplicate.id != existing.id {
            await duplicate.end(nil, dismissalPolicy: .immediate)
            guard isCurrent(scope) else { return }
        }
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.filter {
            isInPairingScope($0, identity: scope.identity)
        }.count
    }

    private func newestExistingActivity(
        identity: LiveActivityPairingIdentity
    ) -> Activity<CodeIslandActivityAttributes>? {
        Activity<CodeIslandActivityAttributes>.activities.filter {
            isInPairingScope($0, identity: identity)
        }.max {
            $0.content.state.updatedAt < $1.content.state.updatedAt
        }
    }

    private func isInCurrentPairingScope(
        _ activity: Activity<CodeIslandActivityAttributes>
    ) -> Bool {
        isInPairingScope(activity, identity: pairingIdentity)
    }

    private var currentPairingScope: PairingIdentityGenerationScope {
        PairingIdentityGenerationScope(
            generation: pairingGeneration,
            identity: pairingIdentity
        )
    }

    private func isCurrent(_ scope: PairingIdentityGenerationScope) -> Bool {
        scope.isCurrent(generation: pairingGeneration, identity: pairingIdentity)
    }

    private func isInPairingScope(
        _ activity: Activity<CodeIslandActivityAttributes>,
        identity: LiveActivityPairingIdentity
    ) -> Bool {
        LiveActivityPairingScope.accepts(
            activityPairingDeviceID: activity.attributes.pairingDeviceID,
            identity: identity
        )
    }

    @discardableResult
    private func migrateLiveActivityLayoutIfNeeded(
        scope expectedScope: PairingIdentityGenerationScope? = nil
    ) async -> Bool {
        let scope = expectedScope ?? currentPairingScope
        guard isCurrent(scope) else { return false }
        let storedVersion = UserDefaults.standard.string(forKey: Self.layoutVersionKey)
        guard storedVersion != Self.currentLayoutVersion else { return false }

        let existingActivities = Activity<CodeIslandActivityAttributes>.activities
        for activity in existingActivities {
            await activity.end(nil, dismissalPolicy: .immediate)
            guard isCurrent(scope) else { return false }
        }

        if !existingActivities.isEmpty {
            clearActivity(id: activityID, resetCursor: true)
        }
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
        UserDefaults.standard.set(Self.currentLayoutVersion, forKey: Self.layoutVersionKey)
        return !existingActivities.isEmpty
    }

    private func apply(
        _ payload: CompanionStatePayload,
        createIfNeeded: Bool,
        allowIdleCreation: Bool,
        scope: PairingIdentityGenerationScope
    ) async {
        guard isCurrent(scope), scope.identity.canCreateOwnedActivity else { return }
        do {
            let contentState = CodeIslandActivityAttributes.ContentState(payload: payload)
            let transition = LiveActivityLifecycle.transition(
                current: lifecycleCursor,
                incoming: LiveActivityLifecycleCursor(
                    sequence: payload.sequence,
                    updatedAt: payload.updatedAt
                ),
                hasActivity: activity != nil,
                hasActiveContent: Self.hasActiveContent(payload),
                createIfNeeded: createIfNeeded,
                allowIdleCreation: allowIdleCreation
            )
            lifecycleCursor = transition.cursor

            switch transition.decision {
            case .ignore:
                return
            case .end:
                for existing in Activity<CodeIslandActivityAttributes>.activities {
                    await existing.end(nil, dismissalPolicy: .immediate)
                    guard isCurrent(scope) else { return }
                }
                clearActivity(id: activityID)
                existingActivityCount = 0
                lastError = nil
                return
            case .create, .update:
                break
            }
            lastContentState = contentState

            if transition.decision == .update, let activity {
                await update(activity, with: contentState, status: payload.status)
                guard isCurrent(scope) else { return }
                lastError = nil
                return
            }

            guard transition.decision == .create else { return }
            let attributes = CodeIslandActivityAttributes(
                sessionId: payload.sessionId,
                pairingDeviceID: scope.identity.pairingDeviceID
            )
            let content = ActivityContent(
                state: contentState,
                staleDate: Date().addingTimeInterval(90),
                relevanceScore: relevanceScore(for: payload.status)
            )
            let existing: Activity<CodeIslandActivityAttributes>
            guard isCurrent(scope) else { return }
            do {
                existing = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: .token
                )
            } catch {
                // Unsigned simulator and locally installed builds can omit the
                // aps-environment entitlement. Preserve the local Lock Screen
                // experience in that case; signed TestFlight builds still take
                // the push-enabled path above and publish an update token.
                existing = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            }
            guard isCurrent(scope) else {
                await existing.end(nil, dismissalPolicy: .immediate)
                return
            }
            activity = existing
            activityID = existing.id
            observeState(of: existing)
            observePushToken(of: existing)
            lastError = nil
            existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.filter {
                isInPairingScope($0, identity: scope.identity)
            }.count
        } catch {
            guard isCurrent(scope) else { return }
            lastError = error.localizedDescription
            await recoverExistingActivity(endingDuplicates: false, scope: scope)
        }
    }

    private func update(
        _ activity: Activity<CodeIslandActivityAttributes>,
        with contentState: CodeIslandActivityAttributes.ContentState,
        status: CompanionStatus
    ) async {
        await activity.update(ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(90),
            relevanceScore: relevanceScore(for: status)
        ))
    }

    private func observeState(of activity: Activity<CodeIslandActivityAttributes>) {
        activityStateTask?.cancel()
        let scope = currentPairingScope
        activityStateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled, let self else { return }
                guard self.isCurrent(scope) else { return }
                guard self.isInPairingScope(activity, identity: scope.identity) else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    guard self.isCurrent(scope) else { return }
                    self.clearActivity(id: activity.id, resetCursor: true)
                    return
                }
                guard let receiptState = RemoteLiveActivityReceipt.ActivityState(state) else { continue }
                LiveActivityTokenMailbox.storeReceipt(
                    source: .activityStateChanged,
                    requestID: activity.attributes.sessionId,
                    kind: activity.content.state.pendingAction.flatMap(RemoteAttentionKind.init(rawValue:)),
                    attentionState: nil,
                    activityState: receiptState,
                    pairingIdentity: scope.identity
                )
                if state == .ended || state == .dismissed {
                    self.clearActivity(id: activity.id)
                    break
                }
            }
        }
    }

    private func observeRemoteStartTokens() {
        guard #available(iOS 17.2, *) else { return }
        pushToStartTokenTask = Task { [weak self] in
            if let token = Activity<CodeIslandActivityAttributes>.pushToStartToken {
                self?.publishPushToStartToken(token)
            }
            for await token in Activity<CodeIslandActivityAttributes>.pushToStartTokenUpdates {
                guard !Task.isCancelled else { return }
                self?.publishPushToStartToken(token)
            }
        }
    }

    private func observeActivitiesStartedByPush() {
        activityDiscoveryTask = Task { [weak self] in
            for await discovered in Activity<CodeIslandActivityAttributes>.activityUpdates {
                guard !Task.isCancelled, let self else { return }
                let scope = self.currentPairingScope
                guard self.isInPairingScope(discovered, identity: scope.identity) else {
                    await discovered.end(nil, dismissalPolicy: .immediate)
                    continue
                }
                await self.recoverExistingActivity(endingDuplicates: true, scope: scope)
                guard !Task.isCancelled,
                      self.isCurrent(scope),
                      self.isInPairingScope(discovered, identity: scope.identity),
                      let pairingDeviceID = LiveActivityPairingScope.normalized(
                        discovered.attributes.pairingDeviceID
                      ),
                      let requestID = discovered.attributes.sessionId,
                      let kind = RemoteAttentionKind(rawValue: discovered.content.state.pendingAction ?? "")
                else { continue }
                LiveActivityTokenMailbox.storeReceipt(
                    source: .activityStarted,
                    requestID: requestID,
                    kind: kind,
                    attentionState: .pending,
                    activityState: .active,
                    pairingIdentity: scope.identity
                )
                NotificationCenter.default.post(
                    name: .codeIslandRemoteAttentionChanged,
                    object: nil,
                    userInfo: [
                        "kind": kind.rawValue,
                        "state": RemoteAttentionState.pending.rawValue,
                        "requestId": requestID,
                        "pairingDeviceID": pairingDeviceID,
                    ]
                )
            }
        }
    }

    private func observePushToken(of activity: Activity<CodeIslandActivityAttributes>) {
        activityPushTokenTask?.cancel()
        activityPushTokenPollingTask?.cancel()
        guard isInCurrentPairingScope(activity),
              let requestID = activity.attributes.sessionId,
              !requestID.isEmpty
        else { return }

        let scope = currentPairingScope
        let capturedInitialToken = capturePushToken(of: activity, requestID: requestID)
        activityPushTokenTask = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                guard !Task.isCancelled, let self else { return }
                guard self.isCurrent(scope) else { return }
                guard self.isInPairingScope(activity, identity: scope.identity) else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    return
                }
                LiveActivityTokenMailbox.storeUpdateToken(token, requestID: requestID)
            }
        }

        // ActivityKit documents pushTokenUpdates as the primary source, but
        // remote push-to-start activities can expose pushToken slightly later
        // without yielding the first value promptly on some OS releases. Keep
        // the async listener above and add a bounded foreground/background-
        // runtime retry so the Mac can still remotely update and end the exact
        // activity. This task stops as soon as a token is available.
        guard !capturedInitialToken else { return }
        activityPushTokenPollingTask = Task { [weak self] in
            for _ in 0..<30 {
                guard !Task.isCancelled, let self else { return }
                guard self.isCurrent(scope) else { return }
                guard self.isInPairingScope(activity, identity: scope.identity) else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    return
                }
                if self.capturePushToken(of: activity, requestID: requestID) {
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    @discardableResult
    private func capturePushToken(
        of activity: Activity<CodeIslandActivityAttributes>,
        requestID: String
    ) -> Bool {
        guard isInCurrentPairingScope(activity), let token = activity.pushToken else { return false }
        LiveActivityTokenMailbox.storeUpdateToken(token, requestID: requestID)
        return true
    }

    @available(iOS 17.2, *)
    private func publishPushToStartToken(_ token: Data) {
        LiveActivityTokenMailbox.storePushToStartToken(token)
    }

    private func clearActivity(id: String?, resetCursor: Bool = false) {
        guard activityID == nil || activityID == id else { return }
        activity = nil
        activityID = nil
        lastContentState = nil
        if resetCursor { lifecycleCursor = nil }
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.filter(isInCurrentPairingScope).count
        activityStateTask?.cancel()
        activityStateTask = nil
        activityPushTokenTask?.cancel()
        activityPushTokenTask = nil
        activityPushTokenPollingTask?.cancel()
        activityPushTokenPollingTask = nil
    }

    private func cancelCurrentActivityObservers(includeDiscovery: Bool) {
        activityStateTask?.cancel()
        activityStateTask = nil
        activityPushTokenTask?.cancel()
        activityPushTokenTask = nil
        activityPushTokenPollingTask?.cancel()
        activityPushTokenPollingTask = nil
        if includeDiscovery {
            activityDiscoveryTask?.cancel()
            activityDiscoveryTask = nil
        }
    }

    private func relevanceScore(for status: CompanionStatus) -> Double {
        switch status {
        case .waitingApproval, .waitingQuestion:
            return 1
        case .processing, .running:
            return 0.7
        case .idle:
            return 0.25
        }
    }

    private static func hasActiveContent(_ payload: CompanionStatePayload) -> Bool {
        payload.status != .idle || payload.sessions.contains(where: { $0.status != .idle })
    }
}

enum LiveActivityTokenMailbox {
    static let pushToStartTokenKey = "codeisland.remote.liveActivity.pushToStartToken"
    static let updateTokensKey = RemoteHostScopedArtifactStore.liveActivityUpdateTokensKey
    static let receiptsKey = RemoteHostScopedArtifactStore.liveActivityReceiptsKey

    static func storePushToStartToken(_ token: Data) {
        UserDefaults.standard.set(token.hexString, forKey: pushToStartTokenKey)
        NotificationCenter.default.post(name: .codeIslandLiveActivityTokenAvailable, object: nil)
    }

    /// Re-queues ActivityKit routes after a pairing credential changes. The
    /// server stores routes on the paired device record, so a same-process
    /// re-pair must publish tokens even when ActivityKit has not emitted a new
    /// token update event.
    static func requeueCurrentTokens(
        includeHostScopedUpdateTokens: Bool,
        pairingIdentity: LiveActivityPairingIdentity
    ) {
        if #available(iOS 17.2, *),
           let token = Activity<CodeIslandActivityAttributes>.pushToStartToken {
            storePushToStartToken(token)
        }
        guard includeHostScopedUpdateTokens else { return }
        for activity in Activity<CodeIslandActivityAttributes>.activities {
            guard LiveActivityPairingScope.accepts(
                    activityPairingDeviceID: activity.attributes.pairingDeviceID,
                    identity: pairingIdentity
                  ),
                  let requestID = activity.attributes.sessionId,
                  !requestID.isEmpty,
                  let token = activity.pushToken
            else { continue }
            storeUpdateToken(token, requestID: requestID)
        }
    }

    static func clearHostScopedArtifacts(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: updateTokensKey)
        defaults.removeObject(forKey: receiptsKey)
    }

    @discardableResult
    static func storeUpdateToken(_ token: Data, requestID: String) -> Bool {
        var tokens = UserDefaults.standard.dictionary(forKey: updateTokensKey) as? [String: String] ?? [:]
        let value = token.hexString
        guard tokens[requestID] != value else { return false }
        tokens[requestID] = value
        UserDefaults.standard.set(tokens, forKey: updateTokensKey)
        NotificationCenter.default.post(name: .codeIslandLiveActivityTokenAvailable, object: nil)
        return true
    }

    static func storeSnapshot(
        pairingIdentity: LiveActivityPairingIdentity = .unpaired
    ) {
        storeReceipt(
            source: .snapshot,
            requestID: nil,
            kind: nil,
            attentionState: nil,
            activityState: nil,
            pairingIdentity: pairingIdentity
        )
    }

    @discardableResult
    static func storeReceipt(
        source: RemoteLiveActivityReceipt.Source,
        requestID: String?,
        kind: RemoteAttentionKind?,
        attentionState: RemoteAttentionState?,
        activityState: RemoteLiveActivityReceipt.ActivityState?,
        pairingIdentity: LiveActivityPairingIdentity = .unpaired,
        postNotification: Bool = true
    ) -> Bool {
        guard let receipt = makeReceipt(
            source: source,
            requestID: requestID,
            kind: kind,
            attentionState: attentionState,
            activityState: activityState,
            pairingIdentity: pairingIdentity
        ) else { return false }
        return storePreparedReceipt(receipt, postNotification: postNotification)
    }

    /// ActivityKit enumeration can involve framework synchronization and must
    /// stay outside the pairing ownership lock. AppDelegate revalidates the
    /// same identity inside its final write transaction before storing this.
    static func makeReceipt(
        source: RemoteLiveActivityReceipt.Source,
        requestID: String?,
        kind: RemoteAttentionKind?,
        attentionState: RemoteAttentionState?,
        activityState: RemoteLiveActivityReceipt.ActivityState?,
        pairingIdentity: LiveActivityPairingIdentity
    ) -> RemoteLiveActivityReceipt? {
        guard pairingIdentity != .credentialPresentButIdentityMissing else { return nil }
        let activities = Activity<CodeIslandActivityAttributes>.activities.filter {
            LiveActivityPairingScope.accepts(
                activityPairingDeviceID: $0.attributes.pairingDeviceID,
                identity: pairingIdentity
            )
        }
        let activeRequestIDs = Array(Set(activities.compactMap(\.attributes.sessionId))).sorted()
        let receipt = RemoteLiveActivityReceipt(
            source: source,
            requestId: requestID,
            kind: kind,
            state: attentionState,
            activityState: activityState,
            activitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled,
            activeActivityCount: activities.count,
            activeRequestIds: activeRequestIDs
        )
        return receipt.isStructurallyValid ? receipt : nil
    }

    /// Low-level UserDefaults write used inside the serialized pairing
    /// transaction. Notification delivery remains explicitly outside it.
    @discardableResult
    static func storePreparedReceipt(
        _ receipt: RemoteLiveActivityReceipt,
        postNotification: Bool = true
    ) -> Bool {
        var receipts = pendingReceipts()
        guard !receipts.contains(where: { $0.eventId == receipt.eventId }) else { return false }
        receipts.append(receipt)
        if receipts.count > 32 {
            receipts = Array(receipts.suffix(32))
        }
        guard let data = try? JSONEncoder().encode(receipts) else { return false }
        UserDefaults.standard.set(data, forKey: receiptsKey)
        if postNotification {
            NotificationCenter.default.post(name: .codeIslandLiveActivityReceiptAvailable, object: nil)
        }
        return true
    }

    static func pendingReceipts() -> [RemoteLiveActivityReceipt] {
        guard let data = UserDefaults.standard.data(forKey: receiptsKey),
              let receipts = try? JSONDecoder().decode([RemoteLiveActivityReceipt].self, from: data)
        else { return [] }
        return receipts
    }

    static func clearReceipts(eventIDs: Set<String>) {
        guard !eventIDs.isEmpty else { return }
        let remaining = pendingReceipts().filter { !eventIDs.contains($0.eventId) }
        if remaining.isEmpty {
            UserDefaults.standard.removeObject(forKey: receiptsKey)
        } else if let data = try? JSONEncoder().encode(remaining) {
            UserDefaults.standard.set(data, forKey: receiptsKey)
        }
    }
}

private extension RemoteLiveActivityReceipt.ActivityState {
    init?(_ state: ActivityState) {
        switch state {
        case .pending: self = .pending
        case .active: self = .active
        case .stale: self = .stale
        case .ended: self = .ended
        case .dismissed: self = .dismissed
        @unknown default: return nil
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
