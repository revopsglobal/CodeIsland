# CodeIsland — current cold handoff

Last updated: 2026-07-17. This supersedes the original v1.0.30 / no-local-Xcode
handoff.

## Latest physical and delivery delta

This section supersedes older build/pairing statements later in the document.

- PR #29 merged at `96c1a74bca0c851dcaf1ef91248cc9751c136816`.
  It stops foreground polling from re-entering a loading state and reserves
  pulse animation for actual approval/question attention. TestFlight
  `1.0.0 (20260718031753)` from run `29628559171`, artifact `8424725763`, is
  installed on Greg's physical iPhone. Four observations over approximately
  15 seconds showed no recurrence of the four-second full-surface flash.
- The iPhone paired at `2026-07-18T02:26:48Z` as device
  `afba2915-b0a3-456f-a5f2-265bf7e8a64a`. The Mac has a production APNs token
  for it and continued receiving authenticated heartbeats after the install.
- The physical iPhone has produced three real audited approval decisions. The
  latest is request `e4e3b760-3eef-43e4-b671-93e483a9981c`, `approve`,
  `resolved`, written at `2026-07-18T03:18:13Z` from device `iPhone`.
- PR #30 merged at `7f311899a97410b7f69727f39a4c8b0e1ad019c6`.
  It makes the compact Buddy header show the authenticated Tailscale Mac name
  instead of misleading `Searching` text while nearby discovery runs. Signed
  TestFlight build `1.0.0 (20260718041048)` uploaded from this exact SHA in run
  `29630108653`; Apple delivery
  `a1fa24b9-1bec-4656-b3b6-8641ede8c854` reported upload success. The initial
  20-minute visibility check timed out while Apple indexed the build; recovery
  run `29630740348` performs verification only and does not duplicate the IPA.
  Do not call the label physically accepted until this build is visible,
  installed, and checked on Greg's iPhone.
- Fresh verification on PR #30 source: 477 Mac app tests passed with two
  intentional skips; 218 core tests passed; the production Swift build passed;
  and the full iPhone scheme passed 6 unit plus 24 UI tests with zero failures.
  Result bundle:
  `~/Library/Developer/Xcode/DerivedData/CodeIslandCompanion-abkbncwynakyihgwigzxamfbugzs/Logs/Test/Test-CodeIslandCompanion-2026.07.17_21-02-54--0700.xcresult`.
- The installed host is now `/Applications/CodeIsland.app` `1.0.40`, signed by
  Team `44JG2Y95CH`, and its real listener answers `/health` with
  `running: true`. The 1.0.40 DMG came from run `29621743481`, source
  `4041ea71d95e18556a6b125d333b2006a31821d0`, artifact `8422488531`.
- The TestFlight workflow now gives Apple 60 minutes to index a normal upload
  and preserves the signed IPA artifact even when the processing check fails.
- Exact physical proof and the still-open matrix are recorded in
  `docs/evidence/2026-07-17-crest-mobile-physical-acceptance.md`. Remaining
  gates are a real question/replay, background push/Live Activity/Dynamic
  Island, cellular/Tailscale with Wi-Fi off, and Greg's real TCC-backed
  Calendar/Reminders/weather/Join plus module/accessory workflows.

## Current outcome

CodeIsland is Greg's private Mac host plus iPhone companion for Crest-class
notch utilities and away-from-Mac coding control. Pomodoro and Apple Watch are
out of scope.

- The Crest/mobile completion implementation and its verification handoff
  merged through PR #19. The Xcode 26 SwiftUI compatibility refactor merged
  through PR #20. The completion implementation source is
  `2f7a6b1bb66e14baad870d45fd0767553f816968`; PR #24 added the Apple-required
  App Intent metadata correction and release guard. Current `main` is
  `7f311899a97410b7f69727f39a4c8b0e1ad019c6`.
- Signed macOS `1.0.40` is installed at
  `/Applications/CodeIsland.app`, running as Team `44JG2Y95CH`, CDHash
  `cc8ccbd31b5daf02fa440a641928706b33a7ae68`.
- The exact DMG is
  `/Users/gregharned/Downloads/CodeIsland-1.0.40-run-29621743481/CodeIsland.dmg`,
  SHA-256
  `6c792b79921ebb67ff820fdcdcde58a89769dcc8c8b831dc1621185aa907f547`.
