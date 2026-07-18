# Buddy Quiet Command Center Design

**Date:** 2026-07-18

**Status:** Approved by delegation and continuation of the approved Crest/mobile completion design

**Product:** CodeIsland Buddy for iPhone

## Outcome

Buddy becomes Greg's calm, native command center when he is away from the Mac.
The first screen answers one question immediately: **does anything need Greg
right now?** If the answer is yes, the exact approval or question becomes the
dominant surface. If the answer is no, the interface stays quiet and exposes a
compact personal timeline plus fast capture.

This design replaces the rejected TestFlight presentation that stacked a Mac
status card, a generic segmented control, and a small Today card above a large
unused beige canvas. It retains the existing typed action contract, pairing,
Tailscale transport, Live Activities, Dynamic Island, sessions, modules, and
native quick-jot behavior.

## Product context

- **Audience:** Greg, as the only intended user.
- **Use context:** one-handed iPhone use at home or away, often to resolve an
  agent decision quickly without opening the Mac.
- **Primary jobs:** notice approvals/questions, act safely, see current agent
  work, join the next meeting, capture a task/note, and reach less frequent
  utilities.
- **Tone:** quiet, precise, confident, personal, and unmistakably native to
  current iOS. It should feel designed by Apple for one person rather than like
  a generic operations dashboard.

## Chosen direction

### Quiet Command Center

The visual system is content-first soft structuralism with a warm adaptive
canvas. System typography, semantic color, native materials, concentric
squircles, and restrained depth replace repetitive bordered cards. Liquid
Glass is reserved for the navigation/action layer; it is not applied to every
content container.

Two alternatives were rejected:

1. **Dynamic Island Control Deck:** visually dramatic and Crest-like, but too
   dark and technical for an all-day personal surface.
2. **Personal Concierge:** warmer and more editorial, but too weak at making
   agent attention and remote actions unmissable.

## Information architecture

### 1. Presence header

The top header is a compact identity and connection surface, not a toolbar
full of equal-weight controls.

- Leading: CodeIsland mark plus the active Mac/session identity.
- Secondary line: `Connected to Greg's MacBook Air`, `Connecting`, or one
  specific recovery status.
- Trailing: a single semantic connection indicator.
- Appearance and discovery actions move into a context menu; they do not
  occupy permanent 44-point tiles on the primary canvas.

### 2. Attention stage

Approvals and questions render before all personal content.

- One pending item becomes a large, high-contrast action stage with source,
  request, workspace, age, exact detail, and safe decision controls.
- Multiple pending items show the highest-priority item plus a clear count and
  a queue affordance; they never rotate automatically.
- Approval uses amber for attention and green only for the affirmative action.
- Question uses system blue for selection and submission.
- Confirmation remains the existing exact, single-use host validation flow.
- Resolved content leaves without a decorative success loop.

When nothing is pending, there is no empty approval card. A compact `All clear`
status is integrated into the Today heading and consumes minimal vertical
space.

### 3. Today timeline

The default screen is a semantic timeline rather than a generic container.

- Large date/greeting title and concise weather line establish context.
- Calendar, reminder, and agent signals use aligned time/icon rails.
- The next joinable meeting gets the only prominent inline action.
- Low-value timestamps and repeated source labels are removed.
- Empty state copy is concise: `Nothing needs you right now.`

### 4. Reachable action dock

A bottom-safe-area dock contains the frequent destinations:

- Now
- Sessions
- Capture
- More

On iOS 26 and later, the dock uses native Liquid Glass with interactive system
button styles. Earlier versions use a system material fallback. Capture opens
native task/note choices. More opens the existing full module surface in a
single NavigationStack and a single ScrollView.

### 5. Sessions and utilities

- Sessions is an explicit destination, not a competing top tab.
- It prioritizes sessions that need approval, a question, or a user decision;
  routine activity remains stable and secondary.
- More preserves full Crest/mobile module parity: Calendar, Reminders,
  Downloads, Shelf, media, system state, notifications, Bluetooth battery,
  camera/mic preflight, Claude, teleprompter, and configuration.
