# CodeIsland Adaptive Native Product Design

**Date:** 2026-07-19

**Status:** Approved by Greg

**Scope:** CodeIsland for macOS, CodeIsland Buddy for iPhone, Live Activities,
Dynamic Island, notifications, and the iOS app icon. Apple Watch and Pomodoro
are excluded.

## Outcome

CodeIsland should feel like one Apple product with two purpose-built surfaces,
not a Mac dashboard squeezed onto an iPhone and not a visual clone of Crest.
The Mac app is a quiet, notch-adjacent attention surface that expands into a
native utility. The iPhone app is the away-from-Mac command center for creating,
steering, approving, and verifying work.

The product promise is: **show Greg the one thing that needs him, preserve the
whole work portfolio one tap away, and make every consequential action exact and
recoverable.**

## Evidence and design decisions

The supplied Crest 4.9.0 build and its changelog establish a strong quality bar
for focused modules, quiet status, permission recovery, one-click meeting join,
utility breadth, persistence, and closed-notch hit testing. The detailed feature
disposition lives in
`docs/plans/2026-07-19-crest-changelog-dmg-parity-audit.md`.

Apple's current guidance reinforces the chosen direction:

- macOS interfaces should respect keyboard and pointing-device conventions,
  active and inactive windows, multiple displays, and native window behavior;
- adaptive system materials should retain legibility under increased contrast,
  reduced transparency, and changing appearance;
- Live Activities should show only essential, glanceable state across Lock
  Screen, compact, minimal, and expanded Dynamic Island presentations; and
- motion, type, controls, and color must remain usable with Reduce Motion,
  Dynamic Type, VoiceOver, and non-color status cues.

Primary references:

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/)

## Chosen direction: platform-native adaptive

The approved direction uses the same information architecture and semantic
color system on both platforms while letting each platform use its native
materials, navigation, density, and interaction model.

Rejected alternatives:

- **Dark Crest clone:** visually coherent but wrong for iPhone, overly dependent
  on the notch metaphor, and too close to a third-party product's expression.
- **Identical cross-platform shell:** superficially consistent but produces
  undersized Mac controls and an un-native iPhone hierarchy.
- **Dashboard-first app:** exposes lots of healthy state while hiding the few
  decisions Greg actually needs to make.

## Information architecture

The stable top-level destinations are:

1. **Now** — one ranked attention item, the deliberately followed task, or a
   calm all-clear state. Equal-priority items never rotate on a timer.
2. **Sessions** — the full Codex and Claude portfolio, grouped by `Needs You`,
   `Working`, `Verified`, and `History`, with search and provider/workspace
   filters.
3. **Tools** — calendar, reminders, weather, notes, downloads, Bluetooth,
   Now Playing, Shelf, preflight, teleprompter, and settings/permissions.

New task is a primary action, not a fourth destination. Approvals, questions,
failure recovery, and completion evidence open as task-bound detail sheets.

## Visual foundation

### Color

- Use Apple semantic backgrounds and labels as the base; never hard-code a warm
  light theme or force dark appearance globally.
- Keep one brand accent: `Signal Amber`. Amber means action is needed or an
  active selection—not generic decoration.
- Use system green for verified, system red for failed/destructive, system blue
  for neutral links and connectivity, and secondary label for routine state.
- Every status also has a symbol and text label; color alone never carries
  meaning.

### Materials

- Navigation, compact controls, and transient overlays may use current system
  glass/material APIs where available, with regular/ultra-thin material
  fallbacks on older OS releases.
- Task content, prompts, and evidence sit on readable opaque or grouped system
  backgrounds. Do not put long text on highly translucent glass.
- Respect Reduce Transparency and Increase Contrast without maintaining a
  separate visual fork.

### Typography and iconography

- Use San Francisco through semantic SwiftUI styles (`largeTitle`, `title2`,
  `headline`, `body`, `caption`) and Dynamic Type. Avoid a forest of hard-coded
  7–11 pt sizes.
- Reserve monospaced type for command fragments, file paths, timestamps,
  provider IDs, and test evidence.
- Use SF Symbols with variable color only when it conveys live state. Prefer
  familiar symbols and labels over custom glyphs.

### Geometry and spacing

- iPhone content uses an 8 pt rhythm, 16–20 pt horizontal margins, 44 pt minimum
  controls, and platform-native corner radii based on container role.
- Mac notch content is dense but never below accessible hit targets. Expanded
  content uses native list, grid, split-view, toolbar, menu, popover, and sheet
  patterns before custom cards.
- Depth comes from hierarchy and materials, not stacked borders and shadows.

## iOS app icon: Paired Signal

Replace the current tiny robot/notch artwork with a simple, high-recognition
mark that communicates connection and attention without text:

- two rounded island forms face each other and create a precise negative-space
  channel at the center;
