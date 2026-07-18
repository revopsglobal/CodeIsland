# Buddy command-center visual acceptance — 2026-07-18

This receipt covers the native iPhone information architecture and visual
system. It does not claim that the same source is installed on Greg's physical
iPhone; TestFlight delivery and physical-device acceptance remain separate.

## Accepted direction

- **Now** is the attention surface. It shows one approval or question at a
  time, keeps that selection stable across routine refreshes, and exposes the
  rest through an explicit queue menu.
- **Sessions** is a focused authenticated Tailscale session board, not a second
  dashboard and not a nearby-Bluetooth discovery substitute.
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
`com.revopsglobal.codeisland.buddy`, waits for the system launch transition to
settle, and writes these native-resolution screenshots under `.build/`:

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

## Remaining delivery boundary

These renders and tests prove native Simulator behavior from current source.
They do not prove a signed TestFlight install, current physical-iPhone build
number, cellular/Tailscale behavior, push wake, Live Activity/Dynamic Island
visibility, or a real approval/task/calendar mutation on this replacement
build. Those are tracked as later delivery and physical E2E gates.
