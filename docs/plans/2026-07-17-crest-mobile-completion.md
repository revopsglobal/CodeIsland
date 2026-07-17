# Crest and Mobile Completion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver useful Crest 4.9 behavior parity on the signed CodeIsland Mac app, excluding Pomodoro and Watch, and make every useful host action available from a signed iPhone app over Tailscale with a private web fallback.

**Architecture:** Keep CodeIsland Mac as the only state/action host. Extend the shared `CodeIslandCore` catalog and typed snapshot/action protocol first, then render the same contract in the Mac, native iPhone, and web clients. Mutations continue to use short-lived, exact, device-bound confirmation tokens; Telegram remains outbound alert/deep-link only.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, EventKit, AVFoundation, ScreenCaptureKit, Speech, ActivityKit, App Intents, UserNotifications/APNs, Carbon hot keys, Accessibility, Tailscale Serve HTTPS, XCTest/XCUITest, GitHub Actions, and the App Store Connect API.

---

## Execution rules

- Work in the dedicated `codex/crest-completion` worktree.
- Preserve a red-green-refactor cycle for each behavior batch.
- Run focused tests before and after each change and the full Swift suite at batch boundaries.
- Keep platform states separate: Simulator is not physical-iPhone proof, upload is not TestFlight availability, and merged source is not an installed DMG.
- Commit each task independently.
- Do not add Pomodoro, Watch work, a generic remote command endpoint, or an inbound Telegram daemon.

## Task 1: Restore Greg's internal TestFlight access

**Files:**

- Create: `scripts/manage-testflight-internal-tester.sh`
- Create: `Tests/Scripts/manage-testflight-internal-tester.bats`
- Create: `.github/workflows/manage-testflight-tester.yml`
- Modify: `CODEX_HANDOFF.md`
- Modify: `docs/crest-mobile-parity.md`

**Step 1: Write failing fixture tests**

Mock App Store Connect responses for an existing user/tester, an existing pending invitation, a missing team user, a wrong app/group, and redaction of JWTs.

Run: `bats Tests/Scripts/manage-testflight-internal-tester.bats`

Expected: FAIL because the manager does not exist.

**Step 2: Implement the idempotent manager**

Reuse `scripts/app-store-connect-jwt.rb`. Resolve the Buddy app, require the matching internal `CodeIsland Internal` group, inspect `/v1/users`, `/v1/userInvitations`, and `/v1/betaTesters`, then add an existing tester to `/v1/betaGroups/{id}/relationships/betaTesters`. If the user is missing, create a scoped `DEVELOPER` `userInvitations` resource for the Buddy app and return an explicit `acceptance-required` receipt. Do not fall back to external review.

**Step 3: Add and run the manual workflow**

The workflow accepts `tester_email` defaulting to `gregharned@gmail.com`, installs the existing App Store Connect key from secrets, runs the manager, and uploads a redacted JSON receipt.

Run:

```bash
actionlint .github/workflows/manage-testflight-tester.yml
bats Tests/Scripts/manage-testflight-internal-tester.bats
```

Expected: PASS.

**Step 4: Commit, push, and execute**

```bash
git add scripts/manage-testflight-internal-tester.sh Tests/Scripts/manage-testflight-internal-tester.bats .github/workflows/manage-testflight-tester.yml CODEX_HANDOFF.md docs/crest-mobile-parity.md
git commit -m "Restore internal TestFlight tester access"
git push -u origin codex/crest-completion
gh workflow run manage-testflight-tester.yml --repo revopsglobal/CodeIsland --ref codex/crest-completion -f tester_email=gregharned@gmail.com
```

Expected: membership is proven or one precise Apple invitation acceptance step is produced.

## Task 2: Persist per-mode racks and dashboard configuration

**Files:**

- Modify: `Sources/CodeIslandCore/PersonalHubProtocol.swift`
- Create: `Sources/CodeIsland/PersonalHubConfigurationStore.swift`
- Modify: `Sources/CodeIsland/PersonalHubService.swift`
- Modify: `Sources/CodeIsland/PersonalHubMacView.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalWebApp.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift`
- Modify: `Tests/CodeIslandCoreTests/PersonalHubProtocolTests.swift`
- Create: `Tests/CodeIslandTests/PersonalHubConfigurationStoreTests.swift`
- Modify: `Tests/CodeIslandTests/RemoteApprovalHTTPServerTests.swift`

**Step 1: Write failing tests** for sanitized saved order, pin/unpin, deduplication, migration from fixed racks, separate Home/Work/Code preferences, local-day progress, persistence, and confirmed remote updates.

Run: `swift test --filter 'PersonalHubProtocolTests|PersonalHubConfigurationStoreTests|RemoteApprovalHTTPServerTests'`

