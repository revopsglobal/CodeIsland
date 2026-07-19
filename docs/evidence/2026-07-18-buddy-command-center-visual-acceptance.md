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

## Outbound Telegram fallback — 2026-07-18

CodeIsland now has an optional Telegram fallback in the Mac Buddy settings. It
is deliberately attention-only: new pending approvals and questions can produce
a redacted outbound Telegram message, but routine session changes, resolved
events, commands, transcripts, workspaces, request IDs, and tool payloads are not
sent.

Verification:

- `DEVELOPER_DIR=/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer swift test --filter APNSNotificationSenderTests`
- Result: **6 passed, 0 failed**.

This is a source-level and unit-test receipt only. No real Telegram message was
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
