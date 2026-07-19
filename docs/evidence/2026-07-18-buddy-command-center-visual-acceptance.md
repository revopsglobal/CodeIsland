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
