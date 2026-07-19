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

## Latest delivery delta — 2026-07-18 night

This delta supersedes older "current build" language below.

- Latest source: PR #84 merged as
  `dcdc2ddc83799e26e1335f4c322c008c1c146866`, adding
  `scripts/report-strict-physical-e2e.sh`, a fail-closed report that combines
  the newest TestFlight physical-build gate with the authenticated remote host
  lifecycle contract. It exits `0` only when the current physical iPhone build
  is matched and the exact pairing / approval / question / replay / altered
  intent interaction test passes.
- Latest strict E2E report at `2026-07-19T02:37:06Z` returned
  `status = physical-gate-incomplete`, `complete = false`: the interaction
  contract passed (`RemoteApprovalHTTPServerTests/testAuthenticatedHostLifecycleOverRealListener`,
  exit `0`), but the physical iPhone is still stale on Buddy
  `1.0.0 (20260718212803)` instead of latest TestFlight
  `1.0.0 (20260719011702)`.
- Previous source: PR #82 merged as
  `aa98b2bf0a8d0f54ed1721213f57ff63908355d0`, adding a visible stale-build
  install guide to Mac Settings with **Open TestFlight** and **Copy install
  steps** actions, plus a matching `installGuide` payload in the latest-build
  physical gate JSON. Local verification covered
  `RemoteBuddyBuildExpectationTests`, the latest-TestFlight gate Bats suite,
  `git diff --check`, and `graphify update . --no-viz`.
- Installed Mac: `1.0.53`, workflow run `29670149624`, downloaded DMG SHA-256
  `aa5d2bdbfdfa9f0a4a5e074473ffbf801a727751e23111415d16520831fff6f4`,
  ARM64, signature valid under Team `44JG2Y95CH`, CDHash
  `a3ac2372a253256292108fd00f920f9b4a0a371d`, local `/health` and
  Tailscale `/health` both running with zero pending work. Installed-binary
  string inspection confirms the **Open TestFlight**, **Copy install steps**,
  and exact Buddy install guidance strings are present.
- Latest-build physical gate now emits `installGuide.testFlightURL =
  "itms-beta://"` and exact copy text: open TestFlight on iPhone, install
  CodeIsland Buddy `1.0.0 (20260719011702)`, open Buddy for at least 10
  seconds, leave Tailscale connected, then rerun
  `scripts/report-latest-testflight-physical-gate.sh`.
- Previous source: PR #80 merged as
  `a946634d61bc77c3db0cb4295e4cee67f0a68248`, surfacing stale Buddy
  TestFlight builds in Mac Settings and syncing the latest expected Buddy
  version/build into `com.codeisland.app` defaults from the strict physical
  gate script. Local verification covered `RemoteBuddyBuildExpectationTests`,
  the latest-TestFlight gate Bats suite, `git diff --check`, and
  `graphify update . --no-viz`.
- Previous installed Mac: `1.0.53`, workflow run `29669820263`, downloaded DMG SHA-256
  `5566399b49e08c0d6301019fec075a5f2e8892db8755eb2bd8027143c3a4d88a`,
  ARM64, signature valid under Team `44JG2Y95CH`, CDHash
  `3cc519663f28ab3191d73ce9e36497ed20f759fe`, local `/health` and
  Tailscale `/health` both running with zero pending work. The strict physical
  gate wrote `remoteApprovalExpectedClientVersion = 1.0.0` and
  `remoteApprovalExpectedClientBuild = 20260719011702` to the Mac app defaults.
- Previous source: PR #78 merged as
  `d9faa5efd75f33f8eda1d02be5edd3ea58a49ae4`, adding a manual
  Telegram fallback test alert in Buddy Settings. The test alert uses the same
  redacted approval/question message shape and private Tailscale link as real
  Telegram fallback alerts.
