# Crest and Mobile Completion Design

**Date:** 2026-07-17

**Status:** Approved by Greg

**Product:** CodeIsland for Mac and CodeIsland Buddy for iPhone

## Outcome

CodeIsland will be Greg's private, single-user Mac utility and away-from-Mac
control surface. It will match the useful behavior of Crest 4.9.0, excluding
Pomodoro and Apple Watch, while adding true iPhone action parity for the things
that matter when Greg is away from the Mac.

Completion means all three delivery surfaces are real and consistent:

1. the signed Mac app is the authoritative host and local action executor;
2. the signed iPhone app can inspect and perform the useful host actions over
   Tailscale, including approvals and task capture; and
3. the responsive private web client provides the same core remote contract as
   a fallback.

A feature is not complete merely because a card, placeholder, Simulator view,
or CI build exists. It must have the action contract, focused automated proof,
and the appropriate native or physical-device acceptance evidence.

## Product boundaries

### In scope

- Crest 4.9 behavior parity for modes, media, Shelf/capture, Calendar,
  notifications, Claude, camera/microphone preflight, teleprompter, quick jot,
  window layouts, and useful notch polish.
- Remote CodeIsland/Codex/Claude sessions, approvals, questions, reviewed
  actions, task and note capture, Calendar/Reminders, files, and utility state.
- Native iPhone editors, share flows, App Intents, push notifications, Live
  Activities, and Dynamic Island status where they improve away use.
- A Tailscale web fallback plus native Buddy push notifications and Live Activities.
- The lowest practical ongoing cost using Greg's existing Apple Developer
  account, GitHub Actions, Mac, and Tailscale.

### Explicitly out of scope

- Pomodoro/focus timers.
- Apple Watch.
- A multi-tenant service or scale-oriented backend.
- A generic remote shell.
- Any Telegram integration, bot, task store, or daemon.
- Remote camera streaming. Camera preview remains private and local to the
  device using it; remote surfaces expose permission/device health only.
- Spotify queue control, because the Spotify macOS automation interface does
  not provide the queue. Playback metadata and exposed controls remain in
  scope.

## Architecture

### One host, one contract

`/Applications/CodeIsland.app` is the sole state and action host. It observes
local sessions and utilities, publishes snapshots from the shared personal-hub
catalog, executes only allow-listed actions, and emits audit receipts.

CodeIsland Buddy is the primary away client. It connects to the Mac through
authenticated HTTPS over Greg's Tailscale tailnet. Nearby Bluetooth can assist
discovery or pairing but is not the away transport. The web client uses the
same listener, authentication, snapshots, confirmation flow, and audit model.

Buddy is the sole away-attention channel. APNs and Live Activities deep-link to
Buddy, which loads fresh state from the Mac and uses the normal confirmation
contract; the authenticated private web surface remains the fallback.

### Remote mutation safety

Remote writes are typed actions, never shell strings. A mutation follows this
sequence:

1. the paired client requests a proposal for one allow-listed action;
2. the host returns the exact action, current target, consequences, and a
   short-lived token bound to the device, action, target, and state revision;
3. the client confirms that exact proposal; and
4. the host revalidates state, consumes the token once, executes, and records
   the result.

Changed intent, changed target, expiration, device mismatch, and replay all
fail closed. Read-only refreshes do not require the second confirmation.

### Shared state and platform-specific presentation

`CodeIslandCore.PersonalHubCatalog` remains the shared capability catalog.
Snapshots and actions are platform-neutral. Mac, iPhone, and web may present
them differently, but an action advertised as remotely useful must remain
available and semantically identical across those surfaces.

Mobile parity means actionable data/control parity, not a literal recreation
of the Mac notch. Mac-only visual behaviors such as drag-to-notch window
layouts remain Mac features; Buddy exposes the resulting useful host actions.

## Completion batches

### 1. Delivery and physical access gate

- Make `gregharned@gmail.com` an eligible internal tester in the
  `CodeIsland Internal` group and prove that the current build is available in
  TestFlight.
