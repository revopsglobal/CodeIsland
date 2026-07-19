# iPhone Edit-and-Test Dispatch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let Greg create and steer Codex or Claude coding tasks from CodeIsland Buddy while the paired Mac automatically performs bounded file edits and tests, then returns authenticated completion evidence and gates every consequential action.

**Architecture:** Add a shared remote-task contract, a durable Mac-owned task/receipt store, provider adapters for Codex app-server and Claude Code, and authenticated task endpoints to the existing Tailscale listener. Extend Buddy's existing `Now`, `Sessions`, deep-link, App Intent, APNs, ActivityKit, and exact-confirmation surfaces; add a Share Extension that hands an editable draft to the main app through an App Group. The Mac remains the sole executor and source of truth; Telegram remains outbound notification only.

**Tech Stack:** Swift 5.9+, SwiftUI, Combine, Foundation, Network.framework, CryptoKit, Codex app-server JSON-RPC, Claude Code stream-json, App Intents, Share Extension, App Groups, UserNotifications, ActivityKit, WidgetKit, XCTest/XCUITest, XcodeGen, GitHub Actions, Tailscale Serve.

---

## Preconditions and delivery rules

- Read `docs/plans/2026-07-19-iphone-edit-test-dispatch-design.md` before implementation.
- Start from current `origin/main` in a dedicated `codex/` worktree. Preserve the existing untracked `.playwright-cli/` and `graphify-out/` directories.
- Keep source, commit, push, merge, signed build, TestFlight availability, physical install, Wi-Fi proof, and cellular proof as separate states.
- Do not add a hosted database, paid service, inbound Telegram bot, generic shell API, Pomodoro feature, or Apple Watch work.
- Run `graphify update . --no-viz` after code changes and before final verification.
- Use `@systematic-debugging` on any unexpected test/runtime failure and `@verification-before-completion` before any completion claim.

### Task 1: Define the shared task, receipt, evidence, and deep-link contract

**Files:**
- Create: `Sources/CodeIslandCore/RemoteTaskProtocol.swift`
- Create: `Tests/CodeIslandCoreTests/RemoteTaskProtocolTests.swift`
- Modify: `Sources/CodeIslandCore/PersonalHubProtocol.swift:857-917`
- Modify: `ios/CodeIslandCompanion/project.yml:14-42`
- Regenerate: `ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj/project.pbxproj`

**Step 1: Write the failing shared-protocol tests**

Cover:

```swift
func testTaskLifecycleExposesOnlySupportedUserStates()
func testTaskRequestBindingIsStableAcrossKeyOrder()
func testReceiptSequenceRejectsOlderState()
func testTaskDeepLinkRoundTripsTaskAndNewTaskRoutes()
func testPushSummaryNeverIncludesPromptOrAttachmentName()
```

Use a contract shaped like:

```swift
public enum RemoteTaskProvider: String, Codable, Sendable {
    case auto, codex, claude
}

public enum RemoteTaskAuthority: String, Codable, Sendable {
    case editAndTest = "edit-and-test"
}

public enum RemoteTaskState: String, Codable, Sendable {
    case waitingForMac, queued, working, needsYou, verified, failed, cancelled
}

public struct RemoteTaskCreateRequest: Codable, Equatable, Sendable {
    public let clientTaskID: UUID
    public let idempotencyKey: UUID
    public let prompt: String
    public let workspaceID: String?
    public let provider: RemoteTaskProvider
    public let authority: RemoteTaskAuthority
    public let attachments: [RemoteTaskAttachmentDescriptor]
    public let requestedProof: String?
    public let createdAt: Date
}
```

Add `RemoteTaskSummary`, `RemoteTaskReceipt`, `RemoteTaskEvidence`,
`RemoteTaskSnapshot`, `RemoteTaskFollowUpRequest`, `RemoteTaskActionIntent`, and
`RemoteTaskPreparedAction`. Make all public wire types `Codable`, `Equatable`,
and `Sendable`.

**Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --filter RemoteTaskProtocolTests
```

Expected: FAIL because `RemoteTaskProtocol` and task deep-link cases do not yet exist.

**Step 3: Implement the minimal versioned contract**

- Use explicit `version` fields on requests/snapshots.
- Store only an opaque attachment ID, filename-safe display name, byte count,
  media type, and SHA-256 in descriptors.
- Add `.task(id:)` and `.newTask(text:)` to `PersonalHubDeepLink`.
- Encode `codeisland://tasks/<id>` and `codeisland://new-task?text=...` without
  ever placing file URLs, tokens, or full prompts in push-safe URLs.
- Add the new shared source to `project.yml`, then regenerate the project:

```bash
cd ios/CodeIslandCompanion
xcodegen generate
```

**Step 4: Run shared and existing deep-link tests**

Run:

```bash
swift test --filter 'RemoteTaskProtocolTests|PersonalHubProtocolTests'
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/CodeIslandCore/RemoteTaskProtocol.swift \
  Sources/CodeIslandCore/PersonalHubProtocol.swift \
  Tests/CodeIslandCoreTests/RemoteTaskProtocolTests.swift \
  ios/CodeIslandCompanion/project.yml \
  ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj/project.pbxproj
git commit -m "feat: define remote coding task contract"
```

### Task 2: Add the durable Mac task and append-only receipt store

**Files:**
- Create: `Sources/CodeIsland/RemoteTaskStore.swift`
- Create: `Tests/CodeIslandTests/RemoteTaskStoreTests.swift`

**Step 1: Write failing persistence and idempotency tests**

