import XCTest

final class EnglishCompanionRegressionTests: XCTestCase {
    func testCompanionAndDynamicIslandProductionSourcesContainNoCJKText() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let roots = [
            repo.appendingPathComponent("ios/CodeIslandCompanion/CodeIslandCompanion"),
            repo.appendingPathComponent("ios/CodeIslandCompanion/CodeIslandCompanionWidget"),
            repo.appendingPathComponent("ios/CodeIslandCompanion/CodeIslandCompanionShared"),
        ]
        let files = roots.flatMap { root -> [URL] in
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey]
            ) else { return [] }
            return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
        XCTAssertFalse(files.isEmpty, "Expected iOS companion production sources")

        let cjk = try NSRegularExpression(pattern: #"[\u3400-\u9FFF]"#)
        let offenders = try files.compactMap { file -> String? in
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            return cjk.firstMatch(in: text, range: range) == nil
                ? nil
                : file.path.replacingOccurrences(of: repo.path + "/", with: "")
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "English personal build contains CJK text in: \(offenders.joined(separator: ", "))"
        )
    }

    func testMacCompanionRuntimeErrorsDoNotBypassLocalization() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            "Sources/CodeIsland/AppleCompanionBluetoothPeripheral.swift",
            "Sources/CodeIsland/SoundManager.swift",
        ]
        let cjk = try NSRegularExpression(pattern: #"[\u3400-\u9FFF]"#)
        for relativePath in files {
            let text = try String(
                contentsOf: repo.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            XCTAssertNil(
                cjk.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                "Hard-coded CJK text bypasses the English preference in \(relativePath)"
            )
        }
    }
}
