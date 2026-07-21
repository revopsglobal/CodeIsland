# Buddy command-center visual acceptance — 2026-07-18

This receipt covers the native iPhone information architecture and visual
system. It does not claim that the same source is installed on Greg's physical
iPhone; TestFlight delivery and physical-device acceptance remain separate.

## Accepted direction

- **Now** is the attention surface. It shows one approval or question at a
  time, keeps that selection stable across routine refreshes, and exposes the
  rest through an explicit queue menu.
- **Sessions** unifies the live nearby session controls and transcript with the
  authenticated Tailscale session roster. Pairing remotely never hides focus,
  approval, recent activity, or Live Activity controls.
- **Capture** is the single entry point for a new task or note.
- **More** contains the configurable Home, Work, and Code tool racks. The old
  Hub/Glances terminology is no longer part of the primary navigation.
- Motion is reserved for direct navigation and real state changes. A four-second
  data refresh does not animate or replace the command-center root.
- Light and dark appearances use the same semantic surfaces, typography,
  radii, touch targets, and orange action accent. iOS 26 and newer use native
  Liquid Glass for the bottom action dock; older iOS versions retain a material
  fallback.

## Native render receipt

Run from the repository root:

```sh
scripts/smoke-companion-ui.sh
```

The runner discovers an available custom-named iPhone Simulator, locates an
installed Xcode when `xcode-select` still points at Command Line Tools, builds
the current source, installs the correct bundle
`com.revopsglobal.codeisland.buddy`, warms the first installed launch, waits for
each system launch transition to settle, and writes these native-resolution
screenshots under `.build/`:

- `companion-ui-now-light.png`
- `companion-ui-approval-light.png`
- `companion-ui-question-light.png`
- `companion-ui-multiple-light.png`
- `companion-ui-sessions-light.png`
- `companion-ui-more-light.png`
- `companion-ui-now-dark.png`
- `companion-ui-more-dark.png`

The 2026-07-18 acceptance run used simulator
`ECC99681-C3ED-4452-B727-0F9E2C09C469` (iPhone 16, iOS 26.5) and completed all
eight renders successfully. Visual inspection confirmed:

- no beige stacked-card shell;
- no always-visible Auto/Home/Work/Code strip on the primary surface;
- no repeated approval/question carousel;
- a single dominant approval or decision stage with explicit context;
- 48-point action controls with destructive and primary roles separated;
- readable light and dark appearances;
- a persistent safe-area-aware native action dock;
- Sessions and More using the same design language as Now.

## Automated acceptance

- Generic iOS Simulator build: passed.
- `testApprovalAttentionStageKeepsExactActionsProminent`: passed.
- `testQuestionAttentionStageUsesNativeSelectionAndSubmit`: passed.
- `testMultipleAttentionItemsDoNotRotateAutomatically`: passed, including a
  wait longer than the former four-second refresh interval.
- Attention result bundle:
  `/tmp/codeisland-attention-dd/Logs/Test/Test-CodeIslandCompanion-2026.07.18_02-29-17--0700.xcresult`.
- `testSessionsUsesAuthenticatedTailscaleInsteadOfNearbyDiscovery`: passed.
- `testPersonalHubModesRenderAdvertisedModules`: passed for the Home, Work, and
  Code racks.
- Tool-rack result bundle:
  `/tmp/codeisland-hub-dd/Logs/Test/Test-CodeIslandCompanion-2026.07.18_02-35-42--0700.xcresult`.
- Six restored session/action regressions passed together: question controls,
  long transcript scrolling, idle controls, Live Activity resolution, rack
  review, and Claude Do review. Result bundle:
  `/tmp/CodeIsland-buddy-six-20260718-025701.xcresult`.
- The authenticated Sessions accessibility contract passed after removing a
  redundant parent grouping that hid the child section from VoiceOver and UI
  automation. Result bundle:
  `/tmp/CodeIsland-buddy-sessions-fix-20260718-030901.xcresult`.
- Complete native scheme: **39 passed, 0 failed, 0 skipped** in one run on the
  iPhone 16 / iOS 26.5 Simulator. Result bundle:
  `/tmp/CodeIsland-buddy-full3-20260718-030951.xcresult`.

## Remaining delivery boundary

