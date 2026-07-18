# Buddy Quiet Command Center Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Buddy's rejected stacked-card home screen with a stable, attention-first, Apple-native command center while preserving full away-use functionality and adding exact installed-build proof.

**Architecture:** Keep `RemoteApprovalClient` and the existing shared personal-hub protocol as the data/action owners. Extract the portrait command-center presentation into focused SwiftUI subviews driven by stable IDs and local navigation state; reserve Liquid Glass for the bottom action dock with an older-iOS material fallback. Polling updates data in place and must never replace the settled root with a transient connecting state.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+ compatibility with iOS 26/27 Liquid Glass enhancement, XCTest/XCUITest, ActivityKit, App Intents, authenticated Tailscale HTTPS, GitHub Actions, and App Store Connect/TestFlight.

---

## Execution rules

- Work only in `/private/tmp/CodeIsland-physical-acceptance` on `codex/device-build-receipt`.
- Preserve the existing red-green test history for client build registration.
- Use native semantic text styles, SF Symbols, Dynamic Type, and system accessibility behavior.
- Do not add a second remote client, action path, state store, web-only design system, or decorative continuous animation.
- Do not remove any existing module or away-use action to simplify the home screen.
- Keep implementation, CI, signed distribution, TestFlight availability, physical install, and physical interaction proof separate.

### Task 1: Finish exact Buddy build registration

**Files:**

- Modify: `Sources/CodeIslandCore/RemoteApprovalProtocol.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalService.swift`
- Modify: `Sources/CodeIsland/SettingsView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalClient.swift`
- Modify: `Tests/CodeIslandCoreTests/RemoteAttentionLifecycleTests.swift`
- Modify: `Tests/CodeIslandTests/RemoteApprovalHTTPServerTests.swift`

**Step 1: Preserve the failing protocol tests**

Require legacy decoding to leave `clientVersion` and `clientBuild` nil, and a
metadata-only registration to round-trip both values.

**Step 2: Validate the host registration contract**

Accept metadata only when version and build are both present, bounded, and
limited to alphanumerics plus `.-_+`. Reject partial metadata and persist both
values with the paired device.

**Step 3: Register once per iPhone app launch**

Read `CFBundleShortVersionString` and `CFBundleVersion`, include them with any
pending APNs/ActivityKit registration, and allow a metadata-only registration
once per process. Retry on failure; do not persist a false success flag.

**Step 4: Show the exact version on Mac**

Render `Buddy 1.0.0 (build)` under the paired device in Settings.

**Step 5: Run focused tests**

```bash
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
  swift test --filter 'RemoteAttentionLifecycleTests|RemoteApprovalHTTPServerTests/testAuthenticatedHostLifecycleOverRealListener'
```

Expected: 9 tests pass with zero failures.

**Step 6: Add restart proof and commit**

Reload `RemoteApprovalDeviceStore` from the same temporary state URL and assert
the version/build survive restart. Commit `Report exact paired Buddy build`.

### Task 2: Lock stable command-center state and motion rules

**Files:**

- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalClient.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/CompanionCommandCenterModel.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionTests/RemoteApprovalClientTests.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionTests/CompanionCommandCenterModelTests.swift`

**Step 1: Write failing reducer tests**

Cover these invariants:

```swift
XCTAssertNil(RemoteApprovalClient.refreshStartState(hasCompletedSnapshot: true))
XCTAssertEqual(
    CompanionAttentionSelection.resolve(previousID: "approval-a", items: refreshed),
    "approval-a"
)
XCTAssertFalse(CompanionMotionPolicy.animatesRoutinePoll)
XCTAssertTrue(CompanionMotionPolicy.animatesNewAttention)
```

Also assert that item order changes do not rotate the selected attention item
while its stable ID still exists.

**Step 2: Run the focused iOS tests and confirm failure**

Generate the project, boot the configured iPhone Simulator, and run only the
new model test classes. Expected: FAIL because the presentation model does not
exist.

**Step 3: Implement value-semantic presentation helpers**

Create small `Equatable` value types for destination, attention selection,
timeline rows, and motion policy. Do not introduce another observable object.

**Step 4: Remove broad root animations**

Keep animation attached only to user-selected destination, explicit action
receipt, and insertion/removal of genuinely new attention. Routine snapshot,
connection timestamp, and work-status changes update without a root animation.

**Step 5: Re-run tests and commit**

Expected: focused model/client tests pass. Commit `Stabilize Buddy polling presentation`.

### Task 3: Build the native command-center shell

**Files:**

- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/CompanionCommandCenterView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionTests/CompanionConnectionPresentationTests.swift`

