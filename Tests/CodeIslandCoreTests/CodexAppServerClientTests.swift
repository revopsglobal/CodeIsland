import XCTest
@testable import CodeIslandCore

final class CodexAppServerClientTests: XCTestCase {

    func testInitializeHandshakeOptsIntoExperimentalAPIForRuntimeWorkspaceRoots() throws {
        let params = CodexAppServerClient.initializeParameters(
            clientName: "CodeIsland",
            clientVersion: "1.0.55"
        )

        let capabilities = try XCTUnwrap(params["capabilities"] as? [String: Any])
        XCTAssertEqual(capabilities["experimentalApi"] as? Bool, true)
    }

    func testTypedThreadStartUsesBoundedEditAndTestConfiguration() throws {
        let sender = RecordingCodexSender()
        let id = try sender.startThread(
            cwd: "/tmp/workspace",
            developerInstructions: "bounded instructions"
        )

        XCTAssertEqual(id, .int(1))
        let request = try XCTUnwrap(sender.requests.first)
        XCTAssertEqual(request.method, "thread/start")
        let params = try XCTUnwrap(request.params as? [String: Any])
        XCTAssertEqual(params["cwd"] as? String, "/tmp/workspace")
        XCTAssertEqual(params["developerInstructions"] as? String, "bounded instructions")
        XCTAssertEqual(params["approvalPolicy"] as? String, "on-request")
        XCTAssertEqual(params["approvalsReviewer"] as? String, "user")
        XCTAssertEqual(params["sandbox"] as? String, "workspace-write")
        XCTAssertEqual(params["runtimeWorkspaceRoots"] as? [String], ["/tmp/workspace"])
        XCTAssertEqual((params["environments"] as? [Any])?.count, 0)
        let config = try XCTUnwrap(params["config"] as? [String: Any])
        let sandbox = try XCTUnwrap(config["sandbox_workspace_write"] as? [String: Any])
        XCTAssertEqual(sandbox["network_access"] as? Bool, false)
    }

    func testTypedTurnStartUsesSchemaInputsAndStableClientMessageID() throws {
        let sender = RecordingCodexSender()
        let attachments = [
            URL(fileURLWithPath: "/tmp/context.png"),
            URL(fileURLWithPath: "/tmp/brief.pdf"),
        ]

        _ = try sender.startTurn(
            threadID: "thread-1",
            text: "Implement and test",
            attachments: attachments,
            clientUserMessageID: "stable-message-1",
            workspaceURL: URL(fileURLWithPath: "/tmp/workspace")
        )

        let params = try XCTUnwrap(sender.requests.first?.params as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, "thread-1")
        XCTAssertEqual(params["clientUserMessageId"] as? String, "stable-message-1")
        XCTAssertEqual(params["approvalPolicy"] as? String, "on-request")
        XCTAssertEqual((params["environments"] as? [Any])?.count, 0)
        let sandbox = try XCTUnwrap(params["sandboxPolicy"] as? [String: Any])
        XCTAssertEqual(sandbox["type"] as? String, "workspaceWrite")
        XCTAssertEqual(sandbox["networkAccess"] as? Bool, false)
        XCTAssertEqual(sandbox["writableRoots"] as? [String], ["/tmp/workspace"])
        let input = try XCTUnwrap(params["input"] as? [[String: Any]])
        XCTAssertEqual(input.map { $0["type"] as? String }, ["text", "localImage", "mention"])
        XCTAssertEqual(input[0]["text"] as? String, "Implement and test")
        XCTAssertEqual(input[1]["path"] as? String, "/tmp/context.png")
        XCTAssertEqual(input[2]["name"] as? String, "brief.pdf")
    }

    func testTypedInterruptUsesThreadAndTurnIDs() throws {
        let sender = RecordingCodexSender()
        _ = try sender.interrupt(threadID: "thread-1", turnID: "turn-2")

        let request = try XCTUnwrap(sender.requests.first)
        XCTAssertEqual(request.method, "turn/interrupt")
        let params = try XCTUnwrap(request.params as? [String: String])
        XCTAssertEqual(params, ["threadId": "thread-1", "turnId": "turn-2"])
    }

