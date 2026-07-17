import Foundation

/// Global pairing throttle for the tailnet-only endpoint. Tailscale Serve
/// forwards over loopback, so per-client source addresses are not available.
struct RemotePairAttemptLimiter {
    private let maximumFailures: Int
    private let window: TimeInterval
    private var failures: [Date] = []

    init(maximumFailures: Int = 8, window: TimeInterval = 300) {
        self.maximumFailures = maximumFailures
        self.window = window
    }

    mutating func canAttempt(at date: Date = Date()) -> Bool {
        prune(at: date)
        return failures.count < maximumFailures
    }

    mutating func recordFailure(at date: Date = Date()) {
        prune(at: date)
        failures.append(date)
    }

    mutating func reset() {
        failures.removeAll(keepingCapacity: true)
    }

    private mutating func prune(at date: Date) {
        let cutoff = date.addingTimeInterval(-window)
        failures.removeAll { $0 <= cutoff }
    }
}
