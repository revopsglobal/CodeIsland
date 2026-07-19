import Foundation

struct RemoteBuddyBuildExpectation: Equatable {
    let expectedVersion: String
    let expectedBuild: String

    init(expectedVersion: String, expectedBuild: String) {
        self.expectedVersion = expectedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expectedBuild = expectedBuild.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        !expectedVersion.isEmpty && !expectedBuild.isEmpty
    }

    func status(for devices: [RemoteApprovalDevice]) -> RemoteBuddyBuildStatus {
        guard isConfigured else { return .notConfigured }
        if let matched = devices.first(where: {
            $0.clientVersion == expectedVersion && $0.clientBuild == expectedBuild
        }) {
            return .matched(deviceName: matched.name, lastSeenAt: matched.lastSeenAt)
        }

        let physicalDevices = devices
            .filter { ($0.clientVersion?.isEmpty == false) || ($0.clientBuild?.isEmpty == false) }
            .sorted { $0.lastSeenAt > $1.lastSeenAt }

        guard let newest = physicalDevices.first else {
            return .missing(expectedVersion: expectedVersion, expectedBuild: expectedBuild)
        }

        return .stale(
            expectedVersion: expectedVersion,
            expectedBuild: expectedBuild,
            newestDeviceName: newest.name,
            newestVersion: newest.clientVersion,
            newestBuild: newest.clientBuild,
            newestLastSeenAt: newest.lastSeenAt
        )
    }
}

struct RemoteBuddyInstallGuidance: Equatable {
    static let testFlightURL = URL(string: "itms-beta://")!

    let expectedVersion: String
    let expectedBuild: String

    init(expectedVersion: String, expectedBuild: String) {
        self.expectedVersion = expectedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.expectedBuild = expectedBuild.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var instruction: String {
        if expectedVersion.isEmpty {
            return "Open TestFlight on the iPhone, install the newest CodeIsland Buddy build, then open Buddy for at least 10 seconds."
        }
        return "Open TestFlight on the iPhone, install CodeIsland Buddy \(expectedVersion) (\(expectedBuild)), then open Buddy for at least 10 seconds."
    }

    var copyText: String {
        "\(instruction) Leave Tailscale connected, then rerun scripts/report-latest-testflight-physical-gate.sh on the Mac."
    }
}

enum RemoteBuddyBuildStatus: Equatable {
    case notConfigured
    case missing(expectedVersion: String, expectedBuild: String)
    case matched(deviceName: String, lastSeenAt: Date)
    case stale(
        expectedVersion: String,
        expectedBuild: String,
        newestDeviceName: String,
        newestVersion: String?,
        newestBuild: String?,
        newestLastSeenAt: Date
    )
}