    // MARK: - drainMessages

    func testDrainMessagesEmptyBuffer() {
        var buffer = Data()
        let messages = CodexAppServerClient.drainMessages(buffer: &buffer)
        XCTAssertTrue(messages.isEmpty)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDrainMessagesSingleCompleteLine() {
        var buffer = Data(#"{"jsonrpc":"2.0","method":"thread/started","params":{"thread":{"id":"t-1"}}}"#.utf8)
        buffer.append(0x0A)

        let messages = CodexAppServerClient.drainMessages(buffer: &buffer)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.kind, .notification(method: "thread/started"))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDrainMessagesTwoLinesConsumedBothLeavesBufferEmpty() {
        var buffer = Data()
        buffer.append(Data(#"{"jsonrpc":"2.0","method":"thread/started","params":{}}"#.utf8))
        buffer.append(0x0A)
        buffer.append(Data(#"{"jsonrpc":"2.0","method":"turn/started","params":{}}"#.utf8))
        buffer.append(0x0A)

        let messages = CodexAppServerClient.drainMessages(buffer: &buffer)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].kind, .notification(method: "thread/started"))
        XCTAssertEqual(messages[1].kind, .notification(method: "turn/started"))
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDrainMessagesKeepsTrailingPartialLineInBuffer() {
        var buffer = Data()
        buffer.append(Data(#"{"jsonrpc":"2.0","method":"thread/started","params":{}}"#.utf8))
        buffer.append(0x0A)
        buffer.append(Data(#"{"jsonrpc":"2.0","method":"turn/partial"#.utf8))

        let messages = CodexAppServerClient.drainMessages(buffer: &buffer)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(String(data: buffer, encoding: .utf8), #"{"jsonrpc":"2.0","method":"turn/partial"#)
    }

    func testDrainMessagesSkipsBlankLines() {
        var buffer = Data()
        buffer.append(0x0A)
        buffer.append(0x0A)
        buffer.append(Data(#"{"jsonrpc":"2.0","method":"thread/started","params":{}}"#.utf8))
        buffer.append(0x0A)

        let messages = CodexAppServerClient.drainMessages(buffer: &buffer)
        XCTAssertEqual(messages.count, 1)
    }

    // MARK: - parseMessage kind detection

    func testParseMessageClassifiesRequest() {
        let data = Data(#"{"jsonrpc":"2.0","id":42,"method":"thread/start","params":{}}"#.utf8)
        let msg = CodexAppServerClient.parseMessage(data)
        XCTAssertEqual(msg?.kind, .request(method: "thread/start", id: .int(42)))
    }

    func testParseMessageClassifiesNotification() {
        let data = Data(#"{"jsonrpc":"2.0","method":"thread/started","params":{}}"#.utf8)
        let msg = CodexAppServerClient.parseMessage(data)
        XCTAssertEqual(msg?.kind, .notification(method: "thread/started"))
    }

    func testParseMessageClassifiesResponse() {
        let data = Data(#"{"id":7,"result":{"ok":true}}"#.utf8)
        let msg = CodexAppServerClient.parseMessage(data)
        XCTAssertEqual(msg?.kind, .response(id: .int(7)))
    }

    func testParseMessageClassifiesError() {
        let data = Data(#"{"id":7,"error":{"code":-32601,"message":"Method not found"}}"#.utf8)
        let msg = CodexAppServerClient.parseMessage(data)
        XCTAssertEqual(msg?.kind, .error(id: .int(7), code: -32601, message: "Method not found"))
    }

    func testParseMessageHandlesStringId() {
        let data = Data(#"{"jsonrpc":"2.0","id":"abc-1","method":"thread/start","params":{}}"#.utf8)
        let msg = CodexAppServerClient.parseMessage(data)
        XCTAssertEqual(msg?.kind, .request(method: "thread/start", id: .string("abc-1")))
    }

    func testParseMessageRejectsInvalidJSON() {
        let data = Data("not json".utf8)
        XCTAssertNil(CodexAppServerClient.parseMessage(data))
    }

    /// Codex surfaces plan-mode prompts as a server->client *request* (has an id),
    /// not a notification. It must classify as `.request` so AppState can answer it. (#209)
    func testParseMessageClassifiesRequestUserInput() {
        let data = Data(#"{"jsonrpc":"2.0","id":"r-1","method":"item/tool/requestUserInput","params":{"threadId":"t-1","turnId":"u-1","itemId":"i-1","questions":[{"id":"q1","header":"Plan","question":"Pick","isOther":false,"isSecret":false,"options":[{"label":"A","description":"d"}]}]}}"#.utf8)
        let msg = CodexAppServerClient.parseMessage(data)
        XCTAssertEqual(msg?.kind, .request(method: "item/tool/requestUserInput", id: .string("r-1")))
        let questions = msg?.raw["params"]?.asObject?["questions"]
        if case .array(let arr)? = questions {
            XCTAssertEqual(arr.first?.asObject?["id"]?.asString, "q1")
        } else {
            XCTFail("expected questions array")
        }
    }

    func testParseMessagePreservesRawParams() {
        let data = Data(#"{"jsonrpc":"2.0","method":"thread/started","params":{"thread":{"id":"t-1","preview":"hi"}}}"#.utf8)
        let msg = CodexAppServerClient.parseMessage(data)
        let params = msg?.raw["params"]?.asObject
        let thread = params?["thread"]?.asObject
        XCTAssertEqual(thread?["id"]?.asString, "t-1")
        XCTAssertEqual(thread?["preview"]?.asString, "hi")
    }

    // MARK: - AnyCodableLike

    func testAnyCodableLikeRoundTripsPrimitives() {
        XCTAssertEqual(AnyCodableLike.from(nil), .null)
        XCTAssertEqual(AnyCodableLike.from(NSNull()), .null)
        XCTAssertEqual(AnyCodableLike.from(true), .bool(true))
        XCTAssertEqual(AnyCodableLike.from(42), .int(42))
        XCTAssertEqual(AnyCodableLike.from(NSNumber(value: 0)), .int(0))
        XCTAssertEqual(AnyCodableLike.from(NSNumber(value: true)), .bool(true))
        XCTAssertEqual(AnyCodableLike.from("hi"), .string("hi"))

        // Floats end up as .double (bridged through NSNumber's float-check logic).
        if case .double(let value) = AnyCodableLike.from(3.14) {
            XCTAssertEqual(value, 3.14, accuracy: 0.0001)
        } else {
            XCTFail("expected .double for 3.14")
        }
    }

    func testAnyCodableLikeHandlesNestedObject() {
        let obj: [String: Any] = [
            "k1": "v1",
            "k2": 2,
            "k3": [1, 2, 3],
            "k4": ["inner": true]
        ]
        let wrapped = AnyCodableLike.from(obj)
        let dict = wrapped.asObject
        XCTAssertEqual(dict?["k1"]?.asString, "v1")
        XCTAssertEqual(dict?["k2"], .int(2))
        if case .array(let a) = dict?["k3"] ?? .null {
            XCTAssertEqual(a, [.int(1), .int(2), .int(3)])
        } else {
            XCTFail("expected array for k3")
        }
        XCTAssertEqual(dict?["k4"]?.asObject?["inner"]?.asBool, true)
    }
}

private final class RecordingCodexSender: CodexAppServerSending {
    struct Request {
        let id: CodexRequestID
        let method: String
        let params: Any?
    }

    var requests: [Request] = []
    var responses: [(CodexRequestID, Any?)] = []

    func sendRequest(method: String, params: Any?) throws -> CodexRequestID {
        let id = CodexRequestID.int(Int64(requests.count + 1))
        requests.append(Request(id: id, method: method, params: params))
        return id
    }

    func sendResponse(id: CodexRequestID, result: Any?) throws {
        responses.append((id, result))
    }
}
