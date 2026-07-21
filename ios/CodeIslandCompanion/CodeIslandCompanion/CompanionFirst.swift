import Foundation

/// Companion-first (design-review B2-11): CodeIsland Buddy is a coding-agent
/// companion, so the Tools hub is trimmed to the modules that earn a place on a
/// phone whose job is watching your agents. Reversible behind a UserDefaults flag
/// (default on) so any trimmed module can be promoted back after real use, before
/// the Mac-side services are ever removed. Nothing here touches CodeIslandCore.
enum CompanionFirst {
    /// UserDefaults key. Absent or true means companion-first is on.
    static let flagKey = "buddy.companionFirst.v1"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: flagKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: flagKey)
    }

    /// The seven keepers: four core (the agents themselves) plus three with a real
    /// away-from-Mac coding nexus (calendar: "meeting soon, pause the agent?";
    /// shelf: capture a snippet to the Mac; system: is my agent thrashing the box?).
    static let keepers: Set<PersonalHubModuleID> = [
        .claude, .agents, .github, .notifications,
        .calendar, .shelf, .system,
    ]

    static func keeps(_ id: PersonalHubModuleID) -> Bool { keepers.contains(id) }

    /// Modules trimmed under companion-first, for the rack editor and any UI that
    /// enumerates the full catalog.
    static func filteredCatalog(_ all: [PersonalHubModuleID]) -> [PersonalHubModuleID] {
        isEnabled ? all.filter(keeps) : all
    }
}

extension PersonalHubSnapshot {
    /// A copy carrying only the keeper modules. Rebuilt via the public initializer
    /// so the shared CodeIslandCore type is left untouched.
    func filteringModules(to keepers: Set<PersonalHubModuleID>) -> PersonalHubSnapshot {
        PersonalHubSnapshot(
            version: version,
            serverName: serverName,
            generatedAt: generatedAt,
            requestedMode: requestedMode,
            resolvedMode: resolvedMode,
            modules: modules.filter { keepers.contains($0.id) },
            configuration: configuration,
            dayProgress: dayProgress
        )
    }

    /// Applies the companion-first trim when the flag is on; otherwise unchanged.
    var companionFiltered: PersonalHubSnapshot {
        CompanionFirst.isEnabled ? filteringModules(to: CompanionFirst.keepers) : self
    }
}
