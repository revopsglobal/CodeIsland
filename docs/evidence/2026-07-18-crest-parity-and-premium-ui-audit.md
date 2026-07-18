# Crest parity and premium UI audit — 2026-07-18

## Scope and evidence

This audit compares the current CodeIsland Mac app, native iPhone companion,
private web fallback, and signed delivery state against:

- Greg's supplied `Crest-4.9.0.dmg`;
- the current Crest modes and module catalog at
  <https://crestnotch.app/#modes>;
- the Crest changelog at <https://crestnotch.app/changelog>;
- the eight native CodeIsland iPhone renders produced by
  `scripts/smoke-companion-ui.sh`;
- the tracked CodeIsland source, tests, and delivery receipts.

The supplied DMG was inspected read-only. Its SHA-256 is
`e9da0a362f0262531e93189ecbac7ed42d6e778dcf554295b01183ccd8a8a66a`.
It contains universal version `4.9.0 (63)`, bundle
`com.zack40x.crest`, signed by Developer ID team `SA6A94K2Y4`, with a stapled
notarization ticket. The current website lists Crest 4.9.1; that update fixes
an invisible closed-notch window and does not add a new product module.

Pomodoro remains explicitly out of scope. Cross-app Notification Center
history is not treated as a parity requirement because macOS exposes no public
API for it. Telegram remains an optional outbound alert/deep-link fallback,
not a second control plane.

## Verdict

CodeIsland has reached **source-level parity with the useful Crest 4.9 module
catalog** and exceeds it in remote control, exact-request security, native
iPhone delivery, Live Activities, Dynamic Island, App Intents, Tailscale file
handoff, and a private web fallback.

The premium command-center remediation in this branch closes the audited
information-architecture gap: exact attention owns the iPhone Now surface,
routine context does not duplicate it, Tools is a compact native directory,
Sessions has one remote roster with progressive disclosure for nearby
controls, and Mac Tools renders one selected module instead of an equal-weight
card stack. The rejected beige cast and repeated green ready indicators are
removed in favor of neutral semantic surfaces and one signal accent.

It has **not reached blanket physical end-to-end completion**. The current
TestFlight build is now installed and registered; real Calendar read,
Reminders/Notes writes, reviewed question continuation, production APNs,
ActivityKit push-to-start, request-scoped update-token registration, terminal
cleanup, and stable foreground rendering are physically proven. Cellular
Tailscale and the named accessory/TCC mutation rows remain separate gates.

## Parity matrix

| Capability | Mac source | iPhone/away source | Final acceptance |
| --- | --- | --- | --- |
| Auto/Home/Work/Code, saved pins/order | Implemented | Implemented and remotely persisted | Physical cross-device mode/persistence run pending |
| Music artwork, progress, controls, seek, lyrics | Implemented | Mirrored controls/seek | Apple Music, transport, seek, and lyrics runtime pending |
| Calendar agenda/month/CRUD/Join | Implemented | Implemented with trusted Join | Current Calendar permission plus real CRUD/Join run pending |
| Tasks, lists, completion, notes, quick jot | Implemented | Implemented with reviewed writes | Replacement-build real task/note round trip pending |
| Shelf, clipboard, capture, downloads | Implemented | Authenticated transfer/share/copy/remove | Cellular Tailscale file round trip pending |
| Agent sessions, approvals, questions | Implemented | Exact, single-use remote actions | Current-build physical question review/answer passed; cellular approval and replay remain |
| System, weather, GitHub, audio, Bluetooth, battery, toggles | Implemented | Mirrored/confirmed host actions | Accessory, audio, GitHub, location, and toggle runtime pending |
| Camera/mic preflight, teleprompter, window snapping | Implemented | Useful remote/native equivalents | Physical permissions and multi-display/window runs pending |
| Push, Live Activity, Dynamic Island, App Intents | Host and APNs path implemented | Native extension and lifecycle implemented | Physical push-to-start, update-token registration, reviewed answer, resolution, and cleanup passed; clean current-build expanded artwork remains |
| Private web fallback | Implemented | Responsive Tailscale path | Physical mobile-browser actions pending |