- Previous installed Mac: `1.0.53`, workflow run `29669425030`, artifact
  `8436864822`, downloaded DMG SHA-256
  `c421fe53f3011eded8cff233c2e7a55b61efb618257ae7b568c909dd51cee58a`,
  ARM64, signature valid under Team `44JG2Y95CH`, CDHash
  `b114eabb5e6307da3509f5a4ff375cdba10c96fb`, local `/health` and
  Tailscale `/health` both running with zero pending work.
- Installed private web root verification from loopback returned the new
  `reviewDialog`, `reviewSheet`, `confirmSheet`, and `promptSheet` code, with
  no remaining `prompt(`, `confirm(`, or `alert(` calls in the served HTML.
- Latest TestFlight delivery remains run `29668329068`, Buddy build
  `1.0.0 (20260719011702)`, delivery UUID
  `c8dcbe08-5e61-4a0e-b27f-7abb19067009`, Apple state `VALID`, audience
  `APP_STORE_ELIGIBLE`, internal group `CodeIsland Internal`, artifact
  `8436493328`, downloaded IPA SHA-256
  `9e781be9b126a34ab43c1a3cfd7ae2a778d3f647efc01c3ad232aa302dbf59cd`.
- Latest physical iPhone state is **stale**, not accepted for the newest
  TestFlight build. Expected Buddy is `1.0.0 (20260719011702)`; newest
  observed physical Buddy is still `1.0.0 (20260718212803)` from device
  `afba2915-b0a3-456f-a5f2-265bf7e8a64a`, last seen
  `2026-07-19T00:17:23Z`.
- Latest-build physical gate: run
  `scripts/report-latest-testflight-physical-gate.sh` to discover the newest
  successful `testflight-ios.yml` delivery on `main`, extract the delivered
  Buddy build, and fail closed until that exact build is opened on the physical
  iPhone.
- Follow-up source hardening on `codex/glances-inline-recovery` is now signed
  and installed via Mac workflow `29668659780`: Calendar and Reminders show
  Grant/Upgrade/Privacy actions inline, and Weather shows Grant/Privacy or Set
  ZIP without requiring Greg to discover the settings icon first.
- Previous Mac source PR #76 merged as
  `fac1d28e53d7d590d4bf4f786dc117aa8023d466`, replacing all browser-native
  `prompt()`, `confirm()`, and `alert()` paths in the private web fallback
  with an inline reviewed action sheet. Installed private web root verification
  from loopback returned the new `reviewDialog`, `reviewSheet`, `confirmSheet`,
  and `promptSheet` code, with no remaining browser-native dialog calls in the
  served HTML.
- Previous Mac source PR #74 merged as
  `b12ad84607ecf3938712d8333e877d23a367b60d`, adding the inline Calendar,
  Reminders, and Weather recovery actions to the Mac Glances panel.

Previous current-source deliveries retained for traceability: PR #72 merged as
`5ccefcd8683ad2ce22ac833f4c16e153df3df8fc`; Mac workflow `29668328492`
delivered the Buddy connection-copy polish, and TestFlight workflow
`29668329068` delivered Buddy `1.0.0 (20260719011702)`. PR #69 merged as
`33fc732043fa93b132a740d478c5bcc2899c47df`; Mac workflow `29667770216` and
TestFlight workflow `29667770858` delivered Buddy `1.0.0 (20260719005630)`,
which was not physically observed before the newer `20260719011702` build
superseded it. PR #68 merged as
`f6c9455979229474e2c7575df34087f895d98716`; Mac workflow `29667371137` and
TestFlight workflow `29667371841` delivered Buddy `1.0.0 (20260719004222)`.

## Final acceptance delta — 2026-07-18

This delta supersedes all older current-build statements below.

- Source after the installed `1.0.53` acceptance now includes late companion
  command-center polish on `codex/continue-e2e-acceptance`: the native idle
  mock renders a calm Now state instead of a fake pending approval, and routine
  Tools/module icons are neutral so orange remains reserved for attention and
  primary actions. This polish is source/simulator verified only until a new
  signed Mac/TestFlight pair is built and physically accepted.