- Keep signed Mac and iPhone builds reproducible through GitHub Actions.
- Pair the physical iPhone, register its push token, and verify Tailscale on
  Wi-Fi and cellular.

This gate is first because every later native feature needs a reliable way to
reach Greg's phone.

### 2. Shared configuration and creation flows

- Persist per-mode module pinning and ordering, plus a saved dashboard and
  day-progress header.
- Add global Mac quick-jot shortcuts for a task and a note with explicit
  destination, confirmation, and undo.
- Expose the same task/note creation state immediately to Buddy and web.

### 3. Calendar, notification, and capture parity

- Add the shared Calendar month surface without removing the two-week agenda,
  CRUD, or trusted one-click Join.
- Mirror recent macOS application notifications where the operating system
  permits it, and keep CodeIsland approval notifications separate.
- Add Shelf drag/drop ingest, automatic screenshot capture, selection capture,
  and screen recording, with private file transfer and the existing 100 MB
  remote cap.

### 4. Media and notch interaction parity

- Add album artwork, arbitrary seeking, a compact media HUD, and the selected
  useful ambient visualizer/floating-art treatment.
- Add brightness and volume HUD feedback.
- Add a drag-to-notch window layout chooser beyond left/right/maximize.

### 5. Voice, presentation, and preflight parity

- Add Mac speech recognition, visible mic/listening state, reviewed Claude Do
  proposals, and deliberate file context.
- Add a screen-share-hidden compact Claude strip where macOS window-sharing
  exclusion is supported.
- Add native Mac camera preview, camera/input selection, microphone meter, and
  matching iPhone microphone preflight.
- Add Mac teleprompter play/pause and WPM pacing, plus the same screen-sharing
  privacy behavior.

### 6. Away-use completion

- Ensure every useful host snapshot/action has a native Buddy surface or
  editor, a web fallback, deep links, and an App Intent where voice/Shortcuts
  provides value.
- Use push, Live Activities, and Dynamic Island for active approvals/questions
  and meaningful session progress, not for decorative always-on status.
- Verify adding tasks, answering questions, approving sessions, Calendar Join,
  file handoff, and reviewed utility actions while the phone is on cellular
  with Tailscale enabled and the Mac is locked but awake.

## Permissions and privacy

- Calendar and Reminders use stable signed identities and explicit in-app
  permission recovery buttons.
- Weather supports Location Services and a manual ZIP fallback.
- Camera and microphone media never leave the local device for preflight.
- Accessibility is requested only for the window actions that need it.
- Push payloads contain opaque identifiers and concise status; Buddy fetches
  current sensitive details through the authenticated Tailscale connection.
- Local stores remain private and single-user. No new paid cloud service is
  required.

## Error handling

Every module distinguishes:

- permission denied or not determined;
- host offline or Tailscale unavailable;
- stale revision or expired confirmation;
- provider limitation, such as Spotify queue absence;
- unsupported device/action; and
- execution failure after confirmation.

The UI must offer the next useful recovery action rather than collapsing these
states into a generic error. Remote action receipts record the requested
action, validating device, result, and timestamp without logging secrets.

## Verification and acceptance

Automated acceptance includes focused unit tests for reducers/providers,
real-listener host tests for pairing/auth/action/replay/audit, native iOS UI
tests for each critical flow, release Mac builds, signed archive checks, and
App Store processing/group availability.

Native acceptance requires:

- a signed Mac DMG whose source SHA, signature, installed version, running PID,
  and local/Tailscale health agree;
- a TestFlight build marked `VALID`, actually visible to
  `gregharned@gmail.com`, installed on Greg's iPhone, and paired;
- visible Mac proof for Calendar/Reminders, media, camera/mic, teleprompter,
  capture, global shortcuts, notification mirror, and window layouts; and
- a physical iPhone Wi-Fi and cellular/Tailscale run covering push, Live
  Activity/Dynamic Island, approval/question, task creation, Calendar read and
  Join, file handoff, and replay rejection.

Completion reporting must keep implemented, committed, pushed, merged,
distributed, installed, and physically verified states separate.
