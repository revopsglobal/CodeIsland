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
| Auto, Home, Work, Code modes | Partial: shared catalog, manual selection, and automatic context; each mode's rack is hard-coded and cannot be pinned or reordered | Partial: shared modes and remote selection mirror the same fixed racks | Implement saved per-mode pin/order customization; then capture native automatic-switch and persistence evidence |
| Now Playing, queue, lyrics, controls | Partial: Music/Spotify metadata, progress, lyrics, ±15-second seek and transport controls; Music queue/play-from-queue; no album art, arbitrary scrubber, visualizer, or floating music circles | Partial: the implemented host controls are mirrored, but the missing visual/scrub behavior is also absent | Implement the missing visual/scrub behavior, then test real Apple Music and Spotify playback; Spotify does not expose queue data through macOS automation |
| Shelf, clipboard history, file handoff | Partial: guarded clipboard/file history, reveal, copy, and remove; no drag/drop ingest, automatic screenshot Shelf, selection capture, or screen recording | Partial: authenticated file download/share plus copy/remove; it mirrors only the implemented subset | Implement Crest's capture/drop flows, then run a Mac/iPhone/web file round trip; keep the 100 MB private-transfer cap |
| Calendar two-week agenda, CRUD, Join | Partial: two-week agenda, add/edit/delete, trusted Join, and stable signed TCC identity; no Calendar month surface | Partial: agenda, add/edit/delete, and trusted Join; no month surface | Implement the shared month surface; verify real events, mutations, and one-click Join after TCC access |
| Tasks/lists/due dates/reorder/archive | Unverified: list create/delete/filter, due dates, add, complete, reorder, archive/restore, and delete | Unverified: same list and task actions with explicit list selection | Grant Reminders once and run real list/task/reorder/archive mutations |
| Notes/jot/categories/checklists/merge | Unverified: persistent add/copy/delete/edit/append, categories, checklist toggles, 20-step undo, and revision-safe replacement | Unverified: same editors/actions with stale-revision rejection | Runtime add/edit/conflict/checklist/undo round trip across Mac and iPhone |
| System CPU/memory/load | Ready: host load/memory/disk/thermal/uptime | Ready: mirrored readings and refresh through an authenticated, exact-confirmation host action | Compare readings with Activity Monitor on the physical Mac/iPhone pair |
| Weather | Unverified: WeatherKit/location with manual ZIP fallback | Unverified: mirrored remote weather and refresh | Permission, remote refresh, and offline-state runtime tests |
| Notifications | Missing Crest parity: CodeIsland shows only its own approval/question alerts and does not mirror recent macOS app notifications | Partial personal extension: approval pushes, Live Activity, and Dynamic Island UI are implemented | Implement the Mac notification mirror separately; physical-iPhone permission, token, delivery, and Live Activity tests remain required for the personal extension |
| Claude co-pilot/voice/proposals | Partial: read-only Ask plus typed Do proposals through authenticated local Claude Code, with tools disabled; no Mac speech recognition, continuous listening/mic indicator, file context, or screen-share-hidden covert strip | Partial: Ask/Do, iPhone speech recognition, proposal review, and a second exact confirmation; no file-context workflow | Implement the missing Mac voice/covert/context behavior; then run real Ask and multi-action Do plus physical-iPhone dictation/task creation |
| AI Coding sessions/approvals/questions | Ready: sessions, questions, approvals, and exact-confirmation actions | Partial: real-listener pairing/auth/approval/question/replay protection is automated; physical native/Tailscale use is unverified | Physical-iPhone approval/question/action tests away from the Mac |
| GitHub pull requests and CI | Ready: authenticated `gh` PR list/status/deep links | Ready: mirrored list/status/deep links | Runtime refresh/open test from iPhone |
| Audio device switcher | Unverified: enumerate/default input/output, switch, mute, and exact 0–100 output volume | Unverified: mirrored device actions, ±10, and native/web volume editor | Physical device switch, volume update, and expected failure states |
| Bluetooth devices/connect/disconnect | Unverified: connected/remembered devices, battery, connect/disconnect | Unverified: mirrored devices and confirmed remote actions | Physical accessory connect/disconnect tests |
| Battery health | Ready: charge, cycles, health percentage, and condition | Ready: mirrored health and accessory readings | Runtime comparison with macOS System Information |
| Quick toggles | Unverified: dark/light, mute/unmute, display sleep, and Lock Mac | Unverified: exact-confirmation remote actions | Physical state/action tests, including expected permission failures |
| Active and recent Downloads | Ready: live progress, 12 recent completed files, Reveal, refresh, age filtering, and a 100 MB private-transfer cap | Ready implementation: paired devices can download/share eligible completed files and the web fallback preserves filenames; physical Tailscale transfer remains unverified | Physical iPhone and web file round trip over Tailscale, plus over-limit rejection |
| Camera and mic pre-check | Partial: opens Photo Booth; CodeIsland itself has no native camera preview, microphone meter, or input selector | Partial: private front-camera preview with permission/failure UI; no microphone meter or device selector | Implement a private native Mac preview plus input selection/meter and the matching iPhone mic check; then run physical permission/device tests |
| Teleprompter/present mode | Partial: persistent floating reader and font size; manual scrolling only, no play/pause or WPM pacing, and the window is not hidden from screen sharing | Partial: full-screen reader, play/pause, WPM, and font size | Implement Mac pacing and covert sharing behavior; then run Mac and physical-iPhone presentation/resume tests |
| Window snapping/remote window actions | Partial: allow-listed left/right/maximize via Accessibility; no drag-a-window-to-the-notch chooser | Partial: confirmed remote left/right/maximize | Implement the notch drag target/expanded layouts, then grant Accessibility and verify real windows |
| Quick jot and global task/note capture | Missing: no Control-Option-T todo jot or Control-Option-N note jot | Missing as a dedicated one-step surface; normal reviewed task/note creation exists | Implement one-step Mac capture with explicit landing list/note and undo; mirror the resulting state on iPhone |
| Media-key HUD and Crest ambient polish | Missing: no Crest-style brightness/volume HUD, album-art circles, or audio visualizer | Not applicable as direct iPhone controls; mirrored host state remains useful | Implement only the useful Mac ambient pieces Greg wants and capture multi-display/full-screen evidence |
| Custom dashboard/day-progress surface | Missing: no saved widget dashboard or day-progress header | Missing | Decide whether this remains useful after mode pinning; if retained, implement one shared configuration model |
| Private web fallback | Partial: responsive client plus live Tailscale root/401 proof and isolated real-listener pairing/auth/mode/action tests | Partial: authenticated Home/Work/Code, approval, question, push registration, exact-action and replay protection are automated | Physical Tailscale browser module/action/file round trip |
| TestFlight distribution | Ready: signed archive/upload pipeline and internal group | Unverified on the physical phone: build `1.0.0 (20260717120420)` is Apple `VALID` and available to the all-builds internal group; install pending | Install, launch, permissions, push, Live Activity, and receipt evidence on Greg's iPhone |