- Follow-up TestFlight delivery: PR #64 merged as
  `cf8f829dbc87b8130cdfcc06c1728e241b0141aa`. Workflow run
  `29666698698` produced Buddy build `1.0.0 (20260719001734)` from that exact
  commit; Apple reported processing state `VALID`, audience
  `APP_STORE_ELIGIBLE`, and internal group `CodeIsland Internal` access.
  Artifact `8436026518` was downloaded to
  `/Users/gregharned/Downloads/CodeIsland-TestFlight-20260719001734-run-29666698698/CodeIslandCompanion.ipa`
  with SHA-256
  `b3c43a4d19c3f4290364527c0ab8c9bf7a8722e972ced1bef202b1cfe82e5480`.
  This is not yet a physical-install claim for build `20260719001734`.
- Current source: PR #61 merge
  `24c2c16d9cc41546db88d5ca8bcc0fa1a182b208` hardens delayed ActivityKit
  update-token recovery; PR #62 merge
  `69a7a6ff7d6040dc338b5ee7d59b740268d2d4c3` advances the signed Mac bundle.
- Installed Mac: `1.0.53`, run `29661855725`, DMG SHA-256
  `08eca54e453e5cd92f247e359d9de12ea58f14b2ea61d17bd92ff5a5fb31026c`,
  ARM64, Team `44JG2Y95CH`, CDHash
  `d9ddede51874623aab8e7213dbc5ae880125ccbd`. Loopback and Tailscale health
  are HTTP 200 with zero pending work.
- Physical iPhone: TestFlight `1.0.0 (20260718212803)` from run
  `29661636076` is Apple `VALID`, installed/opened, and registered from device
  `afba2915-b0a3-456f-a5f2-265bf7e8a64a`. IPA artifact `8434523952` has
  SHA-256
  `af0e7bfa56b99a60aa5e31c1d35e55b2d593f82bb8530653355cc593c181bfbf`.
- Strict physical acceptance passes the exact Mac and iPhone build gates.
  Pairing survived the update; production APNs and ActivityKit push-to-start
  tokens remain registered.
- Request `6ce1e9a8-e928-451d-9571-d10751ee017a` registered a request-scoped
  ActivityKit update token while active, then resolved to zero active
  activities after the reviewed answer; the exact terminal token was pruned.
  A separate real hook returned exact answer `Approve` through the blocked
  continuation.
- Three native captures across more than 15 seconds retained one stable
  structure. Only the expected session state changed between `Processing` and
  `Running`; the former four-second full-surface flash did not recur.
- Current remaining physical gates: cellular-only Tailscale action, a clean
  current-build expanded Dynamic Island capture without Instacart competing
  for the island, and the accessory/TCC mutation rows in the matrix.

Historical final-host record retained below:

- Final source: PR #58 merge
  `5f616bd6926894389d4309aa0e2e3c0f4a2e7e07` fixes web attribute metadata
  and Calendar EventKit targeting; PR #59 merge
  `4449955791a91ac17c16f9a9c58e6452778a5a8d` prevents delayed pending Live
  Activity receipts from replacing a terminal summary.
- Installed Mac: `1.0.52`, run `29658378890`, artifact `8433603147`, DMG
  SHA-256
  `60945033ddbfe84507c2dfb4c0436c97617c77131318ac2fbb53dbc1c898e02c`,
  ARM64, Team `44JG2Y95CH`, CDHash
  `c890f8c2fc11bcec9819019365f778ead3862dc4`. Local and Tailscale health are
  HTTP 200 with zero pending work and Launch at Login enabled.
- Physical iPhone: TestFlight `1.0.0 (20260718183055)` is installed and
  registered from device `afba2915-b0a3-456f-a5f2-265bf7e8a64a` with
  production APNs and ActivityKit push-to-start tokens. Strict delivery and
  physical-build acceptance passes against Mac `1.0.52`.
- Final automated proof: `493` app tests passed with two intentional opt-in
  skips, `223` core tests passed, and the production ARM64 build passed.
