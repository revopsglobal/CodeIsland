# Crest and mobile parity ledger

CodeIsland's target is the useful Crest 4.9 product baseline plus Greg's
personal remote extensions. Pomodoro/focus timers are explicitly out of scope.
“Parity” means the capability is actionable on the
Mac and iPhone, with the private web app as a fallback. A visible placeholder or
an unsigned Simulator build does not count.

Sources used for the baseline:

- Crest 4.9.0 DMG supplied by Greg (`Crest-4.9.0.dmg`, bundle
  `com.zack40x.crest`, signed and notarized, version 4.9.0).
- <https://crestnotch.app/#modes>
- <https://crestnotch.app/changelog>

## Acceptance states

- **Ready**: implementation and focused tests exist on that platform.
- **Partial**: a useful subset exists, but the named capability is incomplete.
- **Missing**: no real implementation exists.
- **Unverified**: implementation exists but lacks the required runtime proof.

## Current baseline audit

| Capability | macOS | iPhone / away | Required completion proof |
| --- | --- | --- | --- |
| Auto, Home, Work, Code modes | Ready implementation: shared catalog, automatic/manual context, versioned per-mode pin/order persistence, drag editing, dashboard toggle, and local-day progress | Ready implementation: shared modes, native reorder/pin editing, dashboard, deep links, and confirmed remote persistence | Capture native automatic-switch, edit, restart, and cross-device persistence evidence |
| Now Playing, queue, lyrics, controls | Physical Spotify read proof on 1.0.43: `Sound of Horns`, progress `1:27`, duration `2:21`, artwork/provider metadata, and the disclosed queue limitation rendered correctly. Apple Music, transport, scrub, seek, and lyrics remain unverified | Ready implementation: artwork, scrubber, mirrored host controls, and exact-confirmation seek | Test Apple Music plus real transport/scrub/seek/lyrics on Mac and iPhone; Spotify does not expose queue data through macOS automation |
| Shelf, clipboard history, file handoff | Ready implementation: guarded clipboard/file history, drag/drop and picker ingest, forward-only automatic screenshot capture, user-selected still capture and recording, reveal/copy/remove, and private storage | Ready implementation: authenticated file download/share plus copy/remove and the same 100 MB/path-confinement rules | Run real Mac capture/drop plus iPhone/web file round trips and permission-denial cases |
| Calendar two-week agenda, CRUD, Join | Physical read proven: the signed Mac host returned Greg's real month, selected-day events, and `40 upcoming`; CRUD, recurrence, and Join remain unverified | Physical read proven through the paired iPhone; CRUD and trusted Join remain implementation-only | Run dedicated real event add/edit/delete, recurrence, and one-click Join acceptance |
| Tasks/lists/due dates/reorder/archive | Physical partial: a task created on iPhone appeared in Apple's real Mac Reminders store and was cleaned up; list/reorder/archive/restore remain unverified | Physical partial: New Task review, exact confirmation, host write, and store visibility are proven | Run a dedicated list plus reorder/complete/archive/restore/delete matrix |
| Notes/jot/categories/checklists/merge | Unverified: persistent add/copy/delete/edit/append, categories, checklist toggles, 20-step undo, and revision-safe replacement | Unverified: same editors/actions with stale-revision rejection | Runtime add/edit/conflict/checklist/undo round trip across Mac and iPhone |
| System CPU/memory/load | Ready: host load/memory/disk/thermal/uptime | Ready: mirrored readings and refresh through an authenticated, exact-confirmation host action | Compare readings with Activity Monitor on the physical Mac/iPhone pair |
| Weather | Physical ZIP fallback proven during the unlocked 1.0.41 run: `61° Clear · Ridgefield, Washington`; Location Services mode remains unverified | Ready implementation: mirrored remote weather and refresh | Physical location-mode, remote refresh, and offline-state runtime tests |
| Notifications | Partial by deliberate platform boundary: CodeIsland action-required alerts are prioritized, deduped, redacted, and separated; macOS exposes no public cross-app Notification Center history API, so CodeIsland does not read private databases or request Full Disk Access | Physical replacement-build proof: production APNs and ActivityKit push-to-start tokens reached the paired Mac; pending and resolved background pushes each woke the client for authenticated refresh at `06:23:23Z` and `06:25:17Z`. No update token or unlocked visual proof was captured | Prove visible Live Activity/Dynamic Island, per-activity update/end, and stale-push behavior |
| Claude co-pilot/voice/proposals | Ready implementation: read-only Ask and reviewed Do through authenticated local Claude Code with tools disabled, push-to-talk/continuous speech, visible listening state, bounded user-selected/drop file context, and best-effort screen-share-hidden strip with honest disclosure | Ready implementation: Ask/Do, speech recognition, proposal review, exact confirmation, and deep-linked task/note preparation | Run real Ask and multi-action Do, Mac voice/file context, and physical-iPhone dictation/task creation |
| AI Coding sessions/approvals/questions | Physical final-build proof: installed 1.0.43 rendered five authenticated sessions, `3 running · no decisions waiting`, with no discovery/loading substitution; decisions-first attention, questions, approvals, exact-confirmation actions, and audited continuation remain implemented | Physical partial on final build `20260718053347`: authenticated heartbeat plus production APNs and ActivityKit push-to-start registration prove install/open and pairing; a pending/resolved background APNs probe woke authenticated refresh twice. Three earlier real approval decisions and one audited question answer remain proven; replacement Sessions rendering, Live Activity, replay, and cellular use still need final physical proof | Unlock the iPhone surface, verify authenticated Sessions and stability, then run replay plus Live Activity and cellular/Tailscale action tests away from the Mac |
| GitHub pull requests and CI | Ready: authenticated `gh` PR list/status/deep links | Ready: mirrored list/status/deep links | Runtime refresh/open test from iPhone |
| Audio device switcher | Physical read proof on 1.0.43: only MacBook Air Microphone and MacBook Air Speakers carry the respective default flags; the remaining real and virtual devices no longer show false defaults. Switching, mute, and exact 0–100 output volume remain physically unverified | Unverified: mirrored device actions, ±10, and native/web volume editor | Run physical device switch, volume update, and expected failure states |
| Bluetooth devices/connect/disconnect | Unverified: connected/remembered devices, battery, connect/disconnect | Unverified: mirrored devices and confirmed remote actions | Physical accessory connect/disconnect tests |
| Battery health | Ready: charge, cycles, health percentage, and condition | Ready: mirrored health and accessory readings | Runtime comparison with macOS System Information |
| Quick toggles | Unverified: dark/light, mute/unmute, display sleep, and Lock Mac | Unverified: exact-confirmation remote actions | Physical state/action tests, including expected permission failures |
| Active and recent Downloads | Ready: live progress, 12 recent completed files, Reveal, refresh, age filtering, and a 100 MB private-transfer cap | Ready implementation: paired devices can download/share eligible completed files and the web fallback preserves filenames; physical Tailscale transfer remains unverified | Physical iPhone and web file round trip over Tailscale, plus over-limit rejection |
| Camera and mic pre-check | Ready implementation: local-only native AVFoundation camera preview, camera/microphone selectors, normalized RMS/peak meter, interruption/disconnect handling, and no media transmission | Ready implementation: private camera preview, microphone health/meter, permission/failure UI, and background cleanup | Run physical permission, device-switch, disconnect, and background tests on both devices |
| Teleprompter/present mode | Ready implementation: floating reader, play/pause, persisted 60–240 WPM pacing, persisted font size, resume/end/manual-scroll behavior, and best-effort sharing exclusion with an honest full-display warning | Ready implementation: full-screen reader, play/pause, WPM, and font size | Run Mac and physical-iPhone presentation/resume tests, including screen-sharing behavior |
| Window snapping/remote window actions | Ready implementation: Accessibility-backed left/right/maximize plus real-drag notch chooser with halves, thirds, quarters, correct-display targeting, hysteresis, cancel, and self-window exclusion | Ready useful remote implementation: confirmed left/right/maximize | Grant Accessibility and verify real windows across multiple displays; remote thirds/quarters are deliberately Mac drag interactions |
| Quick jot and global task/note capture | Ready implementation: Carbon Control-Option-T and Control-Option-N panels with explicit destination, Escape/Return behavior, save, and undo through existing mutation paths | Ready implementation: dedicated New Task/New Note entry points, deep links, review, and exact confirmation | Run global-hotkey, undo, and cross-device visibility acceptance with real data |
| Media-key HUD and Crest ambient polish | Ready supported implementation: short-lived notch HUD for CodeIsland media/volume/brightness actions, bounded artwork, progress, thermal/Reduce Motion-aware ambient bars | Ready useful mirror: artwork/progress and exact host controls; no need to mimic a Mac bezel HUD | Capture multi-display/full-screen evidence; macOS has no public API for intercepting all hardware brightness-key events |
| Custom dashboard/day-progress surface | Ready implementation: one shared saved dashboard toggle, per-mode rack configuration, and local-day progress header | Ready implementation: same configuration and day progress with native editing | Verify saved state and day rollover on the physical pair |
| Private web fallback | Ready automated implementation: responsive authenticated Home/Work/Code, approvals, questions, opaque push registration, exact actions, file transfer, retry/offline state, and replay protection | Ready as an iPhone browser fallback; physical Tailscale browser use is unverified | Physical Tailscale browser module/action/file round trip |
| TestFlight distribution | Ready: signed archive/upload pipeline, source plus compiled App Intent metadata validation, internal group, 60-minute Apple indexing window, and always-preserved IPA artifact | Physical partial: final build `1.0.0 (20260718053347)` is installed/opened, paired, and registered production APNs plus ActivityKit push-to-start tokens. Apple reports it `VALID` and available to `CodeIsland Internal` | Visually confirm connected Sessions and stability, then prove background push/Live Activity on Greg's iPhone |

