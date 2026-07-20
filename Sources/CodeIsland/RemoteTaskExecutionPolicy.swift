import Foundation

enum RemoteTaskExecutionDecision: String, Codable, Equatable, Sendable {
    case allow
    case needsApproval
    case deny
}

enum RemoteTaskExecutionOrigin: String, Codable, Equatable, Sendable {
    case provider
    case phone
}

enum RemoteTaskExecutionAction: Equatable, Sendable {
    case command(executable: String, arguments: [String])
    case shell(String, origin: RemoteTaskExecutionOrigin = .provider)
    case fileRead(url: URL)
    case fileChange(url: URL)
}

struct RemoteTaskCodexConfiguration: Equatable, Sendable {
    let sandboxMode: String
    let approvalPolicy: String
    let networkAccessEnabled: Bool
    let developerInstructions: String
}

/// Pure Edit & Test authority classifier. It evaluates provider actions against
/// a canonical workspace and never treats the task prompt as a security gate.
struct RemoteTaskExecutionPolicy {
    let workspaceURL: URL

    private let canonicalWorkspace: URL
    private let fileManager: FileManager

    init(workspaceURL: URL, fileManager: FileManager = .default) {
        self.workspaceURL = workspaceURL
        canonicalWorkspace = RemoteCwdFilter.canonical(workspaceURL)
        self.fileManager = fileManager
    }

    var codexConfiguration: RemoteTaskCodexConfiguration {
        RemoteTaskCodexConfiguration(
            sandboxMode: "workspace-write",
            approvalPolicy: "on-request",
            networkAccessEnabled: false,
            developerInstructions: """
            CodeIsland Edit & Test authority: inspect and edit only the validated workspace; run bounded builds, formatters, and tests. Stop for explicit approval before commit, push, merge, deploy, release, credentials/auth changes, production mutation, package installation, network enablement, paid actions, or external messages. Never bypass permissions or operate outside the workspace.
            """
        )
    }

    func decision(for action: RemoteTaskExecutionAction) -> RemoteTaskExecutionDecision {
        switch action {
        case .fileRead(let url), .fileChange(let url):
            return isInsideWorkspace(url) ? .allow : .deny
        case .command(let executable, let arguments):
            return classify(tokens: [executable] + arguments, hasShellControl: false)
        case .shell(let command, let origin):
            guard origin == .provider else { return .deny }
            let parsed = Self.parseShell(command)
            guard parsed.isValid, !parsed.tokens.isEmpty else { return .needsApproval }
            return classify(tokens: parsed.tokens, hasShellControl: parsed.hasControlOperator)
        }
    }

    private func classify(tokens originalTokens: [String], hasShellControl: Bool) -> RemoteTaskExecutionDecision {
        guard !originalTokens.isEmpty else { return .needsApproval }
        let lowered = originalTokens.map { $0.lowercased() }
        if Self.containsPermissionBypass(lowered) { return .deny }

        var tokens = originalTokens
        let initialExecutable = Self.basename(tokens[0]).lowercased()
        if initialExecutable == "rm", Self.isBroadRecursiveDeletion(tokens) { return .deny }
        if hasShellControl { return .needsApproval }
        if Self.looksLikeEnvironmentAssignment(tokens[0]) { return .needsApproval }

        tokens = Self.unwrap(tokens)
        guard !tokens.isEmpty else { return .needsApproval }
        let executable = Self.basename(tokens.removeFirst()).lowercased()
        let arguments = tokens

        if Self.containsPermissionBypass(([executable] + arguments).map { $0.lowercased() }) {
            return .deny
        }
        if executable == "rm", Self.isBroadRecursiveDeletion([executable] + arguments) { return .deny }

        if Self.requiresApproval(executable: executable, arguments: arguments) {
            return .needsApproval
        }

        guard Self.isAllowed(executable: executable, arguments: arguments) else {
            return .needsApproval
        }
        guard pathsStayInsideWorkspace(executable: executable, arguments: arguments) else {
            return .deny
        }
        return .allow
    }

