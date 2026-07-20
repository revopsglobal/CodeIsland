import Foundation
import CodeIslandCore

struct RemoteTaskEvidenceCommandResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol RemoteTaskEvidenceCommandRunning: AnyObject {
    func run(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL
    ) throws -> RemoteTaskEvidenceCommandResult
}

final class FoundationRemoteTaskEvidenceCommandRunner: RemoteTaskEvidenceCommandRunning {
    func run(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL
    ) throws -> RemoteTaskEvidenceCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return RemoteTaskEvidenceCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}

final class RemoteTaskEvidenceCollector {
    private let commandRunner: RemoteTaskEvidenceCommandRunning
    private let maximumTextLength: Int

    init(
        commandRunner: RemoteTaskEvidenceCommandRunning = FoundationRemoteTaskEvidenceCommandRunner(),
        maximumTextLength: Int = 2_000
    ) {
        self.commandRunner = commandRunner
        self.maximumTextLength = max(16, maximumTextLength)
    }

    func collect(
        workspaceURL: URL,
        reportedChecks: [RemoteTaskCheck] = [],
        warnings: [String] = [],
        sourceState: RemoteTaskSourceState = .unchanged
    ) throws -> RemoteTaskEvidence {
        let result = try commandRunner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", workspaceURL.path, "status", "--porcelain=v1", "--branch"],
            currentDirectoryURL: workspaceURL
        )
        let parsed = parseStatus(result.stdout)
        var safeWarnings = warnings.map(sanitize)
        if result.exitCode != 0 {
            safeWarnings.append(sanitize("git status failed (\(result.exitCode)): \(result.stderr)"))
        }
        let resolvedState: RemoteTaskSourceState
        if sourceState == .unchanged, !parsed.files.isEmpty {
            resolvedState = .edited
        } else {
            resolvedState = sourceState
        }
        return RemoteTaskEvidence(
            branch: parsed.branch.map(sanitize),
            changedFiles: parsed.files,
            checks: reportedChecks.map {
                RemoteTaskCheck(
                    command: sanitize($0.command),
                    exitCode: $0.exitCode,
                    summary: sanitize($0.summary),
                    durationSeconds: $0.durationSeconds
                )
            },
            warnings: safeWarnings,
            sourceState: resolvedState
        )
    }

    private func parseStatus(_ output: String) -> (branch: String?, files: [RemoteTaskChangedFile]) {
        var branch: String?
        var files: [RemoteTaskChangedFile] = []
        for rawLine in output.split(whereSeparator: \.isNewline).map(String.init) {
            if rawLine.hasPrefix("## ") {
                var value = String(rawLine.dropFirst(3))
                value = value.components(separatedBy: "...").first ?? value
                value = value.replacingOccurrences(of: "No commits yet on ", with: "")
                value = value.replacingOccurrences(of: "Initial commit on ", with: "")
                branch = value.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            guard rawLine.count >= 3 else { continue }
            let status = String(rawLine.prefix(2))
            let payload = String(rawLine.dropFirst(3))
            if status.contains("R"), let arrow = payload.range(of: " -> ") {
                files.append(RemoteTaskChangedFile(
                    path: String(payload[arrow.upperBound...]),
                    kind: .renamed,
                    previousPath: String(payload[..<arrow.lowerBound])
                ))
            } else if status == "??" || status.contains("A") {
                files.append(.init(path: payload, kind: .added))
            } else if status.contains("D") {
                files.append(.init(path: payload, kind: .deleted))
            } else if status.contains("M") {
                files.append(.init(path: payload, kind: .modified))
            }
        }
        return (branch, files)
    }

    private func sanitize(_ value: String) -> String {
        let patterns = [
            #"(?i)\bbearer\s+[^\s\"';,]+"#,
            #"(?i)\b(?:action[-_ ]?token|authorization)\s*[:=]\s*[^\s\"';,]+"#,
        ]
        let redacted = patterns.reduce(value) { current, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return current }
            let range = NSRange(current.startIndex..<current.endIndex, in: current)
            return expression.stringByReplacingMatches(
                in: current,
                range: range,
                withTemplate: "[REDACTED]"
            )
        }
        return String(redacted.prefix(maximumTextLength))
    }
}
