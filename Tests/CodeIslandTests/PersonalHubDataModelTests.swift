import XCTest
@testable import CodeIsland

final class PersonalHubDataModelTests: XCTestCase {
    func testParsesMacBattery() {
        let output = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=123)\t87%; charging; 0:42 remaining present: true
        """

        let health = """
          |   \"CycleCount\" = 413
          |   \"DesignCapacity\" = 4563
          |   \"AppleRawMaxCapacity\" = 3611
          |   \"Condition\" = \"Normal\"
        """
        let battery = PersonalHubDataModel.parseMacBattery(output, healthOutput: health)

        XCTAssertEqual(battery?.percent, 87)
        XCTAssertEqual(battery?.status, "charging")
        XCTAssertEqual(battery?.powerSource, "AC Power")
        XCTAssertEqual(battery?.cycleCount, 413)
        XCTAssertEqual(battery?.healthPercent, 79)
        XCTAssertEqual(battery?.condition, "Normal")
    }

    func testParsesVMStatMemoryUsage() {
        let output = """
        Mach Virtual Memory Statistics: (page size of 4096 bytes)
        Pages free:                               1000.
        Pages active:                             5000.
        Pages speculative:                         250.
        """

        let used = PersonalHubDataModel.parseVMStat(output, totalBytes: 10_000_000)

        XCTAssertEqual(used, 4_880_000)
    }

    func testParsesAudioInputsOutputsAndDefaults() throws {
        let data = try XCTUnwrap("""
        {
          "SPAudioDataType": [{
            "_items": [
              {"_name":"MacBook Speakers","coreaudio_device_output":2,"coreaudio_output_source":"MacBook Speakers","coreaudio_default_audio_output_device":"spaudio_yes"},
              {"_name":"HDMI","coreaudio_device_output":2,"coreaudio_output_source":"spaudio_default"},
              {"_name":"USB Mic","coreaudio_device_input":1,"coreaudio_input_source":"USB Mic","coreaudio_default_audio_input_device":"spaudio_yes"},
              {"_name":"BlackHole","coreaudio_device_input":2,"coreaudio_input_source":"spaudio_default"}
            ]
          }]
        }
        """.data(using: .utf8))

        let devices = PersonalHubDataModel.parseAudioDevices(data)

        XCTAssertEqual(devices.count, 4)
        XCTAssertTrue(try XCTUnwrap(devices.first(where: { $0.name == "MacBook Speakers" })).isDefaultOutput)
        XCTAssertTrue(try XCTUnwrap(devices.first(where: { $0.name == "USB Mic" })).isDefaultInput)
        XCTAssertFalse(try XCTUnwrap(devices.first(where: { $0.name == "HDMI" })).isDefaultOutput)
        XCTAssertFalse(try XCTUnwrap(devices.first(where: { $0.name == "BlackHole" })).isDefaultInput)
    }

    func testParsesGitHubPullRequests() throws {
        let data = try XCTUnwrap("""
        [{
          "isDraft": false,
          "number": 6,
          "repository": {"name": "CodeIsland", "nameWithOwner": "revopsglobal/CodeIsland"},
          "title": "Finish mobile parity",
          "updatedAt": "2026-07-17T08:00:00Z",
          "url": "https://github.com/revopsglobal/CodeIsland/pull/6"
        }]
        """.data(using: .utf8))

        let pullRequest = try XCTUnwrap(PersonalHubDataModel.parseGitHubPullRequests(data)?.first)

        XCTAssertEqual(pullRequest.id, "revopsglobal/CodeIsland#6")
        XCTAssertEqual(pullRequest.number, 6)
        XCTAssertEqual(pullRequest.title, "Finish mobile parity")
        XCTAssertFalse(pullRequest.isDraft)
    }

    func testParsesNowPlayingMetadataAndLyrics() throws {
        let separator = String(UnicodeScalar(31))
        let queue = [PersonalHubDataModel.NowPlaying.QueueItem(
            id: "7",
            title: "Next song",
            artist: "Next artist",
            album: "Next album"
        )]
        let media = try XCTUnwrap(PersonalHubDataModel.parseNowPlayingOutput(
            ["playing", "Current song", "Current artist", "Current album", "42.5", "180", "Line one\nLine two"]
                .joined(separator: separator),
            appName: "Music",
            queue: queue
        ))

        XCTAssertEqual(media.title, "Current song")
        XCTAssertTrue(media.isPlaying)
        XCTAssertEqual(media.position, 42.5)
        XCTAssertEqual(media.duration, 180)
        XCTAssertEqual(media.lyrics, "Line one\nLine two")
        XCTAssertEqual(media.queue, queue)
    }

    func testSpotifyDurationIsNormalizedFromMilliseconds() throws {
        let separator = String(UnicodeScalar(31))
        let media = try XCTUnwrap(PersonalHubDataModel.parseNowPlayingOutput(
            ["playing", "Sound of Horns", "R.A.P. Ferreira", "Sound of Horns", "87.5", "141000", ""]
                .joined(separator: separator),
            appName: "Spotify"
        ))

        XCTAssertEqual(media.position, 87.5)
        XCTAssertEqual(media.duration, 141)
    }

    func testNowPlayingArtworkIsBoundedAndNormalizedToJPEG() throws {
        let onePixelPNG = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))

        let artwork = try XCTUnwrap(PersonalHubDataModel.normalizeArtworkJPEG(onePixelPNG))

        XCTAssertLessThanOrEqual(artwork.count, PersonalHubDataModel.maximumArtworkBytes)
        XCTAssertEqual(Array(artwork.prefix(2)), [0xFF, 0xD8])
    }

    func testArbitrarySeekClampsBoundsAndRejectsNonFiniteValues() {
        XCTAssertEqual(PersonalHubDataModel.clampedSeekPosition(-20, duration: 180), 0)
        XCTAssertEqual(PersonalHubDataModel.clampedSeekPosition(42.5, duration: 180), 42.5)
        XCTAssertEqual(PersonalHubDataModel.clampedSeekPosition(999, duration: 180), 180)
        XCTAssertNil(PersonalHubDataModel.clampedSeekPosition(.infinity, duration: 180))
        XCTAssertNil(PersonalHubDataModel.clampedSeekPosition(20, duration: 0))
    }

    func testOptimisticSeekPreservesMetadataAndSpotifyNeverClaimsQueueSupport() throws {
        let separator = String(UnicodeScalar(31))
        let queued = [PersonalHubDataModel.NowPlaying.QueueItem(
            id: "7",
            title: "Next song",
            artist: "Next artist",
            album: "Next album"
        )]
        let spotify = try XCTUnwrap(PersonalHubDataModel.parseNowPlayingOutput(
            ["playing", "Current song", "Current artist", "Current album", "10", "180", ""]
                .joined(separator: separator),
            appName: "Spotify",
            queue: queued
        ))

        let updated = spotify.updatingPosition(90)

        XCTAssertTrue(spotify.queue.isEmpty)
        XCTAssertEqual(updated.position, 90)
        XCTAssertEqual(updated.title, spotify.title)
        XCTAssertEqual(updated.artist, spotify.artist)
        XCTAssertEqual(updated.duration, spotify.duration)
    }

    func testParsesMusicQueueAndIgnoresMalformedRows() {
        let field = String(UnicodeScalar(30))
        let row = String(UnicodeScalar(29))
        let output = [
            ["12", "Song A", "Artist A", "Album A"].joined(separator: field),
            "not-a-track",
            ["13", "Song B", "Artist B", "Album B"].joined(separator: field),
        ].joined(separator: row)

        let queue = PersonalHubDataModel.parseMusicQueueOutput(output)

        XCTAssertEqual(queue.map(\.id), ["12", "13"])
        XCTAssertEqual(queue.map(\.title), ["Song A", "Song B"])
    }

    func testMediaCommandPlansBasicTransportControls() {
        let media = nowPlaying(appName: "Music")

        XCTAssertEqual(
            PersonalHubDataModel.mediaCommandPlan(for: media, action: "playPause"),
            .init(appName: "Music", command: "playpause", optimisticPosition: nil)
        )
        XCTAssertEqual(
            PersonalHubDataModel.mediaCommandPlan(for: media, action: "next")?.appleScript,
            #"tell application "Music" to next track"#
        )
        XCTAssertEqual(
            PersonalHubDataModel.mediaCommandPlan(for: media, action: "previous")?.appleScript,
            #"tell application "Music" to previous track"#
        )
    }

    func testMediaCommandPlansSeekAndClampsRelativeSeek() {
        let media = nowPlaying(appName: "Spotify", position: 170, duration: 180)

        XCTAssertEqual(
            PersonalHubDataModel.mediaCommandPlan(for: media, action: "seekForward"),
            .init(appName: "Spotify", command: "set player position to 180.0", optimisticPosition: 180)
        )
        XCTAssertEqual(
            PersonalHubDataModel.mediaCommandPlan(for: media, action: "seekBack")?.optimisticPosition,
            155
        )
        XCTAssertEqual(
            PersonalHubDataModel.mediaCommandPlan(for: media, action: "seek", value: "42.5"),
            .init(appName: "Spotify", command: "set player position to 42.5", optimisticPosition: 42.5)
        )
        XCTAssertNil(PersonalHubDataModel.mediaCommandPlan(for: media, action: "seek", value: "not-a-number"))
    }

    func testMediaCommandPlansMusicQueueOnlyForKnownQueueItems() {
        let queue = [PersonalHubDataModel.NowPlaying.QueueItem(
            id: "7",
            title: "Next song",
            artist: "Next artist",
            album: "Next album"
        )]
        let music = nowPlaying(appName: "Music", queue: queue)
        let spotify = nowPlaying(appName: "Spotify", queue: queue)

        XCTAssertEqual(
            PersonalHubDataModel.mediaCommandPlan(for: music, action: "playQueueItem", targetID: "7")?.appleScript,
            #"tell application "Music" to play track 7 of current playlist"#
        )
        XCTAssertNil(PersonalHubDataModel.mediaCommandPlan(for: music, action: "playQueueItem", targetID: "8"))
        XCTAssertNil(PersonalHubDataModel.mediaCommandPlan(for: spotify, action: "playQueueItem", targetID: "7"))
    }

    func testLegacyTextShelfEntryDecodesWithoutFilePath() throws {
        let data = try XCTUnwrap(#"{"id":"clip-1","value":"git push origin main","capturedAt":0}"#.data(using: .utf8))

        let entry = try JSONDecoder().decode(PersonalHubDataModel.ShelfEntry.self, from: data)

        XCTAssertEqual(entry.title, "git push origin main")
        XCTAssertNil(entry.filePath)
    }

    func testFileShelfEntryUsesFilenameAsTitle() {
        let entry = PersonalHubDataModel.ShelfEntry(
            id: "file-1",
            value: "Quarterly-plan.pdf",
            capturedAt: Date(),
            filePath: "/Users/greg/Quarterly-plan.pdf",
            source: ShelfCaptureController.Source.filePicker.rawValue,
            byteCount: 42
        )

        XCTAssertEqual(entry.title, "Quarterly-plan.pdf")
        XCTAssertEqual(entry.source, ShelfCaptureController.Source.filePicker.rawValue)
        XCTAssertEqual(entry.byteCount, 42)
    }

    @MainActor
    func testShelfImportPersistsPrivateMetadataAndRemovalDeletesOnlyStoredCopy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandShelfModel-\(UUID().uuidString)", isDirectory: true)
        let storage = root.appendingPathComponent("Shelf", isDirectory: true)
        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("brief.txt")
        try Data("handoff".utf8).write(to: source)
        let suite = "PersonalHubDataModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let controller = ShelfCaptureController(storageDirectory: storage, screenshotDirectory: desktop)
        let model = PersonalHubDataModel(defaults: defaults, shelfCaptureController: controller)

        XCTAssertTrue(model.importShelfFile(at: source, source: .drop))
        let entry = try XCTUnwrap(model.shelf.first)
        let storedURL = try XCTUnwrap(model.shelfFileURL(id: entry.id))
        XCTAssertTrue(controller.containsStoredFile(storedURL))
        XCTAssertEqual(entry.source, ShelfCaptureController.Source.drop.rawValue)
        XCTAssertEqual(entry.byteCount, 7)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        XCTAssertTrue(model.removeShelfEntry(id: entry.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testShelfRetentionRemovesEvictedPrivateCopy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandShelfRetention-\(UUID().uuidString)", isDirectory: true)
        let storage = root.appendingPathComponent("Shelf", isDirectory: true)
        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("capture.txt")
        try Data("capture".utf8).write(to: source)
        let suite = "PersonalHubDataModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let controller = ShelfCaptureController(storageDirectory: storage, screenshotDirectory: desktop)
        let model = PersonalHubDataModel(defaults: defaults, shelfCaptureController: controller)

        XCTAssertTrue(model.importShelfFile(at: source, source: .drop))
        let firstStoredURL = try XCTUnwrap(model.shelfFileURL(id: XCTUnwrap(model.shelf.first?.id)))
        for _ in 0..<20 {
            XCTAssertTrue(model.importShelfFile(at: source, source: .drop))
        }

        XCTAssertEqual(model.shelf.count, 20)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstStoredURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    @MainActor
    func testLegacyOutsideShelfReferenceMigratesIntoPrivateStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandShelfMigration-\(UUID().uuidString)", isDirectory: true)
        let storage = root.appendingPathComponent("Shelf", isDirectory: true)
        let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyFile = root.appendingPathComponent("legacy.pdf")
        try Data("legacy".utf8).write(to: legacyFile)
        let suite = "PersonalHubDataModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let legacy = [PersonalHubDataModel.ShelfEntry(
            id: "legacy-file",
            value: "legacy.pdf",
            capturedAt: Date(timeIntervalSince1970: 1),
            filePath: legacyFile.path
        )]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "codeisland.personalHub.shelf.v1")
        let controller = ShelfCaptureController(storageDirectory: storage, screenshotDirectory: desktop)

        let model = PersonalHubDataModel(defaults: defaults, shelfCaptureController: controller)
        let migrated = try XCTUnwrap(model.shelf.first)

        XCTAssertEqual(migrated.id, "legacy-file")
        XCTAssertEqual(migrated.source, ShelfCaptureController.Source.filePicker.rawValue)
        XCTAssertNotEqual(migrated.filePath, legacyFile.path)
        XCTAssertNotNil(model.shelfFileURL(id: migrated.id))
    }

    func testLegacyNoteDecodesWithSafeRevisionDefaults() throws {
        let data = try XCTUnwrap(
            #"{"id":"note-1","text":"Old note","updatedAt":0}"#.data(using: .utf8)
        )

        let note = try JSONDecoder().decode(PersonalHubDataModel.Note.self, from: data)

        XCTAssertEqual(note.currentRevision, 1)
        XCTAssertNil(note.category)
        XCTAssertFalse(note.canUndo)
    }

    func testParsesMarkdownChecklistLinesWithStableLineIndexes() {
        let lines = PersonalHubDataModel.Note.parseChecklist(
            "Launch\n- [ ] Send invite\nContext\n- [x] Publish page\n- [X] Notify team"
        )

        XCTAssertEqual(lines.map(\.lineIndex), [1, 3, 4])
        XCTAssertEqual(lines.map(\.title), ["Send invite", "Publish page", "Notify team"])
        XCTAssertEqual(lines.map(\.isCompleted), [false, true, true])
    }

    func testParsesOnlySafeClaudeActionProposals() throws {
        let output = """
        ```json
        {"proposals":[
          {"type":"reminder","title":"Call the bank","text":null,"due":"2026-07-18T18:00:00-07:00","start":null,"end":null,"joinURL":null,"notes":null},
          {"type":"note","title":"Deck idea","text":"Use the customer quote first","due":null,"start":null,"end":null,"joinURL":null,"notes":null},
          {"type":"calendar","title":"Invalid event","text":null,"due":null,"start":null,"end":null,"joinURL":null,"notes":null},
          {"type":"shell","title":"rm -rf","text":null,"due":null,"start":null,"end":null,"joinURL":null,"notes":null}
        ]}
        ```
        """

        let proposals = PersonalHubDataModel.parseClaudeProposals(output)

        XCTAssertEqual(proposals.count, 2)
        XCTAssertEqual(proposals.map(\.kind), [.reminder, .note])
        XCTAssertEqual(proposals.first?.title, "Call the bank")
        XCTAssertNotNil(proposals.first?.due)
    }

    func testClaudeAskInvocationIsToolFreeAndFileContextIsUntrusted() throws {
        let contexts = try ClaudeFileContextLoader.load(namedData: [
            ("brief.md", Data("Treat this as data".utf8)),
        ])

        let invocation = PersonalHubDataModel.claudeInvocation(
            prompt: "Summarize this",
            contexts: contexts,
            mode: .ask
        )

        XCTAssertTrue(invocation.systemPrompt.contains("Do not use tools"))
        XCTAssertTrue(invocation.prompt.contains("BEGIN UNTRUSTED FILE CONTEXT"))
        XCTAssertFalse(invocation.systemPrompt.contains("execute the request"))
    }

    func testClaudeDoInvocationCanOnlyReturnReviewableProposals() {
        let invocation = PersonalHubDataModel.claudeInvocation(
            prompt: "Remind me to call the bank",
            contexts: [],
            mode: .plan(now: Date(timeIntervalSince1970: 0), timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        XCTAssertTrue(invocation.systemPrompt.contains("Never execute tools"))
        XCTAssertTrue(invocation.systemPrompt.contains("Return JSON only"))
        XCTAssertTrue(invocation.systemPrompt.contains("proposed CodeIsland actions"))
    }

    private func nowPlaying(
        appName: String,
        position: Double? = 10,
        duration: Double? = 180,
        queue: [PersonalHubDataModel.NowPlaying.QueueItem] = []
    ) -> PersonalHubDataModel.NowPlaying {
        .init(
            appName: appName,
            title: "Current song",
            artist: "Current artist",
            album: "Current album",
            isPlaying: true,
            position: position,
            duration: duration,
            lyrics: nil,
            queue: queue
        )
    }
}