- Physical current-build proof: Claude Ask rendered the returned answer body;
  the foreground remained stable over nine seconds; ActivityKit request
  `93aa1d8a-2527-4fd1-bb14-b362cf203852` moved from active to resolved and
  dismissed with zero active activities; no work remained pending.
- Authenticated private web proof: a live headless browser client rendered real
  mode racks over the Tailscale endpoint; confirmed System refresh passed; an
  exact 1,401,875-byte Downloads transfer matched SHA-256
  `7195bd5c9ad10c43760f135dafdb68b3686034f6e0caacd241c48f283a471664`;
  Calendar add, edit, trusted one-click Join, and delete passed against the real
  store. All temporary Calendar data is removed and the count is back to
  `40 upcoming`.
- Still separate physical gates: cellular-only Tailscale action, directly
  visible Dynamic Island/Lock Screen artwork, per-activity update-token
  delivery, and the remaining accessory/TCC mutation rows in the matrix.

## Current premium delivery delta — 2026-07-18

This delta supersedes older build numbers in the historical receipt sections
below.

- Premium source: PR #44, merge
  `8c072442fbe1ee44e5c2db133f920cea534ae83d`.
- Installed Mac: `1.0.50`, source merge
  `d4bcc82d1776ac0773e15b394d6dce8a0de9f64f`, run `29655999688`, artifact
  `8432926751`, DMG SHA-256
  `b849fa04183e4d6c740e58e11aad20735044bd8b1291c78c4a16fca309a3a0e5`,
  ARM64, and strict signatures valid under Team `44JG2Y95CH`. The installed
  CDHash is `6ecb26f0d3676f6ba2f47c4a1f1e7403336c8188`; loopback and Tailscale
  `/health` both return HTTP 200 with `running: true`, `hostVersion: 1.0.50`,
  and `launchAtLoginStatus: enabled`. CodeIsland owns a live
  `PreventUserIdleSystemSleep` assertion while remote access is enabled.
- Current physical-iPhone TestFlight build: `1.0.0 (20260718112841)`. The
  replacement `1.0.0 (20260718183055)` was generated from the same `d4bcc82`
  merge by run `29656000448`; Apple reports `VALID`, group
  `CodeIsland Internal` has all-build access, and tester
  `gregharned@gmail.com` is `ready`. Signed IPA artifact `8432920506`, delivery
  UUID `90778d66-464a-40a0-aca5-6f062eb82174`, IPA SHA-256
  `c546486b5fab88f51781cb94e937a054340ce7c9b067598890dd36ab1e831d48`.
  The replacement is distributed but is not classified as physically
  installed until that exact build registers from Greg's iPhone.
- Native premium suite: 39 passed, 0 failed, 0 skipped, 0 runtime warnings;
  result bundle `/tmp/CodeIsland-premium-full-final-20260718-0415.xcresult`.
- Physical premium proof: TestFlight build `20260718112841` is installed and
  open on Greg's iPhone. The paired-device store records
  `clientVersion = 1.0.0` and `clientBuild = 20260718112841`; strict physical
  acceptance passes all delivery gates. Three captures over 16 seconds were visually stable,
  authenticated Sessions rendered without a discovery/loading substitution,
  and Calendar returned Greg's real store with `40 upcoming`.
- Physical attention proof: a real `AskUserQuestion` round trip produced the
  exact decision card and explicit review, returned `Continue` through the
  blocked hook socket, started one ActivityKit activity, and resolved to zero
  active activities. iPhone Mirroring did not render the compact or expanded
  Dynamic Island artwork, and no per-activity update token registered, so those
  two visual/update claims remain open.
