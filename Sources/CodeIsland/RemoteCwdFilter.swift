import Foundation

/// Canonical, component-aware filesystem boundary checks shared by remote
/// workspace and attachment validation. It never authorizes by raw string
/// prefix because `/work/repo-escape` is not inside `/work/repo`.
enum RemoteCwdFilter {
    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
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
