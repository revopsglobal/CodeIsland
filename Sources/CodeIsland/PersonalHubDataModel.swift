import AppKit
import Combine
import Foundation

/// Local-only data providers for personal hub modules that do not belong to the
/// agent runtime. Notes and shelf history persist in this Mac user's defaults;
/// system/media/audio values are sampled from macOS and never leave the tailnet.
@MainActor
final class PersonalHubDataModel: ObservableObject {
    static let shared = PersonalHubDataModel()

    struct Note: Codable, Equatable, Identifiable, Sendable {
        let id: String
        var text: String
        var updatedAt: Date

        var title: String {
            text.split(whereSeparator: \Character.isNewline).first.map(String.init) ?? text
        }
    }

    struct ShelfEntry: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let value: String
        let capturedAt: Date

        var title: String {
            let oneLine = value.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return oneLine.count > 72 ? "\(oneLine.prefix(69))…" : oneLine
        }
    }

    struct SystemSnapshot: Equatable, Sendable {
        let load1: Double
        let load5: Double
        let load15: Double
        let memoryUsedBytes: UInt64?
        let memoryTotalBytes: UInt64
        let diskFreeBytes: Int64?
        let uptime: TimeInterval
        let processorCount: Int
        let thermalState: String

        var memoryPercent: Int? {
            guard let memoryUsedBytes, memoryTotalBytes > 0 else { return nil }
            return Int((Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100).rounded())
        }
    }

    struct MacBattery: Equatable, Sendable {
        let percent: Int
        let status: String
        let powerSource: String
        let cycleCount: Int?
        let healthPercent: Int?
        let condition: String?
    }

    struct AudioDevice: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let isInput: Bool
        let isOutput: Bool
        let isDefaultInput: Bool
        let isDefaultOutput: Bool
    }

    struct NowPlaying: Equatable, Sendable {
        let appName: String
        let title: String
        let artist: String
        let album: String
        let isPlaying: Bool
        let position: Double?
        let duration: Double?
        let lyrics: String?
    }

    struct GitHubPullRequest: Equatable, Identifiable, Sendable {
        let id: String
        let repository: String
        let number: Int
        let title: String
        let url: URL
        let isDraft: Bool
        let updatedAt: Date?
    }

    struct QuickSettings: Equatable, Sendable {
        let darkMode: Bool
        let outputMuted: Bool
    }

    @Published private(set) var notes: [Note] = []
    @Published private(set) var shelf: [ShelfEntry] = []
    @Published private(set) var system: SystemSnapshot?
    @Published private(set) var macBattery: MacBattery?
    @Published private(set) var audioDevices: [AudioDevice] = []
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var mediaPermissionError: String?
    @Published private(set) var githubPullRequests: [GitHubPullRequest]?
    @Published private(set) var quickSettings: QuickSettings?
    @Published private(set) var teleprompterText = ""
    @Published private(set) var claudeLastPrompt: String?
    @Published private(set) var claudeLastResponse: String?
    @Published private(set) var claudeBusy = false
    @Published private(set) var claudeError: String?

    private static let notesKey = "codeisland.personalHub.notes.v1"
    private static let shelfKey = "codeisland.personalHub.shelf.v1"
    private static let teleprompterKey = "codeisland.personalHub.teleprompter.v1"
    private var clipboardTimer: Timer?
    private var systemTimer: Timer?
    private var mediaTimer: Timer?
    private var lastPasteboardChangeCount = NSPasteboard.general.changeCount
    private var started = false

    private init() {
        notes = Self.load([Note].self, key: Self.notesKey) ?? []
        shelf = Self.load([ShelfEntry].self, key: Self.shelfKey) ?? []
        teleprompterText = UserDefaults.standard.string(forKey: Self.teleprompterKey) ?? ""
    }

    func start() {
        guard !started else { return }
        started = true
        captureClipboardIfChanged(force: true)
        refreshHostData()
        refreshNowPlaying()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureClipboardIfChanged() }
        }
        systemTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshHostData() }
        }
        mediaTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNowPlaying() }
        }
    }

    func addNote(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 20_000 else { return false }
        notes.insert(.init(id: UUID().uuidString, text: text, updatedAt: Date()), at: 0)
        persist(notes, key: Self.notesKey)
        return true
    }

    func deleteNote(id: String) -> Bool {
        let before = notes.count
        notes.removeAll { $0.id == id }
        guard notes.count != before else { return false }
        persist(notes, key: Self.notesKey)
        return true
    }

    func replaceNote(id: String, rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 20_000,
              let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        notes[index].text = text
        notes[index].updatedAt = Date()
        notes.sort { $0.updatedAt > $1.updatedAt }
        persist(notes, key: Self.notesKey)
        return true
    }

    func appendToNote(id: String, rawText: String) -> Bool {
        let addition = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty,
              let note = notes.first(where: { $0.id == id }) else { return false }
        let combined = "\(note.text)\n\(addition)"
        return replaceNote(id: id, rawText: combined)
    }

    func setTeleprompterText(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 50_000 else { return false }
        teleprompterText = text
        UserDefaults.standard.set(text, forKey: Self.teleprompterKey)
        return true
    }

    func askClaude(_ rawPrompt: String) -> Bool {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !claudeBusy, !prompt.isEmpty, prompt.count <= 20_000 else { return false }
        let candidates = ["/usr/local/bin/claude", "/opt/homebrew/bin/claude"]
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            claudeError = "Claude Code is not installed on the Mac"
            return false
        }

        claudeBusy = true
        claudeError = nil
        claudeLastPrompt = prompt
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                ProcessRunner.run(
                    path: path,
                    args: [
                        "--print",
                        "--output-format", "text",
                        "--permission-mode", "dontAsk",
                        "--tools", "",
                        "--safe-mode",
                        "--no-session-persistence",
                        "--system-prompt",
                        "You are the private CodeIsland copilot. Answer concisely. Do not use tools or claim to perform actions.",
                        prompt
                    ],
                    timeout: 90
                ).flatMap { String(data: $0, encoding: .utf8) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }.value
            guard let self else { return }
            self.claudeBusy = false
            if let result, !result.isEmpty {
                self.claudeLastResponse = result
                self.claudeError = nil
            } else {
                self.claudeError = "Claude did not return a response"
            }
        }
        return true
    }

    func copyShelfEntry(id: String) -> Bool {
        guard let entry = shelf.first(where: { $0.id == id }) else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(entry.value, forType: .string)
    }

    func removeShelfEntry(id: String) -> Bool {
        let before = shelf.count
        shelf.removeAll { $0.id == id }
        guard shelf.count != before else { return false }
        persist(shelf, key: Self.shelfKey)
        return true
    }

    func runMediaCommand(_ action: String) -> Bool {
        guard let appName = nowPlaying?.appName,
              ["playPause", "next", "previous"].contains(action)
        else { return false }
        let command: String
        switch action {
        case "next": command = "next track"
        case "previous": command = "previous track"
        default: command = "playpause"
        }
        let script = "tell application \"\(appName)\" to \(command)"
        let result = ProcessRunner.run(path: "/usr/bin/osascript", args: ["-e", script], timeout: 5)
        refreshNowPlaying()
        return result != nil
    }

    func refreshHostData() {
        Task { [weak self] in
            let values = await Task.detached(priority: .utility) {
                (
                    Self.readSystemSnapshot(),
                    Self.readMacBattery(),
                    Self.readAudioDevices(),
                    Self.readGitHubPullRequests(),
                    Self.readQuickSettings()
                )
            }.value
            guard let self else { return }
            self.system = values.0
            self.macBattery = values.1
            self.audioDevices = values.2
            self.githubPullRequests = values.3
            self.quickSettings = values.4
        }
    }

    func refreshNowPlaying() {
        let running = NSWorkspace.shared.runningApplications
        let appName: String?
        if running.contains(where: { $0.bundleIdentifier == "com.apple.Music" }) {
            appName = "Music"
        } else if running.contains(where: { $0.bundleIdentifier == "com.spotify.client" }) {
            appName = "Spotify"
        } else {
            appName = nil
        }
        guard let appName else {
            nowPlaying = nil
            mediaPermissionError = nil
            return
        }
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Self.readNowPlaying(appName: appName)
            }.value
            guard let self else { return }
            self.nowPlaying = result
            self.mediaPermissionError = result == nil
                ? "Allow CodeIsland to control \(appName) in Privacy & Security → Automation"
                : nil
        }
    }

    private func captureClipboardIfChanged(force: Bool = false) {
        let pasteboard = NSPasteboard.general
        guard force || pasteboard.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pasteboard.changeCount
        guard !(pasteboard.types ?? []).contains(where: {
            $0.rawValue.localizedCaseInsensitiveContains("concealed")
                || $0.rawValue.localizedCaseInsensitiveContains("transient")
        }), let value = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.count <= 10_000, shelf.first?.value != value
        else { return }
        shelf.insert(.init(id: UUID().uuidString, value: value, capturedAt: Date()), at: 0)
        if shelf.count > 20 { shelf.removeLast(shelf.count - 20) }
        persist(shelf, key: Self.shelfKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    nonisolated private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    nonisolated static func readSystemSnapshot() -> SystemSnapshot {
        var averages = [Double](repeating: 0, count: 3)
        _ = getloadavg(&averages, 3)
        let total = ProcessInfo.processInfo.physicalMemory
        let used = ProcessRunner.run(path: "/usr/bin/vm_stat", args: [], timeout: 3)
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { parseVMStat($0, totalBytes: total) }
        let disk = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Nominal"
        case .fair: thermal = "Fair"
        case .serious: thermal = "Serious"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unknown"
        }
        return .init(
            load1: averages[0],
            load5: averages[1],
            load15: averages[2],
            memoryUsedBytes: used,
            memoryTotalBytes: total,
            diskFreeBytes: disk ?? nil,
            uptime: ProcessInfo.processInfo.systemUptime,
            processorCount: ProcessInfo.processInfo.processorCount,
            thermalState: thermal
        )
    }

    nonisolated static func parseVMStat(_ output: String, totalBytes: UInt64) -> UInt64? {
        let pageSize: UInt64 = output.firstMatch(#"page size of ([0-9]+) bytes"#).flatMap(UInt64.init) ?? 4096
        let freeKeys = ["Pages free", "Pages speculative"]
        var freePages: UInt64 = 0
        for line in output.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            guard freeKeys.contains(key) else { continue }
            let digits = line[line.index(after: colon)...].filter(\.isNumber)
            freePages += UInt64(digits) ?? 0
        }
        let freeBytes = freePages.multipliedReportingOverflow(by: pageSize).partialValue
        guard totalBytes >= freeBytes else { return nil }
        return totalBytes - freeBytes
    }

    nonisolated static func readMacBattery() -> MacBattery? {
        guard let data = ProcessRunner.run(path: "/usr/bin/pmset", args: ["-g", "batt"], timeout: 3),
              let output = String(data: data, encoding: .utf8)
        else { return nil }
        let healthOutput = ProcessRunner.run(
            path: "/usr/sbin/ioreg",
            args: ["-r", "-n", "AppleSmartBattery"],
            timeout: 4
        ).flatMap { String(data: $0, encoding: .utf8) }
        return parseMacBattery(output, healthOutput: healthOutput)
    }

    nonisolated static func parseMacBattery(_ output: String, healthOutput: String? = nil) -> MacBattery? {
        guard let percentText = output.firstMatch(#"([0-9]{1,3})%;"#),
              let percent = Int(percentText)
        else { return nil }
        let source = output.firstMatch(#"Now drawing from '([^']+)'"#) ?? "Unknown"
        let status = output.firstMatch(#"[0-9]{1,3}%;\s*([^;]+);"#) ?? "Unknown"
        let cycleCount = healthOutput?.firstMatch(#"\"CycleCount\"\s*=\s*([0-9]+)"#).flatMap(Int.init)
        let rawMaximum = healthOutput?.firstMatch(#"\"AppleRawMaxCapacity\"\s*=\s*([0-9]+)"#).flatMap(Double.init)
        let design = healthOutput?.firstMatch(#"\"DesignCapacity\"\s*=\s*([0-9]+)"#).flatMap(Double.init)
        let healthPercent: Int?
        if let rawMaximum, let design, design > 0 {
            healthPercent = min(max(Int((rawMaximum / design * 100).rounded()), 0), 100)
        } else {
            healthPercent = nil
        }
        let condition = healthOutput?.firstMatch(#"\"Condition\"\s*=\s*\"([^\"]+)\""#)
        return .init(
            percent: min(max(percent, 0), 100),
            status: status,
            powerSource: source,
            cycleCount: cycleCount,
            healthPercent: healthPercent,
            condition: condition
        )
    }

    nonisolated static func readAudioDevices() -> [AudioDevice] {
        guard let data = ProcessRunner.run(
            path: "/usr/sbin/system_profiler",
            args: ["SPAudioDataType", "-json"],
            timeout: 8
        ) else { return [] }
        return parseAudioDevices(data)
    }

    nonisolated static func parseAudioDevices(_ data: Data) -> [AudioDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPAudioDataType"] as? [[String: Any]]
        else { return [] }
        return sections.flatMap { $0["_items"] as? [[String: Any]] ?? [] }.compactMap { item in
            guard let name = item["_name"] as? String else { return nil }
            let input = (item["coreaudio_device_input"] as? NSNumber)?.intValue ?? 0
            let output = (item["coreaudio_device_output"] as? NSNumber)?.intValue ?? 0
            return .init(
                id: name,
                name: name,
                isInput: input > 0,
                isOutput: output > 0,
                isDefaultInput: item["coreaudio_input_source"] as? String == "spaudio_default",
                isDefaultOutput: item["coreaudio_output_source"] as? String == "spaudio_default"
            )
        }.sorted { lhs, rhs in
            if lhs.isDefaultOutput != rhs.isDefaultOutput { return lhs.isDefaultOutput }
            if lhs.isDefaultInput != rhs.isDefaultInput { return lhs.isDefaultInput }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated static func readNowPlaying(appName: String) -> NowPlaying? {
        guard ["Music", "Spotify"].contains(appName) else { return nil }
        let script = """
        tell application "\(appName)"
            set ciState to (player state as string)
            set ciTitle to (name of current track as string)
            set ciArtist to (artist of current track as string)
            set ciAlbum to (album of current track as string)
            set ciPosition to ""
            set ciDuration to ""
            set ciLyrics to ""
            try
                set ciPosition to (player position as string)
                set ciDuration to (duration of current track as string)
            end try
            try
                set ciLyrics to (lyrics of current track as string)
            end try
            return ciState & (ASCII character 31) & ciTitle & (ASCII character 31) & ciArtist & (ASCII character 31) & ciAlbum & (ASCII character 31) & ciPosition & (ASCII character 31) & ciDuration & (ASCII character 31) & ciLyrics
        end tell
        """
        guard let data = ProcessRunner.run(path: "/usr/bin/osascript", args: ["-e", script], timeout: 5),
              let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        let parts = output.components(separatedBy: String(UnicodeScalar(31)))
        guard parts.count >= 4 else { return nil }
        let lyrics = parts.count > 6
            ? parts[6].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return .init(
            appName: appName,
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            isPlaying: parts[0].localizedCaseInsensitiveContains("playing"),
            position: parts.count > 4 ? Double(parts[4]) : nil,
            duration: parts.count > 5 ? Double(parts[5]) : nil,
            lyrics: lyrics.isEmpty ? nil : lyrics
        )
    }

    nonisolated static func readGitHubPullRequests() -> [GitHubPullRequest]? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return nil
        }
        guard let data = ProcessRunner.run(
            path: path,
            args: [
                "search", "prs", "--author", "@me", "--state", "open", "--limit", "20",
                "--json", "number,title,repository,url,isDraft,updatedAt"
            ],
            timeout: 12
        ) else { return nil }
        return parseGitHubPullRequests(data)
    }

    nonisolated static func parseGitHubPullRequests(_ data: Data) -> [GitHubPullRequest]? {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let number = row["number"] as? Int,
                  let title = row["title"] as? String,
                  let urlText = row["url"] as? String,
                  let url = URL(string: urlText),
                  let repository = row["repository"] as? [String: Any],
                  let name = (repository["nameWithOwner"] ?? repository["name"]) as? String
            else { return nil }
            return .init(
                id: "\(name)#\(number)",
                repository: name,
                number: number,
                title: title,
                url: url,
                isDraft: row["isDraft"] as? Bool ?? false,
                updatedAt: (row["updatedAt"] as? String).flatMap { formatter.date(from: $0) }
            )
        }
    }

    func toggleDarkMode() -> Bool {
        let script = #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#
        guard ProcessRunner.run(path: "/usr/bin/osascript", args: ["-e", script], timeout: 6) != nil else {
            return false
        }
        refreshHostData()
        return true
    }

    func toggleMute() -> Bool {
        let script = #"set volume output muted not (output muted of (get volume settings))"#
        guard ProcessRunner.run(path: "/usr/bin/osascript", args: ["-e", script], timeout: 5) != nil else {
            return false
        }
        refreshHostData()
        return true
    }

    nonisolated static func readQuickSettings() -> QuickSettings {
        let darkMode = ProcessRunner.run(
            path: "/usr/bin/defaults",
            args: ["read", "-g", "AppleInterfaceStyle"],
            timeout: 3
        ) != nil
        let mutedText = ProcessRunner.run(
            path: "/usr/bin/osascript",
            args: ["-e", "output muted of (get volume settings)"],
            timeout: 4
        ).flatMap { String(data: $0, encoding: .utf8) }
        let muted = mutedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("true") == .orderedSame
        return .init(darkMode: darkMode, outputMuted: muted)
    }
}

private extension String {
    nonisolated func firstMatch(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: self)
        else { return nil }
        return String(self[range])
    }
}
