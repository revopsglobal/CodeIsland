# Crest/mobile physical acceptance — 2026-07-17

This receipt separates automated, signed-delivery, and physical-device proof.
It must not be read as blanket acceptance of every Crest/mobile module.

## Final signed receipt follow-up

PR #39 merged the Live Activity lifecycle-receipt implementation as
`7005f79d3359245d4dfb10564664a97a79112527`. The first signed macOS workflow
exposed a repeatable Xcode 26 signal-6 abort at an `AppState` deallocation test
boundary even though the exact 19-test selection passed locally. PR #40 fixed
that compiler/runtime compatibility issue and merged as
`1e031a3d896fa8b380ddc237fe418b88d2453635`.

Fresh signed macOS run `29637137521` built `1.0.44` from that exact merge,
passed the previously crashing Xcode 26 security selection (19/19), personal
utilities, iPhone model tests, the iPhone Simulator build, ARM64 checks, the
Calendar entitlement check, and strict nested signature verification. Artifact
`8427492349` is installed at `/Applications/CodeIsland.app`; the preserved DMG
is `/Users/gregharned/Downloads/CodeIsland-1.0.44-run-29637137521/CodeIsland.dmg`
with SHA-256
`05fe1c31510127b4e08e0039abf28306b58c3ee689dbfb6245031dd375acd31b`.
Independent mounted-image and installed-app verification passed with Team
`44JG2Y95CH`, CDHash `d89fdc0f680007853a581065c6f63cb25694272c`,
and ARM64 app/helper binaries. The previous 1.0.43 app is preserved at
`/Users/gregharned/Downloads/CodeIsland-app-backups/CodeIsland-1.0.43-pre-1.0.44.app`.
Local and Tailscale `/health` both returned `running: true` after replacement.

TestFlight run `29636436339` uploaded `1.0.0 (20260718075059)` from PR #39's
merge. Apple reported `VALID`, audience `APP_STORE_ELIGIBLE`, and all-build
access for `CodeIsland Internal`. Delivery UUID:
`c21248f4-2b48-4b47-b41c-e4e7952798a2`; signed IPA artifact `8427328057`;
tester receipt artifact `8427248381`. Independent IPA inspection passed strict
signature verification and confirmed production APNs, time-sensitive
notifications, Team `44JG2Y95CH`, and bundle
`com.revopsglobal.codeisland.buddy`. The downloaded IPA is
`/Users/gregharned/Downloads/CodeIsland-TestFlight-20260718075059-run-29636436339/CodeIslandCompanion.ipa`,
SHA-256 `776660d000305d1816116590d6b1a667fa60cd84b27306ae8e2e0fad4297f413`.
The tester receipt records `gregharned@gmail.com` as `ready`.

After the 1.0.44 host restart, the existing physical-iPhone pairing, production
APNs token, and ActivityKit push-to-start token remained intact. The phone
authenticated again at `2026-07-18T08:21:37Z` and `08:24:30Z`. A harmless
question probe returned `Continue`, but no new lifecycle receipt or per-activity
update token reached the Mac. iPhone Mirroring simultaneously reported
`iPhone in Use`, so the physical surface could not be inspected. Therefore the
new TestFlight build is delivered and available, but its physical installation
and visible Live Activity/Dynamic Island lifecycle remain unproven; do not infer
them from the heartbeat or answer alone.

## Automated Live Activity receipt follow-up

The current follow-up adds an authenticated, privacy-preserving lifecycle
receipt from Buddy to the paired Mac. Notification receipt, ActivityKit start,
state change, and snapshot events are bounded and deduplicated; they contain
opaque request/event IDs and lifecycle state, but no prompt, workspace,
command, transcript, action token, or APNs token. The Mac persists the latest
receipt on the paired-device record, appends each new event once to the audit
log, and exposes a timestamped lifecycle status in Settings → Buddy.

The same change makes local Live Activities degrade correctly when an unsigned
Simulator/local build has no `aps-environment`: Buddy first requests a
push-updatable activity and falls back to a local ActivityKit activity if that
request is rejected. Signed TestFlight builds continue to use the push-enabled
path. It also fixes an off-main `AppState` deallocation trap found during the
full Mac run and keeps iPhone action receipts visible for eight seconds so a
sheet dismissal or VoiceOver focus transition cannot hide the result.

Fresh automated proof from this source:

- `CodeIslandTests`: 481 executed, 2 intentional skips, 0 failures.
- `CodeIslandCoreTests`: 220 executed, 0 failures.
- native iPhone logic: 8/8 passed; result bundle
  `/tmp/CodeIsland-ios-unit-final-20260718-0047.xcresult`.
- native iPhone UI: 25/25 passed in 482.7 seconds; result bundle
  `/tmp/CodeIsland-full-ui-final-20260718-0045.xcresult`.
- focused unsigned-ActivityKit fallback and resolved-request lifecycle: passed;
  result bundle
  `/tmp/CodeIsland-live-activity-fallback-20260718-0044.xcresult`.