    private func pathsStayInsideWorkspace(executable: String, arguments: [String]) -> Bool {
        for argument in arguments where Self.isObviousPath(argument) {
            guard isInsideWorkspace(resolvePath(argument)) else { return false }
        }

        if ["cat", "head", "tail", "wc", "file", "stat"].contains(executable) {
            let paths = arguments.filter { !$0.hasPrefix("-") }
            return paths.allSatisfy { isInsideWorkspace(resolvePath($0)) }
        }
        if executable == "find", let root = arguments.first, !root.hasPrefix("-") {
            return isInsideWorkspace(resolvePath(root))
        }
        if ["rg", "grep"].contains(executable) {
            let positional = arguments.filter { !$0.hasPrefix("-") }
            for path in positional.dropFirst() where Self.looksLikePathOperand(path) {
                guard isInsideWorkspace(resolvePath(path)) else { return false }
            }
        }
        return true
    }

    private func resolvePath(_ raw: String) -> URL {
        if raw == "~" || raw.hasPrefix("~/") {
            return URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        return canonicalWorkspace.appendingPathComponent(raw)
    }

    private func isInsideWorkspace(_ url: URL) -> Bool {
        RemoteCwdFilter.contains(url, in: canonicalWorkspace)
    }

    private static func isAllowed(executable: String, arguments: [String]) -> Bool {
        switch executable {
        case "pwd":
            return arguments.isEmpty
        case "cat", "head", "tail", "wc", "file", "stat", "ls":
            return true
        case "rg", "grep":
            return true
        case "find":
            let forbidden = Set(["-delete", "-exec", "-execdir", "-ok", "-okdir"])
            return forbidden.isDisjoint(with: arguments.map { $0.lowercased() })
        case "swift":
            return firstNonFlag(arguments).map { ["test", "build", "format"].contains($0) } ?? false
        case "xcodebuild":
            let actions = Set(arguments.filter { !$0.hasPrefix("-") }.map { $0.lowercased() })
            return !actions.isDisjoint(with: ["test", "build", "analyze"])
                && actions.isDisjoint(with: ["archive", "install", "installsrc"])
        case "npm", "pnpm", "yarn":
            return isAllowedJavaScriptTask(arguments)
        case "pytest", "swiftformat", "prettier", "black", "gofmt":
            return true
        case "ruff":
            return arguments.first.map { ["check", "format"].contains($0.lowercased()) } ?? false
        case "cargo":
            return firstNonFlag(arguments).map { ["test", "check", "build", "fmt", "clippy"].contains($0) } ?? false
        case "go":
            return firstNonFlag(arguments).map { ["test", "build", "fmt", "vet"].contains($0) } ?? false
        case "git":
            return isReadOnlyGit(arguments)
        default:
            return false
        }
    }

    private static func requiresApproval(executable: String, arguments: [String]) -> Bool {
        let first = firstNonFlag(arguments) ?? ""
        let approvalExecutables: Set<String> = [
            "gh", "vercel", "netlify", "fly", "flyctl", "wrangler", "fastlane",
            "psql", "mysql", "sqlite3", "supabase", "security", "ssh-add",
            "sendmail", "mail", "curl", "wget", "ssh", "scp", "sftp", "rsync",
            "nc", "ncat", "telnet", "brew", "pip", "pip3", "gem", "bundle",
            "tailscale", "networksetup", "sudo", "su", "chmod", "chown", "rm",
            "mv", "cp", "mkdir", "touch", "bash", "sh", "zsh", "fish", "osascript",
        ]
        if approvalExecutables.contains(executable) { return true }
        if executable == "git" {
            return [
                "commit", "push", "merge", "rebase", "reset", "clean", "tag", "remote",
                "fetch", "pull", "cherry-pick", "revert", "worktree", "switch", "checkout",
            ].contains(first)
        }
        if ["npm", "pnpm", "yarn"].contains(executable) {
            return ["install", "i", "add", "remove", "uninstall", "publish", "link"].contains(first)
        }
        if executable == "cargo" { return ["install", "publish", "login", "owner"].contains(first) }
        if executable == "go" { return ["install", "get", "env"].contains(first) }
        if executable == "xcodebuild" {
            return arguments.contains { ["archive", "install", "-exportarchive"].contains($0.lowercased()) }
        }
        return false
    }

    private static func isReadOnlyGit(_ arguments: [String]) -> Bool {
        guard let action = firstNonFlag(arguments) else { return false }
        return ["status", "diff", "log", "show", "rev-parse", "ls-files", "ls-tree"].contains(action)
    }

    private static func isAllowedJavaScriptTask(_ arguments: [String]) -> Bool {
        guard let action = firstNonFlag(arguments) else { return false }
        if ["test", "lint", "build", "check", "typecheck", "format"].contains(action) { return true }
        guard action == "run",
              let index = arguments.firstIndex(where: { $0.lowercased() == "run" }),
              arguments.indices.contains(index + 1)
        else { return false }
        let script = arguments[index + 1].lowercased()
        return ["test", "lint", "build", "check", "typecheck", "format"].contains {
            script == $0 || script.hasPrefix($0 + ":")
        }
    }

    private static func unwrap(_ input: [String]) -> [String] {
        var tokens = input
        while let first = tokens.first.map({ basename($0).lowercased() }) {
            switch first {
            case "command":
                tokens.removeFirst()
            case "env":
                tokens.removeFirst()
                guard tokens.first.map({ !looksLikeEnvironmentAssignment($0) }) == true else { return [] }
            case "xcrun":
                tokens.removeFirst()
                while tokens.first?.hasPrefix("-") == true {
                    tokens.removeFirst()
                }
            default:
                return tokens
            }
        }
        return tokens
    }

    private static func containsPermissionBypass(_ loweredTokens: [String]) -> Bool {
        if loweredTokens.contains(where: {
            $0 == "--dangerously-skip-permissions"
                || $0 == "--allow-dangerously-skip-permissions"
                || $0.contains("bypasspermissions")
        }) { return true }
        if let index = loweredTokens.firstIndex(of: "--permission-mode"),
           loweredTokens.indices.contains(index + 1),
           loweredTokens[index + 1] == "bypasspermissions" {
            return true
        }
        return false
    }

    private static func isBroadRecursiveDeletion(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty, basename(tokens[0]).lowercased() == "rm" else { return false }
        let arguments = Array(tokens.dropFirst())
        let flags = arguments.filter { $0.hasPrefix("-") }.joined()
        let recursive = flags.contains("r") || flags.contains("R") || arguments.contains("--recursive")
        let forced = flags.contains("f") || arguments.contains("--force")
        let broadTargets: Set<String> = ["/", "~", "~/", ".", "..", "*", "/*"]
        return recursive && forced && arguments.contains(where: broadTargets.contains)
    }

    private static func isObviousPath(_ value: String) -> Bool {
        value.hasPrefix("/") || value == "~" || value.hasPrefix("~/") || value == ".." || value.hasPrefix("../")
    }

    private static func looksLikePathOperand(_ value: String) -> Bool {
        value.contains("/") || value.hasPrefix(".")
    }

    private static func firstNonFlag(_ arguments: [String]) -> String? {
        arguments.first(where: { !$0.hasPrefix("-") })?.lowercased()
    }

    private static func basename(_ executable: String) -> String {
        URL(fileURLWithPath: executable).lastPathComponent
    }

    private static func looksLikeEnvironmentAssignment(_ token: String) -> Bool {
        guard let equals = token.firstIndex(of: "="), equals != token.startIndex else { return false }
        return token[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private struct ParsedShell {
        let tokens: [String]
        let hasControlOperator: Bool
        let isValid: Bool
    }

    /// Tokenizes one shell command without expansion or evaluation. Control
    /// operators are retained only as a reason to require approval.
    private static func parseShell(_ command: String) -> ParsedShell {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        var hasControl = false
        var index = command.startIndex

        func finishToken() {
            guard !current.isEmpty else { return }
            tokens.append(current)
            current = ""
        }

        while index < command.endIndex {
            let character = command[index]
            let next = command.index(after: index)
            if escaping {
                current.append(character)
                escaping = false
                index = next
                continue
            }
            if character == "\\" {
                escaping = true
                index = next
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                index = next
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                finishToken()
                if character == "\n" || character == "\r" { hasControl = true }
            } else if "|;&<>`".contains(character) {
                finishToken()
                hasControl = true
            } else if character == "$", next < command.endIndex, command[next] == "(" {
                finishToken()
                hasControl = true
            } else {
                current.append(character)
            }
            index = next
        }
        finishToken()
        return ParsedShell(tokens: tokens, hasControlOperator: hasControl, isValid: quote == nil && !escaping)
    }
}
