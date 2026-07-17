# CodeIsland — current cold handoff

Last updated: 2026-07-17. This supersedes the original v1.0.30 / no-local-Xcode
handoff.

## Current outcome

CodeIsland is Greg's private Mac host plus iPhone companion for Crest-class
notch utilities and away-from-Mac coding control. Pomodoro and Apple Watch are
out of scope.

- The installed Mac and current TestFlight binaries come from product commit
  `6ad428e952fb200c51f68182471c38fe7c32e796`. The last merged handoff refresh
  before this behavior audit is `f8473e6029d77a4ec4f3cb7c6c26d7fe7e30a3c0`
  (PR #17).
- Signed macOS `1.0.36` is installed at `/Applications/CodeIsland.app`, running
  as Team `44JG2Y95CH`, CDHash
  `e7749f3369d10cac87e6495843de22d683a5a425`.
- The exact DMG is `/Users/gregharned/Downloads/CodeIsland-1.0.36-arm64.dmg`,
  SHA-256
  `7025c470ab22782f3ebc505ba9c358d97def778758b9955e374f906e675079fb`.
- iOS `1.0.0 (20260717120420)` is Apple `VALID`, audience
  `APP_STORE_ELIGIBLE`, and available to the all-builds internal group
  `CodeIsland Internal` in TestFlight.
- `gregharned@gmail.com` is now verified as an `ACCOUNT_HOLDER,ADMIN` App Store
  Connect user, enrolled in `CodeIsland Internal`, and Apple explicitly sent a
  fresh TestFlight invitation at 2026-07-17 15:20:54Z. Workflow run
  `29591716380`, tester receipt artifact `8411326331`, invitation
  `9679ce07-ac35-4b29-b007-461e0b418801`.
- Mac local and Tailscale `/health` both returned `running: true` after install.
  The Tailscale root returned the expected security headers and an
  unauthenticated Downloads-file request returned `401`.

These receipts prove build, signing, transport, install, and automated runtime
surfaces. They do not prove Greg's physical iPhone, macOS TCC grants, APNs
delivery, Dynamic Island, or real accessory/data mutations.

## Architecture decision

There is one control plane and one task/action contract:

1. `/Applications/CodeIsland.app` is the canonical Mac host. It observes coding
   sessions, owns local utility integrations, performs allow-listed actions,
   and emits audit receipts.
2. CodeIsland Buddy is the primary away client on iPhone. Nearby Bluetooth
   remains useful, but authenticated HTTPS over Tailscale is the away path.
3. The responsive private web client is a fallback over the same Tailscale
   listener and the same pairing/action APIs.
4. Telegram may send an outbound alert/deep link. It is not an inbound bot,
   daemon, task store, or second action system.

Remote mutations use an exact, short-lived, device-bound confirmation token.
There is no generic remote shell. This is intentionally optimized for Greg's
single-user setup rather than scale.

## Delivery receipts

### macOS

- Workflow: `Build macOS ARM DMG`
- Run: `29578951355`
- Artifact: `8406349680` (`CodeIsland-macos-arm64-dmg`)
- Version: `1.0.36`
- Source SHA: `6ad428e952fb200c51f68182471c38fe7c32e796`
- Signing: Apple Development, Team `44JG2Y95CH`
- Previous installed app backup:
  `/Applications/CodeIsland-backup-1.0.35-20260717-051229.app`

### iOS / TestFlight

- Workflow: `Build and Upload iOS TestFlight`
- Run: `29578952503`
- Artifact: `8406281069`
- Version/build: `1.0.0 (20260717120420)`
- Bundle: `com.revopsglobal.codeisland.buddy`
- Apple processing: `VALID`, `APP_STORE_ELIGIBLE`
- Internal group: `CodeIsland Internal`, all-build access
- Internal tester: `gregharned@gmail.com`, enrollment `ready`
- Fresh invitation receipt: run `29591716380`, artifact `8411326331`,
  invitation `9679ce07-ac35-4b29-b007-461e0b418801`

The current Mac build and current TestFlight build come from the same merged
source SHA.

## Implemented product surface

The exact readiness and proof boundary for every capability lives in
`docs/crest-mobile-parity.md`. Treat that ledger as authoritative.

Implemented surfaces include the useful subsets below. This list is not a
claim of full Crest behavior parity; the behavior-level gaps are recorded in
`docs/crest-mobile-parity.md`.

- Auto, Home, Work, and Code modes on Mac, native iPhone, and private web.
- Claude/Codex session status, approvals, questions, exact confirmation,
  replay protection, notifications, and audited host execution.
- Calendar two-week agenda, add/edit/delete, and trusted one-click Join.
- Reminders list selection plus list/task add, reorder, complete,
  archive/restore, and delete.
- Notes/jot persistence, categories, checklists, append/replace, undo, and
  stale-revision rejection.
- Now Playing controls/lyrics/queue where the source app exposes them.
- Shelf and clipboard history with guarded private file transfer.
- Active Downloads plus 12 recent completed files, filename-preserving iPhone
  share/web download, path confinement, and a 100 MB cap.
- Weather with location and manual ZIP fallback; system, battery, Bluetooth,
  audio, quick toggles, teleprompter, camera preview, GitHub, and window actions.
- APNs registration/provider path, time-sensitive notifications, widgets, Live
  Activities, and Dynamic Island UI.

Several of those implementations remain runtime-unverified against Greg's real
Calendar, Reminders, Music/Spotify, Bluetooth/audio devices, windows, and
physical phone. Do not turn implementation presence into a live claim.

## Verification already green

- Full Swift run: 402 app tests with 2 intentional skips and 0 failures, plus
  202 core tests with 0 failures.
- Release Mac build passed.
- Full native companion UI suite: 12 tests, 0 failures on the already-booted
  iPhone Simulator.
- The added camera-path UI test separately passed 1/1 on 2026-07-17. The first
  targeted execution visibly handled the real Simulator Camera permission
  alert; the finalized targeted rerun verified the native full-screen preview
  surface and dismissal. A subsequent 13-test full rerun
  was interrupted by the Xcode 27 beta Simulator launcher after 7 passes; its
  six failures were test-runner `signal term`/`signal kill` infrastructure
  crashes, not assertion failures. Keep the earlier clean 12-test receipt and
  the new focused 1-test receipt separate.
- Real-loopback lifecycle E2E proves pairing, bearer auth, all modes, approvals,
  questions, exact action confirmation, altered-intent/replay rejection, audit
  receipt, and push-token registration.
- Real-loopback Downloads E2E proves snapshot listing, unauthenticated
  rejection, exact bytes/filename, 100 MB enforcement, and traversal rejection.
- The native Downloads test proves a completed file reaches the iOS share
  sheet.

The Downloads watcher intentionally runs blocking protected-filesystem work on
a dedicated utility dispatch queue. Do not move it back to `Task.detached`;
full-suite load demonstrated cooperative-executor starvation.

## Remaining physical acceptance gate

Greg must perform the physical/TCC steps in
`docs/crest-mobile-parity.md#physical-acceptance-run`. The short version:

1. Open the fresh Apple TestFlight invitation sent to
   `gregharned@gmail.com`, accept it in TestFlight, then install CodeIsland
   Buddy `1.0.0 (20260717120420)`. Enable Tailscale on the iPhone.
2. On the unlocked Mac, use CodeIsland Settings permission buttons and approve
   Calendar, Reminders, Location Services, Camera, Microphone/Speech, and
   Accessibility when prompted.
3. Pair Buddy with the Mac's six-digit code. Verify Home/Work/Code first on
   Wi-Fi, then on cellular with Tailscale enabled.
4. Run a real approval and question; verify APNs, Live Activity/Dynamic Island,
   exact continuation, and replay rejection.
5. Run dedicated Reminder and Calendar CRUD tests, including one-click Join.
6. Run the real-data/accessory matrix in the parity ledger, including a
   completed Downloads transfer and an over-100-MB rejection.
7. Lock the Mac, leave local Wi-Fi, and repeat one approval, one task creation,
   and one Calendar read over cellular/Tailscale.

Until those taps happen, the honest final state is: automated E2E and signed
distribution are ready; physical iPhone/TCC/cellular acceptance is pending.

## Known gaps that are not permission-only

- Mode racks are hard-coded. Crest-style per-mode pinning and reordering are
  not implemented.
- Now Playing has no album artwork, arbitrary scrubber, visualizer, or floating
  music circles. Spotify does not expose a queue through macOS automation.
- Shelf has clipboard/file history but not drag/drop ingest, automatic
  screenshot capture, selection capture, or screen recording.
- Calendar has the two-week agenda and CRUD but no month surface.
- Notifications shows CodeIsland alerts only; it does not mirror macOS app
  notifications.
- Mac Claude is typed only and lacks continuous speech, file context, and the
  screen-share-hidden covert strip. iPhone dictation exists.
- Mac camera pre-check launches Photo Booth; native iPhone has a private
  front-camera preview. Microphone metering/device selection is incomplete.
- Mac teleprompter is manual-scroll only and is not hidden from screen sharing;
  iPhone has play/pause and WPM pacing.
- Window actions expose left/right/maximize but not Crest's drag-to-notch layout
  chooser.
- Crest's quick-jot hotkeys, media-key HUD, and custom dashboard/day-progress
  behavior are not implemented.
- Automatic mode switching has unit coverage but still needs native runtime
  evidence.
- Real module actions listed as `Unverified` in the parity ledger still need
  physical data/accessory proof.

## Source map

- Shared catalog/protocol: `Sources/CodeIslandCore/PersonalHubProtocol.swift`
- Mac snapshots/actions: `Sources/CodeIsland/PersonalHubService.swift`
- Remote host/auth/routes: `Sources/CodeIsland/RemoteApprovalService.swift`
- Private web client: `Sources/CodeIsland/RemoteApprovalWebApp.swift`
- Calendar/Reminders/weather: `Sources/CodeIsland/GlancesModel.swift`
- Downloads/Bluetooth/battery: `Sources/CodeIsland/PersonalUtilitiesModel.swift`
- Notes/Shelf/media/system/Claude: `Sources/CodeIsland/PersonalHubDataModel.swift`
- iPhone client: `ios/CodeIslandCompanion/CodeIslandCompanion/`
- Native UI tests:
  `ios/CodeIslandCompanion/CodeIslandCompanionUITests/CodeIslandCompanionUITests.swift`
- Parity/acceptance ledger: `docs/crest-mobile-parity.md`

## Build environment

Local Xcode is now available at
`/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer`; the old
"CommandLineTools only" constraint is obsolete. For signed artifacts, use the
GitHub workflows so the build, signing identity, App Store processing, and
artifact receipts remain reproducible:

```bash
gh workflow run build-macos-arm-dmg.yml \
  --repo revopsglobal/CodeIsland \
  --ref main \
  -f version=<next-version> \
  -f sign_for_internal_testing=true \
  -f sign_and_notarize=false

gh workflow run testflight-ios.yml \
  --repo revopsglobal/CodeIsland \
  --ref main
```

To verify enrollment or explicitly resend Greg's TestFlight email without
building another IPA, dispatch the same workflow with
`manage_tester_only=true`, `tester_email=gregharned@gmail.com`, and
`resend_testflight_invitation=true`.

Never claim a TestFlight build is ready until the workflow reports Apple
`VALID` and internal-group access. Never claim a Mac build is installed until
the downloaded DMG, mounted app signature, installed app signature/version,
running PID, and local/Tailscale health all match.