- iOS `1.0.0 (20260717225004)` is Apple `VALID`, audience
  `APP_STORE_ELIGIBLE`, and available to the all-builds internal group
  `CodeIsland Internal` in TestFlight.
- `gregharned@gmail.com` is now verified as an `ACCOUNT_HOLDER,ADMIN` App Store
  Connect user, enrolled in `CodeIsland Internal`, and Apple explicitly sent a
  fresh TestFlight invitation at 2026-07-17 15:20:54Z. Workflow run
  `29591716380`, tester receipt artifact `8411326331`, invitation
  `9679ce07-ac35-4b29-b007-461e0b418801`.
- Mac local and Tailscale `/health` both returned `running: true` after the
  1.0.39 install.
  The Tailscale root returned the expected security headers and an
  unauthenticated Downloads-file request returned `401`.

Those signed receipts prove build, signing, transport, install, and automated
runtime surfaces from the completed merged source. They do not prove Greg's
physical iPhone, macOS TCC grants, APNs delivery, Dynamic Island, or real
accessory/data mutations.

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
- Run: `29621743481`
- Artifact: `8422488531` (`CodeIsland-macos-arm64-dmg`)
- Version: `1.0.40`
- Source SHA: `4041ea71d95e18556a6b125d333b2006a31821d0`
- Signing: Apple Development, Team `44JG2Y95CH`
- Previous installed app backup:
  `/Applications/CodeIsland-backup-1.0.38-20260717-1449.app`

### iOS / TestFlight

- Workflow: `Build and Upload iOS TestFlight`
- Run: `29619011267`
- Signed IPA artifact: `8421590778`
- Tester receipt artifact: `8421528342`
- Version/build: `1.0.0 (20260717225004)`
- Bundle: `com.revopsglobal.codeisland.buddy`
- Source SHA: `4c3e274d4cdc3f231459a2a10e5a73557dc4e47e`
- Apple processing: `VALID`, `APP_STORE_ELIGIBLE`
- Internal group: `CodeIsland Internal`, all-build access
- Internal tester: `gregharned@gmail.com`, enrollment `ready`
- Upload delivery: `dc6f1d45-d4ab-448e-9d73-49be811710ee`
- Downloaded IPA:
  `/Users/gregharned/Downloads/CodeIsland-TestFlight-20260717225004-run-29619011267/CodeIsland-Buddy-TestFlight-20260717225004/CodeIslandCompanion.ipa`
- IPA SHA-256:
  `431960f551777405b059e09c26bb7e624eb6edc5456ae55f686631354e048ff2`
- Fresh invitation receipt: run `29591716380`, artifact `8411326331`,
  invitation `9679ce07-ac35-4b29-b007-461e0b418801`

The installed Mac build comes from the completion source SHA above. The current
Apple-VALID TestFlight build includes that completion source plus the App Intent
metadata correction and pre-upload validation merged through PR #24.

## Implemented product surface

The exact readiness and proof boundary for every capability lives in
`docs/crest-mobile-parity.md`. Treat that ledger as authoritative.

Implemented surfaces now include the useful Crest 4.9 behavior baseline plus
the single-user away extensions below. `docs/crest-mobile-parity.md` remains
authoritative for API limits and physical-proof state.

- Auto, Home, Work, and Code modes on Mac, native iPhone, and private web, with
  versioned saved per-mode pin/order, rack editors, dashboard toggle, and
  local-day progress.
- Claude/Codex session status, approvals, questions, exact confirmation,
  replay protection, decisions-first attention, opaque APNs, audited host
  execution, pending deep links, Live Activity, and Dynamic Island lifecycle.
- Calendar six-week month, selected-day events, two-week agenda,
  add/edit/delete, and trusted one-click Join.
- Reminders list selection plus list/task add, reorder, complete,
  archive/restore, and delete.
- Notes/jot persistence, categories, checklists, append/replace, undo, and
  stale-revision rejection.
- Now Playing bounded artwork, arbitrary scrubber, controls/lyrics/queue where
  the source app exposes them, and notch media/volume/brightness HUD feedback.
- Shelf and clipboard history with drag/drop, picker ingest, forward-only
  screenshot watching, user-selected still/recording capture, private storage,
  and guarded private file transfer.