**Step 1: Add failing accessibility-contract tests**

Require identifiers for:

- `companion.commandCenter`
- `companion.presence`
- `companion.destination.now`
- `companion.destination.sessions`
- `companion.capture`
- `companion.more`

**Step 2: Implement `CompanionPresenceHeader`**

Use content-leading identity, one connection indicator, and a `Menu` for
appearance/discovery. Remove the two permanent equal-weight trailing tiles.

**Step 3: Implement `CompanionActionDock`**

Use a bottom safe-area inset so controls remain thumb-reachable. On iOS 26+,
group interactive glass controls in `GlassEffectContainer`; otherwise use
`.ultraThinMaterial` plus native button styles. Keep the content beneath it
scrollable and add bottom content clearance equal to the dock height.

**Step 4: Replace top segmented navigation**

Now and Sessions become dock destinations. Capture opens task/note choices.
More presents the existing module surface in one `NavigationStack` and one
`ScrollView`; remove the nested `ScrollView` currently present in the tools
sheet.

**Step 5: Build before proceeding**

```bash
cd ios/CodeIslandCompanion
xcodegen generate
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
  xcodebuild -project CodeIslandCompanion.xcodeproj \
  -scheme CodeIslandCompanion -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: BUILD SUCCEEDED.

**Step 6: Commit**

Commit `Build Buddy command center shell`.

### Task 4: Redesign approvals and questions as the attention stage

**Files:**

- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/CompanionCommandCenterView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift`

**Step 1: Add mock attention launch states**

Add deterministic launch arguments for one approval, one question, and two
pending items. Keep all action tokens synthetic and local to the UI test.

**Step 2: Write failing UI tests**

Assert the highest-priority item is visible, the count is announced, no second
item replaces it after five seconds, and Approve/Deny or question choices have
44-point targets and expected accessibility labels.

**Step 3: Implement the attention stage**

Use a single dominant stage with source, plain-language request title, detail,
workspace, age, and safe action controls. Move session suffix and secondary
technical metadata behind disclosure unless needed to distinguish requests.
Use amber for approval attention, system blue for questions, green for the
affirmative action, and red for denial.

**Step 4: Preserve confirmation safety**

Keep the existing `confirmationDialog`, exact request ID, action token,
busy-state disabling, stale refresh, and replay rejection unchanged.

**Step 5: Run focused UI tests and commit**

Commit `Focus Buddy on actionable attention`.

### Task 5: Replace the Today card with a semantic timeline

**Files:**

- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/CompanionCommandCenterView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift`

**Step 1: Write failing Today-state UI tests**

Cover populated Today, all-clear, loading-with-last-content, and offline-with-
last-content states. Assert `Join` appears only for a trusted meeting action.

**Step 2: Implement `CompanionTodayTimeline`**

Use a large semantic title, a concise weather line, a left time/icon rail, and
unboxed rows separated by rhythm rather than repetitive rounded cards. Keep at
most the next three high-value rows.

**Step 3: Implement concise empty and offline states**

Render `Nothing needs you right now.` without a large container. When the Mac
goes offline after a successful snapshot, retain the last content and add one
compact recovery banner.

**Step 4: Verify Dynamic Type and commit**

Run UI tests with an accessibility content-size launch argument and assert the
dock and primary action remain hittable. Commit `Refine Buddy Today timeline`.

### Task 6: Add native visual-state and stability evidence

**Files:**

- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift`
- Modify: `scripts/smoke-companion-ui.sh`
- Create: `docs/evidence/2026-07-18-buddy-command-center-visual-acceptance.md`

