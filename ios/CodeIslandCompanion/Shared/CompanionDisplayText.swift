import Foundation

enum CompanionDisplayText {
    static func source(_ text: String?) -> String {
        guard let trimmed = cleaned(text) else { return "CodeIsland" }

        switch trimmed.lowercased() {
        case "claude", "claudecode", "clawd":
            return "CLAUDE"
        case "codex", "openai":
            return "CODEX"
        case "gemini":
            return "GEMINI"
        case "cursor", "cursor-cli":
            return "CURSOR"
        case "qoder", "qoder-cli":
            return "QODER"
        case "opencode":
            return "OPENCODE"
        case "qwen":
            return "QWEN"
        default:
            return trimmed.uppercased()
        }
    }

    static func message(_ text: String?) -> String? {
        guard let trimmed = cleaned(text) else { return nil }

        switch trimmed {
        case "[Request interrupted by user]", "Request interrupted by user":
            return "Request interrupted by you"
        case "[Request interrupted by user for tool use]", "Request interrupted by user for tool use":
            return "Tool call interrupted by you"
        default:
            return trimmed
        }
    }

    static func tool(_ text: String?) -> String? {
        guard let trimmed = cleaned(text) else { return nil }

        switch trimmed.lowercased() {
        case "askuserquestion":
            return "Ask"
        case "bash", "shell":
            return "Terminal"
        case "read":
            return "Read"
        case "edit", "write", "multiedit":
            return "Edit"
        case "grep", "glob", "search":
            return "Search"
        case "webfetch", "websearch":
            return "Web"
        case "todowrite":
            return "Plan"
        case "notebookedit":
            return "Note"
        default:
            return trimmed
        }
    }

    static func workspace(_ text: String?) -> String? {
        guard let trimmed = cleaned(text) else { return nil }

        switch trimmed.lowercased() {
        case "workspace":
            return "Workspace"
        default:
            return trimmed
        }
    }

    static func subtitle(workspaceName: String?, toolName: String?, fallback: String) -> String {
        if let workspaceName = workspace(workspaceName) {
            return workspaceName
        }
        if let toolName = tool(toolName) {
            return toolName
        }
        return fallback
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static var markdownCache: [String: AttributedString] = [:]
    private static let markdownCacheLimit = 128

    /// Message body rendering, matching the Mac notch's ChatMessageTextFormatter:
    /// user messages render as plain text (no markdown, so symbols in the input aren't treated as syntax);
    /// assistant messages first strip `::directive{...}` blocks, merge extra blank lines, then apply inline markdown.
    static func messageMarkdown(_ text: String, isUser: Bool) -> AttributedString {
        isUser ? AttributedString(text) : inlineMarkdown(compactText(stripDirectives(text)))
    }

    /// Inline markdown rendering (bold / italic / code / links / ``` fenced code blocks), matching the Mac notch.
    /// Only for prose like message bodies and questions; not for source names / workspace / tool names
    /// (paths with underscores get mistaken for italics).
    ///
    /// Results are cached by text: the same text always returns the same AttributedString, so that when the board
    /// refreshes often for active sessions, static idle sessions aren't repeatedly redrawn/animated (flickering) by SwiftUI from re-parsing into new instances.
    static func inlineMarkdown(_ text: String) -> AttributedString {
        if let cached = markdownCache[text] {
            return cached
        }
        let result = text.contains("```")
            ? renderWithFencedCodeBlocks(text)
            : renderInlineOnly(text)
        if markdownCache.count >= markdownCacheLimit {
            markdownCache.removeAll(keepingCapacity: true)
        }
        markdownCache[text] = result
        return result
    }

    /// Inline parsing; falls back to plain text on failure or empty parsed content (link definitions, unclosed tags, etc.).
    private static func renderInlineOnly(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ), !attributed.characters.isEmpty {
            return attributed
        }
        return AttributedString(text)
    }

    /// Apple's inline parser treats ``` as an inline-code delimiter, collapsing fenced code blocks and leaking the language name.
    /// Split on the fences, keep the code body as plain text line by line, and render the rest as inline markdown.
    private static func renderWithFencedCodeBlocks(_ text: String) -> AttributedString {
        var result = AttributedString()
        var buffer = ""
        var inFence = false
        var hasOutput = false

        func flush() {
            guard !buffer.isEmpty else { return }
            let piece = inFence ? AttributedString(buffer) : renderInlineOnly(buffer)
            if hasOutput { result.append(AttributedString("\n")) }
            result.append(piece)
            hasOutput = true
            buffer = ""
        }

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flush()
                inFence.toggle()
                continue
            }
            if !buffer.isEmpty { buffer.append("\n") }
            buffer.append(line)
        }
        flush()
        return result
    }

    /// Strip `::directive{...}` blocks (which may span multiple lines).
    private static func stripDirectives(_ text: String) -> String {
        var result: [String] = []
        var inDirective = false
        var braceDepth = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if inDirective {
                for ch in line {
                    if ch == "{" { braceDepth += 1 }
                    if ch == "}" { braceDepth -= 1 }
                }
                if braceDepth <= 0 {
                    inDirective = false
                    braceDepth = 0
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("::") && trimmed.contains("{") {
                braceDepth = 0
                for ch in line {
                    if ch == "{" { braceDepth += 1 }
                    if ch == "}" { braceDepth -= 1 }
                }
                if braceDepth > 0 { inDirective = true }
                continue
            }
            result.append(String(line))
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trim each line and merge consecutive blank lines.
    private static func compactText(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .reduce(into: [String]()) { acc, line in
                if line.isEmpty && (acc.last?.isEmpty ?? true) { return }
                acc.append(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