## Behavior-level correction

The table above deliberately distinguishes **module presence** from **Crest
behavior parity**. The previous ledger treated an advertised module and a few
actions as parity even when Crest's defining interaction was absent. That was
incorrect.

The correction is grounded in the supplied signed Crest 4.9.0 app and its
current product/changelog pages. Crest 4.9 includes per-mode pinning, album art
and a scrubber, screenshot/Shelf capture, quick jot, a month Calendar surface,
macOS notification mirroring, Mac speech/covert presentation, camera **and mic**
preflight, and drag-to-notch window layouts. Those are product behaviors, not
visual extras. Pomodoro remains the one explicit exclusion Greg requested.

CodeIsland's personal extensions—away approvals, exact-confirmation actions,
Downloads transfer, Tailscale, APNs, Live Activities, and Dynamic Island—are
valuable additions, but they do not erase a missing Crest behavior. The ledger
must show both dimensions independently.

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

The iOS Simulator suite includes
`CodeIslandCompanionUITests.testCompletedDownloadOpensNativeShareSheet`; the
full companion UI run passed 12 tests with zero failures on 2026-07-17. This is
native Simulator evidence, not physical-iPhone or cellular/Tailscale proof.

`CodeIslandCompanionUITests.testCameraActionOpensPrivateNativePreview` was then
added and passed separately, 1 test with zero failures. Its first targeted
execution visibly handled the real Simulator Camera permission alert; the
finalized targeted rerun proved the native full-screen preview surface and
dismissal. A later 13-test aggregate run reached seven passes—including
camera, Downloads, mode rendering, task creation, Claude Do, landscape, and a
layout test—before the Xcode 27 beta Simulator launcher stalled and was
interrupted. The remaining six results are test-runner `signal term`/`signal
kill` infrastructure failures, not product assertion failures. Do not relabel
that aggregate run as green.

## Current signed delivery receipts

These receipts were captured on 2026-07-17. They prove the automated delivery
surfaces, not the remaining physical-device interactions.

- macOS `1.0.36`: merged commit `6ad428e952fb200c51f68182471c38fe7c32e796`,
  Actions run `29578951355`, artifact `8406349680`, DMG SHA-256
  `7025c470ab22782f3ebc505ba9c358d97def778758b9955e374f906e675079fb`.
  The downloaded DMG passed `codesign --verify --deep --strict` directly from
  its mounted image, and that exact app is installed at
  `/Applications/CodeIsland.app` with team `44JG2Y95CH` and CDHash
  `e7749f3369d10cac87e6495843de22d683a5a425`.
- iOS `1.0.0 (20260717120420)`: merged commit
  `6ad428e952fb200c51f68182471c38fe7c32e796`, Actions run `29578952503`,
  signed IPA artifact `8406281069`. App Store Connect reported bundle
  `com.revopsglobal.codeisland.buddy` as `VALID`, audience
  `APP_STORE_ELIGIBLE`; internal group `CodeIsland Internal` has access to all
  builds.
- The installed Mac host answered both local and Tailscale `/health` with
  `running: true`; the Tailscale root returned the expected CSP/frame/referrer
  headers and unauthenticated Downloads-file access returned `401`.
- The installed app's designated requirement is stable across 1.0.35 and
  1.0.36 (bundle `com.codeisland.app`, the same Apple Development certificate
  and Team `44JG2Y95CH`). Its signed entitlements include Calendar and Apple
  Events automation. Unified logs show the real app requested full Calendar
  access on 2026-07-16 at 23:43:06, received EventKit result `3`, `error = 0`,
  completion `YES`, and immediately issued a Calendar event predicate. This is
  strong proof that the access request succeeded in that installed identity;
  it is not proof of the current visible event list after the 1.0.36 restart.
- APNs team, key ID, topic, and private-key path are configured on the Mac and
  the private key exists. The paired-device store still contains zero devices
  and therefore zero physical push tokens, so delivery cannot be exercised
  until Buddy is installed and paired on Greg's iPhone.

## Physical acceptance run

This is the remaining morning run. It cannot be completed by CI because it
requires Greg's physical iPhone, biometric/permission taps, real accessories,
and real Calendar/Reminders data.

1. On iPhone, install Apple's **TestFlight** app from the App Store. In
   TestFlight, install **CodeIsland Buddy** `1.0.0 (20260717120420)` from
   `CodeIsland Internal`. Install or enable Tailscale and confirm the phone is
   on Greg's tailnet.
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
