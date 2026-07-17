import UIKit
import UserNotifications

final class CompanionAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let pendingPushTokenKey = "codeisland.remote.pendingPushToken"
    private static let pendingApprovalIDKey = "codeisland.remote.pendingApprovalID"

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
        if let notification = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
           let approvalID = notification["approvalId"] as? String {
            UserDefaults.standard.set(approvalID, forKey: Self.pendingApprovalIDKey)
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
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let approvalID = response.notification.request.content.userInfo["approvalId"] as? String
        if let approvalID {
            UserDefaults.standard.set(approvalID, forKey: Self.pendingApprovalIDKey)
            NotificationCenter.default.post(
                name: .codeIslandRemoteApprovalOpened,
                object: nil,
                userInfo: ["approvalId": approvalID]
            )
        }
        completionHandler()
    }
}
