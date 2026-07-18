import ActivityKit
import Foundation

@MainActor
final class LiveActivityController: ObservableObject {
    private static let layoutVersionKey = "CodeIslandLiveActivityLayoutVersion"
    private static let currentLayoutVersion = "2026-07-17-private-lifecycle-v4"

    @Published private(set) var activityID: String?
    @Published private(set) var lastError: String?
    @Published private(set) var existingActivityCount = 0

    private var activity: Activity<CodeIslandActivityAttributes>?
    private var lastContentState: CodeIslandActivityAttributes.ContentState?
    private var lifecycleCursor: LiveActivityLifecycleCursor?
    private var activityStateTask: Task<Void, Never>?
    private var activityPushTokenTask: Task<Void, Never>?
    private var activityDiscoveryTask: Task<Void, Never>?
    private var pushToStartTokenTask: Task<Void, Never>?

    var isRunning: Bool {
        activity != nil
    }

    deinit {
        activityStateTask?.cancel()
        activityPushTokenTask?.cancel()
        activityDiscoveryTask?.cancel()
        pushToStartTokenTask?.cancel()
    }

    init() {
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
        guard let requestID = activity.attributes.sessionId, !requestID.isEmpty else { return }
        if let token = activity.pushToken {
            LiveActivityTokenMailbox.storeUpdateToken(token, requestID: requestID)
        }
        activityPushTokenTask = Task {
            for await token in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                LiveActivityTokenMailbox.storeUpdateToken(token, requestID: requestID)
            }
        }
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
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
        activityStateTask?.cancel()
        activityStateTask = nil
        activityPushTokenTask?.cancel()
        activityPushTokenTask = nil
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

    static func storeUpdateToken(_ token: Data, requestID: String) {
        var tokens = UserDefaults.standard.dictionary(forKey: updateTokensKey) as? [String: String] ?? [:]
        tokens[requestID] = token.hexString
        UserDefaults.standard.set(tokens, forKey: updateTokensKey)
        NotificationCenter.default.post(name: .codeIslandLiveActivityTokenAvailable, object: nil)
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