**Step 2: Implement** versioned shared configuration and an atomic Application Support store. New required modules must be appended after saved modules during upgrades.

**Step 3: Render** drag reorder/pin editing on Mac, native `List.onMove` on Buddy, and accessible move/pin controls on web. Add the saved dashboard toggle and local-day progress header.

**Step 4: Verify and commit.** Add a real-listener restart/persistence test and an iOS reorder UI test, then commit `Add saved mode racks and dashboard`.

## Task 3: Add global quick task and note capture

**Files:**

- Modify: `Sources/CodeIsland/GlobalHotKeyManager.swift`
- Create: `Sources/CodeIsland/QuickJotWindowController.swift`
- Modify: `Sources/CodeIsland/PersonalHubDataModel.swift`
- Modify: `Sources/CodeIsland/CodeIslandApp.swift`
- Modify: `Tests/CodeIslandTests/GlobalHotKeyManagerTests.swift`
- Create: `Tests/CodeIslandTests/QuickJotTests.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift`

**Step 1: Write failing tests** for Control-Option-T, Control-Option-N, conflict-free registration, explicit destination, Escape, Return, undo, and remote snapshot visibility.

**Step 2: Implement** a focused quick-jot panel that reuses the existing Reminders/Notes mutation paths and shows the destination before save.

**Step 3: Add** native Buddy New Task/New Note entry points and deep-link destinations.

Run: `swift test --filter 'GlobalHotKeyManagerTests|QuickJotTests|PersonalHubDataModelTests'`

Commit: `Add global task and note quick jot`.

## Task 4: Add shared Calendar month view and reliable Join

**Files:**

- Modify: `Sources/CodeIslandCore/PersonalHubProtocol.swift`
- Modify: `Sources/CodeIsland/GlancesModel.swift`
- Modify: `Sources/CodeIsland/GlancesView.swift`
- Modify: `Sources/CodeIsland/PersonalHubMacView.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalWebApp.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift`
- Modify: `Tests/CodeIslandTests/GlancesModelTests.swift`
- Modify: `Tests/CodeIslandCoreTests/PersonalHubProtocolTests.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift`

**Step 1: Write failing tests** for local-time month boundaries, adjacent-month cells, day counts, selection, empty days, recurrence-safe IDs, trusted Zoom/Meet/Teams URLs, and rejected schemes.

**Step 2: Implement** a six-week month snapshot with selected-day events while preserving agenda CRUD. Render previous/today/next controls everywhere.

Run: `swift test --filter 'GlancesModelTests|PersonalHubProtocolTests'`, then the focused Calendar XCUITest.

Commit: `Add Calendar month view and Join parity`.

## Task 5: Complete Shelf capture and private file handoff

**Files:**

- Create: `Sources/CodeIsland/ShelfCaptureController.swift`
- Modify: `Sources/CodeIsland/PersonalHubDataModel.swift`
- Modify: `Sources/CodeIsland/PersonalHubMacView.swift`
- Modify: `Sources/CodeIsland/PersonalHubService.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalWebApp.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift`
- Create: `Tests/CodeIslandTests/ShelfCaptureControllerTests.swift`
- Modify: `Tests/CodeIslandTests/PersonalHubDataModelTests.swift`
- Modify: `Tests/CodeIslandTests/RemoteApprovalHTTPServerTests.swift`

**Step 1: Write failing tests** for drag/drop, collision-safe names, screenshot watching, selection capture, recording completion, path confinement, metadata, deletion, and the 100 MB remote cap.

**Step 2: Implement** private Shelf storage and user-selected ScreenCaptureKit flows. Never scrape arbitrary app content.

**Step 3: Render** Mac drop/capture controls and reuse the authenticated Buddy/web transfer and native share flow.

Run: `swift test --filter 'ShelfCaptureControllerTests|PersonalHubDataModelTests|RemoteApprovalHTTPServerTests'`.

Commit: `Complete Shelf capture and handoff`.

## Task 6: Add Now Playing artwork, scrubber, and media HUD

**Files:**

- Modify: `Sources/CodeIsland/PersonalHubDataModel.swift`
- Create: `Sources/CodeIsland/MediaHUDController.swift`
- Modify: `Sources/CodeIsland/PersonalHubMacView.swift`
- Modify: `Sources/CodeIsland/NotchPanelView.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalWebApp.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift`
- Modify: `Tests/CodeIslandTests/PersonalHubDataModelTests.swift`
- Create: `Tests/CodeIslandTests/MediaHUDControllerTests.swift`

**Step 1: Write failing tests** for artwork, clamped arbitrary seek, optimistic scrub state, provider differences, HUD state, and explicit Spotify queue unavailability.

**Step 2: Implement** bounded private artwork, duration/progress/seek, compact artwork/scrubber UI, low-cost ambient artwork/visualizer respecting Reduce Motion and thermal state, and volume/brightness feedback.

