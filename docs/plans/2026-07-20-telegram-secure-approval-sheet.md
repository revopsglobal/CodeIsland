# Telegram Secure Approval Sheet Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let Greg review and resolve an exact pending CodeIsland approval from a summary-first sheet inside Telegram without opening Buddy and without making Telegram a separate approval authority.

**Architecture:** Add a narrowly scoped Telegram Mini App to the existing Tailscale-only remote approval server. Telegram supplies signed `initData`; CodeIsland validates the allowlisted identity, resolves an opaque launch nonce, presents one exact pending request, and delegates the final POST to the existing `RemoteApprovalCoordinator` with its normal 120-second single-use token. Redacted chat messages and all other notification paths remain unchanged.

**Tech Stack:** Swift 6, SwiftUI, CryptoKit, Security/Keychain, Network.framework HTTP server, Telegram Bot API, Telegram Mini App JavaScript API, XCTest, Bats, GitHub Actions, Tailscale Serve.

---

## Preconditions and invariants

- Work only in `/Users/gregharned/work/CodeIsland-telegram-sheet` on `codex/telegram-secure-approval-sheet`.
- Do not touch the user's dirty `design/visual-proofs` checkout at `/Users/gregharned/work/CodeIsland`.
- Keep `RemoteApprovalCoordinator` as the sole approval resolver.
- Never place an action token, device token, command, workspace, or tool input in Telegram chat text or a URL.
- Never mutate approval state from GET, page load, link preview, or Telegram prefetch.
- Do not add a webhook, polling daemon, public ingress, database, scheduler, or paid service.
- Telegram is escalation-only. One pending request creates at most one Telegram message.
- Questions and failed tasks retain their existing private review links in this release. Only pending approvals receive the secure sheet action.
- Use `@verification-before-completion` before claiming implementation or release completion.

### Task 1: Move the Telegram bot token into macOS Keychain

**Files:**
- Create: `Sources/CodeIsland/TelegramCredentialStore.swift`
- Create: `Tests/CodeIslandTests/TelegramCredentialStoreTests.swift`
- Modify: `Sources/CodeIsland/Settings.swift:130-132`
- Modify: `Sources/CodeIsland/TelegramAttentionNotifier.swift:86-99`

**Step 1: Write the failing storage and migration tests**

Cover save/load/delete and migration ordering with an injected in-memory backend. The legacy UserDefaults value must be removed only after a successful Keychain write.

```swift
@MainActor
func testMigrationMovesLegacyTokenAndDeletesPreferenceAfterSuccessfulWrite() throws {
    let defaults = try isolatedDefaults()
    defaults.set("123:secret", forKey: SettingsKey.remoteApprovalTelegramBotToken)
    let backend = MemoryTelegramSecretBackend()
    let store = TelegramCredentialStore(backend: backend, defaults: defaults)

    XCTAssertEqual(try store.loadMigratingLegacyValue(), "123:secret")
    XCTAssertEqual(backend.value, "123:secret")
    XCTAssertNil(defaults.string(forKey: SettingsKey.remoteApprovalTelegramBotToken))
}
```

Also test backend failure leaves the legacy value intact and that errors never contain token text.

**Step 2: Run the focused tests and confirm they fail**

Run:

```bash
swift test --filter TelegramCredentialStoreTests
```

Expected: FAIL because `TelegramCredentialStore` does not exist.

**Step 3: Implement the credential abstraction and Keychain backend**

Use a protocol so tests never touch the user's Keychain:

```swift
protocol TelegramSecretBackend {
    func read(service: String, account: String) throws -> String?
    func write(_ value: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct TelegramCredentialStore {
    static let service = "com.codeisland.telegram.bot-token"
    static let account = "default"

    let backend: TelegramSecretBackend
    let defaults: UserDefaults

    func loadMigratingLegacyValue() throws -> String? {
        if let stored = try backend.read(service: Self.service, account: Self.account) {
            return stored
        }
        guard let legacy = defaults.string(forKey: SettingsKey.remoteApprovalTelegramBotToken),
              !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        try backend.write(legacy, service: Self.service, account: Self.account)
        defaults.removeObject(forKey: SettingsKey.remoteApprovalTelegramBotToken)
        return legacy
    }
}
```

