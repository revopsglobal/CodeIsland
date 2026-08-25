import UIKit
import UserNotifications

final class CompanionAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let pendingApprovalIDKey = RemoteHostScopedArtifactStore.pendingApprovalIDKey
    private static let pendingQuestionIDKey = RemoteHostScopedArtifactStore.pendingQuestionIDKey
    private static let pushHistoryKey = "codeisland.remote.pushHistory.v1"
    private static let taskStateHistoryKey = "codeisland.remote.taskPushState.v1"

    internal enum PushProcessingOutcome: Equatable {
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
        // Buddy is the away-from-desk approval channel, so a fresh install
        // must be able to alert immediately: request permission at launch,
        // then register. Already-authorized installs see no prompt and
        // register exactly as before.
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        if let notification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            _ = processLegacy(notification)
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        RemotePushTokenMailbox.store(token)
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
        let userInfo = notification.request.content.userInfo
        let outcome = processLegacy(userInfo)
        completionHandler(Self.presentationOptions(for: outcome))
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        switch processLegacy(userInfo) {
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
        let userInfo = response.notification.request.content.userInfo
        _ = processLegacy(userInfo)
        completionHandler()
    }

    @discardableResult
    internal func processLegacy(
        _ userInfo: [AnyHashable: Any],
        afterPairingValidation: (() -> Void)? = nil
    ) -> PushProcessingOutcome {
        let fields = Dictionary(uniqueKeysWithValues: userInfo.compactMap { key, value in
            (key as? String).map { ($0, value) }
        })

        guard let envelope = RemoteAttentionPushEnvelope(payloadFields: fields) else {
            // Backward compatibility with the first internal Buddy build.
            guard let approvalID = fields["approvalId"] as? String, !approvalID.isEmpty else { return .unrecognized }
            // It can still present, but cannot prove a pairing and therefore
            // never emits a trusted in-app route or host receipt.
            return .accepted
        }

        let stagedPairingIdentity = RemotePairingIdentityStore.runtimeIdentity()
        guard RemoteAttentionPushPairingScope.acceptsHostScopedArtifacts(
            payloadPairingDeviceID: envelope.pairingDeviceID,
            identity: stagedPairingIdentity
        ) else {
            return envelope.pairingDeviceID == nil ? .accepted : .rejectedStale
        }
        guard let pairingDeviceID = LiveActivityPairingScope.normalized(
            envelope.pairingDeviceID
        ) else { return .rejectedStale }
        // Test hooks and ActivityKit framework synchronization stay outside the
        // ownership lock. The final transaction revalidates this exact identity
        // before making any host-scoped mutation.
        afterPairingValidation?()
        let stagedReceipt = LiveActivityTokenMailbox.makeReceipt(
            source: .notification,
            requestID: envelope.requestID,
            kind: envelope.kind,
            attentionState: envelope.state,
            activityState: nil,
            pairingIdentity: stagedPairingIdentity
        )

        var storedReceipt = false
        var attentionEvent: (
            kind: RemoteAttentionKind,
            state: RemoteAttentionState,
            requestID: String,
            taskState: RemoteTaskState?,
            pairingDeviceID: String
        )?
        let outcome: PushProcessingOutcome = RemotePairingIdentityStore.withRuntimeIdentityTransaction {
            pairingIdentity in
            guard pairingIdentity == stagedPairingIdentity,
                  RemoteAttentionPushPairingScope.acceptsHostScopedArtifacts(
                payloadPairingDeviceID: envelope.pairingDeviceID,
                identity: pairingIdentity
            ) else {
                return .rejectedStale
            }
            let scopedRequestKey = "\(pairingDeviceID):\(envelope.requestKey)"

            var history = UserDefaults.standard.dictionary(
                forKey: Self.pushHistoryKey
            ) as? [String: Double] ?? [:]
            let previous = history[scopedRequestKey].map(Date.init(timeIntervalSince1970:))
            guard envelope.isFresh(lastIssuedAt: previous) else { return .rejectedStale }
            if envelope.kind == .task, let incomingState = envelope.taskState {
                var taskStates = UserDefaults.standard.dictionary(
                    forKey: Self.taskStateHistoryKey
                ) as? [String: String] ?? [:]
                let scopedTaskKey = "\(pairingDeviceID):\(envelope.requestID)"
                let previousState = taskStates[scopedTaskKey].flatMap(
                    RemoteTaskState.init(rawValue:)
                )
                guard RemoteTaskAttentionPolicy.accepts(
                    previousState: previousState,
                    incomingState: incomingState
                ) else { return .rejectedStale }
                taskStates[scopedTaskKey] = incomingState.rawValue
                if taskStates.count > 64 {
                    taskStates = Dictionary(uniqueKeysWithValues: taskStates.prefix(64).map {
                        ($0.key, $0.value)
                    })
                }
                UserDefaults.standard.set(taskStates, forKey: Self.taskStateHistoryKey)
            }
            history[scopedRequestKey] = envelope.issuedAt.timeIntervalSince1970
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

            if let stagedReceipt {
                storedReceipt = LiveActivityTokenMailbox.storePreparedReceipt(
                    stagedReceipt,
                    postNotification: false
                )
            }
            attentionEvent = (
                envelope.kind,
                envelope.state,
                envelope.requestID,
                envelope.taskState,
                pairingDeviceID
            )
            return .accepted
        }

        // NotificationCenter delivery stays outside the ownership lock. Every
        // trusted event remains owner-tagged and the observer exact-checks that
        // owner again at delivery, so an A event delivered after A→B is inert.
        if storedReceipt {
            NotificationCenter.default.post(
                name: .codeIslandLiveActivityReceiptAvailable,
                object: nil
            )
        }
        if let attentionEvent {
            postAttention(
                kind: attentionEvent.kind,
                state: attentionEvent.state,
                requestID: attentionEvent.requestID,
                taskState: attentionEvent.taskState,
                pairingDeviceID: attentionEvent.pairingDeviceID
            )
        }
        return outcome
    }

    private func postAttention(
        kind: RemoteAttentionKind,
        state: RemoteAttentionState,
        requestID: String,
        taskState: RemoteTaskState? = nil,
        pairingDeviceID: String
    ) {
        var userInfo = [
            "kind": kind.rawValue,
            "state": state.rawValue,
            "requestId": requestID,
            "pairingDeviceID": pairingDeviceID,
        ]
        if let taskState { userInfo["taskState"] = taskState.rawValue }
        NotificationCenter.default.post(
            name: .codeIslandRemoteAttentionChanged,
            object: nil,
            userInfo: userInfo
        )
    }
}