Cover:

```swift
func testCreateReturnsExistingTaskForRepeatedIdempotencyKey()
func testReceiptSequenceIsMonotonicAndAppendOnly()
func testReloadRestoresTerminalAndNonTerminalTasks()
func testOutOfOrderReceiptCannotRegressTaskState()
func testStoreNeverPersistsBearerOrActionTokens()
func testCorruptSnapshotIsQuarantinedWithoutDeletingReceiptLog()
```

Inject all file locations in tests. Never write test data to Greg's real
Application Support directory.

**Step 2: Run the focused test and verify it fails**

```bash
swift test --filter RemoteTaskStoreTests
```

Expected: FAIL because `RemoteTaskStore` does not exist.

**Step 3: Implement atomic snapshots plus a JSONL receipt ledger**

Implement:

```swift
@MainActor
final class RemoteTaskStore: ObservableObject {
    @Published private(set) var tasks: [RemoteTaskRecord]

    func create(_ request: RemoteTaskCreateRequest, deviceID: String) throws -> RemoteTaskRecord
    func append(_ receipt: RemoteTaskReceipt) throws
    func task(id: UUID) -> RemoteTaskRecord?
    func snapshot() -> RemoteTaskSnapshot
}
```

Default paths:

```text
~/Library/Application Support/CodeIsland/Remote Tasks/tasks.json
~/Library/Application Support/CodeIsland/Remote Tasks/receipts.jsonl
```

Write snapshots atomically, fsync the JSONL receipt before publishing the new
state, keep the latest 200 terminal tasks in the snapshot, and retain the
append-only ledger. Quarantine corrupt snapshots by renaming them with an ISO
timestamp; do not truncate the receipt log.

**Step 4: Run focused tests**

```bash
swift test --filter RemoteTaskStoreTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/CodeIsland/RemoteTaskStore.swift Tests/CodeIslandTests/RemoteTaskStoreTests.swift
git commit -m "feat: persist remote task receipts"
```

### Task 3: Validate workspaces and stage private attachments

**Files:**
- Create: `Sources/CodeIsland/RemoteWorkspaceCatalog.swift`
- Create: `Sources/CodeIsland/RemoteTaskAttachmentStore.swift`
- Create: `Tests/CodeIslandTests/RemoteWorkspaceCatalogTests.swift`
- Create: `Tests/CodeIslandTests/RemoteTaskAttachmentStoreTests.swift`
- Modify: `Sources/CodeIsland/RemoteCwdFilter.swift`
- Modify: `Tests/CodeIslandTests/RemoteCwdFilterTests.swift`

**Step 1: Write failing workspace tests**

Prove that the catalog:

- canonicalizes symlinks such as the compatibility OB1 path;
- offers recent session roots before older explicitly allowed roots;
- rejects a non-directory, deleted directory, home directory, `/`, and paths
  outside configured roots;
- returns `ambiguous` instead of guessing when two candidates score equally;
- preserves a stable opaque workspace ID while never sending an absolute path
  in a push payload.

**Step 2: Write failing attachment-boundary tests**

Prove:

- filename traversal (`../`, absolute paths, encoded separators) is rejected;
- SHA-256 and byte count are computed from stored bytes;
- one file over 25 MB or one task over 50 MB is rejected;
- MIME type and extension mismatch is recorded and never treated as executable;
- cleanup removes only the exact task inbox; and
- a staged file cannot escape the task-scoped directory through a symlink.

**Step 3: Run and verify failure**

```bash
swift test --filter 'RemoteWorkspaceCatalogTests|RemoteTaskAttachmentStoreTests|RemoteCwdFilterTests'
```

Expected: FAIL for missing types and new validation behavior.

**Step 4: Implement the catalog and inbox**

Use:

```text
~/Library/Application Support/CodeIsland/Remote Tasks/Attachments/<task-id>/<attachment-id>
```

The workspace catalog may ingest `AppState.sessions` and explicit saved roots,
but the host must resolve the opaque ID back to a canonical path at execution
time. Do not trust an iPhone-supplied absolute path.

**Step 5: Run focused tests**

```bash
swift test --filter 'RemoteWorkspaceCatalogTests|RemoteTaskAttachmentStoreTests|RemoteCwdFilterTests'
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodeIsland/RemoteWorkspaceCatalog.swift \
  Sources/CodeIsland/RemoteTaskAttachmentStore.swift \
  Sources/CodeIsland/RemoteCwdFilter.swift \
  Tests/CodeIslandTests/RemoteWorkspaceCatalogTests.swift \
  Tests/CodeIslandTests/RemoteTaskAttachmentStoreTests.swift \
  Tests/CodeIslandTests/RemoteCwdFilterTests.swift
git commit -m "feat: validate remote workspaces and attachments"
```

### Task 4: Enforce the Edit & Test execution policy

**Files:**
- Create: `Sources/CodeIsland/RemoteTaskExecutionPolicy.swift`
- Create: `Tests/CodeIslandTests/RemoteTaskExecutionPolicyTests.swift`
- Modify: `Sources/CodeIsland/CodexPermissionRules.swift`

**Step 1: Write the failing policy matrix**

The pure classifier must return one of `allow`, `needsApproval`, or `deny`.
Test at least:

```text
ALLOW: read files, apply file edits, swift test, xcodebuild test, npm test,
       pnpm test, pytest, cargo test, go test, formatters, git status/diff/log
NEEDS APPROVAL: git commit/push/merge, gh pr create/merge, deploy/release,
                production SQL, credentials/auth/2FA, external messages,
                package installation, network enablement
DENY: recursive broad deletion, writing outside the validated workspace,
      arbitrary shell requested directly by the phone, bypass-permission flags
```