- Locked-host follow-up on installed Mac `1.0.50`: while macOS and iPhone
  Mirroring were locked, a temporary real hook-socket question caused the
  physical build `20260718112841` to authenticate, report one active
  ActivityKit question at `2026-07-18T18:44:26Z`, and return to zero active
  activities after the socket was cancelled at `2026-07-18T18:44:46Z`.
  Request `4d23434e-fd78-4738-ae33-2b5708b227a9` left no pending action. This
  proves current locked-host APNs wake/start/resolution on the existing phone
  build; it does not prove replacement-build installation or visible Dynamic
  Island artwork.
- The installed `1.0.50` private Tailscale web root returned HTTP 200 with the
  current Claude answer-body renderer and required CSP, referrer, and frame
  protections. An unauthenticated Code-rack request returned 401. Authenticated
  mobile-browser actions remain a separate physical acceptance gate.

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
| Calendar two-week agenda, CRUD, Join | Physical read proven from Greg's real store; live authenticated browser automation through Tailscale passed add/edit/delete and trusted one-click Join against the signed Mac host, with exact confirmation and full cleanup | Physical read proven through the paired iPhone; native-iPhone CRUD, recurrence, and physical-iPhone browser use remain separate | Run native-iPhone recurrence/CRUD and the physical browser path if parity requires them rather than the live web service proof |
| Tasks/lists/due dates/reorder/archive | Physical partial: a task created on iPhone appeared in Apple's real Mac Reminders store and was cleaned up; list/reorder/archive/restore remain unverified | Physical partial: New Task review, exact confirmation, host write, and store visibility are proven | Run a dedicated list plus reorder/complete/archive/restore/delete matrix |
| Notes/jot/categories/checklists/merge | Physical partial: the current iPhone build created a reviewed/confirmed note on the host, rendered it as revision 1, and the exact test data was cleaned up; delete/edit/append/categories/checklists/undo remain unverified | Physical partial: composer, exact reviewed action, separate `Do it`, host persistence, and refreshed iPhone visibility passed | Run in-app delete, edit/conflict, category, checklist, and undo round trips across Mac and iPhone |
| System CPU/memory/load | Ready: host load/memory/disk/thermal/uptime | Ready: mirrored readings and refresh through an authenticated, exact-confirmation host action | Compare readings with Activity Monitor on the physical Mac/iPhone pair |
| Weather | Physical ZIP fallback proven during the unlocked 1.0.41 run: `61° Clear · Ridgefield, Washington`; Location Services mode remains unverified | Ready implementation: mirrored remote weather and refresh | Physical location-mode, remote refresh, and offline-state runtime tests |
| Notifications | Partial by deliberate platform boundary: CodeIsland action-required alerts are prioritized, deduped, redacted, and separated; macOS exposes no public cross-app Notification Center history API, so CodeIsland does not read private databases or request Full Disk Access | Physical current-build proof: production APNs, ActivityKit push-to-start, and request-scoped update tokens are registered. A real question rendered the exact attention card, returned the reviewed answer, registered token for request `6ce1e9a8-e928-451d-9571-d10751ee017a`, resolved to zero active activities, and pruned that terminal token | Capture clean current-build compact/expanded artwork without the competing Instacart activity and exercise stale-push behavior |
| Claude co-pilot/voice/proposals | Ready implementation: read-only Ask and reviewed Do through authenticated local Claude Code with tools disabled, push-to-talk/continuous speech, visible listening state, bounded user-selected/drop file context, and best-effort screen-share-hidden strip with honest disclosure | Ready implementation: Ask/Do, speech recognition, proposal review, exact confirmation, and deep-linked task/note preparation | Run real Ask and multi-action Do, Mac voice/file context, and physical-iPhone dictation/task creation |
| AI Coding sessions/approvals/questions | Signed 1.0.53 is installed, healthy, keeps the private host awake, and backed the physical question continuation | Physical build `20260718212803` is installed/opened and authenticated. A real exact question was selected, reviewed, answered `Approve`, audited, and drained without routine-content noise | Run exact-request replay and one cellular/Tailscale approval away from local Wi-Fi |
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
| Private web fallback | Ready and live-exercised from a headless browser client: responsive authenticated Home/Work/Code, exact actions, Calendar CRUD/Join, confirmed System refresh, exact-byte Downloads transfer, retry/offline state, and replay protection | Physical-iPhone browser and cellular-only use remain unverified | Toggle iPhone Wi-Fi off and repeat one action plus file read in the physical iPhone browser over cellular Tailscale |
| TestFlight distribution | Ready: signed archive/upload pipeline, source plus compiled App Intent metadata validation, internal group, 60-minute Apple indexing window, and always-preserved IPA artifact | Current build `1.0.0 (20260718212803)` is Apple `VALID`, installed/opened from `CodeIsland Internal`, and confirmed by paired `clientVersion = 1.0.0` plus exact `clientBuild`; stability, background ActivityKit token lifecycle, reviewed answer, and final-host reauthentication passed physically | Preserve the current internal delivery pipeline; clean expanded Dynamic Island artwork and cellular action remain separate runtime gates |

