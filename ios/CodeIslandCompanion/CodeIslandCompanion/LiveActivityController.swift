import ActivityKit
import Foundation
import UserNotifications

enum AgentOpsFollowedTaskState: Equatable {
    case queued
    case working
    case needsYou
    case verified
    case failed
    case cancelled
}

@MainActor
final class LiveActivityController: ObservableObject {
    private static let layoutVersionKey = "CodeIslandLiveActivityLayoutVersion"
    private static let currentLayoutVersion = "2026-07-17-private-lifecycle-v4"
    private static let followedTaskKey = "codeisland.liveActivity.followedTask.v1"

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

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-CodeIslandCompanionResetFollowedTask") {
            UserDefaults.standard.removeObject(forKey: Self.followedTaskKey)
        }
#endif
        followedTaskID = UserDefaults.standard.string(forKey: Self.followedTaskKey).flatMap(UUID.init(uuidString:))
        observeRemoteStartTokens()
        observeActivitiesStartedByPush()
        Task {
            await migrateLiveActivityLayoutIfNeeded()
            recoverExistingActivity()
            LiveActivityTokenMailbox.storeSnapshot()
        }
    }

    func updateIfRunning(with payload: CompanionStatePayload) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard followedTaskID == nil else { return }

        Task {
            let shouldRecreate = await migrateLiveActivityLayoutIfNeeded()
            await recoverExistingActivity(endingDuplicates: true)
            guard activity != nil || shouldRecreate else { return }
            await apply(payload, createIfNeeded: shouldRecreate, allowIdleCreation: false)
        }
    }

    /// Remote attention should appear on the Lock Screen and Dynamic Island
    /// without requiring Buddy to already be open. Non-actionable snapshots
    /// only update or end an activity that is already running.
    func syncAttention(with payload: CompanionStatePayload) {
        if Self.shouldAutoStart(for: payload.status) {
            startOrUpdate(with: payload)
        } else {
            updateIfRunning(with: payload)
        }
    }

    func isFollowing(taskID: UUID) -> Bool {
        followedTaskID == taskID
    }

    func follow(_ task: RemoteTaskSummary) {
        followedTaskID = task.id
        UserDefaults.standard.set(task.id.uuidString.lowercased(), forKey: Self.followedTaskKey)
        Task { await applyTask(task, createIfNeeded: true) }
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
        Task {
            await applyTask(task, createIfNeeded: true)
            if task.state.isTerminal {
                try? await Task.sleep(for: .seconds(8))
                guard self.followedTaskID == task.id else { return }
                self.followedTaskID = nil
                UserDefaults.standard.removeObject(forKey: Self.followedTaskKey)
                self.stopAll()
            }
        }
    }

    func followAgentOps(_ task: AgentOpsWorkSummary) {
        followedTaskID = task.id
        UserDefaults.standard.set(
            task.id.uuidString.lowercased(),
            forKey: Self.followedTaskKey
        )
        Task { await applyAgentOpsTask(task, createIfNeeded: true) }
    }

    func syncAgentOpsWork(_ tasks: [AgentOpsWorkSummary]) {
        guard let followedTaskID else { return }
        guard let task = tasks.first(where: { $0.id == followedTaskID }) else {
            return
        }
        Task {
            await applyAgentOpsTask(task, createIfNeeded: true)
            let state = Self.agentOpsState(for: task)
            if Self.shouldEndAgentOpsActivity(
                followedTaskID: followedTaskID,
                eventTaskID: task.id,
                state: state
            ) {
                try? await Task.sleep(for: .seconds(8))
                guard self.followedTaskID == task.id else { return }
                await self.endAgentOpsActivity(taskID: task.id)
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
            Task {
                if let activity {
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
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    static func shouldAutoStart(for status: CompanionStatus) -> Bool {
        status == .waitingApproval || status == .waitingQuestion
    }

    func startOrUpdate(with payload: CompanionStatePayload) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "This iPhone doesn't have Live Activities enabled."
            return
        }

        Task {
            await migrateLiveActivityLayoutIfNeeded()
            await recoverExistingActivity(endingDuplicates: true)
            if activity == nil {
                // An explicit user start is a fresh lifecycle even when the
                // latest synchronized payload has not changed.
                lifecycleCursor = nil
            }
            await apply(payload, createIfNeeded: true, allowIdleCreation: true)
        }
    }

    func stop() {
        followedTaskID = nil
        UserDefaults.standard.removeObject(forKey: Self.followedTaskKey)
        stopAll()
    }

    func stopAll() {
        Task {
            for activity in Activity<CodeIslandActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            clearActivity(id: activityID, resetCursor: true)
            existingActivityCount = 0
            lastError = nil
        }
    }

    private func applyTask(_ task: RemoteTaskSummary, createIfNeeded: Bool) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "This iPhone doesn't have Live Activities enabled."
            return
        }
        do {
            await recoverExistingActivity(endingDuplicates: true)
            let taskID = task.id.uuidString.lowercased()
            if let activity, activity.attributes.sessionId != taskID {
                await activity.end(nil, dismissalPolicy: .immediate)
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
            } else if createIfNeeded {
                let attributes = CodeIslandActivityAttributes(sessionId: taskID)
                let created: Activity<CodeIslandActivityAttributes>
                do {
                    created = try Activity.request(attributes: attributes, content: content, pushType: .token)
                } catch {
                    created = try Activity.request(attributes: attributes, content: content, pushType: nil)
                }
                activity = created
                activityID = created.id
                observeState(of: created)
                observePushToken(of: created)
            }
            lastContentState = contentState
            existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    static func agentOpsState(
        for task: AgentOpsWorkSummary
    ) -> AgentOpsFollowedTaskState {
        let lifecycle = task.lifecycle.status.lowercased()
        if lifecycle == "verified" {
            return task.proof.state.lowercased() == "verified"
                ? .verified
                : .working
        }
        switch lifecycle {
        case "queued", "pending", "created":
            return .queued
        case "blocked", "needs_person", "needs_approval":
            return .needsYou
        case "failed":
            return .failed
        case "cancelled", "canceled":
            return .cancelled
        default:
            return .working
        }
    }

    static func shouldEndAgentOpsActivity(
        followedTaskID: UUID?,
        eventTaskID: UUID,
        state: AgentOpsFollowedTaskState
    ) -> Bool {
        guard followedTaskID == eventTaskID else { return false }
        return state == .verified
            || state == .failed
            || state == .cancelled
    }

    private func applyAgentOpsTask(
        _ task: AgentOpsWorkSummary,
        createIfNeeded: Bool
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "This iPhone doesn't have Live Activities enabled."
            return
        }
        let state = Self.agentOpsState(for: task)
        do {
            await recoverExistingActivity(endingDuplicates: true)
            let taskID = task.id.uuidString.lowercased()
            if let activity, activity.attributes.sessionId != taskID {
                await activity.end(nil, dismissalPolicy: .immediate)
                clearActivity(id: activity.id, resetCursor: true)
            }
            let contentState = CodeIslandActivityAttributes.ContentState(
                sequence: UInt64(
                    max(0, task.lifecycle.updatedAt.timeIntervalSince1970)
                ),
                source: "agentops",
                status: Self.activityStatus(for: state),
                toolName: nil,
                workspaceName: nil,
                message: Self.taskSummary(for: state),
                pendingAction: state == .needsYou ? RemoteAttentionKind.task.rawValue : nil,
                taskID: taskID,
                taskState: task.lifecycle.status,
                questionText: nil,
                questionHeader: nil,
                questionProgress: nil,
                sessions: [],
                updatedAt: task.lifecycle.updatedAt
            )
            let content = ActivityContent(
                state: contentState,
                staleDate: Date().addingTimeInterval(180),
                relevanceScore: state == .needsYou || state == .failed ? 1 : 0.75
            )
            if let activity {
                await activity.update(content)
            } else if createIfNeeded {
                let attributes = CodeIslandActivityAttributes(sessionId: taskID)
                let created: Activity<CodeIslandActivityAttributes>
                do {
                    created = try Activity.request(
                        attributes: attributes,
                        content: content,
                        pushType: .token
                    )
                } catch {
                    created = try Activity.request(
                        attributes: attributes,
                        content: content,
                        pushType: nil
                    )
                }
                activity = created
                activityID = created.id
                observeState(of: created)
                observePushToken(of: created)
            }
            lastContentState = contentState
            existingActivityCount =
                Activity<CodeIslandActivityAttributes>.activities.count
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func activityStatus(
        for state: AgentOpsFollowedTaskState
    ) -> String {
        switch state {
        case .queued: return "processing"
        case .working: return "running"
        case .needsYou: return "waitingApproval"
        case .verified: return "taskVerified"
        case .failed: return "taskFailed"
        case .cancelled: return "idle"
        }
    }

    private static func taskSummary(
        for state: AgentOpsFollowedTaskState
    ) -> String {
        switch state {
        case .queued: return "Queued in AgentOps"
        case .working: return "Working; verified proof is still pending"
        case .needsYou: return "A decision is waiting in Buddy"
        case .verified: return "AgentOps verified the proof"
        case .failed: return "Review the failure in AgentOps"
        case .cancelled: return "Task cancelled"
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

    private func recoverExistingActivity() {
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
        guard activity == nil, let existing = newestExistingActivity() else { return }
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

    private func recoverExistingActivity(endingDuplicates: Bool) async {
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
        guard let existing = newestExistingActivity() else {
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
        for duplicate in Activity<CodeIslandActivityAttributes>.activities where duplicate.id != existing.id {
            await duplicate.end(nil, dismissalPolicy: .immediate)
        }
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
    }

    private func newestExistingActivity() -> Activity<CodeIslandActivityAttributes>? {
        Activity<CodeIslandActivityAttributes>.activities.max {
            $0.content.state.updatedAt < $1.content.state.updatedAt
        }
    }

    @discardableResult
    private func migrateLiveActivityLayoutIfNeeded() async -> Bool {
        let storedVersion = UserDefaults.standard.string(forKey: Self.layoutVersionKey)
        guard storedVersion != Self.currentLayoutVersion else { return false }

        let existingActivities = Activity<CodeIslandActivityAttributes>.activities
        for activity in existingActivities {
            await activity.end(nil, dismissalPolicy: .immediate)
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
        allowIdleCreation: Bool
    ) async {
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
                lastError = nil
                return
            }

            guard transition.decision == .create else { return }
            let attributes = CodeIslandActivityAttributes(sessionId: payload.sessionId)
            let content = ActivityContent(
                state: contentState,
                staleDate: Date().addingTimeInterval(90),
                relevanceScore: relevanceScore(for: payload.status)
            )
            let existing: Activity<CodeIslandActivityAttributes>
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
            activity = existing
            activityID = existing.id
            observeState(of: existing)
            observePushToken(of: existing)
            lastError = nil
            existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
        } catch {
            lastError = error.localizedDescription
            recoverExistingActivity()
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
        activityStateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard let receiptState = RemoteLiveActivityReceipt.ActivityState(state) else { continue }
                LiveActivityTokenMailbox.storeReceipt(
                    source: .activityStateChanged,
                    requestID: activity.attributes.sessionId,
                    kind: activity.content.state.pendingAction.flatMap(RemoteAttentionKind.init(rawValue:)),
                    attentionState: nil,
                    activityState: receiptState
                )
                if state == .ended || state == .dismissed {
                    self?.clearActivity(id: activity.id)
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
                await self.recoverExistingActivity(endingDuplicates: true)
                if discovered.content.state.source == "agentops",
                   let taskText = discovered.attributes.sessionId,
                   let taskID = UUID(uuidString: taskText)
                {
                    self.followedTaskID = taskID
                    UserDefaults.standard.set(
                        taskID.uuidString.lowercased(),
                        forKey: Self.followedTaskKey
                    )
                }
                guard let requestID = discovered.attributes.sessionId,
                      let kind = RemoteAttentionKind(rawValue: discovered.content.state.pendingAction ?? "")
                else { continue }
                LiveActivityTokenMailbox.storeReceipt(
                    source: .activityStarted,
                    requestID: requestID,
                    kind: kind,
                    attentionState: .pending,
                    activityState: .active
                )
                NotificationCenter.default.post(
                    name: .codeIslandRemoteAttentionChanged,
                    object: nil,
                    userInfo: [
                        "kind": kind.rawValue,
                        "state": RemoteAttentionState.pending.rawValue,
                        "requestId": requestID,
                    ]
                )
            }
        }
    }

    private func observePushToken(of activity: Activity<CodeIslandActivityAttributes>) {
        activityPushTokenTask?.cancel()
        activityPushTokenPollingTask?.cancel()
        guard let requestID = activity.attributes.sessionId, !requestID.isEmpty else { return }

        let capturedInitialToken = capturePushToken(of: activity, requestID: requestID)
        activityPushTokenTask = Task {
            for await token in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                LiveActivityTokenMailbox.storeUpdateToken(token, requestID: requestID)
                if let taskID = UUID(uuidString: requestID) {
                    AgentOpsPushTokenStore.shared.storeLiveActivityToken(
                        token,
                        taskID: taskID
                    )
                }
            }
        }

        // ActivityKit documents pushTokenUpdates as the primary source, but
        // remote push-to-start activities can expose pushToken slightly later
        // without yielding the first value promptly on some OS releases. Keep
        // the async listener above and add a bounded foreground/background-
        // runtime retry so the Mac can still remotely update and end the exact
        // activity. This task stops as soon as a token is available.
        guard !capturedInitialToken else { return }
        activityPushTokenPollingTask = Task {
            for _ in 0..<30 {
                guard !Task.isCancelled else { return }
                if capturePushToken(of: activity, requestID: requestID) {
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
        guard let token = activity.pushToken else { return false }
        LiveActivityTokenMailbox.storeUpdateToken(token, requestID: requestID)
        if let taskID = UUID(uuidString: requestID) {
            AgentOpsPushTokenStore.shared.storeLiveActivityToken(
                token,
                taskID: taskID
            )
        }
        return true
    }

    @available(iOS 17.2, *)
    private func publishPushToStartToken(_ token: Data) {
        LiveActivityTokenMailbox.storePushToStartToken(token)
        AgentOpsPushTokenStore.shared.storePushToStartToken(token)
    }

    private func endAgentOpsActivity(taskID: UUID) async {
        let taskKey = taskID.uuidString.lowercased()
        for candidate in Activity<CodeIslandActivityAttributes>.activities
        where candidate.attributes.sessionId?.lowercased() == taskKey {
            await candidate.end(nil, dismissalPolicy: .immediate)
            if candidate.id == activityID {
                clearActivity(id: candidate.id, resetCursor: true)
            }
        }
        AgentOpsPushTokenStore.shared.removeLiveActivityToken(taskID: taskID)
        guard followedTaskID == taskID else { return }
        followedTaskID = nil
        UserDefaults.standard.removeObject(forKey: Self.followedTaskKey)
        existingActivityCount =
            Activity<CodeIslandActivityAttributes>.activities.count
    }

    private func clearActivity(id: String?, resetCursor: Bool = false) {
        guard activityID == nil || activityID == id else { return }
        activity = nil
        activityID = nil
        lastContentState = nil
        if resetCursor { lifecycleCursor = nil }
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
        activityStateTask?.cancel()
        activityStateTask = nil
        activityPushTokenTask?.cancel()
        activityPushTokenTask = nil
        activityPushTokenPollingTask?.cancel()
        activityPushTokenPollingTask = nil
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
    static let updateTokensKey = "codeisland.remote.liveActivity.updateTokens"
    static let receiptsKey = "codeisland.remote.liveActivity.receipts.v1"

    static func storePushToStartToken(_ token: Data) {
        UserDefaults.standard.set(token.hexString, forKey: pushToStartTokenKey)
        NotificationCenter.default.post(name: .codeIslandLiveActivityTokenAvailable, object: nil)
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

    static func storeSnapshot() {
        storeReceipt(
            source: .snapshot,
            requestID: nil,
            kind: nil,
            attentionState: nil,
            activityState: nil
        )
    }

    static func storeReceipt(
        source: RemoteLiveActivityReceipt.Source,
        requestID: String?,
        kind: RemoteAttentionKind?,
        attentionState: RemoteAttentionState?,
        activityState: RemoteLiveActivityReceipt.ActivityState?
    ) {
        let activities = Activity<CodeIslandActivityAttributes>.activities
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
        guard receipt.isStructurallyValid else { return }

        var receipts = pendingReceipts()
        guard !receipts.contains(where: { $0.eventId == receipt.eventId }) else { return }
        receipts.append(receipt)
        if receipts.count > 32 {
            receipts = Array(receipts.suffix(32))
        }
        guard let data = try? JSONEncoder().encode(receipts) else { return }
        UserDefaults.standard.set(data, forKey: receiptsKey)
        NotificationCenter.default.post(name: .codeIslandLiveActivityReceiptAvailable, object: nil)
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
