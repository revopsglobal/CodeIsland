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
- A real physical question is also proven. Request
  `820a59cc-62da-44ba-9cbc-457c89af5e1e` appeared on the iPhone, `Continue` was
  selected and explicitly confirmed, the blocked bridge resumed with the exact
  answer, and the host wrote `question-answer` / `resolved` at
  `2026-07-18T04:47:24Z`.
- The physical **New Task** path created a temporary Reminder, Apple's Mac
  Reminders app showed it in the real Grocery list, and the item was cleaned up
  and confirmed absent. Buddy's Calendar also returned Greg's real July data,
  selected-day events, and `40 upcoming`. Those prove a Reminders add and
  Calendar read—not their full CRUD matrices.
- PR #30 merged at `7f311899a97410b7f69727f39a4c8b0e1ad019c6`.
  It makes the compact Buddy header show the authenticated Tailscale Mac name
  instead of misleading `Searching` text while nearby discovery runs. Signed
  TestFlight build `1.0.0 (20260718041048)` uploaded from this exact SHA in run
  `29630108653`; Apple delivery
  `a1fa24b9-1bec-4656-b3b6-8641ede8c854` reported upload success. The initial
  20-minute visibility check timed out while Apple indexed the build. Recovery
  run `29630740348` did not duplicate the IPA and found the build at
  `2026-07-18T05:14:12Z`: `VALID`, `APP_STORE_ELIGIBLE`, and available to the
  all-builds `CodeIsland Internal` group. Do not call the label physically
  accepted until the final replacement build is installed and checked on
  Greg's iPhone.
- Fresh verification on the current follow-up source: 480 Mac app tests passed
  with two intentional skips on the clean rerun; 219 core tests passed; the
  production Swift build passed; and the full iPhone scheme passed 7 unit plus
  25 UI tests with zero failures.
  Result bundle:
  `/tmp/CodeIsland-final-full-20260717-2223.xcresult`.
- PR #31 merged as `61310ee2d20c651221ee6ef9a3ef823bb7bb0558`.
  Signed Mac `1.0.41` from run `29632458432`, artifact `8425985562`, is
  installed at `/Applications/CodeIsland.app`; strict signature verification
  passed with Team `44JG2Y95CH`, CDHash
  `3922e9616d0ec54d7a590331325ab254197d29e2`. Both local and Tailscale health
  return `running: true`, and the physical iPhone pairing plus production APNs
  token survived the replacement.
- Final TestFlight build `1.0.0 (20260718053347)` from run `29632459018` is
  Apple `VALID`, `APP_STORE_ELIGIBLE`, and available to all builds in
  `CodeIsland Internal`. Delivery UUID:
  `835af987-3aef-4cc9-82d4-8d88ec0684f1`; IPA artifact `8425978534`; tester
  receipt `8425940062` records `gregharned@gmail.com` as `ready`. It includes
  the authenticated Sessions and ActivityKit push-to-start work, but remains
  signed-delivery proof until Greg unlocks iPhone Mirroring or updates it on
  the physical phone.
- The TestFlight workflow now gives Apple 60 minutes to index a normal upload
  and preserves the signed IPA artifact even when the processing check fails.
- Live unlocked inspection of Mac `1.0.41` exposed two provider-truth defects:
  Spotify reported its track duration in milliseconds while playback position
  was seconds, and the audio parser treated every listed input/output as the
  default device. PR #33 merged the Spotify normalization as
  `bca730bd9ac47f7ab9cb6e5a4352b6fab15f2d9b`; PR #34 merged the real
  `coreaudio_default_audio_input_device` /
  `coreaudio_default_audio_output_device` parsing as
  `265cc544d20a7144c3cfe1cd340a2f10748ab267`.
- Final signed Mac `1.0.43` from run `29633277978`, artifact `8426279211`, is
  installed from that PR #34 source. Its DMG SHA-256 is
  `e0369fbfd51c939b6b8e8e8afe7fa91a447e64a825b638a9885ec3c40a219b20`;
  mounted-image and installed-app strict signature checks passed with Team
  `44JG2Y95CH`, CDHash `78ef64fc758f0bebed52066a88eaf80c9bbad9dd`.
  Local and Tailscale health both returned `running: true`, and the physical
  iPhone pairing plus production APNs token survived this second replacement.
  The exact 19-test remote-security selection passed locally; its first CI
  attempt stopped transiently with signal 5 immediately after one passing
  test, and the clean rerun of the same workflow passed every gate and packaged
  the DMG. Post-install visual reinspection of the two provider fixes is still
  pending because macOS locked before that check.
- The previous installed build exposed one more truthful-state defect: Sessions could
  show nearby `Waiting for Mac` despite an authenticated Tailscale connection.
  PR #31 fetches the Code session rack independently and uses
  nearby discovery only when unpaired. It also registers ActivityKit
  push-to-start/update tokens, remotely starts a privacy-redacted Live Activity
  only for approvals/questions, and remotely ends it on resolution. Replacement
  signed Mac and iPhone builds are now delivered; physical iPhone installation
  and acceptance are still required before calling either behavior live.