The production backend uses `kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and `SecItemCopyMatching`/`SecItemAdd`/`SecItemUpdate`/`SecItemDelete`.

**Step 4: Route notifier configuration through the credential store**

Remove token reads from UserDefaults. Keep the legacy key only for one-time migration compatibility. Do not log Keychain error payloads or token fragments.

**Step 5: Run the focused tests**

Run:

```bash
swift test --filter TelegramCredentialStoreTests
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodeIsland/TelegramCredentialStore.swift Sources/CodeIsland/Settings.swift Sources/CodeIsland/TelegramAttentionNotifier.swift Tests/CodeIslandTests/TelegramCredentialStoreTests.swift
git commit -m "Secure Telegram bot token in Keychain"
```

### Task 2: Validate Telegram Mini App identity cryptographically

**Files:**
- Create: `Sources/CodeIsland/TelegramInitDataValidator.swift`
- Create: `Tests/CodeIslandTests/TelegramInitDataValidatorTests.swift`
- Modify: `Sources/CodeIsland/Settings.swift:130-134`

**Step 1: Add failing validation tests**

Build deterministic fixtures with fixed bot token, user JSON, query ID, and `auth_date`. Cover:

- valid signature and configured user;
- tampered user JSON;
- missing or malformed hash;
- stale `auth_date`;
- future `auth_date` outside clock tolerance;
- wrong allowlisted user;
- malformed percent encoding; and
- generic errors that do not echo raw `initData`.

```swift
func testValidSignedInitDataReturnsAllowlistedIdentity() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let raw = fixture.signedInitData(userID: 8_567_114_601, authDate: now)
    let identity = try TelegramInitDataValidator(botToken: fixture.botToken)
        .validate(raw, allowedUserID: 8_567_114_601, now: now)
    XCTAssertEqual(identity.userID, 8_567_114_601)
}
```

**Step 2: Run the focused tests and confirm they fail**

```bash
swift test --filter TelegramInitDataValidatorTests
```

Expected: FAIL because the validator does not exist.

**Step 3: Implement the official two-stage HMAC check**

Parse the query without trusting `initDataUnsafe`. Remove `hash`, sort remaining decoded `key=value` pairs, and join with line feeds. Derive the secret with HMAC-SHA-256 using `WebAppData`, then authenticate the data-check string. Compare lowercase hex signatures in constant time.

```swift
let secretBytes = HMAC<SHA256>.authenticationCode(
    for: Data(botToken.utf8),
    using: SymmetricKey(data: Data("WebAppData".utf8))
)
let expected = HMAC<SHA256>.authenticationCode(
    for: Data(checkString.utf8),
    using: SymmetricKey(data: Data(secretBytes))
)
```

Decode only the fields required for authorization. Accept `auth_date` no older than 60 seconds and no more than 15 seconds in the future.

**Step 4: Add the allowlisted Telegram user setting**

Add `remoteApprovalTelegramUserID` as a string-backed setting to avoid 32-bit truncation. Default it from the configured private chat ID only when that chat ID is a positive private-user identifier. Never infer a user from a negative group/channel ID.

**Step 5: Run the focused tests**

```bash
swift test --filter TelegramInitDataValidatorTests
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodeIsland/TelegramInitDataValidator.swift Sources/CodeIsland/Settings.swift Tests/CodeIslandTests/TelegramInitDataValidatorTests.swift
git commit -m "Validate Telegram Mini App identity"
```

### Task 3: Add launch and approval-session vaults

**Files:**
- Create: `Sources/CodeIsland/TelegramApprovalSessionVault.swift`
- Create: `Tests/CodeIslandTests/TelegramApprovalSessionVaultTests.swift`

**Step 1: Write failing launch/session lifecycle tests**

Cover random nonce issuance, request and chat binding, ten-minute launch expiry, five-minute session expiry, cleanup after resolution, mismatched user rejection, and replay after terminal resolution.

```swift
func testSessionIsBoundToLaunchRequestAndTelegramIdentity() throws {
    var vault = TelegramApprovalSessionVault(tokenGenerator: { "launch-token" })
    let launch = vault.issueLaunch(requestID: "request-1", chatID: 42, now: now)
    let session = try vault.openSession(
        launchNonce: launch.nonce,
        telegramUserID: 42,
        expectedChatID: 42,
        now: now
    )
    XCTAssertEqual(session.requestID, "request-1")
    XCTAssertThrowsError(try vault.authorize(sessionNonce: session.nonce, requestID: "request-2", userID: 42, now: now))
}
```

**Step 2: Run and confirm failure**

```bash
swift test --filter TelegramApprovalSessionVaultTests
```

Expected: FAIL because the vault does not exist.

**Step 3: Implement the in-memory vault**

Use 32 random bytes encoded base64url for both launch and session nonces. Store only in process memory. The vault must provide:

```swift
mutating func issueLaunch(requestID: String, chatID: Int64, now: Date = Date()) -> TelegramApprovalLaunch
mutating func attachMessageID(_ messageID: Int, to launchNonce: String)
mutating func openSession(launchNonce: String, telegramUserID: Int64, expectedChatID: Int64, now: Date = Date()) throws -> TelegramApprovalSession
mutating func authorize(sessionNonce: String, requestID: String, userID: Int64, now: Date = Date()) throws -> TelegramApprovalSession
mutating func resolve(requestID: String) -> TelegramApprovalLaunch?
mutating func discardExpired(now: Date = Date())
```

Mark the type `@MainActor` or keep it exclusively inside an `@MainActor` controller so no lock is required.

**Step 4: Run focused tests**

```bash
swift test --filter TelegramApprovalSessionVaultTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/CodeIsland/TelegramApprovalSessionVault.swift Tests/CodeIslandTests/TelegramApprovalSessionVaultTests.swift
git commit -m "Add Telegram approval session vault"
```

### Task 4: Build a summary-first Telegram approval presentation

**Files:**
- Create: `Sources/CodeIsland/TelegramApprovalPresentation.swift`
- Create: `Tests/CodeIslandTests/TelegramApprovalPresentationTests.swift`
- Modify: `Sources/CodeIsland/RemoteTaskEvidenceCollector.swift:124-138` only if extracting a reusable secret redactor is necessary

**Step 1: Write failing presentation tests**

Create permission fixtures for Bash, Write/Edit, network access, credential access, package installation, and an unclassified tool. Assert:

- deterministic headline, agent, workspace, risk, and risk reason;
- stable changed-scope ordering;
- exact command is only in `details`, never the summary text;
- known credential values are redacted while the credential boundary remains visible;
- field and aggregate length caps; and
- action fingerprint stability for the same request and change for a different request.

```swift
func testBashPushIsSummaryFirstWithExpandableExactCommand() throws {
    let presentation = TelegramApprovalPresentationBuilder.build(
        request: fixture.permission(tool: "Bash", input: ["command": "git push origin main"]),
        appState: fixture.appState
    )
    XCTAssertEqual(presentation.headline, "Codex wants to push changes to GitHub")
    XCTAssertFalse(presentation.summary.localizedCaseInsensitiveContains("git push"))
    XCTAssertTrue(presentation.details.contains { $0.value == "git push origin main" })
}
```

**Step 2: Run and confirm failure**

```bash
swift test --filter TelegramApprovalPresentationTests
```

Expected: FAIL because the builder does not exist.

**Step 3: Implement DTOs and deterministic builder**

Create Codable response types local to the Mac target:

```swift
struct TelegramApprovalPresentation: Codable, Equatable {
    let requestID: String
    let headline: String
    let agent: String
    let workspace: String?
    let risk: CommandRisk
    let riskReason: String
    let changedScope: [String]
    let details: [TelegramApprovalDetail]
    let fingerprint: String
    let createdAt: Date
    let actionToken: String
    let actionExpiresAt: Date
}
```

Reuse `CommandRiskClassifier`. Build a deterministic plain-language risk reason. Serialize known tool inputs in an allowlisted key order, apply credential-value redaction, and cap the total response. Do not change `RemoteApprovalSnapshot` or its existing payload-minimization contract.

**Step 4: Run focused tests**

```bash
swift test --filter TelegramApprovalPresentationTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/CodeIsland/TelegramApprovalPresentation.swift Sources/CodeIsland/RemoteTaskEvidenceCollector.swift Tests/CodeIslandTests/TelegramApprovalPresentationTests.swift
git commit -m "Build Telegram approval presentation"
```

### Task 5: Make Telegram delivery testable and add the secure review button

**Files:**
- Create: `Sources/CodeIsland/TelegramBotAPIClient.swift`
- Create: `Tests/CodeIslandTests/TelegramBotAPIClientTests.swift`
- Modify: `Sources/CodeIsland/TelegramAttentionNotifier.swift:6-164`
- Modify: `Tests/CodeIslandTests/APNSNotificationSenderTests.swift:187-263`

**Step 1: Write failing Bot API payload tests**

Assert that pending approvals send:

- redacted text;
- exactly one inline keyboard row;
- a `web_app` button labeled `Review securely`;
- an HTTPS Tailscale URL containing only `launch=<opaque nonce>`; and
- no request ID, action token, command, workspace, or transcript.

Questions and failed tasks must not receive an approval button.

```swift
XCTAssertEqual(payload.replyMarkup?.inlineKeyboard.first?.first?.text, "Review securely")
XCTAssertEqual(payload.replyMarkup?.inlineKeyboard.first?.first?.webApp?.url, "https://mac.tailnet:9443/telegram/approval?launch=opaque")
XCTAssertFalse(try encoded(payload).contains("git push"))
```

Also test parsing Telegram's `sendMessage` response to retain `message_id`, and `editMessageText`/`editMessageReplyMarkup` payloads that remove the button.

**Step 2: Run and confirm failure**

```bash
swift test --filter TelegramBotAPIClientTests
swift test --filter APNSNotificationSenderTests
```

Expected: FAIL on missing client and review-button contract.

**Step 3: Implement an injectable Bot API client**

```swift
protocol TelegramBotAPIClientProtocol {
    func sendMessage(_ payload: TelegramSendMessagePayload, botToken: String) async throws -> TelegramSentMessage
    func editMessage(_ payload: TelegramEditMessagePayload, botToken: String) async throws
}
```

Use `URLSession` in production. Set `disable_web_page_preview` and parse non-2xx Telegram descriptions without logging request bodies or tokenized URLs.

**Step 4: Refactor the notifier around injected configuration and client**

For `.approval` + `.pending`, ask the shared Telegram approval controller for a launch URL and send the web-app button. Attach the returned `message_id` to the launch record. Preserve current redacted fallback links.

**Step 5: Run focused tests**

```bash
swift test --filter TelegramBotAPIClientTests
swift test --filter APNSNotificationSenderTests
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodeIsland/TelegramBotAPIClient.swift Sources/CodeIsland/TelegramAttentionNotifier.swift Tests/CodeIslandTests/TelegramBotAPIClientTests.swift Tests/CodeIslandTests/APNSNotificationSenderTests.swift
git commit -m "Add secure Telegram review button"
```

### Task 6: Serve the focused Telegram Mini App shell

**Files:**
- Create: `Sources/CodeIsland/TelegramApprovalWebApp.swift`
- Create: `Tests/CodeIslandTests/TelegramApprovalWebAppTests.swift`

**Step 1: Write failing static-contract tests**

Assert the HTML contains:

- `telegram-web-app.js`;
- summary, risk, scope, details disclosure, deny, and approve controls;
- `Telegram.WebApp.initData` but not `initDataUnsafe` for authorization;
- POST-only session and decision calls;
- no service worker, localStorage token, remote font, analytics, or unrelated Hub UI;
- CSS safe-area variables, Telegram theme variables, visible focus states, reduced motion, and 44-point targets; and
- escaped text insertion using `textContent`, not interpolated `innerHTML`, for server data.

**Step 2: Run and confirm failure**

```bash
swift test --filter TelegramApprovalWebAppTests
```

Expected: FAIL because `TelegramApprovalWebApp` does not exist.

**Step 3: Implement the HTML/CSS/JS asset**

The shell reads `launch` from the URL, calls `Telegram.WebApp.ready()`, POSTs raw `initData`, and renders the server response. Summary is visible first. Exact details use a native disclosure control.

The approval path is:

```javascript
await fetch(`/api/telegram/approvals/${encodeURIComponent(model.requestID)}/decision`, {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    initData: Telegram.WebApp.initData,
    launchNonce,
    sessionNonce: model.sessionNonce,
    actionToken: model.actionToken,
    decision
  })
});
```

Use `Telegram.WebApp.showPopup` or a custom accessible dialog to repeat the action fingerprint before the POST. A page open, `Show details`, or browser back action must never resolve the request.

**Step 4: Run focused tests**

```bash
swift test --filter TelegramApprovalWebAppTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/CodeIsland/TelegramApprovalWebApp.swift Tests/CodeIslandTests/TelegramApprovalWebAppTests.swift
git commit -m "Build focused Telegram approval sheet"
```

### Task 7: Add authenticated Telegram approval routes

**Files:**
- Create: `Sources/CodeIsland/TelegramApprovalController.swift`
- Create: `Tests/CodeIslandTests/TelegramApprovalHTTPAPITests.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalService.swift:25-68`
- Modify: `Sources/CodeIsland/RemoteApprovalService.swift:492-775`

**Step 1: Write failing real-listener integration tests**

Use the existing local HTTP listener fixture style. Cover:

- shell GET returns 200, `Cache-Control: no-store`, and no private details;
- shell GET with a valid nonce does not consume or resolve anything;
- session POST with valid signed `initData` returns one exact pending approval;
- invalid signature, wrong user, stale auth, missing launch, wrong kind, and resolved request return generic 403/404/409 without details;
- approve and deny call the real `RemoteApprovalCoordinator`;
- action replay fails;
- action token expiry requires a fresh session snapshot; and
- a session cannot act on another request.

```swift
let response = try await send(
    port: port,
    method: "POST",
    path: "/api/telegram/session",
    body: encode(.init(initData: signed, launchNonce: launch.nonce))
)
XCTAssertEqual(response.status, 200)
```

**Step 2: Run and confirm failure**

```bash
swift test --filter TelegramApprovalHTTPAPITests
```

Expected: FAIL because routes/controller do not exist.

**Step 3: Implement the controller**

The `@MainActor` controller owns the launch/session vault, credential store, identity validator factory, presentation builder, and Bot API client. It exposes narrow methods to the notifier and HTTP service:

```swift
func prepareLaunch(for envelope: RemoteAttentionPushEnvelope, baseURL: URL) throws -> TelegramApprovalLaunch
func createSession(_ request: TelegramSessionRequest, appState: AppState, coordinator: RemoteApprovalCoordinator) -> TelegramRouteResult
func decide(_ request: TelegramDecisionRouteRequest, requestID: String, appState: AppState, coordinator: RemoteApprovalCoordinator) -> TelegramRouteResult
func reconcileResolved(requestID: String) async
```

Session creation calls `coordinator.snapshot(appState:deviceID:)` with `deviceID = "telegram:<allowlisted user id>"`, selects only the launch-bound request, and passes it through the Telegram presentation builder.

**Step 4: Add routes before paired-device bearer authentication**

The Telegram routes authenticate themselves with signed Telegram data, so route them before the existing `authenticate(request)` guard. All other remote endpoints retain their bearer-token requirement.

Add response headers:

```swift
[
  "Cache-Control": "no-store",
  "Content-Security-Policy": "default-src 'self'; script-src 'self' https://telegram.org; connect-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors https://web.telegram.org https://*.telegram.org",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff"
]
```

If Telegram requires a different documented script origin during physical testing, change the narrow allowlist only after observing the actual request.

**Step 5: Run focused tests**

```bash
swift test --filter TelegramApprovalHTTPAPITests
swift test --filter RemoteApprovalHTTPServerTests
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodeIsland/TelegramApprovalController.swift Sources/CodeIsland/RemoteApprovalService.swift Tests/CodeIslandTests/TelegramApprovalHTTPAPITests.swift
git commit -m "Route authenticated Telegram approvals"
```

### Task 8: Reconcile resolution and deduplicate escalation messages

**Files:**
- Modify: `Sources/CodeIsland/RemoteApprovalService.swift:382-428`
- Modify: `Sources/CodeIsland/TelegramApprovalController.swift`
- Modify: `Sources/CodeIsland/TelegramAttentionNotifier.swift`
- Create: `Tests/CodeIslandTests/TelegramApprovalReconciliationTests.swift`

**Step 1: Write failing lifecycle tests**

Cover:

- duplicate pending envelopes reuse one message;
- approval from Telegram edits the original message and removes its button;
- approval from Buddy/web/Mac edits the same message;
- deny, expired, and resolved-elsewhere labels;
- resolution edit failure does not roll back the authoritative approval;
- repeated resolved events are idempotent; and
- routine/verified task events remain silent.

**Step 2: Run and confirm failure**

```bash
swift test --filter TelegramApprovalReconciliationTests
```

Expected: FAIL on missing reconciliation behavior.

**Step 3: Wire resolved events into the controller**

When `stateDidChange()` observes `resolvedIDs`, call reconciliation after the existing APNs/Live Activity event. The controller consumes the launch mapping, edits the original Telegram message to a terminal state, and drops the review keyboard.

Do not send a second completion message.

**Step 4: Run focused tests**

```bash
swift test --filter TelegramApprovalReconciliationTests
swift test --filter APNSNotificationSenderTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/CodeIsland/RemoteApprovalService.swift Sources/CodeIsland/TelegramApprovalController.swift Sources/CodeIsland/TelegramAttentionNotifier.swift Tests/CodeIslandTests/TelegramApprovalReconciliationTests.swift
git commit -m "Reconcile Telegram approval messages"
```

### Task 9: Upgrade Buddy settings for secure Telegram readiness

**Files:**
- Modify: `Sources/CodeIsland/SettingsView.swift:1545-1577`
- Modify: `Sources/CodeIsland/SettingsView.swift:2070-2100`
- Modify: `Sources/CodeIsland/Settings.swift`
- Create: `Tests/CodeIslandTests/TelegramSettingsStatusTests.swift`

**Step 1: Write failing readiness-model tests**

Model explicit states: disabled, missing token, missing chat ID, missing user ID, invalid Tailnet HTTPS URL, configured, delivered, and failed. Assert no status string contains a token or complete private identifier.

**Step 2: Run and confirm failure**

```bash
swift test --filter TelegramSettingsStatusTests
```

Expected: FAIL because the status model does not exist.

**Step 3: Replace direct AppStorage token binding**

The UI must not bind a secret to UserDefaults. Present:

- a blank `SecureField("New bot token")`;
- `Save token` or `Replace token`;
- `Clear token`;
- private Chat ID and allowed Telegram user ID fields;
- Mini App Tailscale origin readiness;
- `Send test escalation`;
- `Open test approval sheet`; and
- last delivery/error.

Keep errors selectable but redact secrets. Use standard SwiftUI controls and existing Settings styling.

**Step 4: Update explanatory copy**

State that Telegram is escalation-only, chat content is redacted, exact details are fetched over Tailscale, and every decision remains a single-use CodeIsland approval.

**Step 5: Run focused tests and build**

```bash
swift test --filter TelegramSettingsStatusTests
swift build
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/CodeIsland/SettingsView.swift Sources/CodeIsland/Settings.swift Tests/CodeIslandTests/TelegramSettingsStatusTests.swift
git commit -m "Add secure Telegram approval settings"
```

### Task 10: Update readiness audits and release documentation

**Files:**
- Modify: `scripts/report-away-readiness.sh`
- Modify: `Tests/Scripts/report-away-readiness.bats`
- Modify: `CHANGELOG.md`
- Modify: version metadata files identified by `rg -n '1\.0\.61|CFBundleShortVersionString|MARKETING_VERSION' .github scripts Sources Package.swift`

**Step 1: Write failing Bats cases**

Add fixtures for:

- Keychain token present without printing it;
- secure approval configuration complete;
- alert-only fallback remains available when Mini App setup is incomplete;
- missing allowlisted user or invalid Mini App origin reported as a clear optional blocker; and
- no report field contains token content.

**Step 2: Run and confirm failure**

```bash
bats Tests/Scripts/report-away-readiness.bats
```

Expected: FAIL on missing secure-approval status fields.

**Step 3: Update the audit safely**

The script may report booleans such as `tokenInKeychain`, `identityConfigured`, `miniAppReady`, `lastDelivery`, and `secureApprovalsAvailable`. It must not invoke `security find-generic-password -w` in a way that prints the secret.

**Step 4: Document the user-visible release**

Add a changelog entry for version 1.0.62 or the next available patch version. State:

- secure Telegram approval sheet;
- summary-first review and expandable exact details;
- escalation-only notification policy;
- single-use existing approval token;
- Keychain token migration; and
- no new public service or cost.

**Step 5: Run Bats and shell syntax checks**

```bash
bash -n scripts/report-away-readiness.sh
bats Tests/Scripts/report-away-readiness.bats
```

Expected: PASS.

**Step 6: Commit**

```bash
git add scripts/report-away-readiness.sh Tests/Scripts/report-away-readiness.bats CHANGELOG.md
git add <exact version files found during this task>
git commit -m "Report secure Telegram approval readiness"
```

### Task 11: Run the complete automated verification gate

**Files:**
- Modify only files needed to correct failures caused by this branch

**Step 1: Run formatting and diff safety checks**

```bash
git diff --check origin/main...HEAD
```

Expected: no output.

**Step 2: Run all Swift tests**

```bash
swift test
```

Expected: all CodeIsland and CodeIslandCore tests pass; only repository-documented skips are allowed.

If XCTest or SwiftUI macros resolve against CommandLineTools, rerun with the installed full Xcode:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

**Step 3: Run all script tests**

```bash
bats Tests/Scripts/*.bats
```

Expected: all Bats tests pass.

**Step 4: Build the Mac app**

```bash
swift build -c release
```

Expected: release build succeeds.

**Step 5: Run repository release validation**

Discover the current canonical command from the release workflow and scripts rather than inventing it:

```bash
rg -n "swift test|build.*dmg|validate|codesign|notar" .github/workflows scripts | head -200
```

Run the exact non-destructive local validators used by `build-macos-arm-dmg.yml`.

**Step 6: Review security-sensitive diff**

Manually verify:

- no token or action data in URLs, Telegram JSON fixtures, logs, snapshots, changelog, or Git diff;
- no mutation on GET;
- no auth bypass for existing `/api/*` routes;
- no public bind or new daemon;
- all decisions delegate to `RemoteApprovalCoordinator`; and
- every terminal path consumes or invalidates session/action state.

**Step 7: Commit any verification-only corrections**

```bash
git add <only corrected files>
git commit -m "Harden Telegram approval verification"
```

Skip this commit if no corrections were needed.

### Task 12: Push, CI, install, and physical Telegram acceptance

**Files:**
- Add evidence only in the repository's existing release/evidence location if one exists

**Step 1: Push the feature branch**

```bash
git push -u origin codex/telegram-secure-approval-sheet
```

Expected: push succeeds to `revopsglobal/CodeIsland`.

**Step 2: Open a ready PR and enable auto-merge after green checks**

Use the repository's GitHub CLI context explicitly:

```bash
gh pr create --repo revopsglobal/CodeIsland --base main --head codex/telegram-secure-approval-sheet --title "Add secure Telegram approval sheet" --body-file <prepared-pr-body>
gh pr merge --repo revopsglobal/CodeIsland --auto --squash <pr-number>
```

Expected: PR is ready, CI is visible, and auto-merge is enabled. Do not claim merged until GitHub confirms it.

**Step 3: Configure the Mini App origin in BotFather**

Using Greg's authenticated Telegram Mac app and the existing Orca bot:

1. open BotFather;
2. select the existing bot;
3. configure the Mini App or allowed Web App origin to the exact Tailscale HTTPS origin;
4. do not create a new bot or public host; and
5. do not expose the bot token in chat, screenshots, terminal output, or the PR.

If BotFather rejects the private MagicDNS host or explicit port, stop and preserve the exact error. Do not add public ingress. The approved fallback is the same secure sheet opened by a standard URL button in Telegram's in-app browser, still protected by Telegram identity validation and Tailscale.

**Step 4: Build and install the signed Mac artifact**

After merge, dispatch the canonical signed DMG workflow against the merged commit, download the exact artifact, verify signing/version/commit, preserve the current installed app as a backup using the existing install script, and install the new build.

Do not conflate workflow success, artifact signing, installation, process launch, or physical Telegram acceptance.

**Step 5: Run real harmless approval acceptance**

On the physical iPhone with Tailscale connected:

1. trigger a harmless approval from Codex or Claude;
2. verify exactly one redacted Orca Telegram escalation;
3. open `Review securely`;
4. verify summary-first presentation and expandable exact details;
5. verify light/dark mode, Dynamic Type, VoiceOver labels, reduced motion, and safe areas;
6. approve once and prove the exact waiting hook receives allow;
7. repeat with deny;
8. prove replay, stale request, expired action, offline Mac, and wrong identity fail closed;
9. resolve one request from Buddy/web/Mac and prove the original Telegram message edits without a second alert; and
10. verify APNs, Live Activity, Buddy, and the full private web app still work independently.

**Step 6: Record exact proof handles**

Record:

- merged PR and commit;
- CI run IDs;
- signed DMG workflow run and artifact ID;
- installed app version and code-sign result;
- Tailscale health status;
- Telegram delivery timestamp and terminal edited-message state;
- exact harmless approval request ID and hook response;
- automated test totals; and
- physical iPhone acceptance result.

Only after all required proof exists may the feature be described as complete end to end.