Include chained, quoted, absolute-executable, alias, and newline-separated
variants. A substring-only implementation is not acceptable.

**Step 2: Run and verify failure**

```bash
swift test --filter RemoteTaskExecutionPolicyTests
```

Expected: FAIL because the classifier does not exist.

**Step 3: Implement a conservative structured policy**

- Prefer provider-supplied parsed command actions.
- Parse the executable and arguments without evaluating the shell.
- Treat shell metacharacters or unparseable compound commands as
  `needsApproval`, never `allow`.
- Bind decisions to the canonical task workspace.
- Allow file changes inside the isolated worktree.
- Start Codex tasks with `sandbox = workspace-write`, network disabled, and an
  approval policy that produces server approval requests.
- Start Claude with `--permission-mode acceptEdits`; route Bash/tool permission
  hooks through the same classifier.
- Add developer instructions stating the authority boundary, but do not treat
  prompt text as the security control.

**Step 4: Run the policy and existing permission tests**

```bash
swift test --filter 'RemoteTaskExecutionPolicyTests|CodexPermissionRules|AppStatePermissionFlowTests'
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/CodeIsland/RemoteTaskExecutionPolicy.swift \
  Sources/CodeIsland/CodexPermissionRules.swift \
  Tests/CodeIslandTests/RemoteTaskExecutionPolicyTests.swift
git commit -m "feat: enforce edit and test authority"
```

### Task 5: Add Codex task start, follow-up, interrupt, and completion routing

**Files:**
- Create: `Sources/CodeIsland/CodexRemoteTaskRunner.swift`
- Create: `Tests/CodeIslandTests/CodexRemoteTaskRunnerTests.swift`
- Modify: `Sources/CodeIslandCore/CodexAppServerClient.swift:108-291`
- Modify: `Tests/CodeIslandCoreTests/CodexAppServerClientTests.swift`
- Modify: `Sources/CodeIsland/AppState+CodexAppServer.swift:67-190`
- Modify: `Tests/CodeIslandTests/AppStateCodexAppServerTests.swift`
- Modify: `Tests/CodeIslandTests/AppStateCodexRequestUserInputTests.swift`

**Step 1: Add failing JSON-RPC correlation tests**

Test request/response correlation for:

```text
thread/start -> thread ID
turn/start -> turn ID
turn/interrupt -> terminal interrupted event
item/commandExecution/requestApproval -> policy decision or Buddy attention
item/fileChange/requestApproval -> automatic edit acceptance
item/permissions/requestApproval -> Buddy attention
turn/completed -> verified/failed task receipt
```

Also test that an unknown app-server response ID is ignored without mutating a
task.

**Step 2: Run and verify failure**

```bash
swift test --filter 'CodexAppServerClientTests|CodexRemoteTaskRunnerTests|AppStateCodexAppServerTests'
```

Expected: FAIL because response correlation and the runner do not exist.

**Step 3: Implement typed app-server helpers**

Add helpers rather than duplicating raw dictionaries throughout the app:

```swift
func startThread(cwd: String, developerInstructions: String) throws -> CodexRequestID
func startTurn(threadID: String, text: String, attachments: [URL]) throws -> CodexRequestID
func interrupt(threadID: String, turnID: String) throws -> CodexRequestID
```

Use the generated local app-server schema as the compatibility source. Include
a focused fixture that validates the minimum fields CodeIsland consumes.

Locate Codex in this order: explicit CodeIsland setting, running Codex app
bundle, `/Applications/Codex.app/Contents/Resources/codex`, `/usr/local/bin/codex`,
`/opt/homebrew/bin/codex`, then a validated executable discovered from the
host's noninteractive login PATH. Never accept a path supplied by Buddy.

**Step 4: Implement `CodexRemoteTaskRunner`**

- Start one thread in the canonical workspace/worktree.
- Attach `clientUserMessageId = task.idempotencyKey` on the first turn.
- Map thread and turn IDs back to the CodeIsland task ID.
- Convert app-server approvals/questions into existing exact Buddy attention
  items, preserving exact session routing.
- Append `started`, `changed`, `tested`, `needs-*`, and terminal receipts.
- Follow up through another `turn/start`; stop through `turn/interrupt`.

**Step 5: Run focused tests**

```bash
swift test --filter 'CodexAppServerClientTests|CodexRemoteTaskRunnerTests|AppStateCodexAppServerTests|AppStateCodexRequestUserInputTests'
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodeIsland/CodexRemoteTaskRunner.swift \
  Sources/CodeIslandCore/CodexAppServerClient.swift \
  Sources/CodeIsland/AppState+CodexAppServer.swift \
  Tests/CodeIslandTests/CodexRemoteTaskRunnerTests.swift \
  Tests/CodeIslandCoreTests/CodexAppServerClientTests.swift \
  Tests/CodeIslandTests/AppStateCodexAppServerTests.swift \
  Tests/CodeIslandTests/AppStateCodexRequestUserInputTests.swift
git commit -m "feat: run remote Codex tasks"
```

### Task 6: Add the Claude Code stream-json task runner

**Files:**
- Create: `Sources/CodeIsland/ClaudeRemoteTaskRunner.swift`
- Create: `Sources/CodeIsland/ClaudeStreamEvent.swift`
- Create: `Tests/CodeIslandTests/ClaudeRemoteTaskRunnerTests.swift`
- Create: `Tests/CodeIslandTests/ClaudeStreamEventTests.swift`
- Modify: `Sources/CodeIsland/PersonalHubDataModel.swift:430-550`