## Behavior-level completion adjudication

The table distinguishes **implementation**, **automated proof**, and **physical
acceptance**. Crest's defining behaviors are represented rather than inferred
from module names: saved mode pin/order, artwork and arbitrary scrub, Shelf
capture/drop, global quick jot, Calendar month navigation, a supported
notification boundary, Mac speech/file context, camera and microphone
preflight, paced teleprompter, and drag-to-notch layouts.

Pomodoro remains the explicit exclusion Greg requested. Cross-app macOS
Notification Center history is the other non-parity item, but for a different
reason: Apple exposes no public API for it. CodeIsland shows that limitation
instead of reading private databases or requesting Full Disk Access. Spotify
queue enumeration and universal hardware brightness-key interception have
similar provider/API limits and are disclosed at the affected surface.

CodeIsland's personal extensions—away approvals and questions, exact-confirmation
actions, Downloads/Shelf transfer, Tailscale, APNs, Live Activities, Dynamic
Island, App Intents, and web fallback—are evaluated separately. Their automated
contracts are green; the installed physical iPhone has now proved pairing,
foreground stability, authenticated polling, three approval decisions, one
question continuation, one Reminders add/store/cleanup round trip, and real
Calendar read access. Cellular, background push/Live Activity, replay, and the
remaining TCC-backed mutations remain distinct gates.