- Exact physical proof and the still-open matrix are recorded in
  `docs/evidence/2026-07-17-crest-mobile-physical-acceptance.md`. Remaining
  gates are physical replay rejection, background push/Live Activity/Dynamic
  Island, cellular/Tailscale with Wi-Fi off, and the remaining real TCC-backed
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
  `265cc544d20a7144c3cfe1cd340a2f10748ab267`.
- Signed macOS `1.0.43` is installed at
  `/Applications/CodeIsland.app`, running as Team `44JG2Y95CH`, CDHash
  `78ef64fc758f0bebed52066a88eaf80c9bbad9dd`.
- The exact DMG is
  `/Users/gregharned/Downloads/CodeIsland-1.0.43-run-29633277978/CodeIsland.dmg`,
  SHA-256
  `e0369fbfd51c939b6b8e8e8afe7fa91a447e64a825b638a9885ec3c40a219b20`.
- iOS `1.0.0 (20260718053347)` is Apple `VALID`, audience
  `APP_STORE_ELIGIBLE`, and available to the all-builds internal group
  `CodeIsland Internal` in TestFlight.
- `gregharned@gmail.com` is now verified as an `ACCOUNT_HOLDER,ADMIN` App Store
  Connect user, enrolled in `CodeIsland Internal`, and Apple explicitly sent a
  fresh TestFlight invitation at 2026-07-17 15:20:54Z. Workflow run
  `29591716380`, tester receipt artifact `8411326331`, invitation
  `9679ce07-ac35-4b29-b007-461e0b418801`.
- Mac local and Tailscale `/health` both returned `running: true` after the
  1.0.43 install.
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
- Run: `29633277978`
- Artifact: `8426279211` (`CodeIsland-macos-arm64-dmg`)
- Version: `1.0.43`
- Source SHA: `265cc544d20a7144c3cfe1cd340a2f10748ab267`
- Signing: Apple Development, Team `44JG2Y95CH`
- DMG SHA-256:
  `e0369fbfd51c939b6b8e8e8afe7fa91a447e64a825b638a9885ec3c40a219b20`
- Installed CDHash: `78ef64fc758f0bebed52066a88eaf80c9bbad9dd`
- Previous installed app backup:
  `/Users/gregharned/Downloads/CodeIsland-app-backups/CodeIsland-1.0.41-pre-1.0.43.app`

### iOS / TestFlight

- Workflow: `Build and Upload iOS TestFlight`
- Run: `29632459018`
- Signed IPA artifact: `8425978534`
- Tester receipt artifact: `8425940062`
- Version/build: `1.0.0 (20260718053347)`
- Bundle: `com.revopsglobal.codeisland.buddy`
- Source SHA: `61310ee2d20c651221ee6ef9a3ef823bb7bb0558`
- Apple processing: `VALID`, `APP_STORE_ELIGIBLE`
- Internal group: `CodeIsland Internal`, all-build access
- Internal tester: `gregharned@gmail.com`, enrollment `ready`
- Upload delivery: `835af987-3aef-4cc9-82d4-8d88ec0684f1`
- Downloaded IPA:
  `/Users/gregharned/Downloads/CodeIsland-TestFlight-20260718053347-run-29632459018/CodeIslandCompanion.ipa`
- IPA SHA-256:
  `27259eccd5eb7890c3a4e852a52782cbf323b98956ef9025cb03f7e2925b2630`
- Fresh invitation receipt: run `29591716380`, artifact `8411326331`,
  invitation `9679ce07-ac35-4b29-b007-461e0b418801`

The installed Mac build contains the completion source plus the Mac-only
Spotify-duration and audio-default corrections in PRs #33 and #34. The current
Apple-VALID TestFlight build remains compatible and comes from PR #31; the two
new provider corrections execute on the Mac host and do not require a new iOS
binary.

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

- Full current-head target-isolated Swift run: 480 app tests with two intentional skips and
  zero failures on the clean rerun, plus 219 core tests with zero failures.
- Release Mac build passed. Existing Swift 6 migration/deprecation warnings are
  non-fatal and should be retired separately.
- Complete native companion scheme: 7 unit tests plus 25 UI tests, zero
  failures on Simulator `OB1 Widget Proof iPhone 16`, iOS 26.5.
  Result bundle:
  `/tmp/CodeIsland-final-full-20260717-2223.xcresult`.
- A first aggregate run found an XCTest accessibility-shape assumption in the
  hub module helper. The focused Home/Work/Code matrix passed after the helper
  was hardened, followed by the clean 25-test UI aggregate. This is not being
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
   install or update CodeIsland Buddy to `1.0.0 (20260718053347)`. The tester is
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