**Step 1: Write failing stream fixtures**

Add redacted JSONL fixtures for initialization, assistant output, tool use,
hook permission request, result, error, and resumed follow-up. Prove malformed
or unknown events do not crash or advance task state.

**Step 2: Run and verify failure**

```bash
swift test --filter 'ClaudeRemoteTaskRunnerTests|ClaudeStreamEventTests'
```

Expected: FAIL because the parser and runner do not exist.

**Step 3: Implement the runner**

Launch the host-installed Claude executable with an argument vector, never a
shell string:

```text
claude --print
       --input-format stream-json
       --output-format stream-json
       --include-hook-events
       --permission-mode acceptEdits
       --session-id <uuid>
       --name CodeIsland-<short-task-id>
```

- Set `currentDirectoryURL` to the validated workspace.
- Preserve normal project `CLAUDE.md` and hooks.
- Send the first prompt and follow-ups over stdin as documented stream-json
  user messages.
- Keep the process handle only inside the host runner.
- Route hook permission requests through `RemoteTaskExecutionPolicy` and the
  existing approval coordinator.
- Persist the Claude session ID for restart/resume.
- Convert exit/result into explicit receipts.

Do not use `--dangerously-skip-permissions`, `--allow-dangerously-skip-permissions`,
or `--permission-mode bypassPermissions`.

**Step 4: Run focused and existing Claude tests**

```bash
swift test --filter 'ClaudeRemoteTaskRunnerTests|ClaudeStreamEventTests|ClaudeDesktopSupportTests|PersonalHubDataModelTests'
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/CodeIsland/ClaudeRemoteTaskRunner.swift \
  Sources/CodeIsland/ClaudeStreamEvent.swift \
  Sources/CodeIsland/PersonalHubDataModel.swift \
  Tests/CodeIslandTests/ClaudeRemoteTaskRunnerTests.swift \
  Tests/CodeIslandTests/ClaudeStreamEventTests.swift
git commit -m "feat: run remote Claude tasks"
```

### Task 7: Coordinate routing, restart recovery, evidence, and consequential approvals

**Files:**
- Create: `Sources/CodeIsland/RemoteTaskCoordinator.swift`
- Create: `Sources/CodeIsland/RemoteTaskEvidenceCollector.swift`
- Create: `Tests/CodeIslandTests/RemoteTaskCoordinatorTests.swift`
- Create: `Tests/CodeIslandTests/RemoteTaskEvidenceCollectorTests.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalService.swift:12-130`

**Step 1: Write failing coordinator tests**

Cover:

- `auto` selects an available provider using recent workspace affinity and
  falls back deterministically;
- accepted tasks survive a Mac service restart;
- a running Codex task resumes by thread ID and a Claude task by session ID;
- uncertain provider state becomes `needsYou`, never silently `working`;
- duplicate execution is impossible after restart;
- follow-up targets the exact provider session;
- commit/push/deploy proposals use existing short-lived exact action tokens;
- a token for one task/action cannot confirm another; and
- cancellation is idempotent.

**Step 2: Write failing evidence tests**

Collect only bounded, structured evidence:

```swift
RemoteTaskEvidence(
    branch: "codex/example",
    changedFiles: [...],
    checks: [.init(command: "swift test --filter X", exitCode: 0, summary: "12 passed")],
    warnings: [],
    sourceState: .edited
)
```

Prove secrets and full environment dumps are redacted, test output is capped,
and Git states remain `edited`, `committed`, `pushed`, `merged`, and `deployed`
instead of collapsing into `done`.

**Step 3: Run and verify failure**

```bash
swift test --filter 'RemoteTaskCoordinatorTests|RemoteTaskEvidenceCollectorTests'
```

Expected: FAIL.

**Step 4: Implement coordinator and evidence collection**

- The coordinator owns store, catalog, attachment store, runners, and policy.
- `RemoteApprovalService.start(appState:)` starts recovery after the listener is
  ready and stops runners cleanly on service shutdown.
- Every state transition appends a receipt before publishing.
- Completion is `verified` only when requested checks have an exit code 0;
  otherwise use `failed` or `needsYou` with the exact missing proof.
- Consequential actions call the current `RemoteActionTokenVault`; do not add a
  second token system.

**Step 5: Run focused tests**

```bash
swift test --filter 'RemoteTaskCoordinatorTests|RemoteTaskEvidenceCollectorTests|RemoteActionTokenVaultTests'
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodeIsland/RemoteTaskCoordinator.swift \
  Sources/CodeIsland/RemoteTaskEvidenceCollector.swift \
  Sources/CodeIsland/RemoteApprovalService.swift \
  Tests/CodeIslandTests/RemoteTaskCoordinatorTests.swift \
  Tests/CodeIslandTests/RemoteTaskEvidenceCollectorTests.swift
git commit -m "feat: coordinate remote task lifecycle"
```

### Task 8: Add authenticated task and bounded attachment HTTP endpoints

**Files:**
- Modify: `Sources/CodeIsland/RemoteApprovalHTTPServer.swift:90-260`
- Modify: `Sources/CodeIsland/RemoteApprovalService.swift:263-540`
- Modify: `Tests/CodeIslandTests/RemoteApprovalHTTPServerTests.swift`

**Step 1: Write failing real-listener API tests**

Add end-to-end loopback tests for:

