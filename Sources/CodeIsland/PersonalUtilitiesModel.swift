import AppKit
import Darwin
import Foundation
import os.log

/// Personal, local-only notch signals that do not depend on an agent session.
///
/// This intentionally favors Greg's Mac over a configurable multi-user system:
/// Downloads means `~/Downloads`, Bluetooth data comes from macOS itself, and
/// monitoring becomes frequent only while an active transfer exists.
@MainActor
final class PersonalUtilitiesModel: ObservableObject {
    static let shared = PersonalUtilitiesModel()

    struct DownloadInfo: Identifiable, Equatable, Sendable {
        let id: String
        let url: URL
        let name: String
        let bytesReceived: Int64
        let totalBytes: Int64?
        let modifiedAt: Date

        var progress: Double? {
            guard let totalBytes, totalBytes > 0 else { return nil }
            return min(max(Double(bytesReceived) / Double(totalBytes), 0), 1)
        }

        var percent: Int? { progress.map { Int(($0 * 100).rounded()) } }

        var isStalled: Bool {
            Date().timeIntervalSince(modifiedAt) > 45
        }
    }

    struct BatteryLevel: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let percent: Int
    }

    struct DeviceBattery: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let levels: [BatteryLevel]

        var primaryPercent: Int {
            levels.map(\.percent).min() ?? 0
        }

        var summary: String {
            if levels.count == 1, let only = levels.first {
                return "\(only.percent)%"
            }
            return levels.map { "\($0.label) \($0.percent)%" }.joined(separator: " · ")
        }
    }

    @Published private(set) var downloads: [DownloadInfo] = []
    @Published private(set) var recentDownloadCompleted: String?
    @Published private(set) var deviceBatteries: [DeviceBattery] = []
    @Published private(set) var bluetoothError: String?
    @Published private(set) var isRefreshingBluetooth = false

    var primaryDownload: DownloadInfo? {
        downloads.first(where: { !$0.isStalled }) ?? downloads.first
    }

    var lowBattery: DeviceBattery? {
        deviceBatteries
            .filter { $0.primaryPercent <= 30 }
            .min { $0.primaryPercent < $1.primaryPercent }
    }

    var hasCompactStatus: Bool {
        primaryDownload != nil || recentDownloadCompleted != nil || lowBattery != nil
    }

    private static let log = Logger(subsystem: "com.codeisland", category: "PersonalUtilities")
    nonisolated private static let partialExtensions: Set<String> = [
        "crdownload", "download", "opdownload", "part", "partial",
    ]

    private let downloadsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true)
    private var directorySource: DispatchSourceFileSystemObject?
    private var progressTimer: Timer?
    private var batteryTimer: Timer?
    private var completionClearTimer: Timer?
    private var hasScannedDownloads = false
    private var started = false
    private var lastBluetoothRefresh = Date.distantPast

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        startDownloadsWatcher()
        scanDownloads()
        refreshBluetooth(force: true)
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshBluetooth() }
        }
    }

    func stop() {
        directorySource?.cancel()
        directorySource = nil
        progressTimer?.invalidate()
        progressTimer = nil
        batteryTimer?.invalidate()
        batteryTimer = nil
        completionClearTimer?.invalidate()
        completionClearTimer = nil
        started = false
    }

    func refreshAll() {
        scanDownloads()
        refreshBluetooth(force: true)
    }

    func openDownloads() {
        NSWorkspace.shared.open(downloadsURL)
    }

    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Downloads

    private func startDownloadsWatcher() {
        let descriptor = open(downloadsURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Self.log.error("Unable to watch Downloads at \(self.downloadsURL.path, privacy: .public)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scanDownloads() }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        directorySource = source
    }

    private func scanDownloads() {
        let previous = downloads
        let previousCompletion = recentDownloadCompleted
        let current = Self.scanDownloadEntries(in: downloadsURL)
        downloads = current

        if hasScannedDownloads, !previous.isEmpty {
            let currentIDs = Set(current.map(\.id))
            if let finished = previous.first(where: { !currentIDs.contains($0.id) }) {
                recentDownloadCompleted = finished.name
                completionClearTimer?.invalidate()
                completionClearTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.recentDownloadCompleted = nil
                        AppleCompanionPublisher.shared.notifyDirty()
                    }
                }
            }
        }
        hasScannedDownloads = true
        updateProgressTimer()
        if current != previous || recentDownloadCompleted != previousCompletion {
            AppleCompanionPublisher.shared.notifyDirty()
        }
    }

    private func updateProgressTimer() {
        if downloads.isEmpty {
            progressTimer?.invalidate()
            progressTimer = nil
        } else if progressTimer == nil {
            progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.scanDownloads() }
            }
        }
    }

    nonisolated static func scanDownloadEntries(in directory: URL) -> [DownloadInfo] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard partialExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let values = try? url.resourceValues(forKeys: keys)
            let isDirectory = values?.isDirectory == true
            let metadata = isDirectory ? progressMetadata(in: url) : nil
            let measuredBytes = isDirectory
                ? directoryByteSize(url)
                : Int64(values?.fileSize ?? 0)
            let received = max(metadata?.received ?? 0, measuredBytes)
            let modified = values?.contentModificationDate ?? Date()
            let displayName = url.deletingPathExtension().lastPathComponent
            return DownloadInfo(
                id: url.path,
                url: url,
                name: displayName.isEmpty ? url.lastPathComponent : displayName,
                bytesReceived: received,
                totalBytes: metadata?.total,
                modifiedAt: modified
            )
        }
        .filter { Date().timeIntervalSince($0.modifiedAt) < 86_400 }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    nonisolated private static func directoryByteSize(_ directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    nonisolated private static func progressMetadata(in directory: URL) -> (received: Int64, total: Int64)? {
        let receivedKeys = Set([
            "downloadentryprogressbytessofar", "nsurlsessionresumebytesreceived",
            "bytesreceived", "bytessofar",
        ])
        let totalKeys = Set([
            "downloadentryprogresstotaltoload", "nsurlsessionresumebytesexpected",
            "totalbytes", "bytestotal",
        ])

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var received: Int64?
        var total: Int64?
        for case let url as URL in enumerator {
            guard ["plist", "downloadmetadata"].contains(url.pathExtension.lowercased()),
                  let data = try? Data(contentsOf: url),
                  let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
                continue
            }
            received = received ?? numericValue(in: object, matching: receivedKeys)
            total = total ?? numericValue(in: object, matching: totalKeys)
            if let received, let total, total > 0 { return (received, total) }
        }
        guard let received, let total, total > 0 else { return nil }
        return (received, total)
    }

    nonisolated private static func numericValue(in object: Any, matching keys: Set<String>) -> Int64? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if keys.contains(key.lowercased()), let number = integerValue(value) {
                    return number
                }
                if let nested = numericValue(in: value, matching: keys) { return nested }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let nested = numericValue(in: value, matching: keys) { return nested }
            }
        }
        return nil
    }

    // MARK: - Bluetooth and HID batteries

    func refreshBluetooth(force: Bool = false) {
        guard !isRefreshingBluetooth else { return }
        guard force || Date().timeIntervalSince(lastBluetoothRefresh) >= 30 else { return }
        isRefreshingBluetooth = true
        lastBluetoothRefresh = Date()

        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                let profilerData = PersonalUtilitiesModel.runProcess(
                    executable: "/usr/sbin/system_profiler",
                    arguments: ["SPBluetoothDataType", "-json"]
                )
                let hidData = PersonalUtilitiesModel.runProcess(
                    executable: "/usr/sbin/ioreg",
                    arguments: ["-a", "-r", "-c", "AppleDeviceManagementHIDEventService"]
                )
                let profiler = profilerData.map(PersonalUtilitiesModel.parseBluetoothProfiler) ?? []
                let hid = hidData.map(PersonalUtilitiesModel.parseHIDBatteries) ?? []
                return PersonalUtilitiesModel.mergeBatteries(profiler + hid)
            }.value

            guard let self else { return }
            let previous = self.deviceBatteries
            self.deviceBatteries = result
            self.bluetoothError = result.isEmpty ? "No battery readings from connected accessories" : nil
            self.isRefreshingBluetooth = false
            if result != previous {
                AppleCompanionPublisher.shared.notifyDirty()
            }
        }
    }

    nonisolated static func parseBluetoothProfiler(_ data: Data) -> [DeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]],
              let section = sections.first,
              let connected = section["device_connected"] as? [[String: Any]] else { return [] }

        return connected.flatMap { row -> [DeviceBattery] in
            row.compactMap { name, raw in
                guard let details = raw as? [String: Any] else { return nil }
                let levels = batteryLevels(from: details)
                guard !levels.isEmpty else { return nil }
                return DeviceBattery(id: name.lowercased(), name: name, levels: levels)
            }
        }
    }

    nonisolated static func parseHIDBatteries(_ data: Data) -> [DeviceBattery] {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let rows = object as? [[String: Any]] else { return [] }

        return rows.compactMap { row in
            guard let name = (row["Product"] ?? row["ProductName"]) as? String,
                  name != "Apple Internal Keyboard / Trackpad",
                  let percent = integerValue(row["BatteryPercent"] ?? row["BatteryLevel"] as Any),
                  (0...100).contains(percent) else { return nil }
            return DeviceBattery(
                id: name.lowercased(),
                name: name,
                levels: [BatteryLevel(id: "main", label: "Battery", percent: Int(percent))]
            )
        }
    }

    nonisolated private static func batteryLevels(from details: [String: Any]) -> [BatteryLevel] {
        let order = ["l": 0, "r": 1, "case": 2, "main": 3, "battery": 4]
        return details.compactMap { key, value -> BatteryLevel? in
            let normalized = key.lowercased()
            guard normalized.contains("battery") && normalized.contains("level"),
                  let parsed = integerValue(value), (0...100).contains(parsed) else { return nil }
            let label: String
            if normalized.contains("left") { label = "L" }
            else if normalized.contains("right") { label = "R" }
            else if normalized.contains("case") { label = "Case" }
            else { label = "Battery" }
            let id = label.lowercased()
            return BatteryLevel(id: id, label: label, percent: Int(parsed))
        }
        .reduce(into: [String: BatteryLevel]()) { result, level in result[level.id] = level }
        .values
        .sorted {
            (order[$0.id] ?? 99, $0.id) < (order[$1.id] ?? 99, $1.id)
        }
    }

    nonisolated private static func mergeBatteries(_ batteries: [DeviceBattery]) -> [DeviceBattery] {
        var merged: [String: DeviceBattery] = [:]
        for battery in batteries {
            if let existing = merged[battery.id], existing.levels.count >= battery.levels.count { continue }
            merged[battery.id] = battery
        }
        return merged.values.sorted {
            if $0.primaryPercent == $1.primaryPercent { return $0.name < $1.name }
            return $0.primaryPercent < $1.primaryPercent
        }
    }

    nonisolated private static func integerValue(_ value: Any) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("0x") {
            return Int64(trimmed.dropFirst(2), radix: 16)
        }
        let digits = trimmed.prefix { $0.isNumber || $0 == "-" }
        if let value = Int64(digits), !digits.isEmpty { return value }
        let runs = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted)
        return runs.first(where: { !$0.isEmpty }).flatMap(Int64.init)
    }

    nonisolated private static func runProcess(executable: String, arguments: [String]) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }
}
