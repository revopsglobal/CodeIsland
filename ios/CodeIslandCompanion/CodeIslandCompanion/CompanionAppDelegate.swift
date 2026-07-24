import UIKit
import UserNotifications

final class CompanionAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let pendingPushTokenKey = "codeisland.remote.pendingPushToken"
    private static let pendingApprovalIDKey = "codeisland.remote.pendingApprovalID"
    private static let pendingQuestionIDKey = "codeisland.remote.pendingQuestionID"
    private static let pushHistoryKey = "codeisland.remote.pushHistory.v1"
    private static let taskStateHistoryKey = "codeisland.remote.taskPushState.v1"

    internal enum PushProcessingOutcome {
        case accepted
        case rejectedStale
        case unrecognized
    }

    internal static func presentationOptions(for outcome: PushProcessingOutcome) -> UNNotificationPresentationOptions {
        switch outcome {
        case .accepted, .unrecognized:
            return [.banner, .list, .sound]
        case .rejectedStale:
            return []
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Do not surprise the user with a permission sheet at app launch.
        // Existing authorized installs still register immediately; Task 14's
        // explicit Attention opt-in owns the first permission request.
        center.getNotificationSettings { settings in
            guard [.authorized, .provisional, .ephemeral]
                .contains(settings.authorizationStatus)
            else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        if let notification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            _ = process(notification)
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.pendingPushTokenKey)
        NotificationCenter.default.post(name: .codeIslandPushTokenAvailable, object: nil)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Remote approval polling remains fully functional without APNs.
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let outcome = process(notification.request.content.userInfo)
        completionHandler(Self.presentationOptions(for: outcome))
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        switch process(userInfo) {
        case .accepted:
            completionHandler(.newData)
        case .rejectedStale, .unrecognized:
            completionHandler(.noData)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        _ = process(response.notification.request.content.userInfo)
        completionHandler()
    }

    @discardableResult
    private func process(_ userInfo: [AnyHashable: Any]) -> PushProcessingOutcome {
        let fields = Dictionary(uniqueKeysWithValues: userInfo.compactMap { key, value in
            (key as? String).map { ($0, value) }
        })

        guard let envelope = RemoteAttentionPushEnvelope(payloadFields: fields) else {
            // Backward compatibility with the first internal Buddy build.
            guard let approvalID = fields["approvalId"] as? String, !approvalID.isEmpty else { return .unrecognized }
            UserDefaults.standard.set(approvalID, forKey: Self.pendingApprovalIDKey)
            LiveActivityTokenMailbox.storeReceipt(
                source: .notification,
                requestID: approvalID,
                kind: .approval,
                attentionState: .pending,
                activityState: nil
            )
            postAttention(kind: .approval, state: .pending, requestID: approvalID)
            return .accepted
        }

        var history = UserDefaults.standard.dictionary(forKey: Self.pushHistoryKey) as? [String: Double] ?? [:]
        let previous = history[envelope.requestKey].map(Date.init(timeIntervalSince1970:))
        guard envelope.isFresh(lastIssuedAt: previous) else { return .rejectedStale }
        if envelope.kind == .task, let incomingState = envelope.taskState {
            var taskStates = UserDefaults.standard.dictionary(forKey: Self.taskStateHistoryKey) as? [String: String] ?? [:]
            let previousState = taskStates[envelope.requestID].flatMap(RemoteTaskState.init(rawValue:))
            guard RemoteTaskAttentionPolicy.accepts(previousState: previousState, incomingState: incomingState) else {
                return .rejectedStale
            }
            taskStates[envelope.requestID] = incomingState.rawValue
            if taskStates.count > 64 {
                taskStates = Dictionary(uniqueKeysWithValues: taskStates.prefix(64).map { ($0.key, $0.value) })
            }
            UserDefaults.standard.set(taskStates, forKey: Self.taskStateHistoryKey)
        }
        history[envelope.requestKey] = envelope.issuedAt.timeIntervalSince1970
        if history.count > 64 {
            history = Dictionary(uniqueKeysWithValues: history
                .sorted { $0.value > $1.value }
                .prefix(64)
                .map { ($0.key, $0.value) })
        }
        UserDefaults.standard.set(history, forKey: Self.pushHistoryKey)

        switch (envelope.kind, envelope.state) {
        case (.approval, .pending):
            UserDefaults.standard.set(envelope.requestID, forKey: Self.pendingApprovalIDKey)
        case (.question, .pending):
            UserDefaults.standard.set(envelope.requestID, forKey: Self.pendingQuestionIDKey)
        case (.approval, _):
            if UserDefaults.standard.string(forKey: Self.pendingApprovalIDKey) == envelope.requestID {
                UserDefaults.standard.removeObject(forKey: Self.pendingApprovalIDKey)
            }
        case (.question, _):
            if UserDefaults.standard.string(forKey: Self.pendingQuestionIDKey) == envelope.requestID {
                UserDefaults.standard.removeObject(forKey: Self.pendingQuestionIDKey)
            }
        case (.task, _):
            break
        }

        LiveActivityTokenMailbox.storeReceipt(
            source: .notification,
            requestID: envelope.requestID,
            kind: envelope.kind,
            attentionState: envelope.state,
            activityState: nil
        )
        postAttention(
            kind: envelope.kind,
            state: envelope.state,
            requestID: envelope.requestID,
            taskState: envelope.taskState
        )
        return .accepted
    }

    private func postAttention(
        kind: RemoteAttentionKind,
        state: RemoteAttentionState,
        requestID: String,
        taskState: RemoteTaskState? = nil
    ) {
        var userInfo = [
            "kind": kind.rawValue,
            "state": state.rawValue,
            "requestId": requestID,
        ]
        if let taskState { userInfo["taskState"] = taskState.rawValue }
        NotificationCenter.default.post(
            name: .codeIslandRemoteAttentionChanged,
            object: nil,
            userInfo: userInfo
        )
    }
}
