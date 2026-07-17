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
| Now Playing, queue, lyrics, controls | Ready implementation within public provider limits: bounded artwork, arbitrary scrubber, progress, lyrics, transport, ±15-second seek, Music queue, and low-cost notch media/HUD treatment | Ready implementation: artwork, scrubber, mirrored host controls, and exact-confirmation seek | Test real Apple Music and Spotify playback; Spotify does not expose queue data through macOS automation |
| Shelf, clipboard history, file handoff | Ready implementation: guarded clipboard/file history, drag/drop and picker ingest, forward-only automatic screenshot capture, user-selected still capture and recording, reveal/copy/remove, and private storage | Ready implementation: authenticated file download/share plus copy/remove and the same 100 MB/path-confinement rules | Run real Mac capture/drop plus iPhone/web file round trips and permission-denial cases |
| Calendar two-week agenda, CRUD, Join | Ready implementation: six-week month, selected-day events, two-week agenda, add/edit/delete, recurrence-safe IDs, and trusted Join | Ready implementation: month navigation, selected-day events, agenda, CRUD, and trusted Join | Verify real events, mutations, recurrence, and one-click Join after TCC access |
| Tasks/lists/due dates/reorder/archive | Unverified: list create/delete/filter, due dates, add, complete, reorder, archive/restore, and delete | Unverified: same list and task actions with explicit list selection | Grant Reminders once and run real list/task/reorder/archive mutations |
| Notes/jot/categories/checklists/merge | Unverified: persistent add/copy/delete/edit/append, categories, checklist toggles, 20-step undo, and revision-safe replacement | Unverified: same editors/actions with stale-revision rejection | Runtime add/edit/conflict/checklist/undo round trip across Mac and iPhone |
| System CPU/memory/load | Ready: host load/memory/disk/thermal/uptime | Ready: mirrored readings and refresh through an authenticated, exact-confirmation host action | Compare readings with Activity Monitor on the physical Mac/iPhone pair |
| Weather | Unverified: WeatherKit/location with manual ZIP fallback | Unverified: mirrored remote weather and refresh | Permission, remote refresh, and offline-state runtime tests |
| Notifications | Partial by deliberate platform boundary: CodeIsland action-required alerts are prioritized, deduped, redacted, and separated; macOS exposes no public cross-app Notification Center history API, so CodeIsland does not read private databases or request Full Disk Access | Ready personal extension implementation: opaque APNs, pending/resolved routing, token rotation, authenticated detail refresh, Live Activity, and Dynamic Island lifecycle | Physical-iPhone permission, token, delivery, resolved cleanup, and stale-push tests; cross-app history remains unsupported unless Apple adds a public API |
| Claude co-pilot/voice/proposals | Ready implementation: read-only Ask and reviewed Do through authenticated local Claude Code with tools disabled, push-to-talk/continuous speech, visible listening state, bounded user-selected/drop file context, and best-effort screen-share-hidden strip with honest disclosure | Ready implementation: Ask/Do, speech recognition, proposal review, exact confirmation, and deep-linked task/note preparation | Run real Ask and multi-action Do, Mac voice/file context, and physical-iPhone dictation/task creation |
| AI Coding sessions/approvals/questions | Ready: sessions, decisions-first attention model, questions, approvals, exact-confirmation actions, and audited continuation | Ready implementation: real-listener pairing/auth/approval/question/replay protection, pending deep links, opaque push routing, Live Activity lifecycle, and away-use action surfaces; physical Tailscale use is unverified | Physical-iPhone approval/question/action tests away from the Mac |
| GitHub pull requests and CI | Ready: authenticated `gh` PR list/status/deep links | Ready: mirrored list/status/deep links | Runtime refresh/open test from iPhone |
| Audio device switcher | Unverified: enumerate/default input/output, switch, mute, and exact 0–100 output volume | Unverified: mirrored device actions, ±10, and native/web volume editor | Physical device switch, volume update, and expected failure states |
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
| TestFlight distribution | Ready: signed archive/upload pipeline and internal group | Ready for acceptance: build `1.0.0 (20260717120420)` is Apple `VALID`; `gregharned@gmail.com` is enrolled in the all-builds internal group and Apple explicitly resent invitation `9679ce07-ac35-4b29-b007-461e0b418801`; physical install remains unverified | Accept the fresh invitation, then install, launch, grant permissions, pair, and prove push/Live Activity on Greg's iPhone |

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
contracts are green; physical iPhone/cellular/TCC proof remains a distinct gate.

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