## Behavior-level completion adjudication

The table distinguishes **implementation**, **automated proof**, and **physical
acceptance**. Crest's defining behaviors are represented rather than inferred
from module names: saved mode pin/order, artwork and arbitrary scrub, Shelf
capture/drop, global quick jot, Calendar month navigation, a supported
notification boundary, Mac speech/file context, camera and microphone
preflight, paced teleprompter, and drag-to-notch layouts.

Shared Mac/iPhone/web action parity is now guarded by
`PersonalHubBuddyParity.validate(snapshot:)`. It checks every module-level,
item-level, and calendar selected-event action in a hub snapshot against the
explicit Buddy route table. The authenticated remote hub lifecycle test
validates the actual `/api/hub/snapshot` responses for Home, Work, and Code, so
new Mac actions cannot silently appear on iPhone or the private web app without
being classified as native, read-only, or Mac-only with a reason.

Pomodoro remains the explicit exclusion Greg requested. Cross-app macOS
Notification Center history is the other non-parity item, but for a different
reason: Apple exposes no public API for it. CodeIsland shows that limitation
instead of reading private databases or requesting Full Disk Access. Spotify
queue enumeration and universal hardware brightness-key interception have
similar provider/API limits and are disclosed at the affected surface.

CodeIsland's personal extensions—away approvals and questions, exact-confirmation
actions, Downloads/Shelf transfer, Tailscale, APNs, Live Activities, Dynamic
Island, App Intents, and web fallback—are evaluated separately. Their automated
contracts are green; the installed current physical build has now proved exact
build identity, foreground stability, authenticated Sessions, Calendar read,
attention-only question presentation, explicit answer review, hook
continuation, and ActivityKit start-to-resolution cleanup. Prior physical proof
also covers three approvals and one Reminders add/store/cleanup round trip; the
current build also completed a reviewed Notes add/visibility/cleanup pass.
Cellular/Tailscale action, a clean current-build expanded Dynamic Island
capture, replay, and the remaining TCC-backed mutations remain distinct gates.

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

Run the non-secret status probe before and after the physical pass. It verifies
the installed Mac/signature/health and reports only booleans for stored push
tokens, never the tokens themselves. Strict mode exits `2` until the exact
physical build has registered with the Mac:

```bash
EXPECTED_MAC_VERSION=1.0.49 \
EXPECTED_CLIENT_VERSION=1.0.0 \
EXPECTED_CLIENT_BUILD=20260718112841 \
STRICT=1 \
scripts/report-physical-acceptance.sh
```

For the current release train, prefer the latest-build gate so stale TestFlight
installs cannot be mistaken for acceptance of a newer upload:

```bash
EXPECTED_MAC_VERSION=1.0.53 \
EXPECTED_CLIENT_VERSION=1.0.0 \
scripts/report-latest-testflight-physical-gate.sh
```

For final E2E acceptance, use the strict combined report. It runs the
latest-build physical gate and the authenticated remote host lifecycle contract,
then exits `2` unless both pass:

```bash
scripts/report-strict-physical-e2e.sh
```

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
