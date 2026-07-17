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
        let liveActivity = LiveActivityController()
        let remoteApprovals = RemoteApprovalClient()
        connection.onStateReceived = { [weak liveActivity] state in
            Task { @MainActor in
                liveActivity?.updateIfRunning(with: state)
            }
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
                liveActivity.startOrUpdate(with: state)
            }

            guard let flagIndex = arguments.firstIndex(of: "-CodeIslandCompanionSmokeDelayedState"),
                  arguments.indices.contains(flagIndex + 1)
            else { return }

            try? await Task.sleep(nanoseconds: 4_000_000_000)
            connection.injectMockState(named: arguments[flagIndex + 1])
        }
    }
#endif
}