- No capability is removed to simplify the default screen.

## Visual system

### Typography

- Use native semantic text styles and San Francisco; respect Dynamic Type.
- Prefer `.rounded` only for short status numerals or compact identity, not for
  all prose.
- Monospaced text is limited to code, a short build identifier, or a terminal
  detail. Location, weather, dates, and navigation never use monospace.
- Primary title, attention prompt, row title, and metadata must form four
  visibly distinct levels.

### Color

- Canvas: adaptive warm system-adjacent neutral, less yellow than the rejected
  build and never pure white/black.
- Primary ink: high-contrast adaptive neutral.
- Amber: pending approval or time-sensitive attention only.
- Blue: question selection and neutral navigation state.
- Green: confirmed connection or successful affirmative completion only.
- Red: destructive denial or unrecoverable error only.
- Every semantic state remains legible without color through iconography and
  text.

### Shape and depth

- Use 20-28 point continuous corner radii aligned with the device silhouette.
- Prefer grouped content and separators over placing every row inside a card.
- Use one content elevation level and one floating navigation elevation level.
- Avoid generic gray one-pixel borders; rely on material contrast, subtle
  highlights, and only necessary separators.

### Motion

- Routine four-second polling is visually inert.
- Do not set the entire screen to `connecting` after the first authenticated
  snapshot.
- New attention may enter once with an opacity/transform transition.
- User-selected navigation and confirmed actions use restrained spring motion.
- No automatic carousel, pulsing normal-work indicator, blur-morph on unchanged
  content, or timeline animation.
- Reduce Motion removes nonessential transitions.

## State and data flow

`RemoteApprovalClient` remains the single remote state owner. The view derives a
small presentation model from stable inputs:

1. connection presentation;
2. ordered pending attention;
3. Today timeline rows;
4. selected primary destination; and
5. presented sheet/destination.

Polling may update timestamps and data without resetting navigation, replacing
stable containers, or triggering root-level animation. List identity is based
on stable request/module/item IDs. View-owned navigation state remains local.

## Error handling

- **Mac offline:** keep last authenticated content visible, add one compact
  offline banner, and expose Retry.
- **Unpaired:** show the focused pairing flow as the primary screen.
- **Permission limitation:** show the specific module and its recovery action.
- **Stale/expired action:** dismiss the proposal, refresh, and explain that the
  Mac changed rather than reporting a generic failure.
- **No data:** use intentional, brief empty states without a large blank card.
- **Older iOS:** use native materials and standard bordered/prominent buttons
  instead of custom Liquid Glass.

## Accessibility

- Minimum 44 by 44 point interactive targets.
- Dynamic Type through accessibility sizes without clipping action copy.
- VoiceOver order follows presence, attention, Today, then dock.
- Selected destination, pending count, connectivity, and destructive action
  are conveyed in labels, not only visually.
- Differentiate Without Color, Increase Contrast, Reduce Transparency, and
  Reduce Motion remain supported through native system behavior and explicit
  fallbacks.

## Verification and acceptance

The redesign is accepted only when all of the following are true:

1. A rendered native iPhone screenshot no longer exhibits the rejected stacked
   toolbar/segmented-card/empty-beige composition.
2. Clear, approval, question, offline, unpaired, Sessions, and More states have
   UI-test coverage and retained screenshots.
3. A paired settled screen remains pixel-stable across at least three
   consecutive four-second polls except for legitimate time text.
4. No pending item rotates automatically; the same item remains selected until
   Greg acts or deliberately changes it.
5. Dynamic Type, Dark Mode, Reduce Motion, and Increase Contrast smoke checks
   remain usable.
6. Existing exact confirmation, replay rejection, App Intent, push, Live
   Activity, Dynamic Island, task/note capture, Calendar Join, and file handoff
   behavior remains intact.
7. The signed TestFlight build is visible, installed, reports its exact version
   and build to the paired Mac, and passes the physical Wi-Fi and cellular
   Tailscale acceptance matrix.

Implementation, CI, Apple `VALID`, TestFlight availability, physical install,
and physical interaction proof remain separate states in completion reporting.