- Active Downloads plus 12 recent completed files, filename-preserving iPhone
  share/web download, path confinement, and a 100 MB cap.
- Weather with location and manual ZIP fallback; system, battery, Bluetooth,
  audio, quick toggles, GitHub, and confirmed host window actions.
- Global task/note quick-jot hotkeys and native/deep-linked Buddy entry points.
- Native Mac/iPhone camera and microphone preflight; Mac Claude push-to-talk or
  continuous speech plus bounded user-selected file context; paced/persisted
  teleprompter; and real-drag notch window layouts including halves, thirds,
  quarters, and correct-display targeting.
- Native Buddy editors, retry/offline/Tailscale state, module and pending-action
  deep links, App Intents, and web fallback over the same allow-listed action
  contract.

Several of those implementations remain runtime-unverified against Greg's real
Calendar, Reminders, Music/Spotify, Bluetooth/audio devices, windows, and
physical phone. Do not turn implementation presence into a live claim.

## Verification already green

- Full current-head target-isolated Swift run: 477 app tests with two intentional skips and
  zero failures, plus 218 core tests with zero failures.
- Release Mac build passed. Existing Swift 6 migration/deprecation warnings are
  non-fatal and should be retired separately.
- Complete native companion scheme: 6 unit tests plus 24 UI tests, zero
  failures on Simulator `OB1 Widget Proof iPhone 16`, iOS 26.5.
  Result bundle:
  `~/Library/Developer/Xcode/DerivedData/CodeIslandCompanion-abkbncwynakyihgwigzxamfbugzs/Logs/Test/Test-CodeIslandCompanion-2026.07.17_21-02-54--0700.xcresult`.
- A first aggregate run found an XCTest accessibility-shape assumption in the
  hub module helper. The focused Home/Work/Code matrix passed after the helper
  was hardened, followed by the clean 24-test aggregate. This is not being
  hidden as a product failure or mislabeled as physical-device proof.
- Real-loopback lifecycle E2E proves pairing, bearer auth, all modes, approvals,
  questions, exact action confirmation, altered-intent/replay rejection, audit
  receipt, and push-token registration.
- Real-loopback Downloads E2E proves snapshot listing, unauthenticated
  rejection, exact bytes/filename, 100 MB enforcement, and traversal rejection.
- The native Downloads test proves a completed file reaches the iOS share
  sheet.
- Six App Intent metadata regression tests pass. Xcode generated
  `Metadata.appintents/extract.actionsdata` from the corrected Release target,
  and both source and compiled metadata pass the `ITMS-90626` guard. The signed
  archive repeated the compiled-metadata check before upload.

The Downloads watcher intentionally runs blocking protected-filesystem work on
a dedicated utility dispatch queue. Do not move it back to `Task.detached`;
full-suite load demonstrated cooperative-executor starvation.

## Remaining physical acceptance gate

Greg must perform the physical/TCC steps in
`docs/crest-mobile-parity.md#physical-acceptance-run`. The short version:

1. Open TestFlight while signed in as `gregharned@gmail.com`, refresh, then
   install or update CodeIsland Buddy to `1.0.0 (20260717225004)`. The tester is
   already enrolled and no public App Store review is required. Enable
   Tailscale on the iPhone.
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

## Deliberate limits and remaining non-automated proof

- macOS has no public API for cross-app Notification Center history. CodeIsland
  never reads private notification databases or requests Full Disk Access; the
  Notifications module shows the provider limitation and keeps action-required
  alerts separate.
- Spotify does not expose queue enumeration through its macOS automation API.
  Apple Music queue behavior remains implemented where exposed.
- macOS has no public API for intercepting every hardware brightness-key event.
  The HUD covers CodeIsland-initiated media/volume/brightness actions.
- Teleprompter/Claude windows request AppKit sharing exclusion, but full-display
  capture can still include them. The UI discloses that instead of promising
  covert behavior the platform cannot guarantee.
- iPhone remote window actions intentionally expose left/right/maximize; the
  expanded halves/thirds/quarters chooser is a direct Mac drag interaction.
- Automatic mode switching, TCC-backed data, media/accessory actions, physical
  push/Live Activity/Dynamic Island, App Intents, cellular Tailscale, and all
  real module mutations still require the physical acceptance matrix.

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