Run: `swift test --filter 'PersonalHubDataModelTests|MediaHUDControllerTests'`.

Commit: `Complete Now Playing and media HUD`.

## Task 7: Mirror recent macOS notifications safely

**Files:**

- Create: `Sources/CodeIsland/SystemNotificationMirror.swift`
- Modify: `Sources/CodeIsland/PersonalHubService.swift`
- Modify: `Sources/CodeIsland/PersonalHubMacView.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalWebApp.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift`
- Create: `Tests/CodeIslandTests/SystemNotificationMirrorTests.swift`

**Step 1: Write failing tests** for ordering, grouping, dedupe, age/entry limits, redaction, CodeIsland-alert separation, and unsupported/permission states.

**Step 2: Implement** only a supported provider boundary. If macOS exposes no public cross-app history API, show the provider limitation and do not read private notification databases or require Full Disk Access.

Run: `swift test --filter SystemNotificationMirrorTests`.

Commit: `Add safe notification mirror surface`.

## Task 8: Add native camera/microphone preflight on Mac and iPhone

**Files:**

- Create: `Sources/CodeIsland/MediaPreflightModel.swift`
- Create: `Sources/CodeIsland/MediaPreflightView.swift`
- Modify: `Sources/CodeIsland/PersonalHubMacView.swift`
- Modify: `Sources/CodeIsland/SettingsView.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/MediaPreflightView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift`
- Create: `Tests/CodeIslandTests/MediaPreflightModelTests.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift`

**Step 1: Write failing tests** for permission transitions, device enumeration/selection, RMS/peak normalization, disconnect/interruption, and stopping on dismissal/background.

**Step 2: Implement** local-only AVFoundation camera preview and microphone meter. Never encode or transmit media; remote state exposes health only.

Run: `swift test --filter MediaPreflightModelTests`, then the focused iOS camera/mic UI tests.

Commit: `Add private camera and microphone preflight`.

## Task 9: Complete Mac Claude voice and file context

**Files:**

- Create: `Sources/CodeIsland/ClaudeVoiceController.swift`
- Modify: `Sources/CodeIsland/PersonalHubMacView.swift`
- Modify: `Sources/CodeIsland/PersonalHubService.swift`
- Modify: `Sources/CodeIsland/PanelWindowController.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalWebApp.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift`
- Create: `Tests/CodeIslandTests/ClaudeVoiceControllerTests.swift`
- Modify: `Tests/CodeIslandTests/PersonalHubDataModelTests.swift`

**Step 1: Write failing tests** for push-to-talk/continuous modes, visible listening state, silence timeout, denial, cancel, file constraints, read-only Ask, reviewed Do, and exact confirmation.

**Step 2: Implement** local Speech/AVFoundation recognition, deliberate open-panel/drop file context, bounded text extraction, and the existing no-tools proposal path.

**Step 3: Add** a compact screen-share-hidden strip where macOS sharing exclusion is supportable, with an honest unsupported state.

Run: `swift test --filter 'ClaudeVoiceControllerTests|PersonalHubDataModelTests'`.

Commit: `Complete Claude voice and file context`.

## Task 10: Complete Mac teleprompter controls and privacy

**Files:**

- Modify: `Sources/CodeIsland/TeleprompterWindowController.swift`
- Modify: `Sources/CodeIsland/PersonalHubMacView.swift`
- Create: `Tests/CodeIslandTests/TeleprompterWindowControllerTests.swift`

**Step 1: Write failing tests** for play/pause, 60-240 WPM, elapsed offset, resume, manual-scroll pause, font size, end-of-script, sharing exclusion, and cleanup.

**Step 2: Implement** timer/display-link-derived pacing, persisted preferences, and honest sharing-exclusion status.

Run: `swift test --filter TeleprompterWindowControllerTests`.

Commit: `Complete Mac teleprompter controls`.

## Task 11: Add drag-to-notch window layouts

**Files:**

- Modify: `Sources/CodeIsland/WindowManagerController.swift`
- Create: `Sources/CodeIsland/WindowLayoutDropController.swift`
- Modify: `Sources/CodeIsland/PanelWindowController.swift`
- Modify: `Sources/CodeIsland/NotchPanelView.swift`
- Create: `Tests/CodeIslandTests/WindowLayoutDropControllerTests.swift`

**Step 1: Write failing tests** for notch hover/hysteresis/cancel, halves, maximize, thirds, quarters, visible frames, multiple displays, and Accessibility denial.

**Step 2: Implement** a chooser active only during a real system window drag, targeting the correct display and never moving CodeIsland's own panel.

Run: `swift test --filter WindowLayoutDropControllerTests`.

Commit: `Add drag-to-notch window layouts`.

