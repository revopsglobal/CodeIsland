import SwiftUI

@main
struct CodeIslandCompanionApp: App {
    @UIApplicationDelegateAdaptor(CompanionAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var connection: CompanionConnection
    @StateObject private var liveActivity: LiveActivityController
    @StateObject private var remoteApprovals: RemoteApprovalClient

    init() {
        let connection = CompanionConnection()
        let remoteApprovals = RemoteApprovalClient()
        let liveActivity = LiveActivityController(
            pairingIdentity: remoteApprovals.liveActivityPairingIdentity
        )
        connection.onStateReceived = { [weak liveActivity] state in
            // Capture the unpaired generation synchronously. A queued nearby
            // update from Mac A is then invalidated if Buddy pairs to Mac B.
            liveActivity?.updateFromNearbyIfRunning(with: state)
        }
        remoteApprovals.onSnapshotReceived = { [weak liveActivity] snapshot in
            guard let state = CompanionStatePayload(remoteApprovalSnapshot: snapshot) else { return }
            liveActivity?.syncAttention(with: state)
        }
        remoteApprovals.onRemoteTasksReceived = { [weak liveActivity] tasks in
            liveActivity?.syncRemoteTasks(tasks)
        }
        remoteApprovals.onPairingIdentityChanged = { [weak liveActivity] pairingIdentity in
            await liveActivity?.pairingIdentityDidChange(to: pairingIdentity)
        }
#if DEBUG
        Self.configureSmokeTestHooks(connection: connection, liveActivity: liveActivity)
#endif
        _connection = StateObject(wrappedValue: connection)
        _liveActivity = StateObject(wrappedValue: liveActivity)
        _remoteApprovals = StateObject(wrappedValue: remoteApprovals)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connection)
                .environmentObject(liveActivity)
                .environmentObject(remoteApprovals)
                .onChange(of: scenePhase) { _, newPhase in
                    remoteApprovals.setActive(newPhase == .active)
                }
                .onChange(of: remoteApprovals.state) { _, state in
                    liveActivity.hostAvailabilityChanged(isAvailable: state == .connected)
                }
                .onOpenURL {
                    remoteApprovals.openDeepLink($0)
                }
        }
    }

#if DEBUG
    private static func configureSmokeTestHooks(
        connection: CompanionConnection,
        liveActivity: LiveActivityController
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-CodeIslandCompanionSmokeLiveActivity") else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if let state = connection.latestState {
                liveActivity.startOrUpdateFromNearby(with: state)
            }

            guard let flagIndex = arguments.firstIndex(of: "-CodeIslandCompanionSmokeDelayedState"),
                  arguments.indices.contains(flagIndex + 1)
            else { return }

            let delaySeconds: Double
            if let delayIndex = arguments.firstIndex(of: "-CodeIslandCompanionSmokeDelayedSeconds"),
               arguments.indices.contains(delayIndex + 1),
               let configured = Double(arguments[delayIndex + 1]) {
                delaySeconds = max(0.5, configured)
            } else {
                delaySeconds = 4
            }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            connection.injectMockState(named: arguments[flagIndex + 1])
        }
    }
#endif
}