- one restrained amber signal point identifies the active connection;
- the silhouette remains legible at 29–60 pt and in monochrome;
- the artwork fills the square safely and lets iOS apply the final icon mask;
- light, dark, and tinted appearances are designed intentionally rather than
  generated by automatic inversion; and
- there are no terminal characters, provider logos, tiny face details, bevels,
  or glossy skeuomorphic shadows.

The icon source must be deterministic and retained at 1024×1024. Smaller legacy
assets are generated from that master, inspected at actual size, and validated
by the asset compiler.

## iPhone behavior

### App shell

- Use a native tab bar for Now, Sessions, and Tools. New Task is available from
  the toolbar and an App Shortcut, not embedded as a permanently competing tab.
- The host/pairing state appears as a compact status affordance. Healthy pairing
  stays quiet; offline, expired, or wrong-host state expands with one recovery
  action and plain-language detail.
- Restore the last safe destination, but route a push, Live Activity, or deep
  link directly to its bound task after re-authentication.

### Now

- `Needs You` outranks followed work, failure, newly verified work, and routine
  working state.
- Show one primary item with the exact question or action, provider, workspace,
  age, and one primary response. Secondary items appear as a small queue, never
  a carousel.
- The all-clear state is compact and useful: pairing health, followed-task
  status if any, and the next calendar event. It does not fill the screen with
  decorative emptiness.

### Sessions and task detail

- Sessions are grouped by meaning, not by provider. Provider, workspace, and
  elapsed state are metadata.
- Task detail presents prompt summary, receipt timeline, changed files, test
  evidence, approval/question UI, follow-up composer, stop, and open-on-Mac.
- `Verified` is shown only after the requested checks actually exit zero.
- A completion review ends with explicit `Done`, `Follow up`, or `Open on Mac`;
  it never silently disappears.

### Tools

- Use a searchable native module list with sections for Today, Capture, Media,
  Device, and Setup.
- Permission rows show current truth, why CodeIsland needs the capability, and
  a single `Allow` or `Open Settings` recovery action.
- Calendar, reminders, weather, meeting join, note/task capture, Downloads,
  Bluetooth, Now Playing, Shelf, camera/microphone preflight, and teleprompter
  follow the Crest parity contract.

## macOS behavior

### Collapsed notch surface

- Graphite/black quiet surface, provider-neutral CodeIsland mark, and a single
  semantic state. Amber is reserved for `Needs You`; green appears briefly for
  verified; red is failure.
- The visible shape is the exact pointer, focus, and accessibility hit region.
  Hover never activates a larger invisible window or steals focus.
- An attention item is sticky until acted on. Healthy sessions never alternate
  every four seconds.

### Expanded surface

- Expand into the current display/space with a clear toolbar and one focused
  content area. Use the same Now, Sessions, and Tools model as iPhone, adapted
  to macOS split views, sidebars, menus, keyboard shortcuts, and resizable
  windows.
- The default expanded state opens the reason it expanded. Routine status and
  utilities remain one navigation action away.
- Permission recovery, calendar join, capture, portfolio, evidence, and module
  catalog share the iPhone vocabulary but use Mac-native controls.

## Motion and refresh

- Replace timer-driven card changes and visible polling reloads with published
  model changes, push/stream events, and debounced background reconciliation.
- No repeated four-second flash, alternating session card, blinking badge,
  restart-on-refresh animation, or decorative endless spinner.
- Use short native transitions only for user-initiated hierarchy changes and
  meaningful state changes. Reduce Motion uses fades or no animation.
- Connection loss preserves the last known content and adds a stable recovery
  banner instead of blanking and rebuilding the hierarchy.

## State and recovery design

Every primary surface must have designed states for:

- first launch and unpaired;
- pairing expired or wrong host;
- paired but Mac unavailable;
- offline with last-known data;
- empty/all clear;
- working;
- needs approval or an exact answer;
- failed with recoverable detail;
- verified with evidence;
- capability denied, restricted, read-only, or unavailable; and
- stale deep link or completed action token.

Each state explains what happened, what remains safe, and the next available
action. A generic spinner or `Try again` without cause is not acceptable.

## Acceptance contract

The redesign is complete only when:

- light, dark, tinted-icon, increased-contrast, reduced-transparency, Reduce
  Motion, VoiceOver, and large Dynamic Type states are exercised;
- the iOS asset catalog compiles and the icon is inspected at 29, 40, 60, and
  1024 pt equivalents;
- Mac collapsed hit testing, keyboard focus, hover, active/inactive window,
  multiple-display, fullscreen, sleep/wake, and reopen persistence pass;
- screenshots are captured from native Mac and iPhone builds, not a web mock;
- push and every Live Activity/Dynamic Island family open the correct task;
- a signed physical iPhone proves pairing, task creation, approval, follow-up,
  test evidence, completion review, Wi-Fi, and cellular/Tailscale behavior; and
- no timer-driven flashing or equal-priority session rotation occurs during a
  ten-minute unattended run.