## Architecture invariant

`CodeIslandCore.PersonalHubCatalog` is the shared catalog. Every personal baseline
module must advertise Mac, iPhone, and web support. Platform implementations may
use different providers—EventKit locally on iPhone and host RPC for Mac-only
state—but they must publish the same snapshot and action contracts.

Remote writes are never generic shell commands. The Mac exposes an allow-listed
module action, binds a short-lived token to the exact device, action, and target,
then revalidates current state before executing it. Telegram may notify Greg and
link into the private client; it is not a second state store or inbound control
daemon.

## Automated host E2E proof

`RemoteApprovalHTTPServerTests.testAuthenticatedHostLifecycleOverRealListener`
starts the real loopback listener with isolated device/audit storage and proves:

- security headers and unauthenticated API rejection;
- invalid-code rejection followed by six-digit pairing and bearer authentication;
- authenticated Home, Work, and Code snapshots from the shared catalog;
- a real `AppState` approval continuation, exact decision, audit receipt, and replay rejection;
- a real `AskUserQuestion` continuation, answer delivery, and replay rejection;
- reviewed action prepare/execute, altered-intent rejection, single-use enforcement; and
- production push-token registration without touching Greg's real paired-device store.

`RemoteApprovalHTTPServerTests.testAuthenticatedRecentDownloadTransfersToPairedDevice`
uses an isolated Downloads directory and the real listener to prove:

- recent completed files appear in the authenticated Work snapshot;
- unauthenticated transfer is rejected;
- a paired device receives the exact bytes and original filename; and
- over-limit files are not advertised for transfer and are rejected; and
- an encoded path outside Downloads is rejected.

Current automated completion evidence on 2026-07-17:

