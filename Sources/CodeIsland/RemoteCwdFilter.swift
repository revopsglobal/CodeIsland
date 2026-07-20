import Foundation

/// Canonical, component-aware filesystem boundary checks shared by remote
/// workspace and attachment validation. It never authorizes by raw string
/// prefix because `/work/repo-escape` is not inside `/work/repo`.
enum RemoteCwdFilter {
    static func canonical(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        var existingAncestor = standardized
        var missingComponents: [String] = []

        // resolvingSymlinksInPath() can leave an intermediate symlink
        // unresolved when the final file does not exist yet. Walk up to the
        // deepest existing ancestor first so new writes cannot escape through
        // a symlinked parent directory.
        while existingAncestor.path != "/",
              !FileManager.default.fileExists(atPath: existingAncestor.path) {
            missingComponents.insert(existingAncestor.lastPathComponent, at: 0)
            existingAncestor.deleteLastPathComponent()
        }
        let resolvedAncestor = existingAncestor.resolvingSymlinksInPath().standardizedFileURL
        return missingComponents.reduce(resolvedAncestor) {
            $0.appendingPathComponent($1)
        }.standardizedFileURL
    }

    static func contains(_ candidate: URL, in root: URL) -> Bool {
        let candidatePath = canonical(candidate).path
        let rootPath = canonical(root).path
        guard rootPath != "/" else { return candidatePath.hasPrefix("/") }
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    static func isSafeWorkspace(
        _ candidate: URL,
        allowedRoots: [URL],
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let canonicalCandidate = canonical(candidate)
        let path = canonicalCandidate.path
        let home = canonical(homeDirectory).path
        guard path != "/", path != home else { return false }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return allowedRoots.contains { contains(canonicalCandidate, in: $0) }
    }
}
