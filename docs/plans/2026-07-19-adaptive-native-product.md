# Adaptive Native Product Implementation Plan

> **Execution note:** Use the existing CodeIsland implementation plan and
> complete this work in its UI/physical-verification batches. Do not create a
> competing product branch.

**Goal:** Ship CodeIsland as an adaptive, Apple-native Mac and iPhone product,
including a new light/dark/tinted app icon, a signal-first information
architecture, event-driven presentation, accessible system materials, and
native/physical visual proof.

**Design contract:**
`docs/plans/2026-07-19-adaptive-native-product-design.md`

**Tech stack:** Swift 5.9+, SwiftUI, AppKit, UIKit asset catalogs, SF Symbols,
ActivityKit, WidgetKit, XCTest/XCUITest, XcodeGen, `sips`, and Xcode asset
compilation.

## Task A1: Add adaptive design primitives

**Files:**

- Create: `Sources/CodeIsland/CodeIslandDesignSystem.swift`
- Create: `ios/CodeIslandCompanion/Shared/CodeIslandDesignSystem.swift`
- Create: `Tests/CodeIslandTests/CodeIslandDesignSystemTests.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionTests/CodeIslandDesignSystemTests.swift`
- Modify: `ios/CodeIslandCompanion/project.yml`

1. Write failing tests for semantic status mapping, accessible label mapping,
   contrast-safe fallback selection, and Reduce Motion duration policy.
2. Run:

   ```bash
   swift test --filter CodeIslandDesignSystemTests
   DEVELOPER_DIR=/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer \
     xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
     -scheme CodeIslandCompanion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     -only-testing:CodeIslandCompanionTests/CodeIslandDesignSystemTests test
   ```

   Expect missing-symbol failures.
3. Implement semantic status, spacing, shape, typography-role, material, and
   motion primitives. Use system colors and styles; do not add an external font
   or a second hard-coded theme.
4. Regenerate the Xcode project and rerun the tests.
5. Commit: `feat: add adaptive native design system`.

## Task A2: Replace the iOS app icon with Paired Signal

**Files:**

- Create: `Design/AppIcon/paired-signal-light.svg`
- Create: `Design/AppIcon/paired-signal-dark.svg`
- Create: `Design/AppIcon/paired-signal-tinted.svg`
- Create: `Design/AppIcon/README.md`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Replace: `ios/CodeIslandCompanion/CodeIslandCompanion/Assets.xcassets/AppIcon.appiconset/*.png`
- Create: `scripts/generate-app-icons.sh`
- Create: `Tests/CodeIslandTests/AppIconAssetTests.swift`

1. Write a failing asset test that requires 1024×1024 light, dark, and tinted
   masters, an opaque alpha channel, declared luminosity appearances, complete
   legacy sizes, and stable source/master hashes.
2. Generate a concept study, then redraw the chosen Paired Signal geometry as
   deterministic SVG source. The shipping asset must not depend on a lossy
   generative file.
3. Render the three 1024 masters and all required legacy iPhone/iPad sizes.
   Keep the outer square unmasked and opaque.
4. Update `Contents.json` with universal iOS light/dark/tinted appearances while
   preserving legacy compatibility where required by the deployment target.
5. Inspect the masters and a contact sheet at 29, 40, and 60 pt equivalents.
6. Validate with:

   ```bash
   swift test --filter AppIconAssetTests
   DEVELOPER_DIR=/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer \
     xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
     -scheme CodeIslandCompanion -destination 'generic/platform=iOS Simulator' build
   ```

7. Commit: `design: replace iOS app icon`.

## Task A3: Rebuild the iPhone shell and connection state

**Files:**

- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/AppShellView.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/HostStatusView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionTests/ContentViewPresentationTests.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/AppShellUITests.swift`

1. Add failing presentation/UI tests for native Now/Sessions/Tools navigation,
   quiet healthy pairing, offline last-known data, expired pairing recovery,
   deep-link routing, Dynamic Type, and selected-tab restoration.
2. Replace the custom segmented shell with native adaptive navigation and a
   compact host-status affordance. Remove global forced color scheme.
3. Keep New Task in the toolbar and task-bound deep links in navigation state.
4. Run focused unit/UI tests in light and dark appearances.
5. Commit: `design: rebuild iPhone app shell`.

## Task A4: Make Now signal-first and stable

**Files:**

- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/NowView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/CompanionCommandCenterModel.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionTests/CompanionCommandCenterModelTests.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/NowViewUITests.swift`

1. Add failing tests for deterministic attention ordering, sticky equal-priority
   selection, queue display, compact all-clear, followed-task priority, and no
   timer-driven card rotation.
2. Implement a single primary attention item, secondary queue, calm all-clear,
   task-bound action UI, and stable offline/error states.
3. Remove any presentation timer that changes visible content without a model
   event or user input.
4. Run a ten-minute unattended UI test with two equal-priority sessions and
   assert no selection/flash changes.
5. Commit: `design: make Now signal first`.

## Task A5: Rebuild Sessions and completion review

**Files:**

- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/SessionsView.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteTaskDetailView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionTests/RemoteTaskPresentationTests.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/SessionsUITests.swift`

1. Test semantic grouping, search/filter, receipt ordering, changed-file and
   test evidence, exact approvals/questions, follow-up/stop, and completion
   review actions.
2. Implement native list/section/task-detail patterns. Use provider and
   workspace as metadata, not primary grouping.
3. Ensure `Verified` presentation requires zero-exit requested checks from the
   coordinator contract.
4. Run focused tests and capture native iPhone screenshots.
5. Commit: `design: rebuild task portfolio and review`.

## Task A6: Rebuild Tools and permission recovery

**Files:**

- Create: `ios/CodeIslandCompanion/CodeIslandCompanion/ToolsView.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift`
- Modify: `Sources/CodeIsland/PersonalHubMacView.swift`
- Modify: `Sources/CodeIsland/GlancesModel.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/ToolsUITests.swift`
- Modify: `Tests/CodeIslandTests/GlancesModelTests.swift`

1. Add failing tests for searchable module sections, honest permission states,
   explicit reminder-list filtering, calendar join availability, and manual
   weather city/ZIP fallback.
2. Implement the native Tools catalog and permission rows. Keep notes, capture,
   downloads, Bluetooth, media, Shelf, preflight, and teleprompter out of
   primary navigation.
3. Complete every adopted Crest utility requirement or record the exact
   unavailable platform API limitation in the parity audit.
4. Run unit/UI tests with granted, denied, restricted, offline, and empty
   fixtures.
5. Commit: `design: rebuild tools and permissions`.

## Task A7: Rebuild the Mac notch and expanded shell

**Files:**

- Modify: `Sources/CodeIsland/PersonalHubMacView.swift`
- Modify: `Sources/CodeIsland/NotchWindowController.swift`
- Modify: `Sources/CodeIsland/AppState.swift`
- Create: `Sources/CodeIsland/MacProductShellView.swift`
- Modify: `Tests/CodeIslandTests/NotchHoverInteractionTests.swift`
- Create: `Tests/CodeIslandTests/MacProductPresentationTests.swift`

1. Add failing tests for exact visible hit region, no hover focus theft, sticky
   attention, active/inactive appearance, prior destination restore, multiple
   display targeting, and no four-second UI rotation.
2. Replace timer-driven visible reloads with model events plus a debounced,
   non-animated reconciliation path.
3. Implement a quiet graphite collapsed state and a native resizable expanded
   shell using Now/Sessions/Tools semantics, Mac toolbar/sidebar, keyboard
   shortcuts, menus, popovers, and sheets.
4. Run tests plus native pointer, keyboard, VoiceOver, fullscreen, external
   display, sleep/wake, and reopen checks.
5. Commit: `design: rebuild Mac product shell`.

## Task A8: Align notifications, Live Activities, and Dynamic Island

**Files:**

- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionWidget/CodeIslandLiveActivityWidget.swift`
- Modify: `ios/CodeIslandCompanion/Shared/CodeIslandActivityAttributes.swift`
- Modify: `Sources/CodeIsland/APNSNotificationPayloadBuilder.swift`
- Modify: `ios/CodeIslandCompanion/CodeIslandCompanionTests/LiveActivityPrivacyTests.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/LiveActivityVisualTests.swift`

1. Test compact/minimal/expanded/Lock Screen hierarchy, redaction, stale-token
   recovery, exact task deep links, immediate terminal dismissal, and no prompt
   or attachment names in push-safe text.
2. Apply the shared semantic colors, typography, and provider-neutral Paired
   Signal identity while keeping content glanceable.
3. Capture ActivityKit simulator renders for every family and verify a physical
   Dynamic Island tap routes to authenticated current state.
4. Commit: `design: align live activity surfaces`.

## Task A9: Accessibility, visual regression, and physical proof

**Files:**

- Create: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/AccessibilityUITests.swift`
- Create: `ios/CodeIslandCompanion/CodeIslandCompanionUITests/VisualRegressionUITests.swift`
- Create: `Tests/CodeIslandTests/MacAccessibilityTests.swift`
- Create: `docs/acceptance/2026-07-19-adaptive-native-proof.md`

1. Exercise light/dark, increased contrast, reduced transparency, Reduce
   Motion, VoiceOver, large accessibility type, landscape, offline, empty,
   needs-you, failure, and verified states.
2. Build signed Mac and iPhone artifacts through the established CI/TestFlight
   path. Keep archive, upload, processing, tester availability, install, and
   physical verification as separate evidence.
3. On Greg's physical iPhone, prove pairing, new task, file/share capture,
   exact approval/question, follow-up, stop, test evidence, completion review,
   push, Live Activity, Dynamic Island, Wi-Fi, and cellular/Tailscale.
4. Run a ten-minute no-flash soak on both native platforms and capture the
   result.
5. Record exact build, commit, device, OS, timestamp, screenshots, commands,
   exit codes, and unresolved platform limitations.
6. Commit: `test: record adaptive native physical proof`.

## Integration order

Complete A1–A2 as independent visual foundations. Land A3–A6 with the remote
task coordinator/Buddy networking batch so the UI binds to real state rather
than fixtures. Land A7–A8 after provider runners and coordinator events are
stable. Task A9 is part of the final signed/physical E2E gate and cannot be
replaced by Simulator screenshots.