## Task 12: Complete iPhone away-use surfaces, App Intents, and deep links

**Files:**

- Modify: `Sources/CodeIslandCore/PersonalHubProtocol.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalClient.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/CodeIslandAppIntents.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/CodeIslandCompanionApp.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/Info.plist`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift`

**Step 1: Add a failing parity-contract test** requiring every catalog module to have a Buddy route and each useful action to be native, deliberately read-only, or marked Mac-only with a reason.

**Step 2: Finish** native editors, shared deep links, pending-push routing, retry/offline state, and host/Tailscale status.

**Step 3: Add App Intents** for opening pending approval/module and preparing a task/note creation. Mutations still hand off to exact confirmation unless explicitly safe and idempotent.

Run the full `CodeIslandCompanion` Xcode test scheme.

Commit: `Complete iPhone away-use action parity`.

## Task 13: Harden push, Live Activities, and Dynamic Island lifecycle

**Files:**

- Modify: `Sources/CodeIsland/APNSNotificationSender.swift`
- Modify: `Sources/CodeIsland/RemoteApprovalService.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/LiveActivityController.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/CodeIslandActivityState+Payload.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionWidget/CodeIslandLiveActivityWidget.swift`
- Modify: `Tests/CodeIslandTests/RemoteApprovalHTTPServerTests.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift`

**Step 1: Write failing tests** for opaque payloads, pending/answered/expired states, multiple sessions, token rotation, activity update/end, stale push ignore, deep-link selection, and replay after end.

**Step 2: Implement** concise active approval/question/session state and prompt activity cleanup; sensitive detail remains behind authenticated refresh.

Run: `swift test --filter RemoteApprovalHTTPServerTests`, then focused Live Activity UI tests.

Commit: `Harden push and Live Activity lifecycle`.

## Task 14: Full automated verification and evidence refresh

**Files:**

- Modify: `docs/crest-mobile-parity.md`
- Modify: `CODEX_HANDOFF.md`

**Step 1: Run Mac tests/build:** `swift test && swift build -c release`.

**Step 2: Run the complete iOS scheme** with Xcode beta on the `OB1 Widget Proof iPhone 16` Simulator. Keep product assertions separate from Simulator launcher failures.

**Step 3: Run real-listener E2E** for pairing, auth, modes, approvals, questions, confirmation, altered intent, replay, audit, downloads, and path confinement.

**Step 4: Run `graphify update . --no-viz`, read the report, update evidence-backed ledger states, and omit generated graph artifacts if they are not tracked output.

Commit: `Verify Crest and mobile completion`.

## Task 15: Signed distribution and installation

**Files:**

- Modify if required: `.github/workflows/build-macos-arm-dmg.yml`
- Modify if required: `.github/workflows/testflight-ios.yml`
- Modify: `CODEX_HANDOFF.md`

**Step 1:** Push, open a ready PR, enable auto-merge only after required checks pass, and repair failures instead of bypassing protection.

**Step 2:** From merged `main`, build the next signed Mac DMG. Verify source SHA, artifact ID, SHA-256, mounted signature, installed signature/version/team/CDHash, PID, local health, and Tailscale health.

**Step 3:** From the same merged SHA, build/upload Buddy. Require Apple `VALID`, `CodeIsland Internal`, and confirmed membership for `gregharned@gmail.com`; upload success alone is insufficient.

**Step 4:** Record exact workflow/build/artifact receipts in `CODEX_HANDOFF.md`.

## Task 16: Physical Mac/iPhone end-to-end acceptance

**Files:**

- Create: `docs/evidence/2026-07-17-crest-mobile-physical-acceptance.md`
- Modify: `docs/crest-mobile-parity.md`
- Modify: `CODEX_HANDOFF.md`

**Step 1:** Install Buddy from TestFlight, enable Tailscale, pair, and confirm the device plus production APNs token on the Mac.

**Step 2:** Run Mac native acceptance with real data/permissions for Calendar, Reminders, mode racks, quick jot, Shelf/capture, Apple Music/Spotify exposed controls, HUD, notification provider state, camera/mic, Claude voice/context, teleprompter, and window layouts.

**Step 3:** On iPhone Wi-Fi, verify every mode, task/note creation, approval/question, exact confirmation, Calendar Join, downloads/Shelf share, push, Live Activity/Dynamic Island, App Intent, and deep links.

**Step 4:** Lock the awake Mac, disable phone Wi-Fi, keep cellular Tailscale active, then complete one approval, question, task creation, Calendar read/Join, file handoff, altered-intent rejection, and replay rejection.

**Step 5:** Record exact devices, versions, network state, timestamps, permission states, and action receipts. Commit `Record physical Crest and mobile acceptance`.

The project is complete only when the physical run passes or the remaining human-only tap is named precisely. Automated evidence may not substitute for it.
