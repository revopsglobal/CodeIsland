import Foundation

enum TailscaleServeManager {
    enum ServeError: LocalizedError {
        case executableMissing
        case commandFailed(String)
        case tailnetNameMissing

        var errorDescription: String? {
            switch self {
            case .executableMissing:
                return "Tailscale CLI was not found"
            case .commandFailed(let message):
                return message
            case .tailnetNameMissing:
                return "Tailscale is running but its MagicDNS name was unavailable"
            }
        }
    }

    static func configure(localPort: Int, httpsPort: Int) throws -> String {
        let executable = [
            "/usr/local/bin/tailscale",
            "/opt/homebrew/bin/tailscale"
        ].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        guard let executable else { throw ServeError.executableMissing }

        let target = "http://127.0.0.1:\(localPort)"
        _ = try run(
            executable,
            arguments: ["serve", "--bg", "--https=\(httpsPort)", target]
        )
        let statusData = try run(executable, arguments: ["status", "--json"])
        guard let root = try JSONSerialization.jsonObject(with: statusData) as? [String: Any],
              let selfNode = root["Self"] as? [String: Any],
              let rawDNSName = selfNode["DNSName"] as? String,
              !rawDNSName.isEmpty
        else {
            throw ServeError.tailnetNameMissing
        }
        let dnsName = rawDNSName.hasSuffix(".") ? String(rawDNSName.dropLast()) : rawDNSName
        return "https://\(dnsName):\(httpsPort)"
    }

    @discardableResult
    private static func run(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.isEmpty ? stdout : stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ServeError.commandFailed(message?.isEmpty == false ? message! : "Tailscale Serve failed")
        }
        return stdout
    }
}

