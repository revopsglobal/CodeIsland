import Foundation
import XCTest
@testable import CodeIsland

@MainActor
final class RemoteApprovalHTTPServerTests: XCTestCase {
    func testServerRetainsConnectionUntilResponseCompletes() async throws {
        let ready = expectation(description: "listener ready")
        var startupError: Error?
        let server = try RemoteApprovalHTTPServer(port: 0) { request in
            guard request.method == "GET", request.path == "/health" else {
                return .json(status: 404, object: ["error": "not found"])
            }
            return .json(status: 200, object: ["running": true])
        }
        defer { server.stop() }

        server.start { result in
            if case .failure(let error) = result {
                startupError = error
            }
            ready.fulfill()
        }
        await fulfillment(of: [ready], timeout: 3)
        if let startupError { throw startupError }

        let port = try XCTUnwrap(server.boundPort)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/health"))
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Bool])
        XCTAssertEqual(object["running"], true)
    }
}
