import CodeIslandCore
import CryptoKit
import Foundation

struct TelegramApprovalDetail: Codable, Equatable {
    let label: String
    let value: String
}

struct TelegramApprovalPresentation: Codable, Equatable {
    let requestID: String
    let headline: String
    let summary: String
    let agent: String
    let workspace: String?
    let risk: CommandRisk
    let riskReason: String
    let changedScope: [String]
    let details: [TelegramApprovalDetail]
    let fingerprint: String
    let createdAt: Date
    let actionToken: String
    let actionExpiresAt: Date
}

enum TelegramApprovalPresentationBuilder {
    private static let priorityKeys = [
        "command", "file_path", "path", "notebook_path", "url", "query", "content"
    ]
    private static let maximumDetailCount = 30
    private static let maximumLabelLength = 80
    private static let maximumValueLength = 4_000
    private static let maximumAggregateDetailLength = 12_000

    static func build(
        request: PermissionRequest,
        approval: RemoteApprovalItem
    ) -> TelegramApprovalPresentation {
        build(requestID: request.id, event: request.event, approval: approval)
    }

    static func build(
        requestID: String,
        event: HookEvent,
        approval: RemoteApprovalItem
    ) -> TelegramApprovalPresentation {
        let input = event.toolInput ?? [:]
        let tool = event.toolName ?? approval.tool
        let agent = capped(approval.source.isEmpty ? "CodeIsland" : approval.source, at: 80)
        let risk = approval.risk ?? CommandRiskClassifier.classify(
            toolName: tool,
            toolInput: input.mapValues { stableString($0) }
        )
        let details = buildDetails(input)
        let scope = changedScope(tool: tool, input: input)
        let headline = headline(agent: agent, tool: tool, input: input)
        let workspace = approval.workspace.map { capped($0, at: 200) }
        let summary = workspace.map {
            "\(agent) is waiting for approval in \($0)."
        } ?? "\(agent) is waiting for approval."
        let fingerprintSeed = ([requestID, tool, agent] + details.flatMap { [$0.label, $0.value] })
            .joined(separator: "\u{1F}")

        return TelegramApprovalPresentation(
            requestID: capped(requestID, at: 200),
            headline: capped(headline, at: 240),
            summary: capped(summary, at: 360),
            agent: agent,
            workspace: workspace,
            risk: risk,
            riskReason: capped(riskReason(risk: risk, input: input), at: 360),
            changedScope: Array(scope.prefix(12)),
            details: details,
            fingerprint: fingerprint(for: fingerprintSeed),
            createdAt: approval.createdAt,
            actionToken: approval.actionToken,
            actionExpiresAt: approval.actionExpiresAt
        )
    }

    private static func headline(agent: String, tool: String, input: [String: Any]) -> String {
        let normalizedTool = tool.lowercased()
        let command = (input["command"] as? String ?? "").lowercased()
        let paths = [input["file_path"], input["path"], input["notebook_path"]]
            .compactMap { $0 as? String }

        if command.range(of: #"\bgit\s+push\b"#, options: .regularExpression) != nil {
            return "\(agent) wants to push changes to GitHub"
        }
        if command.range(
            of: #"\b(npm|pnpm|yarn|bun|pip|pip3|brew)\s+(install|add)\b"#,
            options: .regularExpression
        ) != nil {
            return "\(agent) wants to install software or dependencies"
        }
        if containsCredentialBoundary(input) {
            return "\(agent) wants to access protected credentials"
        }
        if normalizedTool == "bash" || normalizedTool == "shell" {
            return "\(agent) wants to run a command"
        }
        if ["write", "edit", "multiedit", "applypatch", "notebookedit"].contains(normalizedTool) {
            if let path = paths.first, !path.isEmpty {
                return "\(agent) wants to change \(URL(fileURLWithPath: path).lastPathComponent)"
            }
            return "\(agent) wants to change files"
        }
        if normalizedTool.contains("web") || input["url"] != nil {
            return "\(agent) wants to access the network"
        }
        if ["read", "grep", "glob", "ls", "notebookread"].contains(normalizedTool) {
            return "\(agent) wants to read project information"
        }
        return "\(agent) wants to use \(capped(tool.isEmpty ? "an unclassified tool" : tool, at: 100))"
    }

    private static func riskReason(risk: CommandRisk, input: [String: Any]) -> String {
        if containsCredentialBoundary(input) {
            return "This may expose protected credentials or authorization material."
        }
        if risk == .destructive {
            return "This can permanently remove data, overwrite history, or change system access."
        }
        if containsNetworkBoundary(input) {
            return "This contacts an external network service and may transmit project data."
        }
        switch risk {
        case .destructive:
            return "This action has destructive impact."
        case .writes:
            return "This changes files, dependencies, services, or remote state."
        case .readOnly:
            return "This reads information without changing local or remote state."
        }
    }

