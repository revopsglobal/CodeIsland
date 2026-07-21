# Adaptive native acceptance proof

- Date: 2026-07-19 PDT
- Implementation branch: `codex/completion-hardening-20260719`
- Proof branch: `codex/completion-proof-20260719`
- Merged implementation: PR #138, `b0217291fba7ec57544880ca7c4f7a5d7704a94c`
- Privacy diagnostics: PR #140, `a3e07e40fc792fd22ffa2ae03d0a0bb0e51ddb0f`

This record keeps implementation, signed delivery, installed runtime, and
physical-device proof separate. Simulator or source-level evidence is never
treated as physical iPhone acceptance.

## Implemented hardening

- Immediate-attention counts now include only approvals, questions, failed
  work, and tasks that explicitly need Greg. Routine work, followed tasks,
  verified tasks, and Mac queueing no longer inflate the badge.
- The exact approval or decision appears before the generic signal summary.
- Reviewed verified-task state persists across app launches.
- The native action dock and approval chrome remain readable at the largest
  accessibility text size. Approval actions use a vertical layout at
  accessibility sizes.
- The direct-device verifier refuses to OCR an occluded iPhone Mirroring
  window.
- The Mac hardened-runtime entitlement set now includes camera and audio input
  in addition to Bluetooth and calendar access.
- Swift 6 concurrency, isolation, deprecated API, and unsafe Core Audio pointer
  warnings observed in the release build were removed.

## Automated proof

| Surface | Result | Evidence |
| --- | --- | --- |
| Mac app XCTest | 583 passed, 2 intentional skips, 0 failed | `/private/tmp/codeisland-eventkit-health-full-tests.log` |
| Shared core XCTest | 238 passed, 0 failed | `/private/tmp/codeisland-swift-full-tests.log` |
| Acceptance scripts | 69 passed, 0 failed | `/private/tmp/codeisland-all-bats.log` |
| Companion model checks | 25 passed, 0 failed | `/private/tmp/codeisland-model-tests.log` |
| iPhone unit and UI suite | 79 total, 78 passed, 1 opt-in physical test skipped, 0 failed | `/private/tmp/CodeIsland-completion-clean-0719-2.xcresult` |
| UI and protocol static guard | Passed | `/private/tmp/codeisland-ui-regressions.log` |
| Shell and entitlement syntax | Passed | `shellcheck` and `plutil -lint CodeIsland.entitlements` |

The full iPhone suite ran on the `CodeIsland Clean Acceptance` iPhone 16
Simulator, iOS 26.5, device ID
`FE390564-DC30-4460-AA6D-05430B5ED107`. The only skipped test is the explicitly
opt-in live paired Mac test.

## Adaptive visual proof

- Largest accessibility text size: the decision and approval flows remained
  selectable and their primary controls remained hittable.
- Dark appearance, increased contrast, reduced transparency, and Reduce Motion:
  the approval and question tests both passed together.
- Manual rendered captures were inspected at:
  - `/private/tmp/codeisland-question-axxxl-after.png`
  - `/private/tmp/codeisland-approval-axxxl.png`
  - `/private/tmp/codeisland-question-dark-contrast-reduced.png`

## Mac release-candidate proof

The ARM64 `1.0.56` local candidate was produced through
`scripts/build-dmg.sh`, mounted, and passed strict nested code-signature
verification. The packaged app contains the camera and audio-input
entitlements and the DMG is UDZO read-only compressed. This candidate is
ad-hoc signed and not notarized; it is build proof, not the install artifact.

## Signed Mac delivery and installed runtime

The current internal ARM64 workflow completed successfully from the merged
privacy-diagnostics commit:

- Workflow run: <https://github.com/revopsglobal/CodeIsland/actions/runs/29724433337>
- Source SHA: `a3e07e40fc792fd22ffa2ae03d0a0bb0e51ddb0f`
- Artifact: `CodeIsland-macos-arm64-dmg`, ID `8453746230`
- Artifact digest: `sha256:8421bf0a861d135b7bf9d039a04e78852cdf88c7fef5594905de33f9f2338c77`
- Downloaded DMG SHA-256: `2aeeb20b358888fdf90f70b949d4d42cef039a645fef1e9fa417a735798c3a2e`

The downloaded DMG was mounted and checked before installation. The packaged
app is version `1.0.57`, ARM64, signed by Apple Development team
`44JG2Y95CH`, and passes strict nested signature verification. The packaged
entitlements include camera, audio input, Bluetooth, calendar access, and the
hardened-runtime library-validation exception used by the app.

Version `1.0.57` was then installed at `/Applications/CodeIsland.app`. The
previous `1.0.56` app bundle was preserved at
`/private/tmp/CodeIsland.app.backup-1.0.56-20260720` before replacement.

The installed runtime has process ID `95087` and returns `hostVersion:1.0.57`
from both private endpoints:

- `http://127.0.0.1:43891/health` - HTTP 200
- `https://gregs-macbook-air.tail62f27c.ts.net:9443/health` - HTTP 200

Tailscale Serve remains configured as a tailnet-only reverse proxy from port
`9443` to `127.0.0.1:43891`.

A stability soak on version `1.0.56` sampled the same installed process 23 times from
`2026-07-20T06:58:42Z` through `2026-07-20T07:09:52Z`. Every sample retained
process ID `43869`, version `1.0.56`, loopback HTTP 200, and Tailscale HTTP 200.
The process uptime was `12:43` at the final sample. In the native iPhone UI
suite, `testMultipleAttentionItemsDoNotRotateAutomatically` and
`testNeedsYouTaskRemainsStableAcrossPollingWindow` also passed, covering the
reported four-second content-flash cause rather than relying only on process
uptime.

