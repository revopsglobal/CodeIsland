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
| TestFlight distribution | Ready: signed archive/upload pipeline and internal group | Unverified: build processing/group access proven; physical install pending | Install, launch, permissions, push, Live Activity, and receipt evidence on Greg's iPhone |

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
