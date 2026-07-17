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
| Auto, Home, Work, Code modes | Missing | Missing | Mode resolver tests plus native mode-switch and auto-switch runtime evidence |
| Now Playing, queue, lyrics, controls | Partial: Music/Spotify metadata and controls | Partial: mirrored controls | Real Apple Music and Spotify playback plus remaining queue/lyrics tests |
| Shelf, clipboard history, file handoff | Partial: guarded local clipboard history/copy/remove | Partial: remote copy/remove | Persist/re-copy plus remaining file drop/download/open tests across Mac and iPhone |
| Calendar list/month, CRUD, Join | Partial: next event and trusted Join | Missing | Permission, list/month, add/edit/delete, link editing, and Join tests |
| Tasks/lists/due dates/reorder/archive | Partial: selected lists, add, complete | Missing | Real list selection and full mutation tests on both platforms |
| Notes/jot/categories/checklists/merge | Partial: persistent add/copy/delete | Partial: remote add/copy/delete | Append, edit, undo, merge, and conflict tests |
| System CPU/memory/load | Ready: host load/memory/disk/thermal/uptime | Ready: mirrored readings and refresh | Runtime accuracy and remote refresh tests |
| Weather | Ready on Mac with ZIP fallback | Missing | iPhone local/remote refresh and offline-state tests |
| Notifications | Partial: CodeIsland alerts only | Partial: approval pushes only | Permission and delivery tests for every supported alert class |
| Claude co-pilot/voice/proposals | Missing | Missing | Ask and Do proposal confirmation, structured mutations, voice, and cancellation tests |
| AI Coding sessions/approvals/questions | Ready | Partial: approvals and nearby session state | Tailscale session/question parity and physical-iPhone decision tests |
| GitHub pull requests and CI | Missing | Missing | Authenticated PR list/status/open tests |
| Audio device switcher | Partial: enumerate/defaults/open Settings | Partial: mirrored devices/open Settings | Switch, volume, and failure-state tests |
| Bluetooth devices/connect/disconnect | Partial: battery readings | Partial: mirrored readings nearby | Host action and remote action tests |
| Battery health | Partial: Mac/accessory percentages and charge state | Partial: mirrored readings | Cycle/condition health plus accessory detail tests |
| Quick toggles | Partial: confirmed Lock Mac | Partial: confirmed remote Lock Mac | Additional allow-listed state/action tests |
| Active Downloads | Ready on Mac | Partial: nearby summary only | Remote list/progress/open/download tests over Tailscale |
| Camera pre-check | Missing | Missing | Permission, preview, mic/camera selection, and failure tests |
| Teleprompter/present mode | Missing | Missing | Local and remote presentation, speed, visibility, and resume tests |
| Window snapping/remote window actions | Missing | Missing | Accessibility permission and allow-listed action tests |
| Private web fallback | Partial: approvals only | Partial: approvals only | Responsive module/action parity tests |
| TestFlight distribution | Missing | Missing | Signed archive, App Store Connect processing, install, launch, and receipt evidence |

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