- target-isolated `swift test`: `CodeIslandTests` passed **480** tests with two intentional
  skips and zero failures on the clean rerun; `CodeIslandCoreTests` passed **219** tests with zero
  failures. This includes the real loopback listener, configuration restart,
  APNs envelope/privacy, push-token rotation, Live Activity lifecycle, media,
  Shelf, Calendar, camera/mic, Claude voice/context, teleprompter, quick jot,
  and drag-to-notch reducers.
- `swift build -c release` passed. The compiler emitted existing Swift 6
  migration/deprecation warnings, but no release-build error.
- The complete `CodeIslandCompanion` Xcode scheme passed **7 unit tests and
  25 UI tests** with zero failures on Simulator `OB1 Widget Proof iPhone 16`,
  iOS 26.5. Result bundle:
  `/tmp/CodeIsland-final-full-20260717-2223.xcresult`.
  It covers native mode/module rendering, rack reorder review, Calendar month,
  Now Playing seek, task/note creation, Claude Do, Downloads and Shelf share,
  camera preview, deep links, landscape board, pairing recovery, and Live
  Activity automatic resolution.
- The first full iOS attempt found a harness-only accessibility-shape failure
  in `testPersonalHubModesRenderAdvertisedModules`: XCTest sometimes exposed
  the hub surface but not the parent as a typed `ScrollView` after relaunch.
  The helper now uses the companion scroll, hub surface, or application gesture
  target in order. The focused three-mode rerun passed, followed by the clean
  25-test UI aggregate above.

The Simulator emitted a 128-byte ActivityKit push-to-start token and accepted
the privacy-redacted start fixture as a notification. `simctl push` did not
supply the required `liveactivity` APNs headers, so Dynamic Island creation is
still deliberately classified as physical-device/APNs proof, not Simulator
proof.

These test results are native Simulator evidence. Physical-iPhone proof is
recorded separately below; cellular/Tailscale acceptance is still pending.

## Current signed delivery receipts

These receipts were captured on 2026-07-17. They prove the automated delivery
surfaces, not the remaining physical-device interactions.

- macOS `1.0.43`: source commit `265cc544d20a7144c3cfe1cd340a2f10748ab267`,
  Actions run `29633277978`, artifact `8426279211`, DMG SHA-256
  `e0369fbfd51c939b6b8e8e8afe7fa91a447e64a825b638a9885ec3c40a219b20`.
  The downloaded DMG passed `codesign --verify --deep --strict` directly from
  its mounted image, and that exact app is installed at
  `/Applications/CodeIsland.app` with team `44JG2Y95CH` and CDHash
  `78ef64fc758f0bebed52066a88eaf80c9bbad9dd`. The prior 1.0.41 app is
  preserved at
  `/Users/gregharned/Downloads/CodeIsland-app-backups/CodeIsland-1.0.41-pre-1.0.43.app`.
  This build includes PR #33's Spotify duration-unit correction and PR #34's
  real input/output default-device parsing. The focused regressions and full
  480/219 Swift suites passed. Local and Tailscale health passed after install.
  Final visual inspection then confirmed Spotify `1:27 2:21`, the single real
  default input/output labels, and five authenticated Code sessions without a
  discovery/loading substitution.
- iOS `1.0.0 (20260718053347)`: merged commit
  `61310ee2d20c651221ee6ef9a3ef823bb7bb0558`, Actions run `29632459018`,
  signed IPA artifact `8425978534`, delivery UUID
  `835af987-3aef-4cc9-82d4-8d88ec0684f1`. App Store Connect reported `VALID`,
  audience `APP_STORE_ELIGIBLE`, and all-builds group `CodeIsland Internal` has
  access. Tester receipt `8425940062` records `gregharned@gmail.com` as
  `ready`. Independent inspection confirmed the production APNs entitlement,
  `NSSupportsLiveActivities = true`, and valid app/widget signatures. The
  physical iPhone then authenticated and registered the PR #31-only
  ActivityKit push-to-start token, proving installation/open; visual and
  background acceptance remain pending.
- iOS `1.0.0 (20260718031753)`: merged commit
  `96c1a74bca0c851dcaf1ef91248cc9751c136816`, Actions run `29628559171`,
  signed IPA artifact `8424725763`. App Store Connect reported bundle
  `com.revopsglobal.codeisland.buddy` as `VALID`, audience
  `APP_STORE_ELIGIBLE`; internal group `CodeIsland Internal` has access to all
  builds, and tester receipt artifact `8424682761` records
  `gregharned@gmail.com` as `ready`. This exact build is installed and paired
  on Greg's physical iPhone; three approval decisions and foreground stability
  are recorded in the physical evidence receipt. The signed archive's
  strict signature verification passed for both app and widget under Team
  `44JG2Y95CH`, and compiled App Intent metadata passed the `ITMS-90626` guard.