```text
GET    /api/tasks
POST   /api/tasks
GET    /api/tasks/<task-id>
POST   /api/tasks/<task-id>/follow-up
POST   /api/tasks/<task-id>/cancel
POST   /api/tasks/<task-id>/actions/prepare
POST   /api/tasks/<task-id>/actions/execute
PUT    /api/tasks/<task-id>/attachments/<attachment-id>
```

Prove authentication, device binding, idempotency, stale action rejection,
replay rejection, unknown task 404, ownership mismatch 403, unsupported method
405, and exact attachment hash/size.

**Step 2: Add failing body-limit tests**

- Ordinary JSON routes remain capped at 64 KB.
- Only the authenticated task attachment path may declare up to 25 MB.
- Invalid/negative/missing content length fails before buffering the body.
- More bytes than declared or allowed returns 413 and deletes partial data.

**Step 3: Run and verify failure**

```bash
swift test --filter RemoteApprovalHTTPServerTests
```

Expected: FAIL for missing routes and path-aware request limits.

**Step 4: Implement path-aware limits and routes**

Refactor `RemoteHTTPConnection` to inspect the request line and headers before
selecting a maximum body size. Keep the default 65,536-byte limit. Permit the
larger limit only for `PUT /api/tasks/.../attachments/...`; authenticate and
validate task/attachment identity before committing bytes to the inbox.

Return `RemoteTaskSnapshot` from GET routes and a concrete host receipt from
every accepted mutation.

**Step 5: Run focused security tests**

```bash
swift test --filter 'RemoteApprovalHTTPServerTests|RemotePairAttemptLimiterTests|RemotePairingCodeLifecycleTests'
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodeIsland/RemoteApprovalHTTPServer.swift \
  Sources/CodeIsland/RemoteApprovalService.swift \
  Tests/CodeIslandTests/RemoteApprovalHTTPServerTests.swift
git commit -m "feat: expose authenticated remote task API"
```

### Task 9: Add Buddy task networking, offline drafts, and a durable outbox

**Files:**
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskDraftStore.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskClient.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionTests/RemoteTaskDraftStoreTests.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionTests/RemoteTaskClientTests.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalClient.swift:23-55,368-560,801-850`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/CodeIslandCompanionApp.swift`

**Step 1: Write failing outbox tests**

Prove:

- a draft persists locally before network submission;
- `Waiting for Mac` remains local until the host returns `Accepted`;
- retries reuse the same idempotency key;
- attachments upload exactly once and resume safely after interruption;
- an accepted task replaces its draft without changing visible identity;
- 401 moves to pairing recovery without deleting the draft; and
- 409 refreshes current task state rather than inventing success.

**Step 2: Run and verify failure**

```bash
xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
  -scheme CodeIslandCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:CodeIslandCompanionTests/RemoteTaskDraftStoreTests \
  -only-testing:CodeIslandCompanionTests/RemoteTaskClientTests test
```

Expected: FAIL because the stores/clients do not exist.

**Step 3: Implement draft, outbox, and client**

- Keep drafts under Application Support and attachment copies under a private
  task draft directory.
- Use the existing paired bearer token from Keychain through one authenticated
  request helper; do not duplicate token persistence.
- Poll task snapshots while foregrounded using the existing visually inert
  refresh policy.
- Retry pending outbox items on activation and reachability changes with
  bounded exponential backoff.
- Expose task state from `RemoteApprovalClient` so existing approvals,
  questions, hub data, and tasks share one connection banner.

**Step 4: Run focused iOS tests**

Use the same `xcodebuild` command. Expected: PASS.

**Step 5: Commit**

```bash
git add ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskDraftStore.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskClient.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalClient.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/CodeIslandCompanionApp.swift \
  ios/CodeIslandCompanion/CodeIslandCompanionTests/RemoteTaskDraftStoreTests.swift \
  ios/CodeIslandCompanion/CodeIslandCompanionTests/RemoteTaskClientTests.swift
git commit -m "feat: sync remote tasks in Buddy"
```

### Task 10: Build the native composer, signal-ranked Now, Sessions portfolio, and completion review

**Files:**
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskComposerView.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskSessionsView.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskDetailView.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskPresentationModel.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionTests/RemoteTaskPresentationModelTests.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift:100-560`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift`

**Step 1: Write failing presentation-model tests**

Prove ranking:

```text
approval/question > failed/blocked task > selected followed task > unreviewed
verified task > routine running task > all clear
```

Equal-priority items remain stable by prior selection and stable ID. Routine
polls cannot replace the selected task or reinsert loading state.

**Step 2: Add failing XCUITests**

Add launch fixtures and identifiers for:

- `task.composer`, `task.prompt`, `task.workspace`, `task.provider`,
  `task.submit`;
- ambiguous workspace selection;
- Waiting for Mac, Queued, Working, Needs You, Verified, Failed;
- follow-up, cancel, Continue, Revise, Open on Mac, Archive;
- completion evidence showing changed files, tests, warnings, and split Git
  states; and
- Now remaining stable across three simulated four-second polls.

**Step 3: Run and verify failure**

```bash
xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
  -scheme CodeIslandCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:CodeIslandCompanionTests/RemoteTaskPresentationModelTests \
  -only-testing:CodeIslandCompanionUITests test
```

Expected: FAIL for missing surfaces.

**Step 4: Implement the native surfaces**

- Keep the top-level destinations `Now`, `Sessions`, and `Tools`.
- Replace the current Reminder-oriented `New Task` entry point in the coding
  context with the remote coding composer; keep personal Reminder capture in
  Tools.