These renders and tests prove native Simulator behavior from current source.
They do not prove a signed TestFlight install, current physical-iPhone build
number, cellular/Tailscale behavior, push wake, Live Activity/Dynamic Island
visibility, or a real approval/task/calendar mutation on this replacement
build. Those are tracked as later delivery and physical E2E gates.

## Retired outbound Telegram fallback — historical receipt from 2026-07-18

This is retained only as historical evidence. Telegram runtime/settings were
removed in 1.0.62; Buddy APNs and Live Activities are now the sole away-attention
path.

CodeIsland had an optional Telegram fallback in the Mac Buddy settings. It was
deliberately attention-only: new pending approvals and questions could produce a
redacted outbound Telegram message, but routine session changes, resolved events,
commands, transcripts, workspaces, request IDs, and tool payloads were not sent.

Verification:

- `DEVELOPER_DIR=/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer swift test --filter APNSNotificationSenderTests`
- Result: **6 passed, 0 failed**.

This was a source-level and unit-test receipt only. No real Telegram message was
sent, because that would require Greg's bot token/chat ID and an explicit
configured personal alert target.

## Attention fallback delivery — 2026-07-18 evening

Implementation PR: [#67](https://github.com/revopsglobal/CodeIsland/pull/67)
merged to `main` as `c1d5cf536e3d6d7687d53a5db96542485476b566`.

Source verification before merge:

- `DEVELOPER_DIR=/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer swift test --filter APNSNotificationSenderTests`
- Result: **6 passed, 0 failed**.
- `STRICT=0 EXPECTED_MAC_VERSION=1.0.53 EXPECTED_CLIENT_VERSION=1.0.0 EXPECTED_CLIENT_BUILD=20260719001734 scripts/report-physical-acceptance.sh | jq '.gates.physicalBuildStatus'`
- `graphify update . --no-viz`
- `git diff --check`

Signed Mac delivery from `main`:

- Workflow: [Build macOS ARM DMG run 29667371137](https://github.com/revopsglobal/CodeIsland/actions/runs/29667371137)
- Source commit: `c1d5cf536e3d6d7687d53a5db96542485476b566`
- Result: **success**.
- Artifact: `CodeIsland-macos-arm64-dmg`, artifact ID `8436194546`.
- Uploaded artifact zip SHA-256: `661a6ab3240fb6c947131e8ec48239c372183d9d89d9c5d3d0cb3f5866f96378`.
- Downloaded DMG SHA-256: `65953f22a2d44a1cd0bf2296f53a8709b1e13239c54a85791bd6ae0b585686b9`.
- Local DMG: `/Users/gregharned/Downloads/CodeIsland-telegram-fallback-29667371137-174812/CodeIsland-macos-arm64-dmg/CodeIsland.dmg`.
- Installed app: `/Applications/CodeIsland.app`.
- Installed version/build: `1.0.53` / `1.0.53`.
- Installed signature: valid, TeamIdentifier `44JG2Y95CH`, Authority `Apple Development: Greg Harned (BD6FD6Q8AS)`.
- Local health after launch: HTTP 200, `running: true`, `pendingCount: 0`, host version `1.0.53`.
- Tailscale health after launch: HTTP 200 at `https://gregs-macbook-air.tail62f27c.ts.net:9443/health`, `running: true`, `pendingCount: 0`.

Signed Buddy/TestFlight delivery from `main`:

- Workflow: [Build and Upload iOS TestFlight run 29667371841](https://github.com/revopsglobal/CodeIsland/actions/runs/29667371841)
- Source commit: `c1d5cf536e3d6d7687d53a5db96542485476b566`
- Result: **success**.
- Tester receipt: `gregharned@gmail.com`, state `ready`, app `com.revopsglobal.codeisland.buddy`, app ID `6791897500`, group `CodeIsland Internal`, group ID `8db9e637-03e3-4147-afda-895700e127c8`.
- Buddy build: `1.0.0 (20260719004222)`.
- Delivery UUID: `3e7203b8-8dd7-4ba1-ba57-7814853dcc40`.
- Apple state: `VALID`.
- Audience: `APP_STORE_ELIGIBLE`.
- Internal group access: `CodeIsland Internal` has access to all builds.
- Artifact: `CodeIsland-Buddy-TestFlight-20260719004222`, artifact ID `8436181146`.
- Uploaded artifact zip SHA-256: `17747254cdf38e727cc390ac2e123f4a649052f90c66f6a1335ae8423d2bc587`.
- Downloaded IPA SHA-256: `2cd1a35a0a1bd0f8ec3dab2c8203f9cd2a1668c14e7734e10595b73a686bc14c`.
- Local IPA: `/Users/gregharned/Downloads/CodeIsland-TestFlight-29667371841-174812/CodeIsland-Buddy-TestFlight-20260719004222/CodeIslandCompanion.ipa`.

Remaining physical-device boundary:

- The newest Buddy build `20260719004222` is valid in TestFlight, but it has
  not yet been observed from Greg's physical iPhone.
- `scripts/report-physical-acceptance.sh` currently reports physical build
  status `stale`.
- Expected physical Buddy: `1.0.0 (20260719004222)`.
- Newest observed physical Buddy: `1.0.0 (20260718212803)`.
- Newest observed physical device: `afba2915-b0a3-456f-a5f2-265bf7e8a64a`
  (`iPhone`), last seen `2026-07-19T00:17:23Z`.

Next physical acceptance step: install/open CodeIsland Buddy build
`20260719004222` from TestFlight on the iPhone, then rerun strict physical
acceptance with `EXPECTED_CLIENT_BUILD=20260719004222`.

## Current-main parity validator delivery — 2026-07-18 evening

Implementation PR: [#69](https://github.com/revopsglobal/CodeIsland/pull/69)
merged to `main` as `33fc732043fa93b132a740d478c5bcc2899c47df`.

Source verification before merge:

- `DEVELOPER_DIR=/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer swift test --filter PersonalHubProtocolTests`
- Result: **27 passed, 0 failed**.
- `DEVELOPER_DIR=/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer swift test --filter RemoteApprovalHTTPServerTests/testAuthenticatedHostLifecycleOverRealListener`
- Result: **1 passed, 0 failed**.
- `STRICT=0 EXPECTED_MAC_VERSION=1.0.53 EXPECTED_CLIENT_VERSION=1.0.0 EXPECTED_CLIENT_BUILD=20260719004222 scripts/report-physical-acceptance.sh | jq '.gates.physicalBuildStatus'`
- `graphify update . --no-viz`
- `git diff --check`

Signed Mac delivery from `main`:

- Workflow: [Build macOS ARM DMG run 29667770216](https://github.com/revopsglobal/CodeIsland/actions/runs/29667770216)
- Source commit: `33fc732043fa93b132a740d478c5bcc2899c47df`
- Result: **success**.
- Artifact: `CodeIsland-macos-arm64-dmg`, artifact ID `8436322662`.
- Uploaded artifact zip SHA-256: `5a42af01be5f6677cf824b25ee57e86781094a12b0dcd65f8b062f35b5a4bd66`.
- Downloaded DMG SHA-256: `7109cc4a7ba2ab2f38683b4e8d87f11bffe742db24d506c97f0cd5a630ace71e`.
- Local DMG: `/Users/gregharned/Downloads/CodeIsland-main-33fc732-mac-29667770216-180132/CodeIsland-macos-arm64-dmg/CodeIsland.dmg`.
- Installed app: `/Applications/CodeIsland.app`.
- Installed version/build: `1.0.53` / `1.0.53`.
- Installed signature: valid, TeamIdentifier `44JG2Y95CH`, Authority `Apple Development: Greg Harned (BD6FD6Q8AS)`.
- Local health after launch: HTTP 200, `running: true`, `pendingCount: 0`, host version `1.0.53`.
- Tailscale health after launch: HTTP 200, `running: true`, `pendingCount: 0`.

Signed Buddy/TestFlight delivery from `main`:

- Workflow: [Build and Upload iOS TestFlight run 29667770858](https://github.com/revopsglobal/CodeIsland/actions/runs/29667770858)
- Source commit: `33fc732043fa93b132a740d478c5bcc2899c47df`
- Result: **success**.
- Tester receipt: `gregharned@gmail.com`, state `ready`, app `com.revopsglobal.codeisland.buddy`, app ID `6791897500`, group `CodeIsland Internal`, group ID `8db9e637-03e3-4147-afda-895700e127c8`.
- Buddy build: `1.0.0 (20260719005630)`.
- Delivery UUID: `3a9151da-3662-407b-84c0-feb81de00b2f`.
- Apple state: `VALID`.
- Audience: `APP_STORE_ELIGIBLE`.
- Internal group access: `CodeIsland Internal` has access to all builds.
- Artifact: `CodeIsland-Buddy-TestFlight-20260719005630`, artifact ID `8436310864`.
- Uploaded artifact zip SHA-256: `7af4647807d90f6aa29ab15dd79b1751ae80e3ad11989533f91802b5a3b8ea81`.
- Downloaded IPA SHA-256: `9d45a1ecbbe2b245e2d088d45e2f37665fe9f96385448ac55ef2bba2e5f0f987`.
- Local IPA: `/Users/gregharned/Downloads/CodeIsland-main-33fc732-ios-29667770858-180132/CodeIsland-Buddy-TestFlight-20260719005630/CodeIslandCompanion.ipa`.

Remaining physical-device boundary:

- The newest Buddy build `20260719005630` is valid in TestFlight, but it has
  not yet been observed from Greg's physical iPhone.
- `scripts/report-physical-acceptance.sh` currently reports physical build
  status `stale`.
- Expected physical Buddy: `1.0.0 (20260719005630)`.
- Newest observed physical Buddy: `1.0.0 (20260718212803)`.
- Newest observed physical device: `afba2915-b0a3-456f-a5f2-265bf7e8a64a`
  (`iPhone`), last seen `2026-07-19T00:17:23Z`.

Next physical acceptance step: install/open CodeIsland Buddy build
`20260719005630` from TestFlight on the iPhone, then rerun strict physical
acceptance with `EXPECTED_CLIENT_BUILD=20260719005630`.

## Transport-copy polish delivery — 2026-07-18 night

Source PR #72 merged as
`5ccefcd8683ad2ce22ac833f4c16e153df3df8fc`. The change keeps Buddy's primary
connection, pairing, loading, invalid-URL, and Sessions copy focused on
`Greg's Mac` while keeping the private URL available inside Connection
settings. This is a copy/IA polish only; it does not change the private
Tailscale transport.

Focused verification before merge:

- `CodeIslandCompanionTests/LiveActivityPrivacyTests`: **10 passed, 0 failed**.
- `CodeIslandCompanionUITests/testAuthenticatedTailscaleConnectionDoesNotLookLikeNearbySearch`:
  **1 passed, 0 failed**.
- Simulator: `ECC99681-C3ED-4452-B727-0F9E2C09C469`.
- `git diff --check`.
- `graphify update . --no-viz`.

Signed Mac delivery from `main`:

- Workflow: [Build macOS ARM DMG run 29668328492](https://github.com/revopsglobal/CodeIsland/actions/runs/29668328492)
- Source commit: `5ccefcd8683ad2ce22ac833f4c16e153df3df8fc`
- Result: **success**.
- Artifact: `CodeIsland-macos-arm64-dmg`, artifact ID `8436497566`.
- Uploaded artifact zip SHA-256:
  `527c5fec329cccdb21a4a6467b5595ffdf93cfe3947dda3a24e54e0fa0496c07`.
- Downloaded DMG SHA-256:
  `320fcc5ebb42557353e0a1882549ade0fdcc8854cc635bf37b2ee6b911723be8`.
- Local DMG:
  `/Users/gregharned/Downloads/CodeIsland-main-5ccefcd-mac-29668328492-182154/CodeIsland-macos-arm64-dmg/CodeIsland.dmg`.
- Installed app: `/Applications/CodeIsland.app`.
- Installed version/build: `1.0.53` / `1.0.53`.
- Installed signature: valid, TeamIdentifier `44JG2Y95CH`, CDHash
  `24cb7ea82cb63f169a23bc8f1e04476e311bd9c8`, Authority
  `Apple Development: Greg Harned (BD6FD6Q8AS)`.
- Local health after launch: HTTP 200, `running: true`, `pendingCount: 0`,
  host version `1.0.53`.
- Tailscale health after launch: HTTP 200, `running: true`,
  `pendingCount: 0`.

Signed Buddy/TestFlight delivery from `main`:

- Workflow: [Build and Upload iOS TestFlight run 29668329068](https://github.com/revopsglobal/CodeIsland/actions/runs/29668329068)
- Source commit: `5ccefcd8683ad2ce22ac833f4c16e153df3df8fc`
- Result: **success**.
- Tester receipt: `gregharned@gmail.com`, state `ready`, app
  `com.revopsglobal.codeisland.buddy`, app ID `6791897500`, group
  `CodeIsland Internal`, group ID `8db9e637-03e3-4147-afda-895700e127c8`.
- Buddy build: `1.0.0 (20260719011702)`.
- Delivery UUID: `c8dcbe08-5e61-4a0e-b27f-7abb19067009`.
- Apple state: `VALID`.
- Audience: `APP_STORE_ELIGIBLE`.
- Internal group access: `CodeIsland Internal` has access to all builds.
- Artifact: `CodeIsland-Buddy-TestFlight-20260719011702`, artifact ID
  `8436493328`.
- Downloaded IPA SHA-256:
  `9e781be9b126a34ab43c1a3cfd7ae2a778d3f647efc01c3ad232aa302dbf59cd`.
- Local IPA:
  `/Users/gregharned/Downloads/CodeIsland-main-5ccefcd-ios-29668329068-182154/CodeIsland-Buddy-TestFlight-20260719011702/CodeIslandCompanion.ipa`.

Remaining physical-device boundary:

- `scripts/report-latest-testflight-physical-gate.sh` exits `2` because the
  physical iPhone has not opened the latest TestFlight build.
- Expected physical Buddy: `1.0.0 (20260719011702)`.
- Newest observed physical Buddy: `1.0.0 (20260718212803)`.
- Newest observed physical device: `afba2915-b0a3-456f-a5f2-265bf7e8a64a`
  (`iPhone`), last seen `2026-07-19T00:17:23Z`.

Next physical acceptance step: install/open CodeIsland Buddy build
`20260719011702` from TestFlight on the iPhone, then rerun strict physical
acceptance with `EXPECTED_CLIENT_BUILD=20260719011702`.

## Glances inline recovery delivery — 2026-07-18 night

Source PR #74 merged as
`b12ad84607ecf3938712d8333e877d23a367b60d`. The change makes Mac Glances
permission and weather recovery direct from the panel: Calendar shows
Grant/Upgrade/Privacy, Reminders shows Grant/Privacy, and Weather shows
Grant/Privacy or Set ZIP depending on the current Location Services/manual
location state. This preserves the full Glances Settings page while removing
one layer of discovery from the common failure states.

Focused verification before merge:

- `DEVELOPER_DIR=/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer swift test --filter GlancesModelTests`
- Result: **15 passed, 0 failed**.
- `graphify update . --no-viz`.
- `git diff --check`.

Signed Mac delivery from `main`:

- Workflow: [Build macOS ARM DMG run 29668659780](https://github.com/revopsglobal/CodeIsland/actions/runs/29668659780)
- Source commit: `b12ad84607ecf3938712d8333e877d23a367b60d`
- Result: **success**.
- Artifact: `CodeIsland-macos-arm64-dmg`, artifact ID `8436600885`.
- Uploaded artifact zip SHA-256:
  `57b594dbd854d449482a2c0d80236dfebe50dc6e72a291c0cc70e9bb01f9dfa5`.
- Downloaded DMG SHA-256:
  `f25352a62d7b3d5c75dc4c0c7a01e1933b828c01f2045c5ddb5fb2f2b0b7da95`.
- Local DMG:
  `/Users/gregharned/Downloads/CodeIsland-main-b12ad84-mac-29668659780-183452/CodeIsland-macos-arm64-dmg/CodeIsland.dmg`.
- Installed app: `/Applications/CodeIsland.app`.
- Installed version/build: `1.0.53` / `1.0.53`.
- Installed signature: valid, TeamIdentifier `44JG2Y95CH`, CDHash
  `f026ef64aee13e297d0d5c6696bd6b109579f1ef`, Authority
  `Apple Development: Greg Harned (BD6FD6Q8AS)`.
- Local health after launch: HTTP 200, `running: true`, `pendingCount: 0`,
  host version `1.0.53`.
- Tailscale health after launch: HTTP 200, `running: true`,
  `pendingCount: 0`.

No new TestFlight build was generated for PR #74 because this was Mac-only
Glances UI source. The latest valid Buddy build remains `20260719011702`, and
the physical iPhone remains stale until that build is installed/opened.
