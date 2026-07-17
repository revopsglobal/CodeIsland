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
| Auto, Home, Work, Code modes | Ready: shared catalog, manual selection, and automatic context | Ready: shared modes and remote selection | Native runtime evidence for automatic switching |
| Now Playing, queue, lyrics, controls | Unverified: Music/Spotify metadata, progress, lyrics, seek and transport controls; Music queue/play-from-queue | Unverified: every advertised control is mirrored through reviewed host actions | Real Apple Music and Spotify playback; artwork remains a visual enhancement and Spotify does not expose queue data through macOS automation |
| Shelf, clipboard history, file handoff | Unverified: guarded clipboard history, file capture, reveal, copy, and remove | Unverified: authenticated file download/share plus copy/remove | Runtime file round trip across Mac, iPhone, and web; 100 MB cap is enforced |
| Calendar two-week agenda, CRUD, Join | Unverified: two-week agenda, add/edit/delete, trusted Join, and stable signed TCC identity | Unverified: agenda, add/edit/delete, and trusted Join | Grant Calendar once to the newly signed app and verify real events and mutations |
| Tasks/lists/due dates/reorder/archive | Unverified: list create/delete/filter, due dates, add, complete, reorder, archive/restore, and delete | Unverified: same list and task actions with explicit list selection | Grant Reminders once and run real list/task/reorder/archive mutations |
| Notes/jot/categories/checklists/merge | Unverified: persistent add/copy/delete/edit/append, categories, checklist toggles, 20-step undo, and revision-safe replacement | Unverified: same editors/actions with stale-revision rejection | Runtime add/edit/conflict/checklist/undo round trip across Mac and iPhone |
| System CPU/memory/load | Ready: host load/memory/disk/thermal/uptime | Ready: mirrored readings and refresh through an authenticated, exact-confirmation host action | Compare readings with Activity Monitor on the physical Mac/iPhone pair |
| Weather | Unverified: WeatherKit/location with manual ZIP fallback | Unverified: mirrored remote weather and refresh | Permission, remote refresh, and offline-state runtime tests |
| Notifications | Partial: CodeIsland alerts, APNs provider, and time-sensitive entitlement | Partial: approval pushes, Live Activity, and Dynamic Island UI | Physical-iPhone permission, token, delivery, and Live Activity tests |
| Claude co-pilot/voice/proposals | Unverified: read-only Ask plus typed Do proposals through authenticated local Claude Code, with tools disabled | Unverified: Ask/Do, iPhone speech recognition, proposal review, and a second exact confirmation | Real Claude Ask and multi-action Do run; physical-iPhone microphone/speech permission and task creation |
| AI Coding sessions/approvals/questions | Ready: sessions, questions, approvals, and exact-confirmation actions | Partial: real-listener pairing/auth/approval/question/replay protection is automated; physical native/Tailscale use is unverified | Physical-iPhone approval/question/action tests away from the Mac |
| GitHub pull requests and CI | Ready: authenticated `gh` PR list/status/deep links | Ready: mirrored list/status/deep links | Runtime refresh/open test from iPhone |
| Audio device switcher | Unverified: enumerate/default input/output, switch, mute, and exact 0–100 output volume | Unverified: mirrored device actions, ±10, and native/web volume editor | Physical device switch, volume update, and expected failure states |
| Bluetooth devices/connect/disconnect | Unverified: connected/remembered devices, battery, connect/disconnect | Unverified: mirrored devices and confirmed remote actions | Physical accessory connect/disconnect tests |
| Battery health | Ready: charge, cycles, health percentage, and condition | Ready: mirrored health and accessory readings | Runtime comparison with macOS System Information |
| Quick toggles | Unverified: dark/light, mute/unmute, display sleep, and Lock Mac | Unverified: exact-confirmation remote actions | Physical state/action tests, including expected permission failures |
| Active Downloads | Ready on Mac | Partial: nearby summary only | Remote list/progress/open/download tests over Tailscale |
| Camera pre-check | Partial: opens Photo Booth | Unverified: private front-camera preview with permission/failure UI | Physical camera permission/preview test; mic and camera selection remain |
| Teleprompter/present mode | Unverified: persistent floating reader, play/pause, WPM, and font size | Unverified: full-screen reader, play/pause, WPM, and font size | Mac and physical-iPhone presentation/resume tests |
| Window snapping/remote window actions | Unverified: allow-listed left/right/maximize via Accessibility | Unverified: confirmed remote left/right/maximize | Grant Accessibility and verify real windows |
| Private web fallback | Partial: responsive client plus live Tailscale root/401 proof and isolated real-listener pairing/auth/mode/action tests | Partial: authenticated Home/Work/Code, approval, question, push registration, exact-action and replay protection are automated | Physical Tailscale browser module/action/file round trip |
| TestFlight distribution | Ready: signed archive/upload pipeline and internal group | Unverified on the physical phone: build `1.0.0 (20260717113810)` is Apple `VALID` and available to the all-builds internal group; install pending | Install, launch, permissions, push, Live Activity, and receipt evidence on Greg's iPhone |

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

## Current signed delivery receipts

These receipts were captured on 2026-07-17. They prove the automated delivery
surfaces, not the remaining physical-device interactions.

- macOS `1.0.35`: merged commit `0337d0e7d4ee4dcc408d2feb53fb2c2c5f7a5bed`,
  Actions run `29576716261`, artifact `8405419352`, DMG SHA-256
  `59cf43805024991400b0cffc8a290b8c6ffc2402ef334ed1e6aabe58681f8d39`.
  The downloaded DMG passed `codesign --verify --deep --strict` directly from
  its mounted image, and that exact app is installed at
  `/Applications/CodeIsland.app` with team `44JG2Y95CH`.
- iOS `1.0.0 (20260717113810)`: merged commit
  `08b8e6ec69759a6294c3c9e46417b0d4a60ce266`, Actions run `29577487124`,
  signed IPA artifact `8405674273`. App Store Connect reported bundle
  `com.revopsglobal.codeisland.buddy` as `VALID`, audience
  `APP_STORE_ELIGIBLE`; internal group `CodeIsland Internal` has access to all
  builds.
- The installed Mac host answered both local and Tailscale `/health` with
  `running: true`; the Tailscale root returned the expected CSP/frame/referrer
  headers and unauthenticated `/api/hub` access returned `401`.

## Physical acceptance run

This is the remaining morning run. It cannot be completed by CI because it
requires Greg's physical iPhone, biometric/permission taps, real accessories,
and real Calendar/Reminders data.

1. On iPhone, install Apple's **TestFlight** app from the App Store. In
   TestFlight, install **CodeIsland Buddy** `1.0.0 (20260717113810)` from
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
   downloads; dark mode/mute/display sleep; camera preview; teleprompter; and
   Accessibility-backed window snapping.
9. Leave the Mac host running and connected, lock it, move the iPhone off local
   Wi-Fi, and repeat one approval, one task creation, and one Calendar read over
   cellular/Tailscale. This is the final away-from-the-Mac acceptance gate.

Record failures by exact module/action and keep permission denial separate from
implementation failure. Telegram is only an optional outbound alert/deep link;
it is not required for the private Tailscale control path to pass.