    private static func changedScope(tool: String, input: [String: Any]) -> [String] {
        var scope = Set<String>()
        for key in ["file_path", "path", "notebook_path"] {
            if let path = input[key] as? String, !path.isEmpty {
                scope.insert("File: \(capped(path, at: 300))")
            }
        }

        if let urlValue = input["url"] as? String,
           let host = URL(string: urlValue)?.host,
           !host.isEmpty {
            scope.insert("Network: \(host)")
        }

        if let command = input["command"] as? String {
            let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
            if let pushIndex = words.firstIndex(where: { $0.lowercased() == "push" }) {
                let arguments = words.dropFirst(pushIndex + 1).filter { !$0.hasPrefix("-") }
                if let remote = arguments.first {
                    scope.insert("Remote: \(capped(remote, at: 120))")
                }
                if arguments.count > 1 {
                    scope.insert("Branch: \(capped(arguments[arguments.index(after: arguments.startIndex)], at: 120))")
                }
            }
            if let range = command.range(of: #"https?://[^\s'\"]+"#, options: .regularExpression),
               let host = URL(string: String(command[range]))?.host {
                scope.insert("Network: \(host)")
            }
        }

        if scope.isEmpty {
            scope.insert("Tool: \(capped(tool.isEmpty ? "Unclassified" : tool, at: 120))")
        }
        return scope.sorted()
    }

    private static func buildDetails(_ input: [String: Any]) -> [TelegramApprovalDetail] {
        let remainingKeys = input.keys.filter { !priorityKeys.contains($0) }.sorted()
        let orderedKeys = priorityKeys.filter { input[$0] != nil } + remainingKeys
        var details: [TelegramApprovalDetail] = []
        var remainingBudget = maximumAggregateDetailLength

        for key in orderedKeys.prefix(maximumDetailCount) {
            guard let rawValue = input[key] else { continue }
            let label = capped(displayLabel(for: key), at: maximumLabelLength)
            let availableForValue = remainingBudget - label.count
            guard availableForValue > 0 else { break }

            let value = isSensitiveKey(key)
                ? "[REDACTED]"
                : redactSecrets(stableString(rawValue))
            let cappedValue = capped(value, at: min(maximumValueLength, availableForValue))
            details.append(TelegramApprovalDetail(label: label, value: cappedValue))
            remainingBudget -= label.count + cappedValue.count
        }
        return details
    }

    private static func stableString(_ value: Any) -> String {
        if let string = value as? String { return string }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private static func displayLabel(for key: String) -> String {
        let words = key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
        guard let first = words.first else { return "Input" }
        return first.uppercased() + words.dropFirst()
    }

    private static func containsCredentialBoundary(_ input: [String: Any]) -> Bool {
        if input.keys.contains(where: isSensitiveKey) { return true }
        let text = input.map { "\($0.key)=\(stableString($0.value))" }.joined(separator: "\n")
        return text.range(
            of: #"(?i)(authorization|bearer|api[_-]?key|access[_-]?token|private[_-]?key|password|secret|\.env\b)"#,
            options: .regularExpression
        ) != nil
    }

    private static func containsNetworkBoundary(_ input: [String: Any]) -> Bool {
        if input["url"] != nil { return true }
        let command = input["command"] as? String ?? ""
        return command.range(
            of: #"(?i)\b(curl|wget|ssh|scp|rsync|git\s+push)\b|https?://"#,
            options: .regularExpression
        ) != nil
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        key.range(
            of: #"(?i)(password|passphrase|token|secret|api[_-]?key|authorization|private[_-]?key|credential)"#,
            options: .regularExpression
        ) != nil
    }

    private static func redactSecrets(_ value: String) -> String {
        let patterns = [
            #"(?i)\bbearer\s+[^\s\"';,]+"#,
            #"(?i)\b(?:authorization|api[_-]?key|access[_-]?token|token|secret|password)\s*[:=]\s*[^\s\"';,]+"#,
        ]
        return patterns.reduce(value) { current, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return current }
            let range = NSRange(current.startIndex..<current.endIndex, in: current)
            return expression.stringByReplacingMatches(
                in: current,
                range: range,
                withTemplate: "[REDACTED]"
            )
        }
    }

    private static func fingerprint(for value: String) -> String {
        let hex = SHA256.hash(data: Data(value.utf8))
            .prefix(6)
            .map { String(format: "%02X", $0) }
            .joined()
        return stride(from: 0, to: hex.count, by: 4).map { index in
            let start = hex.index(hex.startIndex, offsetBy: index)
            let end = hex.index(start, offsetBy: min(4, hex.count - index))
            return String(hex[start..<end])
        }.joined(separator: "-")
    }

    private static func capped(_ value: String, at limit: Int) -> String {
        String(value.prefix(max(0, limit)))
    }
}