- `swift test`: `CodeIslandTests` passed **472** tests with two intentional
  skips and zero failures; `CodeIslandCoreTests` passed **218** tests with zero
  failures. This includes the real loopback listener, configuration restart,
  APNs envelope/privacy, push-token rotation, Live Activity lifecycle, media,
  Shelf, Calendar, camera/mic, Claude voice/context, teleprompter, quick jot,
  and drag-to-notch reducers.
- `swift build -c release` passed. The compiler emitted existing Swift 6
  migration/deprecation warnings, but no release-build error.
- The complete `CodeIslandCompanion` Xcode scheme passed **24/24** tests with
  zero failures and zero skips on isolated Simulator
  `codex-CodeIsland-Shelf`, iPhone 17 Pro, iOS 27.0. Result bundle:
  `ios/CodeIslandCompanion/.build/Task13DerivedData/Logs/Test/Test-CodeIslandCompanion-2026.07.17_14-16-45--0700.xcresult`.
  It covers native mode/module rendering, rack reorder review, Calendar month,
  Now Playing seek, task/note creation, Claude Do, Downloads and Shelf share,
  camera preview, deep links, landscape board, pairing recovery, and Live
  Activity automatic resolution.
- The first full iOS attempt found a harness-only accessibility-shape failure
  in `testPersonalHubModesRenderAdvertisedModules`: XCTest sometimes exposed
  the hub surface but not the parent as a typed `ScrollView` after relaunch.
  The helper now uses the companion scroll, hub surface, or application gesture
  target in order. The focused three-mode rerun passed, followed by the clean
  24-test aggregate above.

This is native Simulator evidence, not physical-iPhone or cellular/Tailscale
proof.

## Current signed delivery receipts

These receipts were captured on 2026-07-17. They prove the automated delivery
surfaces, not the remaining physical-device interactions.

- macOS `1.0.39`: merged commit `2f7a6b1bb66e14baad870d45fd0767553f816968`,
  Actions run `29616108584`, artifact `8420619293`, DMG SHA-256
  `17d45d870aa8cb8267eeabd537026889b068784e2342fc3e724bae8cdff74041`.
  The downloaded DMG passed `codesign --verify --deep --strict` directly from
  its mounted image, and that exact app is installed at
  `/Applications/CodeIsland.app` with team `44JG2Y95CH` and CDHash
  `e0f24c10a72e631b05de10fef17d3a6c4ca57458`. The prior installed 1.0.38 app
  is preserved at `/Applications/CodeIsland-backup-1.0.38-20260717-1449.app`.
- iOS `1.0.0 (20260717120420)`: merged commit
  `6ad428e952fb200c51f68182471c38fe7c32e796`, Actions run `29578952503`,
  signed IPA artifact `8406281069`. App Store Connect reported bundle
  `com.revopsglobal.codeisland.buddy` as `VALID`, audience
  `APP_STORE_ELIGIBLE`; internal group `CodeIsland Internal` has access to all
  builds.
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
  1.0.38 and installed 1.0.39 (bundle `com.codeisland.app`, the same Apple
  Development certificate and Team `44JG2Y95CH`). Its signed entitlements
  include Calendar and Apple Events automation. Unified logs show the real app
  requested full Calendar access on 2026-07-16 at 23:43:06, received EventKit
  result `3`, `error = 0`, completion `YES`, and immediately issued a Calendar
  event predicate. This is strong proof that the access request succeeded in
  that installed identity; it is not proof of the current visible event list
  after the 1.0.39 restart.
- APNs team, key ID, topic, and private-key path are configured on the Mac and
  the private key exists. The paired-device store still contains zero devices
  and therefore zero physical push tokens, so delivery cannot be exercised
  until Buddy is installed and paired on Greg's iPhone.

## Physical acceptance run

This is the remaining morning run. It cannot be completed by CI because it
requires Greg's physical iPhone, biometric/permission taps, real accessories,
and real Calendar/Reminders data.

1. On iPhone, open the fresh Apple invitation sent to
   `gregharned@gmail.com`, accept it in Apple's **TestFlight** app, and install
   **CodeIsland Buddy** `1.0.0 (20260717120420)` from `CodeIsland Internal`.
   Install or enable Tailscale and confirm the phone is on Greg's tailnet.
2. Unlock the Mac and open CodeIsland Settings. Use the app's permission
   buttons, then approve CodeIsland in System Settings under Calendars,
   Reminders, Location Services, Camera, and Accessibility as each test needs.
3. Pair the iPhone from CodeIsland Settings using the displayed six-digit code.
   Confirm Home, Work, and Code load in Buddy over Wi-Fi, then repeat over
   cellular with Tailscale enabled.
4. Trigger a real coding approval and a real question on the Mac. Confirm the
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
