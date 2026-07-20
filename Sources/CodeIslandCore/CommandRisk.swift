import Foundation

/// How much damage approving a request could do.
///
/// A dangerous-command classifier already existed in the TypeScript hook shims
/// (`Resources/codeisland-*.ts`), but it only decided *whether* to raise a
/// permission prompt — the verdict was discarded at the hook boundary and never
/// reached a view. So `rm -rf /` and reading a config file rendered with
/// identical chrome. This recomputes it on the Swift side, where the UI can act
/// on it, which avoids widening the hook payload.
public enum CommandRisk: String, Codable, Sendable, CaseIterable {
    /// Irreversible or wide-blast-radius: deletion, force-push, privilege
    /// escalation, permission loosening, piping the network into a shell.
    case destructive
    /// Mutates the working tree but is recoverable.
    case writes
    /// Cannot change anything.
    case readOnly

    public var isDestructive: Bool { self == .destructive }
}

public enum CommandRiskClassifier {
    /// Mirrors the shim's `DANGEROUS_PATTERNS`, plus the cases that motivated
    /// this work: force-push and remote-pipe-to-shell. Word-boundary anchored so
    /// `npm run format` is not mistaken for `rm`.
    private static let destructivePatterns: [String] = [
        #"\brm\s+(-[a-z]*[rf][a-z]*|--recursive|--force)"#,
        #"\bsudo\b"#,
        #"\b(chmod|chown)\b[^\n]*777"#,
        #"\bgit\s+push\b[^\n]*(--force|-f)\b"#,
        #"\bgit\s+(reset\s+--hard|clean\s+-[a-z]*f)"#,
        #"\b(curl|wget)\b[^\n]*\|\s*(sudo\s+)?(ba|z|k|)sh\b"#,
        #"\b(mkfs|dd)\b[^\n]*\bof=/dev/"#,
        #"\bdrop\s+(table|database)\b"#,
    ]

    /// Tools that cannot mutate anything, whatever their arguments.
    private static let readOnlyTools: Set<String> = [
        "read", "grep", "glob", "ls", "notebookread", "todoread", "websearch", "webfetch",
    ]

    /// Tools that write but are recoverable.
    private static let writeTools: Set<String> = [
        "edit", "write", "notebookedit", "multiedit", "applypatch",
    ]

    public static func classify(toolName: String?, toolInput: [String: String]) -> CommandRisk {
        let tool = (toolName ?? "").lowercased()

        if readOnlyTools.contains(tool) { return .readOnly }
        if writeTools.contains(tool) { return .writes }

        // Bash and anything unrecognised are judged on their payload: an
        // unknown tool with a destructive-looking command is still destructive.
        let haystack = toolInput
            .sorted { $0.key < $1.key }
            .map(\.value)
            .joined(separator: "\n")

        if haystack.isEmpty { return .writes }

        for pattern in destructivePatterns {
            if haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return .destructive
            }
        }

        return .writes
    }
}