- Graphify refreshed successfully: 4,677 nodes, 12,204 edges, 53 communities.

This is automated protocol, UI, and Simulator proof. The replacement signed Mac
is installed and the replacement TestFlight build is Apple-valid and available,
but a physical install of that iPhone build has not been confirmed. Until the
phone emits the new lifecycle receipt, visible Live Activity/Dynamic Island
creation and remote end remain unproven.

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
- **Physical question continuation:** a real `AskUserQuestion` bridge request
  (`820a59cc-62da-44ba-9cbc-457c89af5e1e`) appeared on the paired iPhone with
  the exact prompt and choices. Greg's iPhone selected `Continue`, reviewed the
  single-use confirmation, and the blocked bridge resumed with
  `behavior: allow` plus `updatedInput.answers = Continue`. The host wrote a
  `question-answer` / `resolved` audit receipt at `2026-07-18T04:47:24Z` from
  device `iPhone`. This proves the physical answer path; an exact-request replay
  rejection is still only automated proof.
- **Physical Reminders write:** the iPhone's **New Task** flow reviewed and
  confirmed `CodeIsland physical E2E test - delete me`. The task appeared in
  Apple's real Reminders app on the Mac in the Grocery list. It was then removed
  through Reminders and a second search confirmed that the temporary item was
  gone. This proves add/store visibility and cleanup, not the full
  reorder/archive/restore matrix.
- **Physical Calendar read:** Buddy's Calendar module returned Greg's real July
  2026 data (`40 upcoming`), the six-week month, and selected-day events. This
  proves the installed Mac identity now has working Calendar access and that the
  authenticated iPhone read path works. Calendar mutation, recurrence, and
  one-click Join remain unproven.
- **Final replacement host installed:** `/Applications/CodeIsland.app` `1.0.43` is
  installed from run `29633277978`, source
  `265cc544d20a7144c3cfe1cd340a2f10748ab267`, artifact `8426279211`.
  The downloaded DMG SHA-256 is
  `e0369fbfd51c939b6b8e8e8afe7fa91a447e64a825b638a9885ec3c40a219b20`.
  Mounted-image and installed-app strict signature verification passed; the
  ARM64 app is signed by Team `44JG2Y95CH` with CDHash
  `78ef64fc758f0bebed52066a88eaf80c9bbad9dd`. Local and Tailscale `/health`
  both returned `running: true`, server `Greg’s MacBook Air`. The paired
  physical-iPhone record and its production APNs token survived the update.
- **Unlocked host data surfaces:** before the final replacement, installed
  1.0.41 rendered four
  current authenticated coding sessions without the previous discovery card,
  Greg's real Calendar (`40 upcoming`), the selected Grocery Reminders list,
  12 recent Downloads, 18 Shelf items, and manual-ZIP weather
  (`61° Clear · Ridgefield, Washington`). This is physical Mac read proof, not
  iPhone acceptance of the replacement build. That live inspection also found
  an incorrect Spotify duration unit and multiple false default-audio labels.
  PR #33 (`bca730bd9ac47f7ab9cb6e5a4352b6fab15f2d9b`) normalized Spotify
  milliseconds to seconds; PR #34
  (`265cc544d20a7144c3cfe1cd340a2f10748ab267`) reads the real input/output
  default keys. Both focused regressions and the full 480-app/219-core suites
  passed. Signed 1.0.43 contains both fixes. After macOS unlocked, the installed
  app rendered Spotify's real `Sound of Horns` track as `1:27 2:21` rather than
  `2350:00`; only MacBook Air Speakers and MacBook Air Microphone were labeled
  default output/input. The 1.0.43 Code rack also rendered five authenticated
  sessions and `3 running · no decisions waiting`, with no discovery/loading
  substitution. This closes the final Mac read/visual checks for PRs #31, #33,
  and #34; audio switching and other mutations remain separate gates.

## Final replacement TestFlight delivery

PR #31 merged as `61310ee2d20c651221ee6ef9a3ef823bb7bb0558`. TestFlight run
`29632459018` uploaded `1.0.0 (20260718053347)` with delivery UUID
`835af987-3aef-4cc9-82d4-8d88ec0684f1`; Apple reported `VALID`, audience
`APP_STORE_ELIGIBLE`, and confirmed that all-builds group `CodeIsland Internal`
has access. Artifact `8425978534` preserves the signed IPA; its SHA-256 is
`27259eccd5eb7890c3a4e852a52782cbf323b98956ef9025cb03f7e2925b2630`.

Independent local inspection passed strict signature verification for the app
and widget. The app is signed for production APNs, declares
`NSSupportsLiveActivities = true`, and both bundles use Team `44JG2Y95CH`.
Tester receipt artifact `8425940062` records `gregharned@gmail.com` as `ready`
in `CodeIsland Internal` at `2026-07-18T05:33:36Z`.

