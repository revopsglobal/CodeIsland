import Foundation
import XCTest
@testable import CodeIsland

final class RemoteWorkspaceCatalogTests: XCTestCase {
    func testCanonicalizesSymlinkAndKeepsOneStableWorkspaceIdentity() throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let project = try fixture.directory("work/harned/ob1-app")
        let compatibility = fixture.url("work/ob1-app")
        try FileManager.default.createSymbolicLink(at: compatibility, withDestinationURL: project)

        let catalog = RemoteWorkspaceCatalog(
            allowedRoots: [fixture.url("work")],
            candidates: [
                .init(url: compatibility, source: .recentSession, lastUsedAt: Date(timeIntervalSince1970: 200)),
                .init(url: project, source: .saved, lastUsedAt: Date(timeIntervalSince1970: 100)),
            ],
            homeDirectory: fixture.url("home")
        )

        XCTAssertEqual(catalog.entries.count, 1)
        let entry = try XCTUnwrap(catalog.entries.first)
        XCTAssertEqual(entry.url, project.resolvingSymlinksInPath().standardizedFileURL)
        XCTAssertEqual(catalog.resolve(id: entry.id), entry.url)

        let restarted = RemoteWorkspaceCatalog(
            allowedRoots: [fixture.url("work")],
            candidates: [.init(url: project, source: .saved)],
            homeDirectory: fixture.url("home")
        )
        XCTAssertEqual(restarted.entries.first?.id, entry.id)
    }

    func testRecentSessionRootsRankAheadOfOlderSavedRoots() throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let recent = try fixture.directory("work/recent")
        let saved = try fixture.directory("work/saved")

        let catalog = RemoteWorkspaceCatalog(
            allowedRoots: [fixture.url("work")],
            candidates: [
                .init(url: saved, source: .saved, lastUsedAt: Date(timeIntervalSince1970: 500)),
                .init(url: recent, source: .recentSession, lastUsedAt: Date(timeIntervalSince1970: 100)),
            ],
            homeDirectory: fixture.url("home")
        )

        XCTAssertEqual(catalog.entries.map(\.name), ["recent", "saved"])
    }

    func testRejectsUnsafeMissingAndOutOfBoundaryCandidates() throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let home = try fixture.directory("home")
        let allowed = try fixture.directory("work")
        let valid = try fixture.directory("work/valid")
        let outside = try fixture.directory("outside")
        let file = fixture.url("work/not-a-directory")
        try Data("x".utf8).write(to: file)
        let deleted = try fixture.directory("work/deleted")
        try FileManager.default.removeItem(at: deleted)

        let catalog = RemoteWorkspaceCatalog(
            allowedRoots: [allowed, home],
            candidates: [
                .init(url: valid, source: .recentSession),
                .init(url: outside, source: .recentSession),
                .init(url: file, source: .saved),
                .init(url: deleted, source: .saved),
                .init(url: home, source: .saved),
                .init(url: URL(fileURLWithPath: "/"), source: .saved),
            ],
            homeDirectory: home
        )

        XCTAssertEqual(catalog.entries.map(\.url), [valid.standardizedFileURL])

        let rootCatalog = RemoteWorkspaceCatalog(
            allowedRoots: [URL(fileURLWithPath: "/")],
            candidates: [.init(url: URL(fileURLWithPath: "/"), source: .saved)],
            homeDirectory: home
        )
        XCTAssertTrue(rootCatalog.entries.isEmpty)
    }

    func testEqualWorkspaceMatchesReturnAmbiguousInsteadOfGuessing() throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let first = try fixture.directory("work-a/shared")
        let second = try fixture.directory("work-b/shared")
        let catalog = RemoteWorkspaceCatalog(
            allowedRoots: [fixture.url("work-a"), fixture.url("work-b")],
            candidates: [
                .init(url: first, source: .recentSession),
                .init(url: second, source: .recentSession),
            ],
            homeDirectory: fixture.url("home")
        )

        guard case .ambiguous(let matches) = catalog.match("shared") else {
            return XCTFail("Expected an ambiguous workspace match")
        }
        XCTAssertEqual(Set(matches.map(\.id)), Set(catalog.entries.map(\.id)))
    }

    func testWireSummaryUsesOpaqueStableIDWithoutAbsolutePath() throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let project = try fixture.directory("work/private-project")
        let catalog = RemoteWorkspaceCatalog(
            allowedRoots: [fixture.url("work")],
            candidates: [.init(url: project, source: .saved)],
            homeDirectory: fixture.url("home")
        )
        let entry = try XCTUnwrap(catalog.entries.first)

        let encoded = String(decoding: try JSONEncoder().encode(entry.summary), as: UTF8.self)

        XCTAssertFalse(encoded.contains(project.path))
        XCTAssertFalse(encoded.contains(fixture.root.path))
        XCTAssertEqual(entry.summary.id, entry.id)
        XCTAssertEqual(entry.id.count, 64)
    }

    func testLateSessionWorkspaceBecomesResolvableWithoutRestartingService() throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let project = try fixture.directory("work/revops-global")
        let identity = RemoteWorkspaceCatalog(
            allowedRoots: [project],
            candidates: [.init(url: project, source: .recentSession)],
            homeDirectory: fixture.url("home")
        ).entries[0].id
        let catalog = RemoteWorkspaceCatalog(
            allowedRoots: [],
            candidates: [],
            homeDirectory: fixture.url("home")
        )

        catalog.register([
            .init(url: project, source: .recentSession, lastUsedAt: Date())
        ])

        XCTAssertEqual(catalog.resolve(id: identity), project.standardizedFileURL)
        XCTAssertEqual(catalog.entries.map(\.name), ["revops-global"])
    }

    func testWorkspaceRootPersistenceIsCanonicalDeduplicatedAndBounded() throws {
        let fixture = try WorkspaceFixture()
        defer { fixture.remove() }
        let first = try fixture.directory("work/first")
        let second = try fixture.directory("work/second")

        let roots = RemoteWorkspaceRootPersistence.merging(
            [second, first, second],
            into: [first.path],
            limit: 2
        )

        XCTAssertEqual(roots, [first.standardizedFileURL.path, second.standardizedFileURL.path])
    }
}

private final class WorkspaceFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandWorkspaceCatalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func url(_ path: String) -> URL {
        path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    func directory(_ path: String) throws -> URL {
        let result = url(path)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