Version `1.0.57` adds read-only privacy diagnostics to the same private health
response. Both loopback and Tailscale report Calendar `fullAccess`, Reminders
`fullAccess`, manual weather fallback configured, and a selected reminder-list
filter configured. System Location remains `notDetermined`, which does not
block weather because the manual fallback is active. No calendar or reminder
content is exposed by the health response.

A seven-sample post-install soak ran from `2026-07-20T07:30:24Z` through
`2026-07-20T07:33:27Z`. Every sample retained process ID `95087`, HTTP 200 on
both private routes, `hostVersion:1.0.57`, both EventKit statuses at
`fullAccess`, and both fallback-configuration flags at `true`.

## Internal TestFlight delivery

The current internal TestFlight workflow completed successfully from the same
merged privacy-diagnostics commit:

- Workflow run: <https://github.com/revopsglobal/CodeIsland/actions/runs/29724514209>
- Build: `1.0.0 (20260720072452)`
- Apple processing state: `VALID`
- Audience: `APP_STORE_ELIGIBLE`
- Delivery UUID: `a2ccaa76-b5bc-4924-aebe-d176e88cacc1`
- IPA artifact: `CodeIsland-Buddy-TestFlight-20260720072452`, ID `8453792602`
- Artifact digest: `sha256:9dd0a8007cd163fe0ab4f32c78534f4305eafae76f1a741e8fff975932f68b47`

The `CodeIsland Internal` group has all-build access. Its tester receipt shows
`gregharned@gmail.com` active for app ID `6791897500`, bundle
`com.revopsglobal.codeisland.buddy`, group ID
`8db9e637-03e3-4147-afda-895700e127c8`, and tester ID
`4510ab81-87ea-4967-bde4-47d3f2e083af`.

The downloaded IPA has SHA-256
`35adef0b69ecca592b090592569520ae341c765b795a356ac4b5f6925d68ea3d`.
Its main app and both extensions pass strict signature verification. The main
app is signed for production APNs, time-sensitive notifications, the private
app group, and App Store beta reporting; `NSSupportsLiveActivities` is enabled.
The compiled `120x120` and `152x152` App Store icon assets are present, and the
main app, Live Activity/widget extension, and share extension all carry build
`20260720072452`.

## Live private transport proof

Tailscale reported `Running` for
`gregs-macbook-air.tail62f27c.ts.net` at `100.84.86.6`. After the installed Mac
app was running, both endpoints returned HTTP 200 with `running:true`:

- `http://127.0.0.1:43891/health`
- `https://gregs-macbook-air.tail62f27c.ts.net:9443/health`

The same checks now pass after installing signed version `1.0.57`; the private
route therefore proves the delivered runtime rather than only the previous
installation.

## Away-use and feature coverage

`scripts/report-away-readiness.sh` reports the private web fallback healthy.
It detects the native delivery as current, Tailscale and loopback transport as
healthy, and the mobile web shell as ready with task, question, approval, hub,
safe-area, touch-target, live-feedback, inline-review, and PWA markers.
Telegram has since been retired from the CodeIsland runtime. Buddy APNs, Live
Activities, and the private Tailscale client are the away-use surfaces.

The automated suites cover the user-facing surfaces requested for this
release: pairing lifecycle and rate limiting, task creation and execution
policy, exact approval and question routing, sessions and attention state,
push and Live Activity token handling, Calendar and Reminders payloads,
one-click calendar actions, weather/location fallback modeling, Downloads,
Bluetooth battery, Now Playing, Shelf import and retention, teleprompter,
camera/audio preflight, notification mirroring, adaptive iPhone layouts,
widgets, StandBy, App Intents, and the English-language regression contract.

## Current release gates

These rows must be updated with current evidence before the work is described
as fully delivered:

| Gate | Current state | Required proof |
| --- | --- | --- |
| Pull request and CI | Complete | PR #138 merged at `b0217291fba7ec57544880ca7c4f7a5d7704a94c` after green checks |
| Signed Mac artifact | Complete | Run `29724433337`; version `1.0.57` downloaded, signature-checked, installed, launched, and healthy through loopback and Tailscale |
| Mac Calendar and Reminders access | Complete | Installed `1.0.57` reports `fullAccess` for both through the private diagnostic response |
| Internal TestFlight build | Complete | Run `29724514209`; Apple `VALID`, tester receipt ready, exact build `20260720072452` |
| Physical iPhone acceptance | Waiting for exact-build check-in | The paired production iPhone reported old build `20260720031027` at `2026-07-20T07:28:45Z`; install/open `20260720072452` for at least ten seconds and rerun strict acceptance |
| Direct-device visual proof | Optional and currently occluded | Unobscured iPhone Mirroring or a physical device visible to `devicectl` |

The paired production iPhone already has a production APNs token, Live
Activity push-to-start token, per-activity update token, and a recorded Live
Activity receipt. Those establish the previously shipped physical channel,
but do not substitute for the exact-build `20260720072452` check-in. The Mac
was locked and iPhone Mirroring reported `Connection Paused`; `devicectl`
listed only simulators. The strict report therefore correctly remains
`physical-gate-incomplete` instead of converting simulator or stale-device
evidence into a physical pass.
