import AppKit
import Combine
import CodeIslandCore
import Foundation

/// Local-only data providers for personal hub modules that do not belong to the
/// agent runtime. Notes and shelf history persist in this Mac user's defaults;
/// system/media/audio values are sampled from macOS and never leave the tailnet.
@MainActor
final class PersonalHubDataModel: ObservableObject {
    static let shared = PersonalHubDataModel()

    struct Note: Codable, Equatable, Identifiable, Sendable {
        struct Version: Codable, Equatable, Sendable {
            let text: String
            let category: String?
        }

        struct ChecklistLine: Equatable, Sendable {
            let lineIndex: Int
            let title: String
            let isCompleted: Bool
        }

        let id: String
        var text: String
        var updatedAt: Date
        var category: String?
        var revision: Int?
        var history: [Version]?

        var title: String {
            text.split(whereSeparator: \Character.isNewline).first.map(String.init) ?? text
        }

        var currentRevision: Int { revision ?? 1 }
        var canUndo: Bool { !(history ?? []).isEmpty }
        var checklist: [ChecklistLine] { Self.parseChecklist(text) }

        static func parseChecklist(_ text: String) -> [ChecklistLine] {
            text.components(separatedBy: .newlines).enumerated().compactMap { index, line in
                let unchecked = "- [ ] "
                let checkedPrefixes = ["- [x] ", "- [X] "]
                if line.hasPrefix(unchecked) {
                    return .init(lineIndex: index, title: String(line.dropFirst(unchecked.count)), isCompleted: false)
                }
                if let prefix = checkedPrefixes.first(where: line.hasPrefix) {
                    return .init(lineIndex: index, title: String(line.dropFirst(prefix.count)), isCompleted: true)
                }
                return nil
            }
        }
    }

    struct ShelfEntry: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let value: String
        let capturedAt: Date
        let filePath: String?

        init(id: String, value: String, capturedAt: Date, filePath: String? = nil) {
            self.id = id
            self.value = value
            self.capturedAt = capturedAt
            self.filePath = filePath
        }

        var title: String {
            if let filePath { return URL(fileURLWithPath: filePath).lastPathComponent }
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
        struct QueueItem: Equatable, Identifiable, Sendable {
            let id: String
            let title: String
            let artist: String
            let album: String
        }

        let appName: String
        let title: String
        let artist: String
        let album: String
        let isPlaying: Bool
        let position: Double?
        let duration: Double?
        let lyrics: String?
        let queue: [QueueItem]
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
        let outputVolume: Int?
    }

    struct ClaudeProposal: Equatable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable {
            case reminder
            case note
            case calendar
        }

        let id: String
        let kind: Kind
        let title: String
        let text: String?
        let due: Date?
        let start: Date?
        let end: Date?
        let joinURL: URL?
        let notes: String?

        var summary: String {
            switch kind {
            case .reminder: return due == nil ? "Task" : "Reminder"
            case .note: return "Note"
            case .calendar: return "Calendar event"
            }
        }
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
    @Published private(set) var claudeProposals: [ClaudeProposal] = []
    @Published private(set) var claudeBusy = false
    @Published private(set) var claudeError: String?

    private static let notesKey = "codeisland.personalHub.notes.v1"
    private static let shelfKey = "codeisland.personalHub.shelf.v1"
    private static let teleprompterKey = "codeisland.personalHub.teleprompter.v1"
    private let defaults: UserDefaults
    private var clipboardTimer: Timer?
    private var systemTimer: Timer?
    private var mediaTimer: Timer?
    private var lastPasteboardChangeCount = NSPasteboard.general.changeCount
    private var started = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notes = Self.load([Note].self, key: Self.notesKey, defaults: defaults) ?? []
        shelf = Self.load([ShelfEntry].self, key: Self.shelfKey, defaults: defaults) ?? []
        teleprompterText = defaults.string(forKey: Self.teleprompterKey) ?? ""
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
        notes.insert(.init(
            id: UUID().uuidString,
            text: text,
            updatedAt: Date(),
            category: nil,
            revision: 1,
            history: []
        ), at: 0)
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

    func replaceNote(
        id: String,
        rawText: String,
        expectedRevision: Int? = nil,
        category: String? = nil
    ) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 20_000,
              let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        guard expectedRevision == nil || notes[index].currentRevision == expectedRevision else { return false }
        rememberCurrentVersion(at: index)
        notes[index].text = text
        if category != nil {
            notes[index].category = Self.normalizedCategory(category)
        }
        notes[index].revision = notes[index].currentRevision + 1
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