The full feature-by-feature proof ledger remains in
`docs/crest-mobile-parity.md`. A module is not considered physically accepted
merely because its card renders or its test fixture passes.

## Baseline UI findings and resolution

The findings below were recorded from the pre-remediation native renders. The
seven presentation findings are resolved in the premium command-center branch;
the final transport-copy item remains intentionally visible during pairing and
connection repair, where the Tailscale distinction is actionable. The final
settled renders and test result bundle are the acceptance evidence.

### High — a pending approval is immediately duplicated

Evidence: `companion-ui-approval-light.png` shows the complete approval stage,
then a second `Today` agent row labeled `Waiting for approval` with a `Review`
button. `CompanionTodayTimeline` always includes the first Agents item even
when `RemoteApprovalSurface` already owns the exact request.

Impact: the same decision appears to be two separate objects. `Review` routes
to Sessions rather than the exact approval stage, which weakens trust and adds
an unnecessary navigation choice.

Required correction: when exact attention exists, the approval/question is
the only agent object on Now. Calendar and task context may remain below it,
but the generic Agents summary must be suppressed.

### High — More is still a card feed, not an Apple-quality tool directory

Evidence: `companion-ui-more-light.png` begins with a four-pill mode strip,
connection diagnostics, two oversized quick actions, day progress, and then
full Agents, GitHub, and Claude cards with repeated Refresh rows. The first
screen does not expose a concise module directory; it exposes internal rack
rendering.

Impact: tools take several screens to scan and every module receives equal
visual weight. The sheet is visually and structurally disconnected from the
calm Now destination.

Required correction: use native navigation hierarchy. The More root should
show mode context, a compact adaptive module directory, and settings. Opening
a module should navigate to its existing full module renderer. Keep Capture in
the dock and remove duplicate New Task/New Note buttons from the More root.

### High — Mac still presents Sessions, Glances, and Hub as peer products

Evidence: `NotchPanelView` renders `GlancesToggleRow`, then switches among
`SessionListView`, `GlancesView`, and `PersonalHubMacView`. The Hub itself uses
8–11 point labels, 25-point mode controls, uppercase machine typography, and a
full card for every module.

Impact: implementation-era nouns remain the primary mental model on Mac. Tiny
controls and dense cards may fit the notch but do not feel considered, legible,
or consistent with the iPhone command center.

Required correction: use one Mac hierarchy: Now, Today, Sessions, Tools.
Auto/Home/Work/Code remain a context selector inside Tools, not a competing
product navigation system. Exact approvals/questions preempt the default
surface; routine sessions never rotate.

### Medium — Capture remains the loudest dock action during urgent decisions

Evidence: the orange circular Capture control is visually dominant in every
state, including when an approval card is on screen.

Impact: a secondary creation action competes with the request that currently
needs a decision.

Required correction: reserve the signal accent for the current primary job.
Capture is prominent when idle and visually neutral while attention exists.

### Medium — the warm beige theme reproduces the rejected visual character

Evidence: `CITheme.background` explicitly describes the light appearance as
`off-white beige`; the user rejected the beige stacked-card visual language.

Impact: even after the card reduction, the entire app retains the color cast
of the rejected design.

Required correction: adopt semantic system-neutral backgrounds and materials.
Keep one CodeIsland signal accent, use semantic red only for destructive
actions, and avoid separate purple/blue/green/orange module branding on the
primary surface.

### Medium — the presence icon does not hold up at header size

Evidence: the rendered mascot is pale and pixel-soft at 36 points, while the
app name and connection status are crisp.

Impact: the first branded object appears lower quality than the native
typography around it.

