import Foundation

struct TelegramWebAppInfo: Codable, Equatable {
    let url: URL
}

struct TelegramInlineKeyboardButton: Codable, Equatable {
    let text: String
    let webApp: TelegramWebAppInfo?

    enum CodingKeys: String, CodingKey {
        case text
        case webApp = "web_app"
    }
}

struct TelegramInlineKeyboardMarkup: Codable, Equatable {
    let inlineKeyboard: [[TelegramInlineKeyboardButton]]

    static let empty = TelegramInlineKeyboardMarkup(inlineKeyboard: [])

    enum CodingKeys: String, CodingKey {
        case inlineKeyboard = "inline_keyboard"
    }
}

struct TelegramSendMessagePayload: Codable, Equatable {
    let chatID: String
    let disableWebPagePreview: Bool
    let text: String
    let replyMarkup: TelegramInlineKeyboardMarkup?

    static func secureReview(chatID: String, text: String, reviewURL: URL) -> Self {
        Self(
            chatID: chatID,
            disableWebPagePreview: true,
            text: text,
            replyMarkup: TelegramInlineKeyboardMarkup(inlineKeyboard: [[
                TelegramInlineKeyboardButton(
                    text: "Review securely",
                    webApp: TelegramWebAppInfo(url: reviewURL)
                )
            ]])
        )
    }

    static func redactedAlert(chatID: String, text: String) -> Self {
        Self(
            chatID: chatID,
            disableWebPagePreview: true,
            text: text,
            replyMarkup: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case disableWebPagePreview = "disable_web_page_preview"
        case text
        case replyMarkup = "reply_markup"
    }
}

struct TelegramEditMessagePayload: Codable, Equatable {
    let chatID: String
    let messageID: Int
    let text: String?
    let replyMarkup: TelegramInlineKeyboardMarkup

    enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case messageID = "message_id"
        case text
        case replyMarkup = "reply_markup"
    }
}

struct TelegramSentMessage: Equatable {
    let messageID: Int
}

protocol TelegramBotAPIClientProtocol {
    func sendMessage(
        _ payload: TelegramSendMessagePayload,
        botToken: String
    ) async throws -> TelegramSentMessage

    func editMessage(
        _ payload: TelegramEditMessagePayload,
        botToken: String
    ) async throws
}

struct TelegramBotAPIClient: TelegramBotAPIClientProtocol {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func sendMessage(
        _ payload: TelegramSendMessagePayload,
        botToken: String
    ) async throws -> TelegramSentMessage {
        let request = try makeRequest(
            endpoint: "sendMessage",
            botToken: botToken,
            body: encoder.encode(payload)
        )
        let (data, response) = try await session.data(for: request)
        let result: TelegramAPIResponse<TelegramMessageResult> = try decodeResponse(
            data: data,
            response: response
        )
        guard let message = result.result else {
            throw TelegramBotAPIError.invalidResponse
        }
        return TelegramSentMessage(messageID: message.messageID)
    }

    func editMessage(
        _ payload: TelegramEditMessagePayload,
        botToken: String
    ) async throws {
        let endpoint = payload.text == nil ? "editMessageReplyMarkup" : "editMessageText"
        let request = try makeRequest(
            endpoint: endpoint,
            botToken: botToken,
            body: encoder.encode(payload)
        )
        let (data, response) = try await session.data(for: request)
        let _: TelegramAPIResponse<TelegramMessageResult> = try decodeResponse(
            data: data,
            response: response
        )
    }

    private func makeRequest(endpoint: String, botToken: String, body: Data) throws -> URLRequest {
        let trimmedToken = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty,
              let url = URL(string: "https://api.telegram.org/bot\(trimmedToken)/\(endpoint)")
        else {
            throw TelegramBotAPIError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body
        return request
    }

    private func decodeResponse<Result: Decodable>(
        data: Data,
        response: URLResponse
    ) throws -> TelegramAPIResponse<Result> {
        guard let http = response as? HTTPURLResponse else {
            throw TelegramBotAPIError.invalidResponse
        }
        let decoded = try? decoder.decode(TelegramAPIResponse<Result>.self, from: data)
        guard (200..<300).contains(http.statusCode), decoded?.ok == true else {
            let description = decoded?.description.map(Self.sanitizedDescription) ?? "Request rejected"
            throw TelegramBotAPIError.rejected(status: http.statusCode, description: description)
        }
        guard let decoded else {
            throw TelegramBotAPIError.invalidResponse
        }
        return decoded
    }

    private static func sanitizedDescription(_ value: String) -> String {
        let withoutURLs = value.replacingOccurrences(
            of: #"https?://[^\s]+"#,
            with: "[URL]",
            options: .regularExpression
        )
        return String(withoutURLs.prefix(300))
    }
}

private enum TelegramBotAPIError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case rejected(status: Int, description: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Telegram configuration is incomplete"
        case .invalidResponse:
            return "Telegram returned an invalid response"
        case .rejected(let status, let description):
            return "Telegram rejected the request (\(status)): \(description)"
        }
    }
}

private struct TelegramAPIResponse<Result: Decodable>: Decodable {
    let ok: Bool
    let result: Result?
    let description: String?
}

private struct TelegramMessageResult: Decodable {
    let messageID: Int

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
    }
}
