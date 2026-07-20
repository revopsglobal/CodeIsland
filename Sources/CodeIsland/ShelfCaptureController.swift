import AppKit
import Combine
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

private struct ShelfScreenshotCandidate: Sendable {
    let url: URL
    let signature: String
}

/// Foundation documents FileManager's shared methods as thread-safe. The box
/// makes that contract explicit when the watcher moves directory reads away
/// from the main actor.
private final class ShelfFileManagerBox: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}

/// Owns every file that appears in Shelf. User-selected files, dropped files,
/// screenshots, and recordings are copied into one private Application Support
/// directory before they are exposed to Buddy or the web client.
@MainActor
final class ShelfCaptureController: NSObject, ObservableObject {
    enum Source: String, Codable, Equatable, Sendable {
        case clipboardFile
        case filePicker
        case drop
        case automaticScreenshot
        case selection
        case recording
    }

    struct StoredFile: Equatable, Sendable {
        let url: URL
        let source: Source
        let capturedAt: Date
        let byteCount: Int64
    }

    enum CaptureError: LocalizedError, Equatable {
        case invalidFile
        case unsafePath
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "Choose a regular file that is still available."
            case .unsafePath:
                return "Shelf refused a file outside its private storage."
            case .unavailable(let message):
                return message
            }
        }
    }

    @Published private(set) var isPresentingPicker = false
    @Published private(set) var isRecording = false
    @Published private(set) var lastError: String?

    var onStoredFile: ((StoredFile) -> Void)?

    let storageDirectory: URL
    private let screenshotDirectory: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let screenshotCandidateLoader: @Sendable () -> [URL]
    private var screenshotTimer: Timer?
    private var screenshotScanInFlight = false
    private var screenshotWatchGeneration = 0
    private var seenScreenshotSignatures: Set<String> = []
    private var pendingCaptureSource: Source?
    private var pickerObserverRegistered = false

    private var recordingSessionBox: AnyObject?

    @available(macOS 15.0, *)
    private var recordingSession: RecordingSession? {
        get { recordingSessionBox as? RecordingSession }
        set { recordingSessionBox = newValue }
    }

    init(
        storageDirectory: URL? = nil,
        screenshotDirectory: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        screenshotCandidateLoader: (@Sendable () -> [URL])? = nil
    ) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let resolvedScreenshotDirectory = (screenshotDirectory
            ?? fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)).standardizedFileURL
        self.storageDirectory = (storageDirectory
            ?? appSupport.appendingPathComponent("CodeIsland/Shelf", isDirectory: true)).standardizedFileURL
        self.screenshotDirectory = resolvedScreenshotDirectory
        self.fileManager = fileManager
        self.now = now
        let backgroundFileManager = ShelfFileManagerBox(fileManager)
        self.screenshotCandidateLoader = screenshotCandidateLoader ?? {
            Self.screenshotCandidates(
                in: resolvedScreenshotDirectory,
                fileManager: backgroundFileManager.value
            )
        }
        super.init()
    }

    deinit {
        screenshotTimer?.invalidate()
        if #available(macOS 14.0, *), pickerObserverRegistered {
            SCContentSharingPicker.shared.remove(self)
        }
    }

    @discardableResult
    func importFile(
        at sourceURL: URL,
        source: Source,
        capturedAt: Date? = nil
    ) throws -> StoredFile {
        let sourceURL = sourceURL.standardizedFileURL
        let sourceValues = try? sourceURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard sourceValues?.isRegularFile == true,
              sourceValues?.isSymbolicLink != true else {
            throw CaptureError.invalidFile
        }

        try ensureStorageDirectory()
        let destination = collisionSafeDestination(for: sourceURL.lastPathComponent)
        try fileManager.copyItem(at: sourceURL, to: destination)
        do {
            return try storedFile(at: destination, source: source, capturedAt: capturedAt ?? now())
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func containsStoredFile(_ url: URL) -> Bool {
        validatedStoredFileURL(path: url.path) != nil
    }

    func validatedStoredFileURL(path: String) -> URL? {
        let candidate = URL(fileURLWithPath: path).standardizedFileURL
        guard isDescendant(candidate, of: storageDirectory) else { return nil }
        let values = try? candidate.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return nil }
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(resolved, of: storageDirectory.resolvingSymlinksInPath()) else { return nil }
        return candidate
    }

    func removeStoredFile(path: String) throws {
        guard let url = validatedStoredFileURL(path: path) else { throw CaptureError.unsafePath }
        try fileManager.removeItem(at: url)
    }

    /// Marks the current Desktop screenshots as already known. This makes
    /// automatic capture forward-only on each launch rather than reimporting a
    /// user's entire screenshot history.
    func primeScreenshotDirectory() {
        seenScreenshotSignatures = Set(screenshotCandidates().map(screenshotSignature))
    }

    @discardableResult
    func scanForNewScreenshots() -> [StoredFile] {
        var stored: [StoredFile] = []
        for candidate in screenshotCandidates() {
            let signature = screenshotSignature(candidate)
            guard !seenScreenshotSignatures.contains(signature) else { continue }
            seenScreenshotSignatures.insert(signature)
            guard let imported = try? importFile(at: candidate, source: .automaticScreenshot) else { continue }
            stored.append(imported)
            onStoredFile?(imported)
        }
        return stored
    }

    func startWatchingScreenshots() {
        guard screenshotTimer == nil else { return }
        screenshotWatchGeneration += 1
        let generation = screenshotWatchGeneration
        screenshotTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleBackgroundScreenshotScan(
                    importingNewFiles: true,
                    generation: generation
                )
            }
        }
        scheduleBackgroundScreenshotScan(importingNewFiles: false, generation: generation)
    }

    func stopWatchingScreenshots() {
        screenshotTimer?.invalidate()
        screenshotTimer = nil
        screenshotWatchGeneration += 1
    }

    func presentSelectionCapture() {
        presentPicker(for: .selection)
    }

    func presentRecordingCapture() {
        guard #available(macOS 15.0, *) else {
            lastError = "Screen recording requires macOS 15 or later."
            return
        }
        presentPicker(for: .recording)
    }

    func stopRecording() {
        guard #available(macOS 15.0, *), let session = recordingSession else { return }
        isRecording = false
        Task {
            do {
                try session.stream.removeRecordingOutput(session.output)
                try await session.stream.stopCapture()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Called by capture implementations after a complete file has been
    /// atomically written inside Shelf. It is intentionally internal so the
    /// lifecycle and exactly-once callback can be regression tested.
    @discardableResult
    func completeCapture(at url: URL, source: Source) throws -> StoredFile {
        let stored = try storedFile(at: url, source: source, capturedAt: now())
        onStoredFile?(stored)
        return stored
    }

    private func presentPicker(for source: Source) {
        guard [.selection, .recording].contains(source) else { return }
        lastError = nil
        pendingCaptureSource = source
        isPresentingPicker = true
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow, .singleDisplay, .singleApplication]
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier].compactMap { $0 }
        configuration.allowsChangingSelectedContent = false
        let picker = SCContentSharingPicker.shared
        picker.configuration = configuration
        if !pickerObserverRegistered {
            picker.add(self)
            pickerObserverRegistered = true
        }
        picker.isActive = true
        picker.present()
    }

    private func handleSelectedFilter(_ filter: SCContentFilter) {
        let source = pendingCaptureSource
        pendingCaptureSource = nil
        isPresentingPicker = false
        SCContentSharingPicker.shared.isActive = false
        switch source {
        case .selection:
            captureSelection(filter: filter)
        case .recording:
            if #available(macOS 15.0, *) {
                startRecording(filter: filter)
            }
        default:
            break
        }
    }

    private func captureSelection(filter: SCContentFilter) {
        let configuration = streamConfiguration(for: filter)
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { [weak self] image, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                guard let image else {
                    self.lastError = "The selected content did not produce an image."
                    return
                }
                do {
                    try self.ensureStorageDirectory()
                    let url = self.collisionSafeDestination(for: self.captureFilename(prefix: "Selection", extension: "png"))
                    try self.writePNG(image, to: url)
                    try self.completeCapture(at: url, source: .selection)
                } catch {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    @available(macOS 15.0, *)
    private func startRecording(filter: SCContentFilter) {
        do {
            try ensureStorageDirectory()
            let outputURL = collisionSafeDestination(for: captureFilename(prefix: "Recording", extension: "mp4"))
            let stream = SCStream(filter: filter, configuration: streamConfiguration(for: filter), delegate: self)
            let outputConfiguration = SCRecordingOutputConfiguration()
            outputConfiguration.outputURL = outputURL
            let output = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
            try stream.addRecordingOutput(output)
            recordingSession = RecordingSession(stream: stream, output: output, url: outputURL)
            Task {
                do {
                    try await stream.startCapture()
                } catch {
                    try? self.fileManager.removeItem(at: outputURL)
                    recordingSession = nil
                    isRecording = false
                    lastError = error.localizedDescription
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func streamConfiguration(for filter: SCContentFilter) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let scale = max(CGFloat(filter.pointPixelScale), 1)
        configuration.width = max(1, min(Int(filter.contentRect.width * scale), 7_680))
        configuration.height = max(1, min(Int(filter.contentRect.height * scale), 4_320))
        configuration.showsCursor = true
        configuration.queueDepth = 3
        return configuration
    }

    private func storedFile(at url: URL, source: Source, capturedAt: Date) throws -> StoredFile {
        guard let safeURL = validatedStoredFileURL(path: url.path) else { throw CaptureError.unsafePath }
        let values = try safeURL.resourceValues(forKeys: [.fileSizeKey])
        return StoredFile(
            url: safeURL,
            source: source,
            capturedAt: capturedAt,
            byteCount: Int64(values.fileSize ?? 0)
        )
    }

    private func ensureStorageDirectory() throws {
        try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    private func collisionSafeDestination(for proposedName: String) -> URL {
        let safeName = sanitizedFilename(proposedName)
        let original = storageDirectory.appendingPathComponent(safeName, isDirectory: false)
        guard fileManager.fileExists(atPath: original.path) else { return original }
        let name = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        var suffix = 2
        while true {
            let candidateName = ext.isEmpty ? "\(name) \(suffix)" : "\(name) \(suffix).\(ext)"
            let candidate = storageDirectory.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }

    private func sanitizedFilename(_ value: String) -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Shelf Item" : String(cleaned.prefix(180))
    }

    private func captureFilename(prefix: String, extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: now())).\(ext)"
    }

    private func scheduleBackgroundScreenshotScan(
        importingNewFiles: Bool,
        generation: Int
    ) {
        guard !screenshotScanInFlight else { return }
        screenshotScanInFlight = true
        let loader = screenshotCandidateLoader
        let scanTask = Task.detached(priority: .utility) {
            loader().map { url in
                ShelfScreenshotCandidate(
                    url: url,
                    signature: Self.screenshotSignature(for: url)
                )
            }
        }

        Task { @MainActor [weak self] in
            let candidates = await scanTask.value
            guard let self else { return }
            self.screenshotScanInFlight = false
            guard self.screenshotTimer != nil,
                  self.screenshotWatchGeneration == generation else { return }

            if !importingNewFiles {
                self.seenScreenshotSignatures = Set(candidates.map(\.signature))
                return
            }

            for candidate in candidates {
                guard !self.seenScreenshotSignatures.contains(candidate.signature) else { continue }
                self.seenScreenshotSignatures.insert(candidate.signature)
                guard let imported = try? self.importFile(
                    at: candidate.url,
                    source: .automaticScreenshot
                ) else { continue }
                self.onStoredFile?(imported)
            }
        }
    }

    private func screenshotCandidates() -> [URL] {
        screenshotCandidateLoader()
    }

    nonisolated private static func screenshotCandidates(
        in screenshotDirectory: URL,
        fileManager: FileManager
    ) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: screenshotDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { url in
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()
            let supported = ["png", "jpg", "jpeg", "heic"].contains(ext)
            return supported && (name.hasPrefix("screenshot ") || name.hasPrefix("screen shot "))
        }
        .sorted { $0.path < $1.path }
    }

    private func screenshotSignature(_ url: URL) -> String {
        Self.screenshotSignature(for: url)
    }

    nonisolated private static func screenshotSignature(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(url.standardizedFileURL.path)#\(modified)#\(values?.fileSize ?? 0)"
    }

    private func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let directoryComponents = directory.standardizedFileURL.pathComponents
        return candidateComponents.count > directoryComponents.count
            && candidateComponents.starts(with: directoryComponents)
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.unavailable("Shelf could not create the screenshot file.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.unavailable("Shelf could not finish the screenshot file.")
        }
    }
}

@available(macOS 15.0, *)
private final class RecordingSession {
    let stream: SCStream
    let output: SCRecordingOutput
    let url: URL

    init(stream: SCStream, output: SCRecordingOutput, url: URL) {
        self.stream = stream
        self.output = output
        self.url = url
    }
}

extension ShelfCaptureController: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            self?.pendingCaptureSource = nil
            self?.isPresentingPicker = false
            picker.isActive = false
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor [weak self] in self?.handleSelectedFilter(filter) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor [weak self] in
            self?.pendingCaptureSource = nil
            self?.isPresentingPicker = false
            self?.lastError = error.localizedDescription
            SCContentSharingPicker.shared.isActive = false
        }
    }
}

@available(macOS 15.0, *)
extension ShelfCaptureController: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in self?.isRecording = true }
    }

    nonisolated func recordingOutput(
        _ recordingOutput: SCRecordingOutput,
        didFailWithError error: any Error
    ) {
        Task { @MainActor [weak self] in
            if let url = self?.recordingSession?.url {
                try? self?.fileManager.removeItem(at: url)
            }
            self?.recordingSession = nil
            self?.isRecording = false
            self?.lastError = error.localizedDescription
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self, let session = self.recordingSession else { return }
            self.recordingSession = nil
            self.isRecording = false
            do {
                try self.completeCapture(at: session.url, source: .recording)
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }
}

@available(macOS 15.0, *)
extension ShelfCaptureController: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, self.recordingSession?.stream === stream else { return }
            if let url = self.recordingSession?.url {
                try? self.fileManager.removeItem(at: url)
            }
            self.recordingSession = nil
            self.isRecording = false
            self.lastError = error.localizedDescription
        }
    }
}
