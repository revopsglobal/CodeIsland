import UIKit
import UserNotifications

final class CompanionAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let pendingPushTokenKey = "codeisland.remote.pendingPushToken"
    private static let pendingApprovalIDKey = "codeisland.remote.pendingApprovalID"
    private static let pendingQuestionIDKey = "codeisland.remote.pendingQuestionID"
    private static let pushHistoryKey = "codeisland.remote.pushHistory.v1"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
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
        _ = process(notification.request.content.userInfo)
        completionHandler([.banner, .list, .sound])
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(process(userInfo) ? .newData : .noData)
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
    private func process(_ userInfo: [AnyHashable: Any]) -> Bool {
        let fields = Dictionary(uniqueKeysWithValues: userInfo.compactMap { key, value in
            (key as? String).map { ($0, value) }
        })

        guard let envelope = RemoteAttentionPushEnvelope(payloadFields: fields) else {
            // Backward compatibility with the first internal Buddy build.
            guard let approvalID = fields["approvalId"] as? String, !approvalID.isEmpty else { return false }
            UserDefaults.standard.set(approvalID, forKey: Self.pendingApprovalIDKey)
            LiveActivityTokenMailbox.storeReceipt(
                source: .notification,
                requestID: approvalID,
                kind: .approval,
                attentionState: .pending,
                activityState: nil
            )
            postAttention(kind: .approval, state: .pending, requestID: approvalID)
            return true
        }

        var history = UserDefaults.standard.dictionary(forKey: Self.pushHistoryKey) as? [String: Double] ?? [:]
        let previous = history[envelope.requestKey].map(Date.init(timeIntervalSince1970:))
        guard envelope.isFresh(lastIssuedAt: previous) else { return false }
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
        }

        LiveActivityTokenMailbox.storeReceipt(
            source: .notification,
            requestID: envelope.requestID,
            kind: envelope.kind,
            attentionState: envelope.state,
            activityState: nil
        )
        postAttention(kind: envelope.kind, state: envelope.state, requestID: envelope.requestID)
        return true
    }

    private func postAttention(
        kind: RemoteAttentionKind,
        state: RemoteAttentionState,
        requestID: String
    ) {
        NotificationCenter.default.post(
            name: .codeIslandRemoteAttentionChanged,
            object: nil,
            userInfo: [
                "kind": kind.rawValue,
                "state": state.rawValue,
                "requestId": requestID,
            ]
        )
    }
}
