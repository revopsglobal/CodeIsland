import Foundation
import CodeIslandCore

final class PersonalHubConfigurationStore {
    enum StoreError: LocalizedError {
        case invalidMode

        var errorDescription: String? {
            switch self {
            case .invalidMode: return "Auto follows the resolved Home, Work, or Code rack"
            }
        }
    }

    static let shared = PersonalHubConfigurationStore()

    private(set) var configuration: PersonalHubConfiguration
    private let stateURL: URL

    init(stateURL: URL? = nil) {
        self.stateURL = stateURL ?? Self.defaultStateURL()
        if let data = try? Data(contentsOf: self.stateURL),
           let saved = try? JSONDecoder().decode(PersonalHubConfiguration.self, from: data) {
            configuration = PersonalHubConfiguration.sanitized(saved)
        } else {
            configuration = .default
        }
    }

    func updateRack(mode: PersonalHubMode, modules: [PersonalHubModuleID]) throws {
        guard mode != .auto else { throw StoreError.invalidMode }
        let updated = PersonalHubConfiguration(
            racks: [.home, .work, .code].map { candidateMode in
                PersonalHubModeRack(
                    mode: candidateMode,
                    modules: candidateMode == mode
                        ? modules
                        : configuration.rack(for: candidateMode)
                )
            },
            dashboardEnabled: configuration.dashboardEnabled,
            knownModules: PersonalHubModuleID.allCases
        )
        try persist(PersonalHubConfiguration.sanitized(updated))
    }

    func setDashboardEnabled(_ enabled: Bool) throws {
        let updated = PersonalHubConfiguration(
            racks: configuration.racks,
            dashboardEnabled: enabled,
            knownModules: PersonalHubModuleID.allCases
        )
        try persist(PersonalHubConfiguration.sanitized(updated))
    }

    private func persist(_ updated: PersonalHubConfiguration) throws {
        let directory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(updated)
        try data.write(to: stateURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        configuration = updated
    }

    private static func defaultStateURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("CodeIsland", isDirectory: true)
            .appendingPathComponent("personal-hub-configuration.json")
    }
}
