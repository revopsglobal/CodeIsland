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

    var isRunning: Bool {
        activity != nil
    }

    deinit {
        activityStateTask?.cancel()
    }

    init() {
        Task {
            await migrateLiveActivityLayoutIfNeeded()
            recoverExistingActivity()
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
            let existing = try Activity.request(attributes: attributes, content: content)
            activity = existing
            activityID = existing.id
            observeState(of: existing)
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
                guard state == .ended || state == .dismissed else { continue }
                self?.clearActivity(id: activity.id)
                break
            }
        }
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