Required correction: use a crisp vector/SF-symbol-based CodeIsland mark in the
presence header. Preserve mascots inside agent/session detail where their
identity has meaning.

### Medium — Sessions repeats nearby, recent, and remote state as three cards

Evidence: `companion-ui-sessions-light.png` shows a local session card, Recent
Activity, and a second Sessions card. Each is technically truthful, but they
read like independent products.

Impact: the user has to infer which connection owns which controls.

Required correction: compose one Sessions destination with a single title,
one active roster, progressive disclosure for transcript/recent activity, and
Live Activity as a contextual row action.

### Medium — polling and status copy still surface transport details

The current command center no longer animates routine four-second refreshes,
which is correct. However, pairing/offline surfaces still mention Tailscale,
nearby discovery, and local-vs-remote mechanisms more often than the normal
task requires.

Required correction: default to `Connected to Greg's Mac` or one repair
action. Put transport diagnostics behind Connection Details.

## Accepted design contract

### iPhone

- **Now**: one exact attention object, or a compact Today composition when
  idle. No duplicated agent summary.
- **Sessions**: one coherent roster with status, project, latest useful event,
  and contextual Live Activity/session actions.
- **Capture**: task/note entry in one native sheet.
- **More**: compact module directory grouped by Home, Work, and Code; full
  module content appears after navigation, not all at once.
- The bottom dock remains stable. Signal color follows attention priority.
- No routine polling animation, ornamental pulse, carousel, or blur/scale
  transition. Reduce Motion is authoritative.

### Mac

- Collapsed notch: one stable summary; attention preempts routine state.
- Expanded notch: exact attention first, otherwise Today.
- Sessions and Tools are secondary destinations.
- Auto/Home/Work/Code configure context inside Tools.
- Typography must remain legible without reducing all content to a dashboard;
  progressive disclosure is preferred over 8-point type.

### Visual language

- Semantic system backgrounds/materials, one warm signal accent, and a near
  black/white neutral scale.
- SF typography and symbols; monospaced text only for commands, identifiers,
  and machine metrics.
- Borders only where they communicate grouping; do not outline every nested
  object.
- Minimum 44 x 44 point iPhone targets and equivalent comfortable Mac hit
  regions.
- Color is never the only status cue. Light, dark, Dynamic Type, VoiceOver,
  and Reduce Motion are release gates.

## Completion gates

### Source and Simulator verification completed

- `scripts/smoke-companion-ui.sh` completed with a 20-second system settle
  gate and produced eight full-chrome native renders: idle, approval,
  question, multiple-attention, Sessions, Tools, light, and dark.
- The final iPhone result bundle at
  `/tmp/CodeIsland-premium-full-final-20260718-0415.xcresult` passed **39 of
  39** tests with zero failures, zero skips, and zero runtime warnings on the
  iPhone 16 Simulator running iOS 26.5.
- `swift test -j 1` completed with exit code 0 for the Mac/Core packages.
- `swift build -c release -j 1` completed with exit code 0 in 217.22 seconds.
- `graphify update . --no-viz` rebuilt the source graph at 4,732 nodes,
  12,357 edges, and 55 communities.

The remaining gates are signed distribution and physical-device acceptance;
they are intentionally not inferred from Simulator or source proof.

Source changes are complete only after:

1. new settled native renders for idle, approval, question, multi-attention,
   Sessions, More, light, and dark states;
2. the complete iPhone unit/UI scheme passes with no skips;
3. serial Mac/Core tests and a release build pass;
4. a signed Mac build and `VALID` TestFlight build are generated from the
   merged commit if native source changes;
5. the exact TestFlight build number registers from Greg's physical iPhone;
6. Calendar/Reminders permission, real Join, task/note creation, visible Live
   Activity/Dynamic Island, background push, and cellular Tailscale actions are
   accepted on the physical pair.

Until gates 5–6 pass, the accurate state is **implemented, automated, signed,
and distributed — not physically accepted end to end**.