- Use a single prominent New Task affordance.
- Ask for workspace only when confidence is insufficient.
- Show `Edit & Test` as the default, with its boundary summarized in one line.
- Keep evidence collapsed by default but exact and inspectable.
- Present a separate exact-confirmation sheet for commit/push/deploy proposals.
- Preserve Dynamic Type, VoiceOver, Reduce Motion, dark mode, and 44-point
  targets.

**Step 5: Run focused tests and visual smoke states**

Run the command above plus the existing screenshot harness for clear,
attention, working, verified, failed, offline, and ambiguous-workspace states.
Expected: PASS with stable screenshots.

**Step 6: Commit**

```bash
git add ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskComposerView.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskSessionsView.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskDetailView.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskPresentationModel.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift \
  ios/CodeIslandCompanion/CodeIslandCompanionTests/RemoteTaskPresentationModelTests.swift \
  ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift
git commit -m "feat: add Buddy coding command center"
```

### Task 11: Add the iOS Share Extension and shared draft inbox

**Files:**
- Create: `ios/CodeIslandCompanion/CodeIslandShareExtension/ShareViewController.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandShareExtension/Info.plist`
- Create: `ios/CodeIslandCompanion/CodeIslandShareExtension/CodeIslandShareExtension.entitlements`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/SharedDraftInbox.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionTests/SharedDraftInboxTests.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/CodeIslandCompanion.entitlements`
- Modify: `ios/CodeIslandCompanion/project.yml`
- Regenerate: `ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj/project.pbxproj`
- Modify: `ios/CodeIslandCompanion/ExportOptions.plist`
- Modify: `.github/workflows/testflight-ios.yml:194-336`

**Step 1: Write failing shared-inbox tests**

Cover text, URL, image, file, duplicate activation, unsupported type, file too
large, traversal filename, and cleanup only after the main app imports the
draft.

**Step 2: Run and verify failure**

```bash
xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
  -scheme CodeIslandCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:CodeIslandCompanionTests/SharedDraftInboxTests test
```

Expected: FAIL.

**Step 3: Implement the App Group handoff**

Use App Group:

```text
group.com.revopsglobal.codeisland.buddy
```

The extension copies selected content into an App Group draft inbox, writes a
small versioned manifest atomically, and opens `codeisland://new-task`. The
main app imports the draft into its private draft store and presents it for
review. The extension never reads the pairing bearer token and never submits a
task directly.

**Step 4: Add target and signing configuration**

- Bundle ID: `com.revopsglobal.codeisland.buddy.share`
- Provisioning profile name: `CodeIsland Buddy Share App Store`
- GitHub secret: `IOS_SHARE_PROFILE_BASE64`
- Add the share target dependency to the app archive.
- Verify app and extension App Group entitlements in CI.
- Update the export options provisioning map.

Creating the App ID/profile and changing the GitHub secret are external account
actions; perform them only under Greg's explicit authorization for the
implementation run. No public release is needed.

**Step 5: Regenerate and run tests**

```bash
cd ios/CodeIslandCompanion
xcodegen generate
cd ../..
xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
  -scheme CodeIslandCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Expected: PASS; archive contains the signed share extension.

**Step 6: Commit**

```bash
git add ios/CodeIslandCompanion/CodeIslandShareExtension \
  ios/CodeIslandCompanion/CodeIslandCompanion/SharedDraftInbox.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/CodeIslandCompanion.entitlements \
  ios/CodeIslandCompanion/CodeIslandCompanionTests/SharedDraftInboxTests.swift \
  ios/CodeIslandCompanion/project.yml \
  ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj/project.pbxproj \
  ios/CodeIslandCompanion/ExportOptions.plist \
  .github/workflows/testflight-ios.yml
git commit -m "feat: capture coding tasks from iOS share sheet"
```

### Task 12: Add App Intents, Siri/Spotlight/Action Button, voice, and task deep links

**Files:**
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/CodeIslandAppIntents.swift:1-110`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalClient.swift:554-635`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/CodeIslandCompanionApp.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/Info.plist`
- Modify: `Sources/CodeIslandCore/PersonalHubProtocol.swift:862-917`
- Modify: `Tests/CodeIslandCoreTests/PersonalHubProtocolTests.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift`
- Modify: `scripts/validate-app-intent-metadata.sh`

**Step 1: Add failing intent/deep-link tests**

Test:

- `New CodeIsland Task` accepts optional text and provider but always opens an
  editable draft;
- `Open CodeIsland Task` routes to the exact task;
- `Follow CodeIsland Task` selects the one Live Activity task;
- cold-launch pending routes survive until task data loads; and
- a malformed/unknown task link cannot select another task.

**Step 2: Run and verify failure**

Run the focused core and iOS UI tests. Expected: FAIL.

**Step 3: Implement intents and routes**

- Extend `PrepareCodeIslandTaskIntent` instead of creating a competing task
  type.
- Donate shortcuts for New Task, Open Needs You, and Open Sessions.
- Keep dictation local to the reviewed composer using the existing Speech
  authorization path.
- App Intent execution prepares/opens a draft; it does not silently perform a
  consequential action.
- Update metadata validation so release archives fail if the new intent
  metadata is absent.

**Step 4: Run tests and metadata validation**

```bash
swift test --filter PersonalHubProtocolTests
scripts/test-validate-app-intent-metadata.sh
scripts/validate-app-intent-metadata.sh
```