    func setNoteCategory(id: String, rawCategory: String?, expectedRevision: Int) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].currentRevision == expectedRevision else { return false }
        rememberCurrentVersion(at: index)
        notes[index].category = Self.normalizedCategory(rawCategory)
        notes[index].revision = notes[index].currentRevision + 1
        notes[index].updatedAt = Date()
        notes.sort { $0.updatedAt > $1.updatedAt }
        persist(notes, key: Self.notesKey)
        return true
    }

    func undoNote(id: String) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              var history = notes[index].history,
              let previous = history.popLast() else { return false }
        notes[index].text = previous.text
        notes[index].category = previous.category
        notes[index].history = history
        notes[index].revision = notes[index].currentRevision + 1
        notes[index].updatedAt = Date()
        notes.sort { $0.updatedAt > $1.updatedAt }
        persist(notes, key: Self.notesKey)
        return true
    }

    func toggleChecklistLine(id: String, lineIndex: Int, expectedRevision: Int) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].currentRevision == expectedRevision else { return false }
        var lines = notes[index].text.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex) else { return false }
        if lines[lineIndex].hasPrefix("- [ ] ") {
            lines[lineIndex].replaceSubrange(lines[lineIndex].startIndex..<lines[lineIndex].index(lines[lineIndex].startIndex, offsetBy: 6), with: "- [x] ")
        } else if lines[lineIndex].hasPrefix("- [x] ") || lines[lineIndex].hasPrefix("- [X] ") {
            lines[lineIndex].replaceSubrange(lines[lineIndex].startIndex..<lines[lineIndex].index(lines[lineIndex].startIndex, offsetBy: 6), with: "- [ ] ")
        } else {
            return false
        }
        return replaceNote(
            id: id,
            rawText: lines.joined(separator: "\n"),
            expectedRevision: expectedRevision,
            category: notes[index].category
        )
    }

    private func rememberCurrentVersion(at index: Int) {
        var history = notes[index].history ?? []
        history.append(.init(text: notes[index].text, category: notes[index].category))
        notes[index].history = Array(history.suffix(20))
    }

    nonisolated private static func normalizedCategory(_ value: String?) -> String? {
        let category = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !category.isEmpty else { return nil }
        return String(category.prefix(40))
    }

    func setTeleprompterText(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 50_000 else { return false }
        teleprompterText = text
        defaults.set(text, forKey: Self.teleprompterKey)
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

    func planClaudeActions(_ rawPrompt: String) -> Bool {
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
        claudeProposals = []
        let now = ISO8601DateFormatter().string(from: Date())
        let zone = TimeZone.current.identifier
        Task { [weak self] in
            let output = await Task.detached(priority: .userInitiated) {
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
                        """
                        You convert one private personal request into proposed CodeIsland actions. Never execute tools. Return JSON only, no markdown, with this exact shape:
                        {"proposals":[{"type":"reminder|note|calendar","title":"short title","text":null,"due":null,"start":null,"end":null,"joinURL":null,"notes":null}]}
                        Use reminder for tasks or reminders, note for saved text, and calendar only for an event with a clear start and end. ISO-8601 dates must include an offset. It is now \(now) in \(zone). If a time is ambiguous, omit that proposal rather than guessing. Keep at most 8 proposals.
                        """,
                        prompt
                    ],
                    timeout: 90
                ).flatMap { String(data: $0, encoding: .utf8) }
            }.value
            guard let self else { return }
            self.claudeBusy = false
            let proposals = output.map(Self.parseClaudeProposals) ?? []
            if proposals.isEmpty {
                self.claudeError = "Claude did not produce any safe, reviewable actions"
                self.claudeLastResponse = nil
            } else {
                self.claudeProposals = proposals
                self.claudeLastResponse = "Review \(proposals.count) proposed action\(proposals.count == 1 ? "" : "s") below. Nothing runs until you tap Review and confirm."
                self.claudeError = nil
            }
        }
        return true
    }

    func removeClaudeProposal(id: String) {
        claudeProposals.removeAll { $0.id == id }
    }

    nonisolated static func parseClaudeProposals(_ rawOutput: String) -> [ClaudeProposal] {
        var text = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
        }
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["proposals"] as? [[String: Any]] else { return [] }
        let formatter = ISO8601DateFormatter()
        return rows.prefix(8).compactMap { row in
            guard let type = row["type"] as? String,
                  let kind = ClaudeProposal.Kind(rawValue: type),
                  let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty, title.count <= 500 else { return nil }
            let text = (row["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let due = (row["due"] as? String).flatMap { formatter.date(from: $0) }
            let start = (row["start"] as? String).flatMap { formatter.date(from: $0) }
            let end = (row["end"] as? String).flatMap { formatter.date(from: $0) }
            let joinURL = (row["joinURL"] as? String).flatMap { value -> URL? in
                guard let url = URL(string: value),
                      let scheme = url.scheme?.lowercased(),
                      ["https", "http"].contains(scheme) else {
                    return nil
                }
                return url
            }
            let notes = (row["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (notes?.count ?? 0) <= 5_000 else { return nil }
            switch kind {
            case .note:
                guard let text, !text.isEmpty, text.count <= 20_000 else { return nil }
            case .calendar:
                guard let start, let end, end > start else { return nil }
            case .reminder:
                break
            }
            return .init(
                id: UUID().uuidString,
                kind: kind,
                title: title,
                text: text,
                due: due,
                start: start,
                end: end,
                joinURL: joinURL,
                notes: notes
            )
        }
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

    func shelfFileURL(id: String) -> URL? {
        guard let entry = shelf.first(where: { $0.id == id }),
              let filePath = entry.filePath else { return nil }
        let url = URL(fileURLWithPath: filePath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return url
    }

    func runMediaCommand(_ action: String, targetID: String? = nil) -> Bool {
        guard let media = nowPlaying else { return false }
        let appName = media.appName
        let command: String
        switch action {
        case "next": command = "next track"
        case "previous": command = "previous track"
        case "playPause": command = "playpause"
        case "seekBack", "seekForward":
            let delta = action == "seekBack" ? -15.0 : 15.0
            let current = media.position ?? 0
            let duration = media.duration ?? .greatestFiniteMagnitude
            let destination = min(max(current + delta, 0), duration)
            command = "set player position to \(destination)"
        case "playQueueItem":
            guard appName == "Music",
                  let targetID,
                  media.queue.contains(where: { $0.id == targetID }),
                  let index = Int(targetID),
                  index > 0 else { return false }
            command = "play track \(index) of current playlist"
        default:
            return false
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
        }) else { return }

        if let fileURL = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first(where: \.isFileURL),
           shelf.first?.filePath != fileURL.path {
            let entry = ShelfEntry(
                id: UUID().uuidString,
                value: fileURL.lastPathComponent,
                capturedAt: Date(),
                filePath: fileURL.path
            )
            shelf.insert(entry, at: 0)
            if shelf.count > 20 { shelf.removeLast(shelf.count - 20) }
            persist(shelf, key: Self.shelfKey)
            return
        }

        guard let value = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.count <= 10_000, shelf.first?.value != value
        else { return }
        shelf.insert(.init(id: UUID().uuidString, value: value, capturedAt: Date()), at: 0)
        if shelf.count > 20 { shelf.removeLast(shelf.count - 20) }
        persist(shelf, key: Self.shelfKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
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
        let queue = appName == "Music" ? readMusicQueue() : []
        return parseNowPlayingOutput(output, appName: appName, queue: queue)
    }

    nonisolated static func parseNowPlayingOutput(
        _ output: String,
        appName: String,
        queue: [NowPlaying.QueueItem] = []
    ) -> NowPlaying? {
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
            lyrics: lyrics.isEmpty ? nil : lyrics,
            queue: queue
        )
    }

    nonisolated static func readMusicQueue() -> [NowPlaying.QueueItem] {
        let script = """
        tell application "Music"
            set ciRows to ""
            try
                set ciPlaylist to current playlist
                set ciCurrentIndex to index of current track
                set ciTracks to every track of ciPlaylist
                set ciLastIndex to count of ciTracks
                repeat with ciIndex from (ciCurrentIndex + 1) to ciLastIndex
                    if ciIndex > (ciCurrentIndex + 8) then exit repeat
                    set ciTrack to item ciIndex of ciTracks
                    set ciRows to ciRows & (ciIndex as string) & (ASCII character 30) & (name of ciTrack as string) & (ASCII character 30) & (artist of ciTrack as string) & (ASCII character 30) & (album of ciTrack as string) & (ASCII character 29)
                end repeat
            end try
            return ciRows
        end tell
        """
        guard let data = ProcessRunner.run(
            path: "/usr/bin/osascript",
            args: ["-e", script],
            timeout: 5
        ), let output = String(data: data, encoding: .utf8) else { return [] }
        return parseMusicQueueOutput(output)
    }

    nonisolated static func parseMusicQueueOutput(_ output: String) -> [NowPlaying.QueueItem] {
        output.components(separatedBy: String(UnicodeScalar(29))).compactMap { row in
            let parts = row.components(separatedBy: String(UnicodeScalar(30)))
            guard parts.count >= 4,
                  let index = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  index > 0 else { return nil }
            return .init(
                id: String(index),
                title: parts[1],
                artist: parts[2],
                album: parts[3]
            )
        }
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

    func changeOutputVolume(by delta: Int) -> Bool {
        let current = quickSettings?.outputVolume ?? Self.readQuickSettings().outputVolume ?? 50
        return setOutputVolume(current + delta)
    }

    func setOutputVolume(_ requested: Int) -> Bool {
        let value = min(max(requested, 0), 100)
        let script = "set volume output volume \(value)"
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
        let volumeText = ProcessRunner.run(
            path: "/usr/bin/osascript",
            args: ["-e", "output volume of (get volume settings)"],
            timeout: 4
        ).flatMap { String(data: $0, encoding: .utf8) }
        let volume = volumeText.flatMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.map { min(max($0, 0), 100) }
        return .init(darkMode: darkMode, outputMuted: muted, outputVolume: volume)
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