- App Store Connect tester repair run `29591716380` verified
  `gregharned@gmail.com` as an `ACCOUNT_HOLDER,ADMIN` user with all-app access,
  enrolled tester `4510ab81-87ea-4967-bde4-47d3f2e083af` in
  `CodeIsland Internal`, and explicitly sent invitation
  `9679ce07-ac35-4b29-b007-461e0b418801`. Receipt artifact `8411326331` records
  state `ready` at 2026-07-17T15:20:54Z.
- The installed Mac host answered both local and Tailscale `/health` with
  `running: true`; the Tailscale root returned the expected CSP/frame/referrer
  headers and unauthenticated Downloads-file access returned `401`.
- The installed app's designated requirement is stable across the preserved
  1.0.41 and installed 1.0.43 (bundle `com.codeisland.app`, the same Apple
  Development certificate and Team `44JG2Y95CH`). Its signed entitlements
  include Calendar and Apple Events automation. Unified logs show the real app
  requested full Calendar access on 2026-07-16 at 23:43:06, received EventKit
  result `3`, `error = 0`, completion `YES`, and immediately issued a Calendar
  event predicate. The unlocked 1.0.41 run subsequently rendered the real six-week
  month, selected-day events, and `40 upcoming`, so current Calendar read
  access is physically proven on the Mac.
- APNs team, key ID, topic, and private-key path are configured on the Mac and
  the private key exists. The paired-device store contains Greg's physical
  iPhone with a production push token and continuing authenticated heartbeats.
  Token registration is proven; background delivery and resolved cleanup are
  not yet physically proven.

## Physical acceptance run

This run is partially complete. CI cannot finish the remaining items because
they require Greg's physical iPhone, biometric/permission taps, real
accessories, and real Calendar/Reminders data. Exact completed proof is in
`docs/evidence/2026-07-17-crest-mobile-physical-acceptance.md`.

1. On iPhone, open Apple's **TestFlight** app while signed in as
   `gregharned@gmail.com`, refresh, and install the newest **CodeIsland Buddy**
   build from `CodeIsland Internal`. The tester is already enrolled; this
   private internal build does not require public App Store review. Tailscale
   must remain enabled on Greg's tailnet.
2. Unlock the Mac and open CodeIsland Settings. Use the app's permission
   buttons, then approve CodeIsland in System Settings under Calendars,
   Reminders, Location Services, Camera, and Accessibility as each test needs.
3. Pairing and authenticated foreground polling are already proven. Confirm
   Home, Work, and Code on the newest build over Wi-Fi, then repeat over
   cellular with Tailscale enabled.
4. Real physical approvals are already proven. Trigger a real question on the
   Mac. Confirm the
   iPhone receives the push, the Live Activity/Dynamic Island surface appears,
   approval/answer resumes only the selected request, and replay is rejected.
5. Create a dedicated test reminder list; add, reorder, complete, archive,
   restore, and delete a task from iPhone. Confirm the same state on Mac.
6. Create, edit, and delete a dedicated calendar event. Include a Zoom or Meet
   URL and verify one-click **Join** from both Mac and iPhone.
7. Run Claude Ask, then a multi-action Claude Do proposal that creates a task.
   Review the proposal and confirm it once; verify the write and audit receipt.
   Repeat once with iPhone dictation after granting microphone and speech access.
8. Exercise the remaining Crest baseline against real data: Apple Music and
   Spotify playback controls; Shelf file round trip; clipboard copy/remove;
   notes/checklists/undo; weather ZIP and location modes; GitHub PR deep link;
   audio output/input and volume; Bluetooth connect/disconnect and battery;
   downloads (including a completed file below 100 MB and an over-limit file);
   dark mode/mute/display sleep; camera preview; teleprompter; and
   Accessibility-backed window snapping.
9. Leave the Mac host running and connected, lock it, move the iPhone off local
   Wi-Fi, and repeat one approval, one task creation, and one Calendar read over
   cellular/Tailscale. This is the final away-from-the-Mac acceptance gate.

Record failures by exact module/action and keep permission denial separate from
implementation failure. Telegram is only an optional outbound alert/deep link;
it is not required for the private Tailscale control path to pass.
