# Crest/mobile physical acceptance — 2026-07-17

This receipt separates automated, signed-delivery, and physical-device proof.
It must not be read as blanket acceptance of every Crest/mobile module.

## Physical proof completed

- **Installed iPhone build:** CodeIsland Buddy `1.0.0 (20260718031753)` was
  installed from TestFlight on Greg's physical iPhone. Source SHA
  `96c1a74bca0c851dcaf1ef91248cc9751c136816`; workflow run
  `29628559171`; signed IPA artifact `8424725763`.
- **Paired host:** the physical device paired at `2026-07-18T02:26:48Z` as
  device `afba2915-b0a3-456f-a5f2-265bf7e8a64a`. The installed Mac host
  continued to receive authenticated heartbeats after the install and stores a
  production APNs token for that device.
- **Stable foreground rendering:** after PR #29, the physical app stayed
  visually stable through four observations over approximately 15 seconds.
  The former four-second full-surface flash did not recur. This proves the
  foreground anti-flash fix; it does not prove background push behavior.
- **Physical approval decisions:** the paired iPhone produced three audited
  `approve` / `resolved` decisions for real CodeIsland approval requests:
  `3b0efdb4-89df-47f4-a000-268464ed356d`,
  `1a657939-770e-4cde-9d5f-91e2f7a27cee`, and
  `e4e3b760-3eef-43e4-b671-93e483a9981c`. The latest receipt was written at
  `2026-07-18T03:18:13Z` from device `iPhone`, source `Codex`, tool `Bash`.
- **Host availability:** `/Applications/CodeIsland.app` `1.0.40` is signed by
  Team `44JG2Y95CH` and running. Its real listener answered local `/health`
  with `running: true`; Tailscale reported the Mac online at
  `gregs-macbook-air.tail62f27c.ts.net` / `100.84.86.6`.

## Latest connection-status correction

PR #30 merged at `7f311899a97410b7f69727f39a4c8b0e1ad019c6`. It prevents nearby
Bluetooth discovery from presenting an authenticated Tailscale session as
`Searching`, displays the authenticated Mac name, and reserves activity motion
for real discovery/action-required states.

Signed build `1.0.0 (20260718041048)` uploaded successfully in run
`29630108653`; Apple delivery
`a1fa24b9-1bec-4656-b3b6-8641ede8c854` reported no upload errors. The normal
job's 20-minute App Store Connect visibility check expired while Apple indexed
the build. Verification-only run `29630740348` is waiting for the same build
without uploading another IPA. The workflow has been hardened to allow 60
minutes and to preserve the IPA artifact even when Apple's indexing is slow.

Verification on the merged source:

- `CodeIslandTests`: 477 passed, 2 intentional skips, 0 failures.
- `CodeIslandCoreTests`: 218 passed, 0 failures.
- production Swift build: passed.
- complete iPhone scheme: 6 unit tests and 24 UI tests passed, 0 failures.
- iPhone result bundle:
  `~/Library/Developer/Xcode/DerivedData/CodeIslandCompanion-abkbncwynakyihgwigzxamfbugzs/Logs/Test/Test-CodeIslandCompanion-2026.07.17_21-02-54--0700.xcresult`.

The fresh TestFlight build from this source is a signed-delivery proof until it
is installed and visually accepted on the physical phone.

## Still requires physical proof

- install the PR #30 TestFlight build and confirm the header shows the Mac name
  instead of `Searching`, with no recurrence of the four-second flash;
- a real question answer plus exact-request replay rejection on the phone;
- background APNs delivery, resolved cleanup, Live Activity, and Dynamic Island;
- Wi-Fi-off cellular/Tailscale approval, task creation, Calendar read, and
  private web fallback while the Mac is locked;
- real Calendar and Reminders permission/data CRUD, recurrence, selected list,
  weather location/ZIP, and one-click Join;
- real task, note, checklist/undo, Shelf/Downloads file transfer, Claude Do,
  dictation, and App Intent execution;
- Music/Spotify, audio, Bluetooth, battery, quick toggles, camera/mic,
  teleprompter, and Accessibility-backed window actions against Greg's real
  devices and data.

No Apple Watch or Pomodoro acceptance is required. Telegram remains an optional
outbound alert/deep-link fallback, not a second control plane.
