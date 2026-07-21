import XCTest
@testable import CodeIsland

final class TelegramBotAPIClientTests: XCTestCase {
    override func tearDown() {
        TelegramURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testSecureReviewPayloadContainsOnlyOpaqueLaunchURL() throws {
        let payload = TelegramSendMessagePayload.secureReview(
            chatID: "42",
            text: "CodeIsland needs your approval.",
            reviewURL: try XCTUnwrap(URL(string: "https://mac.tailnet:9443/telegram/approval?launch=opaque"))
        )
        let data = try JSONEncoder.telegram.encode(payload)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let markup = try XCTUnwrap(object["reply_markup"] as? [String: Any])
        let rows = try XCTUnwrap(markup["inline_keyboard"] as? [[[String: Any]]])
        let button = try XCTUnwrap(rows.first?.first)
        let webApp = try XCTUnwrap(button["web_app"] as? [String: Any])
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(button["text"] as? String, "Review securely")
        XCTAssertEqual(webApp["url"] as? String, "https://mac.tailnet:9443/telegram/approval?launch=opaque")
        XCTAssertFalse(encoded.contains("request-1"))
        XCTAssertFalse(encoded.contains("action-token"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("git push"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("workspace"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("transcript"))
    }

    func testRedactedAlertHasNoApprovalButton() throws {
        let payload = TelegramSendMessagePayload.redactedAlert(
            chatID: "42",
            text: "CodeIsland needs your answer."
        )
        let data = try JSONEncoder.telegram.encode(payload)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(object["reply_markup"])
    }

    @MainActor
    func testPreparedReviewURLContainsOnlyOpaqueLaunchNonce() throws {
        let controller = TelegramApprovalController(
            vault: TelegramApprovalSessionVault(tokenGenerator: { "opaque-launch" })
        )
        let prepared = try controller.prepareLaunch(
            requestID: "request-1",
            chatID: 42,
            baseURL: try XCTUnwrap(URL(string: "https://mac.tailnet:9443"))
        )
        let components = try XCTUnwrap(
            URLComponents(url: prepared.reviewURL, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(components.path, "/telegram/approval")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "launch", value: "opaque-launch")])
        XCTAssertFalse(prepared.reviewURL.absoluteString.contains("request-1"))
    }

    func testSendMessageParsesTelegramMessageID() async throws {
        let session = stubbedSession { request in
            XCTAssertEqual(request.url?.path, "/bot123:test/sendMessage")
            return Self.response(
                for: request,
                status: 200,
                body: #"{"ok":true,"result":{"message_id":314}}"#
            )
        }
        let client = TelegramBotAPIClient(session: session)
        let sent = try await client.sendMessage(
            .redactedAlert(chatID: "42", text: "Needs attention"),
            botToken: "123:test"
        )

        XCTAssertEqual(sent.messageID, 314)
    }

    func testEditMessageRemovesReviewButton() async throws {
        let session = stubbedSession { request in
            XCTAssertEqual(request.url?.path, "/bot123:test/editMessageText")
            let body = try Self.requestBody(request)
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let markup = try XCTUnwrap(object["reply_markup"] as? [String: Any])
            let rows = try XCTUnwrap(markup["inline_keyboard"] as? [Any])
            XCTAssertTrue(rows.isEmpty)
            return Self.response(
                for: request,
                status: 200,
                body: #"{"ok":true,"result":{"message_id":314}}"#
            )
        }
        let client = TelegramBotAPIClient(session: session)

        try await client.editMessage(
            TelegramEditMessagePayload(
                chatID: "42",
                messageID: 314,
                text: "Approved in CodeIsland",
                replyMarkup: .empty
            ),
            botToken: "123:test"
        )
    }

    private func stubbedSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        TelegramURLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelegramURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }

    private static func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private final class TelegramURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension JSONEncoder {
    static var telegram: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
