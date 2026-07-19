import CryptoKit
import Foundation
import ImageIO
import XCTest

final class AppIconAssetTests: XCTestCase {
    private var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private var iconDirectory: URL {
        repositoryRoot
            .appendingPathComponent("ios/CodeIslandCompanion/CodeIslandCompanion/Assets.xcassets/AppIcon.appiconset")
    }

    func testCatalogDeclaresLightDarkAndTintedUniversalIcons() throws {
        let data = try Data(contentsOf: iconDirectory.appendingPathComponent("Contents.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let images = try XCTUnwrap(object["images"] as? [[String: Any]])
        let universal = images.filter {
            $0["idiom"] as? String == "universal" &&
                $0["platform"] as? String == "ios" &&
                $0["size"] as? String == "1024x1024"
        }

        XCTAssertEqual(universal.count, 3)
        XCTAssertEqual(Set(universal.compactMap { $0["filename"] as? String }), [
            "AppIcon-Light-1024.png",
            "AppIcon-Dark-1024.png",
            "AppIcon-Tinted-1024.png",
        ])

        let appearanceValues = universal.compactMap { image -> String? in
            guard let appearances = image["appearances"] as? [[String: String]] else {
                return "light"
            }
            return appearances.first(where: { $0["appearance"] == "luminosity" })?["value"]
        }
        XCTAssertEqual(Set(appearanceValues), ["light", "dark", "tinted"])
    }

    func testMastersAreOpaque1024SquarePNGs() throws {
        for name in ["AppIcon-Light-1024.png", "AppIcon-Dark-1024.png", "AppIcon-Tinted-1024.png"] {
            let url = iconDirectory.appendingPathComponent(name)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), name)
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                name
            )
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1024, name)
            XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 1024, name)
            if let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool {
                XCTAssertFalse(hasAlpha, name)
            }
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), name)
            XCTAssertTrue(
                [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo),
                "\(name) uses alpha info \(image.alphaInfo)"
            )
        }
    }

    func testDeterministicSourcesAndManifestMatchGeneratedMasters() throws {
        let sourceDirectory = repositoryRoot.appendingPathComponent("Design/AppIcon")
        for name in ["paired-signal-light.svg", "paired-signal-dark.svg", "paired-signal-tinted.svg"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent(name).path), name)
        }

        let manifestData = try Data(contentsOf: sourceDirectory.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: String])
        for name in ["AppIcon-Light-1024.png", "AppIcon-Dark-1024.png", "AppIcon-Tinted-1024.png"] {
            let data = try Data(contentsOf: iconDirectory.appendingPathComponent(name))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(manifest[name], hash, name)
        }
    }

    func testLegacyNotificationAndHomeScreenSizesExist() throws {
        let legacyDirectory = repositoryRoot.appendingPathComponent("Design/AppIcon/Legacy")
        let expected = [
            "Icon-20x20@1x.png": 20,
            "Icon-20x20@2x.png": 40,
            "Icon-20x20@3x.png": 60,
            "Icon-29x29@1x.png": 29,
            "Icon-29x29@2x.png": 58,
            "Icon-29x29@3x.png": 87,
            "Icon-40x40@1x.png": 40,
            "Icon-40x40@2x.png": 80,
            "Icon-40x40@3x.png": 120,
            "Icon-60x60@2x.png": 120,
            "Icon-60x60@3x.png": 180,
            "Icon-76x76@1x.png": 76,
            "Icon-76x76@2x.png": 152,
            "Icon-83.5x83.5@2x.png": 167,
        ]

        for (name, pixels) in expected {
            let url = legacyDirectory.appendingPathComponent(name)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), name)
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                name
            )
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, pixels, name)
            XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, pixels, name)
        }
    }
}
