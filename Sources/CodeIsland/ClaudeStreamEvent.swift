import CodeIslandCore
import Foundation

struct ClaudeToolUse: Equatable {
    let id: String
    let name: String
    let input: [String: AnyCodableLike]
}

struct ClaudeToolResult: Equatable {
    let toolUseID: String
    let isError: Bool
    let content: String?
    let exitCode: Int?
}

struct ClaudeControlPermissionRequest: Equatable {
    let requestID: String
    let toolName: String
    let input: [String: AnyCodableLike]
    let toolUseID: String
    let blockedPath: String?
    let decisionReason: String?
    let requiresUserInteraction: Bool
}

struct ClaudeResultEvent: Equatable {
    let subtype: String
    let isError: Bool
    let result: String?
    let sessionID: String?
    let permissionDenials: [String]
}

enum ClaudeStreamEvent: Equatable {
    case initialization(sessionID: String, cwd: String?)
    case assistant(text: String?, toolUses: [ClaudeToolUse], sessionID: String?)
    case toolResults([ClaudeToolResult], sessionID: String?)
    case controlRequest(ClaudeControlPermissionRequest)
    case hook(subtype: String, hookName: String?, sessionID: String?)
    case permissionDenied(
        toolName: String,
        toolUseID: String,
        message: String,
        sessionID: String?
    )
    case result(ClaudeResultEvent)
    case unknown(type: String?, subtype: String?)
    case malformed

    static func parse(line: String) -> ClaudeStreamEvent {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else { return .malformed }

        let type = root["type"] as? String
        let subtype = root["subtype"] as? String
        let sessionID = root["session_id"] as? String

        switch type {
        case "system" where subtype == "init":
            guard let sessionID else { return .malformed }
            return .initialization(sessionID: sessionID, cwd: root["cwd"] as? String)

        case "system" where ["hook_started", "hook_progress", "hook_response"].contains(subtype):
            return .hook(
                subtype: subtype ?? "hook",
                hookName: root["hook_name"] as? String,
                sessionID: sessionID
            )

        case "system" where subtype == "permission_denied":
            guard let toolName = root["tool_name"] as? String,
                  let toolUseID = root["tool_use_id"] as? String,
                  let message = root["message"] as? String
            else { return .malformed }
            return .permissionDenied(
                toolName: toolName,
                toolUseID: toolUseID,
                message: message,
                sessionID: sessionID
            )

        case "assistant":
            guard let message = root["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return .malformed }
            let text = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n").nilIfEmpty
            let toolUses = content.compactMap { block -> ClaudeToolUse? in
                guard block["type"] as? String == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String
                else { return nil }
                return ClaudeToolUse(
                    id: id,
                    name: name,
                    input: Self.codableObject(block["input"])
                )
            }
            return .assistant(text: text, toolUses: toolUses, sessionID: sessionID)

        case "user":
            guard let message = root["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return .unknown(type: type, subtype: subtype) }
            let sharedResult = root["tool_use_result"] as? [String: Any]
            let results = content.compactMap { block -> ClaudeToolResult? in
                guard block["type"] as? String == "tool_result",
                      let toolUseID = block["tool_use_id"] as? String
                else { return nil }
                let text = Self.textContent(block["content"])
                return ClaudeToolResult(
                    toolUseID: toolUseID,
                    isError: block["is_error"] as? Bool ?? false,
                    content: text,
                    exitCode: Self.exitCode(from: sharedResult, fallbackText: text)
                )
            }
            return results.isEmpty
                ? .unknown(type: type, subtype: subtype)
                : .toolResults(results, sessionID: sessionID)

        case "control_request":
            guard let requestID = root["request_id"] as? String,
                  let request = root["request"] as? [String: Any],
                  request["subtype"] as? String == "can_use_tool",
                  let toolName = request["tool_name"] as? String,
                  let toolUseID = request["tool_use_id"] as? String
            else { return .unknown(type: type, subtype: subtype) }
            return .controlRequest(ClaudeControlPermissionRequest(
                requestID: requestID,
                toolName: toolName,
                input: Self.codableObject(request["input"]),
                toolUseID: toolUseID,
                blockedPath: request["blocked_path"] as? String,
                decisionReason: request["decision_reason"] as? String,
                requiresUserInteraction: request["requires_user_interaction"] as? Bool ?? false
            ))

        case "result":
            let denials = (root["permission_denials"] as? [[String: Any]] ?? []).compactMap {
                ($0["tool_name"] as? String) ?? ($0["message"] as? String)
            }
            return .result(ClaudeResultEvent(
                subtype: subtype ?? "unknown",
                isError: (root["is_error"] as? Bool) ?? (subtype != "success"),
                result: root["result"] as? String,
                sessionID: sessionID,
                permissionDenials: denials
            ))

        default:
            return .unknown(type: type, subtype: subtype)
        }
    }

    private static func codableObject(_ value: Any?) -> [String: AnyCodableLike] {
        AnyCodableLike.from(value).asObject ?? [:]
    }

    private static func textContent(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let blocks = value as? [[String: Any]] {
            return blocks.compactMap { block in
                (block["text"] as? String) ?? (block["content"] as? String)
            }.joined(separator: "\n").nilIfEmpty
        }
        return nil
    }

    private static func exitCode(from object: [String: Any]?, fallbackText: String?) -> Int? {
        for key in ["exitCode", "exit_code", "code"] {
            if let value = object?[key] as? Int { return value }
            if let value = object?[key] as? NSNumber { return value.intValue }
        }
        guard let fallbackText,
              let expression = try? NSRegularExpression(pattern: #"(?i)exit code\s+(-?\d+)"#),
              let match = expression.firstMatch(
                in: fallbackText,
                range: NSRange(fallbackText.startIndex..., in: fallbackText)
              ),
              let range = Range(match.range(at: 1), in: fallbackText)
        else { return nil }
        return Int(fallbackText[range])
    }
}

struct ClaudeControlPermissionResponse: Equatable {
    enum Decision: Equatable {
        case allow
        case deny(message: String)
    }

    let requestID: String
    let toolUseID: String
    let decision: Decision

    static func allow(requestID: String, toolUseID: String) -> Self {
        Self(requestID: requestID, toolUseID: toolUseID, decision: .allow)
    }

    static func deny(requestID: String, toolUseID: String, message: String) -> Self {
        Self(requestID: requestID, toolUseID: toolUseID, decision: .deny(message: message))
    }

    func jsonLine() throws -> String {
        var permission: [String: Any] = ["toolUseID": toolUseID]
        switch decision {
        case .allow:
            permission["behavior"] = "allow"
        case .deny(let message):
            permission["behavior"] = "deny"
            permission["message"] = message
        }
        let object: [String: Any] = [
            "type": "control_response",
            "response": [
                "subtype": "success",
                "request_id": requestID,
                "response": permission,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let line = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return line
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