**Step 1: Capture deterministic native states**

Retain screenshots for light/dark clear state, approval, question, offline,
unpaired, Sessions, More, and accessibility text size.

**Step 2: Add a three-poll stability test**

Capture the settled screen before and after three simulated routine polls.
Mask only the clock/time label, compare the remaining pixels or stable
accessibility frame tree, and fail on insertion/removal or layout movement.

**Step 3: Run native UI smoke**

```bash
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
  scripts/smoke-companion-ui.sh
```

Expected: all state tests pass and screenshots are produced.

**Step 4: Review at original resolution**

Reject any state with generic equal-weight card stacks, low-contrast metadata,
unintentional dead space, clipped Dynamic Type, inaccessible contrast, or
continuous decorative motion. Record exact artifact paths and verdicts.

**Step 5: Commit**

Commit `Verify Buddy command center visuals`.

### Task 7: Run full protocol, native, and performance verification

**Files:**

- Modify as evidence requires: `docs/crest-mobile-parity.md`
- Modify as evidence requires: `CODEX_HANDOFF.md`

**Step 1: Run Swift tests**

```bash
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" swift test
```

Expected: zero failures.

**Step 2: Run the complete iOS scheme**

Run `CodeIslandCompanionTests` and `CodeIslandCompanionUITests` on the selected
iPhone Simulator. Separate app assertions from Simulator infrastructure errors.

**Step 3: Run code-first performance audit**

Check for broad observation, unstable `ForEach` identity, derived work in
`body`, root animation modifiers, nested scroll containers, blur on scrolling
content, and continuously animated timelines. Use Instruments/SwiftUI tracing
only if the source audit or three-poll test remains inconclusive.

**Step 4: Re-run real-listener E2E**

Cover pair/auth, metadata persistence, modes, approval, question, exact
confirmation, altered intent, replay rejection, audit, downloads, and path
confinement.

**Step 5: Refresh Graphify**

```bash
graphify update . --no-viz
```

Read the report and keep generated output untracked unless the repo contract
requires it.

### Task 8: Merge and distribute one coherent Mac/iPhone release

**Files:**

- Modify: `CODEX_HANDOFF.md`
- Modify: `docs/crest-mobile-parity.md`
- Modify: `docs/evidence/2026-07-17-crest-mobile-physical-acceptance.md`

**Step 1: Commit and push**

Push `codex/device-build-receipt`, open a ready PR against
`revopsglobal/CodeIsland:main`, enable auto-merge after green checks, and repair
failures rather than bypassing protection.

**Step 2: Build and install the signed Mac app**

Dispatch `build-macos-arm-dmg.yml` from merged `main`. Verify source SHA,
artifact ID/hash, signature team/CDHash, installed version, running PID, local
health, Tailscale health, and the new paired-Buddy version row.

**Step 3: Build and upload Buddy**

Dispatch `testflight-ios.yml` from the same merged SHA. Require Apple `VALID`,
membership in `CodeIsland Internal`, and visibility to
`gregharned@gmail.com`; upload success is not install proof.

**Step 4: Complete physical acceptance**

Install/update the exact TestFlight build, launch it so the Mac records the
version/build, then verify pairing, no four-second flash, approval/question,
task/note capture, Calendar read/Join, file handoff, push, Live Activity,
Dynamic Island, deep link, and App Intent on Wi-Fi. Repeat the away-critical
actions on cellular with Tailscale while the Mac is locked but awake.

**Step 5: Record proof without overstatement**

For every surface, record exact version/build, device, network, timestamp,
receipt, and verdict. Leave any human-only or hardware-only item explicitly
unverified until observed.
