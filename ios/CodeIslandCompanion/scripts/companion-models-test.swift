import Foundation

// Behavior check for #246 tolerant decoding (runs the real CompanionModels.swift).
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL"): \(name)")
    if !condition { exit(1) }
}

// 1. Unknown status value from a newer Mac app → decodes as .idle, not throw.
let unknownStatus = """
{"version":1,"sequence":42,"source":"claude","status":"connecting",
 "messages":[{"role":"user","text":"hi"}],"updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: unknownStatus)
    check("unknown status falls back to idle", state.status == .idle)
} catch { check("unknown status decodes at all", false) }

// 2. Unknown pendingAction + unknown message role → degrade, not throw.
let unknownEnums = """
{"version":1,"sequence":43,"source":"claude","status":"processing",
 "messages":[{"role":"system","text":"x"}],"pendingAction":"handoff",
 "updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: unknownEnums)
    check("unknown pendingAction degrades to nil", state.pendingAction == nil)
    check("unknown role degrades to assistant", state.messages.first?.role == .assistant)
} catch { check("unknown enums decode at all", false) }

// 3. Question missing descriptions/index/total → defaults, not throw.
let sparseQuestion = """
{"version":1,"sequence":44,"source":"claude","status":"waitingQuestion",
 "messages":[],"question":{"question":"Pick one","options":["a","b"]},
 "updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: sparseQuestion)
    check("sparse question decodes", state.question != nil)
    check("total defaults to >= 1", state.question!.total >= 1)
    check("index clamps to >= 0", state.question!.index >= 0)
} catch { check("sparse question decodes at all", false) }

// 4. Negative index / zero total clamp.
let weirdQuestion = """
{"version":1,"sequence":45,"source":"claude","status":"waitingQuestion",
 "messages":[],"question":{"question":"q","options":[],"index":-3,"total":0},
 "updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: weirdQuestion)
    check("negative index clamped", state.question!.index == 0)
    check("zero total clamped", state.question!.total == 1)
} catch { check("weird question decodes at all", false) }

// 5. Malformed question object degrades to nil instead of sinking the payload.
let brokenQuestion = """
{"version":1,"sequence":46,"source":"claude","status":"processing",
 "messages":[],"question":{"options":["a"]},
 "updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: brokenQuestion)
    check("broken question degrades to nil", state.question == nil)
} catch { check("broken question payload decodes at all", false) }

// 6. Missing updatedAt / messages (older Mac app) → defaults.
let minimal = """
{"version":1,"sequence":47,"source":"codex","status":"running"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: minimal)
    check("minimal payload decodes", state.messages.isEmpty && state.sessions.isEmpty && state.personalStatus == nil)
} catch { check("minimal payload decodes at all", false) }

// 7. Round-trip: what today's Mac sends still decodes exactly.
let full = """
{"version":1,"sequence":48,"sessionId":"s1","source":"claude","status":"waitingApproval",
 "toolName":"Bash","workspaceName":"proj",
 "messages":[{"role":"user","text":"do it"},{"role":"assistant","text":"ok"}],
 "pendingAction":"approval",
 "question":null,
 "sessions":[{"source":"claude","status":"waitingApproval","updatedAt":"2026-07-05T12:00:00Z"}],
 "updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: full)
    check("full payload keeps status", state.status == .waitingApproval)
    check("full payload keeps pendingAction", state.pendingAction == .approval)
    check("full payload keeps sessions", state.sessions.count == 1)
    check("full payload keeps messages", state.messages.count == 2)
} catch { check("full payload decodes at all", false) }

// 8. Optional personal signals decode without changing the established agent state.
let personal = """
{"version":1,"sequence":49,"source":"codex","status":"running",
 "personalStatus":{"download":{"name":"Crest-4.9.0.dmg","bytesReceived":50,"totalBytes":100},
 "devices":[{"name":"AirPods","percent":18,"detail":"L 18% · R 22%"}]},
 "updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: personal)
    check("personal download decodes", state.personalStatus?.download?.progress == 0.5)
    check("personal battery decodes", state.personalStatus?.devices.first?.percent == 18)
    check("personal state preserves agent status", state.status == .running)
} catch { check("personal payload decodes at all", false) }

// 9. Remote approval payload keeps its exact request binding and single-use token.
let remoteApproval = """
{"version":1,"serverName":"Greg's Mac","generatedAt":"2026-07-17T04:00:00Z",
 "approvals":[{"id":"request-123","sessionId":"session-456","source":"Codex","tool":"Bash",
 "detail":"npm test","workspace":"CodeIsland","createdAt":"2026-07-17T03:59:00Z",
 "actionToken":"single-use-token","actionExpiresAt":"2026-07-17T04:02:00Z"}],
 "questions":[{"id":"question-123","sessionId":"session-456","source":"Codex","workspace":"CodeIsland",
 "createdAt":"2026-07-17T03:59:30Z","prompts":[{"id":"choice","header":"Mode","question":"Continue?",
 "options":["Yes","No"],"descriptions":[],"allowsMultipleSelection":false}],"requiresLocalResponse":false,
 "actionToken":"question-token","actionExpiresAt":"2026-07-17T04:02:30Z"}]}
""".data(using: .utf8)!
do {
    let snapshot = try decoder.decode(RemoteApprovalSnapshot.self, from: remoteApproval)
    check("remote approval keeps exact request id", snapshot.approvals.first?.id == "request-123")
    check("remote approval keeps action token", snapshot.approvals.first?.actionToken == "single-use-token")
    check("remote question keeps exact request id", snapshot.questions.first?.id == "question-123")
    check("remote question keeps action token", snapshot.questions.first?.actionToken == "question-token")
    let decision = RemoteDecisionRequest(decision: .approve, actionToken: "single-use-token")
    check("remote decision encodes approve", decision.decision == .approve)
} catch { check("remote approval payload decodes at all", false) }

let legacyRemoteApproval = """
{"version":1,"serverName":"Greg's Mac","generatedAt":"2026-07-17T04:00:00Z","approvals":[]}
""".data(using: .utf8)!
do {
    let snapshot = try decoder.decode(RemoteApprovalSnapshot.self, from: legacyRemoteApproval)
    check("legacy remote snapshot defaults questions", snapshot.questions.isEmpty)
} catch { check("legacy remote snapshot still decodes", false) }

let codexRunning = CompanionSessionPreview(
    sessionId: "codex",
    source: "codex",
    status: .running,
    toolName: nil,
    workspaceName: "ob1-app",
    message: nil,
    updatedAt: Date(timeIntervalSince1970: 100)
)
let claudeRunning = CompanionSessionPreview(
    sessionId: "claude",
    source: "claude",
    status: .running,
    toolName: nil,
    workspaceName: "ob1-app",
    message: nil,
    updatedAt: Date(timeIntervalSince1970: 200)
)
let approval = CompanionSessionPreview(
    sessionId: "approval",
    source: "claude",
    status: .waitingApproval,
    toolName: nil,
    workspaceName: "ob1-app",
    message: nil,
    updatedAt: Date(timeIntervalSince1970: 50)
)
check(
    "routine session ordering is stable across heartbeat updates",
    CompanionSessionOrdering.ordered([codexRunning, claudeRunning]).map(\.id)
        == CompanionSessionOrdering.ordered([claudeRunning, codexRunning]).map(\.id)
)
check(
    "action-required session ordering still wins over routine work",
    CompanionSessionOrdering.ordered([codexRunning, approval, claudeRunning]).first?.id == "approval"
)

print("ALL PASS")