Then run the focused XCUITests. Expected: PASS.

**Step 5: Commit**

```bash
git add ios/CodeIslandCompanion/CodeIslandCompanion/CodeIslandAppIntents.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalClient.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/CodeIslandCompanionApp.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/Info.plist \
  Sources/CodeIslandCore/PersonalHubProtocol.swift \
  Tests/CodeIslandCoreTests/PersonalHubProtocolTests.swift \
  ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift \
  scripts/validate-app-intent-metadata.sh
git commit -m "feat: expose remote tasks to iOS system surfaces"
```

### Task 13: Add the Mac task portfolio and exact handoff controls

**Files:**
- Create: `Sources/CodeIsland/RemoteTasksMacView.swift`
- Create: `Tests/CodeIslandTests/RemoteTasksMacViewModelTests.swift`
- Modify: `Sources/CodeIsland/PersonalHubMacView.swift`
- Modify: `Sources/CodeIsland/PersonalHubDataModel.swift`
- Modify: `Sources/CodeIsland/CodeIslandApp.swift`

**Step 1: Write failing view-model tests**

Prove the Mac uses the same task IDs/states as Buddy, ranks Needs You first,
shows exact provider/workspace/evidence, and focuses the exact terminal/Codex
session when `Open on Mac` is invoked.

**Step 2: Run and verify failure**

```bash
swift test --filter RemoteTasksMacViewModelTests
```

Expected: FAIL.

**Step 3: Implement the Mac portfolio**

- Add `Remote Tasks` to the Code mode rather than another top-level `Hub` or
  `Glances` concept.
- Preserve the notch as a compact local attention surface.
- Use a normal resizable window for all sessions, receipts, evidence, task
  settings, allowed workspaces, and recovery.
- `Open on Mac` activates the existing exact session/terminal routing.
- New Mac tasks use the same composer/contract and default authority.

**Step 4: Run tests and a native Mac visual smoke**

```bash
swift test --filter 'RemoteTasksMacViewModelTests|PersonalHubDataModelTests|SessionAttentionRouterTests'
swift build -c release
```

Expected: PASS; native window renders clear, running, needs-you, verified, and
failed fixtures without notch regressions.

**Step 5: Commit**

```bash
git add Sources/CodeIsland/RemoteTasksMacView.swift \
  Sources/CodeIsland/PersonalHubMacView.swift \
  Sources/CodeIsland/PersonalHubDataModel.swift \
  Sources/CodeIsland/CodeIslandApp.swift \
  Tests/CodeIslandTests/RemoteTasksMacViewModelTests.swift
git commit -m "feat: add Mac remote task portfolio"
```

### Task 14: Extend push, Live Activities, Dynamic Island, and the private web fallback

**Files:**
- Modify: `Sources/CodeIsland/APNSNotificationSender.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalService.swift`
- Modify: `Sources/CodeIslandCore/RemoteApprovalProtocol.swift`
- Modify: `Sources/CodeIslandCore/LiveActivityLifecycle.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalWebApp.swift`
- Modify: `Tests/CodeIslandTests/APNSNotificationSenderTests.swift`
- Modify: `Tests/CodeIslandTests/RemoteApprovalWebAppTests.swift`
- Modify: `Tests/CodeIslandCoreTests/RemoteAttentionLifecycleTests.swift`
- Modify: `ios/CodeIslandCompanion/Shared/CodeIslandActivityAttributes.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/LiveActivityController.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionWidget/CodeIslandLiveActivityWidget.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionTests/LiveActivityPrivacyTests.swift`

**Step 1: Write failing notification/privacy tests**

Prove:

- immediate APNs only for Needs You, Failed, a followed task's Verified state,
  or host loss during a followed active task;
- payloads contain task ID, state, expiry, and generic redacted copy only;
- stale/out-of-order push cannot regress terminal state;
- one followed task owns the Live Activity;
- routine task progress does not auto-start or pulse a Live Activity; and
- resolution ends/prunes ActivityKit tokens.

**Step 2: Write failing web-parity tests**

Require task list, composer, detail/evidence, follow-up, cancel, inline exact
confirmation, touch targets, safe-area layout, retry/offline feedback, and no
browser `alert`, `prompt`, or `confirm` calls.

**Step 3: Run and verify failure**

```bash
swift test --filter 'APNSNotificationSenderTests|RemoteApprovalWebAppTests|RemoteAttentionLifecycleTests'
```

Run focused iOS Live Activity tests. Expected: FAIL.

**Step 4: Implement ambient and web surfaces**

- Extend the versioned attention envelope with a task kind without exposing
  prompt text.
- Deep-link to `codeisland://tasks/<id>`.
- Render compact/expanded Dynamic Island states for Working, Needs You,
  Verified, and Failed.
- Use the same task endpoints and exact-confirmation contract from the web
  fallback.
- Do not make Telegram an inbound action surface.

**Step 5: Run focused tests**

Run the same Mac/Core and iOS commands. Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodeIsland/APNSNotificationSender.swift \
  Sources/CodeIsland/RemoteApprovalService.swift \
  Sources/CodeIslandCore/RemoteApprovalProtocol.swift \
  Sources/CodeIslandCore/LiveActivityLifecycle.swift \
  Sources/CodeIsland/RemoteApprovalWebApp.swift \
  Tests/CodeIslandTests/APNSNotificationSenderTests.swift \
  Tests/CodeIslandTests/RemoteApprovalWebAppTests.swift \
  Tests/CodeIslandCoreTests/RemoteAttentionLifecycleTests.swift \
  ios/CodeIslandCompanion/Shared/CodeIslandActivityAttributes.swift \
  ios/CodeIslandCompanion/CodeIslandCompanion/LiveActivityController.swift \
  ios/CodeIslandCompanion/CodeIslandCompanionWidget/CodeIslandLiveActivityWidget.swift \
  ios/CodeIslandCompanion/CodeIslandCompanionTests/LiveActivityPrivacyTests.swift