This replacement build is now installed/opened on Greg's physical iPhone. At
`2026-07-18T06:14:00Z` the existing device
`afba2915-b0a3-456f-a5f2-265bf7e8a64a` authenticated to the Mac and registered
an ActivityKit push-to-start token in addition to its production APNs token.
That registration code exists only in PR #31, so it is evidence for the final
build rather than the older physical build. iPhone Mirroring and the Mac are
currently locked, so this does not yet prove the corrected Sessions rendering
or visible Live Activity/Dynamic Island state.

The background delivery gate was then narrowed further without unlocking the
devices. A temporary, clearly labeled `AskUserQuestion` acceptance probe was
introduced through the real hook socket after the phone had been idle for more
than seven minutes. The paired-device heartbeat advanced at
`2026-07-18T06:23:23Z` immediately after pending attention, proving the physical
client woke and authenticated to refresh details. The unanswered socket was
then cancelled; the host drained the question and sent resolved attention, and
the phone authenticated again at `2026-07-18T06:25:17Z`. The probe ran no
command and left no pending action. This proves pending/resolved background
APNs wake-and-refresh behavior. The host received no per-activity update token,
and the locked screen could not be observed, so Live Activity creation,
Dynamic Island visibility, and token-based remote end remain unproven.

## Latest connection-status correction

PR #30 merged at `7f311899a97410b7f69727f39a4c8b0e1ad019c6`. It prevents nearby
Bluetooth discovery from presenting an authenticated Tailscale session as
`Searching`, displays the authenticated Mac name, and reserves activity motion
for real discovery/action-required states.

Signed build `1.0.0 (20260718041048)` uploaded successfully in run
`29630108653`; Apple delivery
`a1fa24b9-1bec-4656-b3b6-8641ede8c854` reported no upload errors. The normal
job's 20-minute App Store Connect visibility check expired while Apple indexed
the build. Verification-only run `29630740348` later found that same build at
`2026-07-18T05:14:12Z`—about 41 minutes after its verification began—and
reported `VALID`, audience `APP_STORE_ELIGIBLE`, with the all-builds internal
group `CodeIsland Internal`. It did not upload another IPA. The workflow has
been hardened to allow 60 minutes and to preserve the IPA artifact even when
Apple's indexing is slow.

Verification on the current follow-up source:

- `CodeIslandTests`: 480 passed, 2 intentional skips, 0 failures on the clean rerun.
- `CodeIslandCoreTests`: 219 passed, 0 failures.
- production Swift build: passed.
- complete iPhone scheme: 7 unit tests and 25 UI tests passed, 0 failures.
- iPhone result bundle:
  `/tmp/CodeIsland-final-full-20260717-2223.xcresult`.

The Simulator also emitted a 128-byte ActivityKit push-to-start token and
accepted the privacy-redacted start fixture as a notification. The simulator
path did not prove a Dynamic Island start because `simctl push` did not provide
the required `liveactivity` APNs headers; the physical-device/APNs run remains
the acceptance surface for that claim.

The fresh TestFlight build from this source now has physical install/open,
authenticated-heartbeat, production APNs, and ActivityKit push-to-start token
proof. Visual acceptance remains separate.

The installed build also exposed a separate Sessions-tab truth bug: while the
Tailscale client was authenticated, the tab could still render the nearby
Bluetooth `Waiting for Mac` discovery card. The follow-up change makes Sessions
use its own authenticated Code-rack snapshot, reserves nearby discovery for an
unpaired phone, registers ActivityKit push-to-start and update tokens, starts a
privacy-redacted Live Activity remotely only for approvals/questions, and sends
an ActivityKit end on resolution. Its regression tests are green locally. The
replacement Mac and TestFlight builds are installed together and the new token
registration is physical; the Sessions and Dynamic Island UI states are not
yet visually accepted.

## Still requires physical proof

- unlock the physical iPhone surface, confirm the authenticated Mac name and
  Sessions surface on build `20260718053347`, and recheck foreground stability;
- exact-request replay rejection on the phone (the real question answer is
  proven above);
- visible Live Activity/Dynamic Island creation, per-activity update-token
  registration, and token-based remote end (pending/resolved APNs wake-and-
  refresh is proven above);
- Wi-Fi-off cellular/Tailscale approval, task creation, Calendar read, and
  private web fallback while the Mac is locked (Wi-Fi task creation and
  Calendar read are proven above);
- real Calendar and Reminders permission/data CRUD, recurrence, selected list,
  weather location/ZIP, and one-click Join;
- remaining task lifecycle operations, note, checklist/undo, Shelf/Downloads file transfer, Claude Do,
  dictation, and App Intent execution;
- Music/Spotify, audio, Bluetooth, battery, quick toggles, camera/mic,
  teleprompter, and Accessibility-backed window actions against Greg's real
  devices and data.

No Apple Watch or Pomodoro acceptance is required. Telegram remains an optional
outbound alert/deep-link fallback, not a second control plane.
