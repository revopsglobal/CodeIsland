import Darwin
import Foundation
import UIKit

enum AgentOpsMobileReceiptKind: String, Codable, Sendable {
    case appForegrounded = "app.foregrounded"
    case appBackgrounded = "app.backgrounded"
    case audioRouteChanged = "audio.route_changed"
    case voicePlaybackCancelled = "voice.playback_cancelled"
    case voiceBackgroundCancelled = "voice.background_cancelled"
    case voiceTurnCompleted = "voice.turn_completed"
    case voiceProviderUnavailable = "voice.provider_unavailable"
    case draftSaved = "draft.saved"
    case draftReplayed = "draft.replayed"
    case draftCompleted = "draft.completed"
    case pushAcceptedVisible = "push.accepted_visible"
    case pushAcceptedSilent = "push.accepted_silent"
    case pushRejectedStale = "push.rejected_stale"
    case pushRejectedRegressive = "push.rejected_regressive"
    case liveActivityStarted = "live_activity.started"
    case liveActivityUpdated = "live_activity.updated"
    case liveActivityEnded = "live_activity.ended"
}

enum AgentOpsAudioRouteKind: String, Codable, CaseIterable, Sendable {
    case speaker
    case receiver
    case bluetooth
    case airplay
    case headphones
    case other
}

struct AgentOpsMobileClientSnapshot: Codable, Equatable, Sendable {
    let appVersion: String
    let build: String
    let osVersion: String
    let deviceModel: String

    static func current(bundle: Bundle = .main) -> AgentOpsMobileClientSnapshot {
        AgentOpsMobileClientSnapshot(
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            build: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            osVersion: UIDevice.current.systemVersion,
            deviceModel: hardwareModelIdentifier()
        )
    }

    private static func hardwareModelIdentifier() -> String {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else { return UIDevice.current.model }
        let mirror = Mirror(reflecting: systemInfo.machine)
        let bytes = mirror.children.compactMap { element -> UInt8? in
            guard let value = element.value as? Int8, value != 0 else {
                return nil
            }
            return UInt8(bitPattern: value)
        }
        let value = String(bytes: bytes, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else {
            return UIDevice.current.model
        }
        return value
    }
}

struct AgentOpsMobileReceipt: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: AgentOpsMobileReceiptKind
    let observedAt: Date
    let sessionId: UUID?
    let taskId: UUID?
    let audioRoute: AgentOpsAudioRouteKind?
    let pushEventType: AgentOpsMobileEventType?
    let pushVersion: Int?
    let fallbackUsed: Bool?
    let draftCount: Int?

    init(
        id: UUID = UUID(),
        kind: AgentOpsMobileReceiptKind,
        observedAt: Date = Date(),
        sessionId: UUID? = nil,
        taskId: UUID? = nil,
        audioRoute: AgentOpsAudioRouteKind? = nil,
        pushEventType: AgentOpsMobileEventType? = nil,
        pushVersion: Int? = nil,
        fallbackUsed: Bool? = nil,
        draftCount: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.observedAt = observedAt
        self.sessionId = sessionId
        self.taskId = taskId
        self.audioRoute = audioRoute
        self.pushEventType = pushEventType
        self.pushVersion = pushVersion
        self.fallbackUsed = fallbackUsed
        self.draftCount = draftCount
    }
}

@MainActor
final class AgentOpsMobileReceiptJournal {
    static let shared = AgentOpsMobileReceiptJournal()

    private static let pendingKey = "agentops.mobile.receipts.pending.v1"
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private let uuid: () -> UUID
    private let clientProvider: () -> AgentOpsMobileClientSnapshot

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init,
        uuid: @escaping () -> UUID = UUID.init,
        clientProvider: @escaping () -> AgentOpsMobileClientSnapshot = {
            .current()
        }
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.now = now
        self.uuid = uuid
        self.clientProvider = clientProvider
    }

    var client: AgentOpsMobileClientSnapshot {
        clientProvider()
    }

    var pending: [AgentOpsMobileReceipt] {
        guard
            let data = defaults.data(forKey: Self.pendingKey),
            let values = try? Self.decoder.decode(
                [AgentOpsMobileReceipt].self,
                from: data
            )
        else { return [] }
        return values
    }

    @discardableResult
    func record(
        _ kind: AgentOpsMobileReceiptKind,
        sessionID: UUID? = nil,
        taskID: UUID? = nil,
        audioRoute: AgentOpsAudioRouteKind? = nil,
        pushEventType: AgentOpsMobileEventType? = nil,
        pushVersion: Int? = nil,
        fallbackUsed: Bool? = nil,
        draftCount: Int? = nil
    ) -> AgentOpsMobileReceipt {
        let receipt = AgentOpsMobileReceipt(
            id: uuid(),
            kind: kind,
            observedAt: now(),
            sessionId: sessionID,
            taskId: taskID,
            audioRoute: audioRoute,
            pushEventType: pushEventType,
            pushVersion: pushVersion,
            fallbackUsed: fallbackUsed,
            draftCount: draftCount.map { min(max($0, 0), 128) }
        )
        var values = pending
        values.append(receipt)
        if values.count > 128 {
            values = Array(values.suffix(128))
        }
        persist(values)
        notificationCenter.post(
            name: .agentOpsMobileReceiptAvailable,
            object: nil
        )
        return receipt
    }

    func clear(_ receipts: [AgentOpsMobileReceipt]) {
        let ids = Set(receipts.map(\.id))
        guard !ids.isEmpty else { return }
        persist(pending.filter { !ids.contains($0.id) })
    }

    private func persist(_ values: [AgentOpsMobileReceipt]) {
        guard !values.isEmpty else {
            defaults.removeObject(forKey: Self.pendingKey)
            return
        }
        guard let data = try? Self.encoder.encode(values) else { return }
        defaults.set(data, forKey: Self.pendingKey)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension Notification.Name {
    static let agentOpsMobileReceiptAvailable = Notification.Name(
        "agentops.mobile-receipt-available"
    )
}