git commit -m "feat: surface remote task attention everywhere"
```

### Task 15: Add fail-closed CI, signed delivery receipts, and physical E2E acceptance

**Files:**
- Create: `scripts/smoke-remote-task-e2e.sh`
- Create: `scripts/report-remote-task-physical-e2e.sh`
- Create: `Tests/Scripts/remote-task-e2e.bats`
- Modify: `scripts/report-away-readiness.sh`
- Modify: `scripts/report-strict-physical-e2e.sh`
- Modify: `scripts/report-codeisland-completion-audit.sh`
- Modify: `.github/workflows/build-macos-arm-dmg.yml`
- Modify: `.github/workflows/testflight-ios.yml`
- Create: `docs/evidence/2026-07-19-iphone-edit-test-dispatch-acceptance.md`

**Step 1: Write failing script tests**

The report must stay incomplete until it can prove all of:

- current signed Mac source/version/signature/health;
- current TestFlight source/build/Apple `VALID`/tester availability;
- physical iPhone reports that exact build;
- one iPhone-created task has matching client/host task IDs;
- host receipts show Accepted, Started, Changed, Tested, and Verified;
- an attempted commit stopped at Needs You;
- the exact reviewed approval resumed the task;
- no duplicate task exists for the idempotency key;
- Wi-Fi and cellular-only Tailscale runs are separate gates; and
- task prompt, tokens, attachment contents, and absolute workspace paths are
  absent from sanitized reports.

**Step 2: Run and verify failure**

```bash
bats Tests/Scripts/remote-task-e2e.bats
```

Expected: FAIL because the report scripts do not exist.

**Step 3: Implement deterministic automated smoke coverage**

Use fake provider runners for CI to prove the complete HTTP/store/client
lifecycle without using model quota. Add a real-provider local smoke mode that
creates an isolated temporary fixture repo, asks the provider to change one
fixture line and run one test, and never commits or pushes.

**Step 4: Run the full local gate**

```bash
swift test -j 1
swift build -c release
ios/CodeIslandCompanion/scripts/run-model-tests.sh
bats Tests/Scripts/remote-task-e2e.bats
xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
  -scheme CodeIslandCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
graphify update . --no-viz
git diff --check
```

Expected: all commands exit 0.

**Step 5: Extend signed workflows and archive validation**

- Run the remote task focused suite in both Mac DMG and TestFlight workflows.
- Validate app, widget, and share-extension signatures/entitlements.
- Preserve DMG/IPA and sanitized receipt artifacts even if Apple indexing
  times out.
- Include source SHA and exact task-contract version in both host and Buddy
  build receipts.

**Step 6: Commit**

```bash
git add scripts/smoke-remote-task-e2e.sh \
  scripts/report-remote-task-physical-e2e.sh \
  Tests/Scripts/remote-task-e2e.bats \
  scripts/report-away-readiness.sh \
  scripts/report-strict-physical-e2e.sh \
  scripts/report-codeisland-completion-audit.sh \
  .github/workflows/build-macos-arm-dmg.yml \
  .github/workflows/testflight-ios.yml \
  docs/evidence/2026-07-19-iphone-edit-test-dispatch-acceptance.md \
  graphify-out
git commit -m "test: gate iPhone edit and test dispatch"
```

**Step 7: Deliver and run the physical matrix**

After CI is green and the implementation is approved for distribution:

1. Build, sign, download, verify, back up, and install the Mac DMG.
2. Confirm loopback and Tailscale health plus launch-at-login/keep-awake state.
3. Upload the matching Buddy archive to the internal TestFlight group.
4. Open the exact build on Greg's physical iPhone and require its build
   heartbeat.
5. Create a real task from typed text on Wi-Fi; verify edit/test/completion.
6. Repeat capture through dictation, Safari Share Sheet, photo, and file.
7. Send Codex and Claude follow-ups and prove exact session routing.
8. Trigger commit/push/deploy/destructive/credential/external-message probes and
   prove each stops at the intended gate.
9. Disable iPhone Wi-Fi and complete one task over cellular Tailscale.
10. Verify push, cold launch, Live Activity, compact/expanded Dynamic Island,
    stale action, Mac restart, provider crash, and duplicate submission.
11. Capture native light/dark, Dynamic Type, VoiceOver, Reduce Motion, offline,
    failure, and visual-stability evidence.
12. Run `scripts/report-remote-task-physical-e2e.sh --strict`; require exit 0.

Only then update the evidence document from `incomplete` to `complete`.

---

## Final verification oracle

Run from the repository root:

```bash
swift test -j 1 && \
swift build -c release && \
ios/CodeIslandCompanion/scripts/run-model-tests.sh && \
bats Tests/Scripts/remote-task-e2e.bats && \
xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
  -scheme CodeIslandCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test && \
scripts/report-codeisland-completion-audit.sh && \
scripts/report-remote-task-physical-e2e.sh --strict && \
git diff --check
```

Expected: every command exits 0, the completion audit reports `complete: true`,
and the strict physical report identifies the exact signed Mac source and
physical TestFlight build that produced the real task receipts.
