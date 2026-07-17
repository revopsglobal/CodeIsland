# CodeIsland completion UI audit

Date: 2026-07-17  
Scope: signed macOS app, native iPhone companion, private Tailscale web fallback, Live Activities, Dynamic Island, and push-notification routing  
Audience: Greg's private single-user installation

## Anti-pattern verdict

The product is functionally substantial and technically credible, but its primary surfaces still read as a dense developer dashboard instead of a quiet personal Apple product. The main cause is information architecture, not color or corner radius: approvals, session state, utilities, and connection diagnostics are presented as peer cards. On iPhone this produces a long feed in which the one item that needs an immediate decision can be visually buried. On Mac, `Sessions`, `Glances`, and `Hub` expose implementation-era nouns instead of the user's jobs.

The product should keep its current secure transport and feature depth, while presenting one shared model everywhere:

1. **Now** — only items that need Greg now: approval, question, meeting join, failure, or completed work worth reviewing.
2. **Today** — calendar, reminders, weather, and current focus.
3. **Sessions** — stable, user-selected agent status. Routine sessions never carousel.
4. **Tools** — shelf, downloads, clipboard, media, teleprompter, camera/mic preflight, Claude, and settings.

`Hub` and `Glances` remain useful implementation groupings, but should not remain top-level user-facing destinations.

## Executive summary

- Product readiness score: **68/100** before the completion redesign.
- Functional foundation: **strong**. Exact-request approval tokens, Tailscale pairing, APNs registration, Live Activity lifecycle handling, deep links, and one-click meeting join exist.
- Interaction quality: **incomplete**. The native app duplicates pairing/connection concepts, several primary controls are smaller than Apple's recommended iPhone target size, and the private web surface uses blocking browser prompts for core actions.
- Visual hierarchy: **incomplete**. Repeated dark cards, uppercase monospaced labels, borders, and status colors flatten the hierarchy and make all modules feel equally urgent.
- Verification: **strong in automation and Simulator; pending on Greg's physical iPhone**. A signed TestFlight build is valid and available internally, but cellular/Tailscale, APNs receipt, Dynamic Island, Calendar/Location TCC, and real-device pairing cannot be truthfully accepted without device taps.

Finding count:

| Severity | Count |
| --- | ---: |
| High | 3 |
| Medium | 7 |
| Low | 3 |

## Detailed findings

### High 1 — The action that needs attention is not the dominant mobile object

- **Location:** `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift:96`, `Sources/CodeIsland/RemoteApprovalWebApp.swift:162`
- **Category:** information architecture, hierarchy
- **Evidence:** the portrait iPhone stack renders the compact bar, remote approvals, the entire personal hub, live session card, personal status, and recent activity as consecutive peer surfaces. The private web fallback renders the hub and its configuration before agent questions and approvals in DOM order.
- **Impact:** a waiting approval can appear above a very long tool rack but is not the single obvious task. Routine status and utilities compete with urgent decisions.
- **Recommendation:** make `Now` the first and default surface. When an approval or question exists, show one focused decision card and collapse Today/Tools. Push and Live Activity taps must deep-link to that exact request. Show aggregate counts only as secondary metadata.
- **Suggested implementation skill:** `build-ios-apps:swiftui-ui-patterns`, followed by native-device verification.

### High 2 — Pairing exposes two connection systems as simultaneous onboarding cards

- **Location:** `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift:107`, `ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalView.swift:191`, `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift:611`
- **Category:** usability, state clarity
- **Evidence:** an unpaired launch simultaneously shows `Connect to your Mac` for the Tailscale approval channel and `Waiting for Mac` for nearby Multipeer discovery. The Simulator capture displayed both cards plus `Found 1 devices`, while the primary pairing button remained disabled until a code was entered.
- **Impact:** the user cannot tell whether selecting a nearby Mac, entering a Tailscale code, or doing both is required. The same Mac appears to be both found and unavailable.
- **Recommendation:** replace both with one first-run `Connect to Greg's Mac` flow. Use the known Tailscale URL internally, accept the six-digit code, then optionally enable nearby Bluetooth as a background enhancement. After pairing, connection state becomes a compact toolbar indicator, not a card.
- **Suggested implementation skill:** `onboard` plus `build-ios-apps:swiftui-ui-patterns`.

### High 3 — Multiple native iPhone controls are below Apple's recommended 44 x 44 pt target

- **Location:** `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift:164`, `:255`, `:609`, `:782`, `:802`, `:825`, `:858`, `:871`, `:1064`, `:1104`; `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift:789`
- **Category:** accessibility, input reliability
- **Evidence:** interactive controls use minimum heights from 28 to 38 pt. The mode strip and quick-jot actions are 34 pt; the push-to-talk mode control is 28 pt; the Live Activity inline action is 34 pt.
- **Impact:** increased missed taps and accidental adjacent actions, especially while mobile. This is material for approve/deny and voice controls.
- **Standard:** Apple's accessibility guidance recommends 44 x 44 pt iOS targets; WCAG 2.2 AA requires at least 24 x 24 CSS px or sufficient separation, and its enhanced target is 44 x 44.
- **Recommendation:** provide a 44 pt hit region for every iPhone action, even when the visible glyph is smaller. Preserve at least 8–12 pt spacing around destructive pairs.
- **Suggested implementation skill:** `build-ios-apps:swiftui-ui-patterns`.

### Medium 1 — Mac navigation exposes overlapping implementation concepts

- **Location:** `Sources/CodeIsland/GlancesView.swift:439`, `Sources/CodeIsland/NotchPanelView.swift:262`
- **Category:** navigation, mental model
- **Evidence:** the expanded notch presents `SESSIONS`, `GLANCES`, and `HUB` as peer tabs. Glances and Hub both include personal status, while Sessions and Hub both include agent state.
- **Impact:** it is unclear where Calendar, Reminders, approvals, agent totals, and quick actions belong.
- **Recommendation:** remove the three peer tabs. Keep Auto/Home/Work/Code as the context selector, render `Now` and `Today` in the primary panel, and place Sessions and Tools in secondary disclosure surfaces.

### Medium 2 — Core web actions use blocking `prompt`, `confirm`, and `alert`

- **Location:** `Sources/CodeIsland/RemoteApprovalWebApp.swift:280`, `:337`, `:593`
- **Category:** interaction, accessibility
- **Evidence:** reminder, calendar, note, teleprompter, clipboard, volume, confirmation, success, and error flows use browser modal APIs.
- **Impact:** browser chrome breaks the product's visual language, offers poor validation and recovery, can interrupt scrolling, and does not preserve context well.
- **Recommendation:** use one accessible in-page sheet component with labeled fields, inline validation, explicit cancel/confirm, focus trapping, Escape handling, and a nonblocking result banner.

### Medium 3 — Four-second polling replaces large DOM regions

- **Location:** `Sources/CodeIsland/RemoteApprovalWebApp.swift:356`, `:702`, `:716`, `:743`
- **Category:** performance, interaction stability
- **Evidence:** the visible page polls every four seconds and rebuilds the hub, questions, and approval markup using `innerHTML`.
- **Impact:** a refresh can discard focus, selection, partially entered answers, or scroll context. Work is repeated even when only one status field changes.
- **Recommendation:** pause refresh while any editor or decision is active; reconcile keyed elements instead of replacing full regions; restore focus by stable ID. Server-sent events can be considered later, but are unnecessary for this single-user app if polling is made state-aware.

### Medium 4 — The visual system overuses nested dark cards and monospaced uppercase labels

- **Location:** `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift`, `Sources/CodeIsland/PersonalHubMacView.swift`, `Sources/CodeIsland/RemoteApprovalWebApp.swift:43`
- **Category:** visual hierarchy, typography
- **Evidence:** most modules receive their own border, fill, nested item fills, availability badge, uppercase eyebrow, and accent status. The iPhone Debug capture required more than two screen heights to expose the Code rack.
- **Impact:** everything reads as a widget, so nothing reads as primary. The result feels like a monitoring console rather than a personal assistant.
- **Recommendation:** use grouped native lists and section rhythm for Today/Tools, reserve a fully bordered card for `Needs You`, use SF text styles for primary content, and restrict monospaced type to IDs, code, and machine state.

### Medium 5 — The iPhone surface does not honor Reduce Motion globally

- **Location:** `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift:5`
- **Category:** accessibility, motion
- **Evidence:** connection, state, browsing, and status changes use springs and blur/scale transitions without consulting `accessibilityReduceMotion`. Only a Mac media HUD path currently checks the setting.
- **Impact:** frequent agent updates can create unnecessary motion and discomfort.
- **Recommendation:** centralize a motion policy. Under Reduce Motion, replace spring/scale/blur transitions with short opacity changes or no animation.

### Medium 6 — The private web app has no install icon set

- **Location:** `Sources/CodeIsland/RemoteApprovalWebApp.swift:4`
- **Category:** PWA quality, branding
- **Evidence:** the manifest's `icons` array is empty.
- **Impact:** Add to Home Screen produces a generic or poor-quality icon, weakening the web fallback precisely when it is used like an app.
- **Recommendation:** ship 180, 192, and 512 px maskable/non-maskable icons and an Apple touch icon derived from the approved app mark.

### Medium 7 — Primary view files are too large to change safely

- **Location:** `Sources/CodeIsland/NotchPanelView.swift` (3,307 lines), `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift` (1,830), `ios/CodeIslandCompanion/CodeIslandCompanion/PersonalHubView.swift` (1,827), `Sources/CodeIsland/PersonalHubMacView.swift` (1,297)
- **Category:** maintainability, regression risk
- **Impact:** layout, data state, controls, and diagnostics are coupled. A visual change can unintentionally alter connection or approval behavior, and review is harder.
- **Recommendation:** extract shared presentation models plus `Now`, `Today`, `Sessions`, `Tools`, and onboarding components. Keep transport and action-token code unchanged.

### Low 1 — Discovery copy is grammatically wrong for one Mac

- **Location:** `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift:687`
- **Evidence:** the UI displays `Found 1 devices`.
- **Recommendation:** use `Found 1 device` / `Found N devices`, or remove the count in the unified connection flow.

### Low 2 — Motion uses a conspicuously bouncy status spring

- **Location:** `ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift:8`
- **Evidence:** status transitions use a `0.65` damping fraction.
- **Recommendation:** use restrained system transitions for state changes and reserve spring emphasis for a newly arrived decision only.

### Low 3 — The private web label `Personal hub` is product-internal language

- **Location:** `Sources/CodeIsland/RemoteApprovalWebApp.swift:41`, `:144`, `:168`
- **Impact:** it adds a second product name and does not describe the user's task.
- **Recommendation:** use `CodeIsland` as the product and `Now`, `Today`, `Sessions`, and `Tools` as destinations.

## Systemic patterns

1. **Feature parity was added by stacking modules.** The functionality is real, but each new capability arrived as another card rather than being absorbed into a stable hierarchy.
2. **Transport state leaks into the interface.** Bluetooth/Multipeer and Tailscale are implementation details; Greg needs one answer: `Connected to Greg's Mac` or a single repair action.
3. **Machine-state typography dominates human-state copy.** Monospaced uppercase labels are useful for exact IDs and tools but currently compete with task titles and decisions.
4. **The same priority model is not yet expressed on every surface.** `SessionAttentionRouter` correctly prevents equal-priority carouseling, but the iPhone and web layouts still present routine modules at similar visual weight.

## Positive findings

- `SessionAttentionRouter` is stable by design: equal-priority routine sessions never carousel, while a waiting approval or question preempts background work. Four dedicated tests cover this behavior.
- Agent questions and approvals use exact request IDs, single-use tokens, freshness checks, and replay protection rather than generic remote commands.
- APNs payloads intentionally omit sensitive question/prompt text, and resolved events clear stale pending state.
- Live Activity lifecycle code creates, updates, ends, deduplicates, and rejects stale state. Compact, minimal, expanded, Lock Screen, and multi-session layouts exist.
- Calendar items can expose a one-click `Join` deep link, and tool actions support download-to-device, quick task/note creation, camera/mic preflight, teleprompter, media, shelf, and Claude proposal review.
- Native safe-area handling, landscape StandBy presentation, accessibility identifiers, confirmation dialogs for sensitive native actions, and offline polling fallback are already present.
- The signed internal build `1.0.0 (20260717225004)` processed as valid in App Store Connect and contains the signed widget extension.

## Completion design

### macOS notch

- Collapsed: one stable session summary. A question or approval preempts it; equal-priority sessions never rotate.
- Expanded default: `Now`, followed by `Today` only when there is room.
- Context selector: Auto / Home / Work / Code remains.
- Secondary toolbar: Sessions, Tools, appearance, settings.
- No top-level Sessions / Glances / Hub switcher.

### iPhone

- First run: one `Connect to Greg's Mac` flow.
- Default paired screen: `Now` with pending decisions first. If nothing needs attention, show the next meeting/task and a concise active-session summary.
- Secondary destination: `Sessions`, with stable per-session rows and explicit selection.
- Tools are a sheet or secondary page, not a continuous feed.
- Push notification, Live Activity, Dynamic Island, widget, and App Intent deep links land on the exact decision or tool.
- Nearby Bluetooth is opportunistic; Tailscale HTTPS is the away-from-Mac control path.

### Web fallback

- Mirror the iPhone's `Now` order.
- Use accessible in-page sheets instead of browser prompts.
- Keep it as a no-install fallback and emergency pairing path, not a second independent product.

## Verification gates after implementation

### Automated and Simulator

1. Mac unit/core suites and Release build.
2. iOS unit/UI suite on a clean Simulator runtime.
3. UI tests for unpaired, offline, idle, approval, question, two routine sessions, one-click join, quick task, Live Activity lifecycle, and exact deep links.
4. VoiceOver labels/order, Dynamic Type at accessibility sizes, Reduce Motion, light/dark appearance, portrait, landscape, and narrow devices.
5. Private web tests at 390 px and desktop widths, keyboard-only focus order, in-progress editor refresh protection, offline recovery, and PWA install metadata.
6. Signed archive validation, compiled App Intent metadata guard, entitlements, IPA signature, and App Store Connect processing.

### Physical iPhone acceptance

These cannot be replaced by Simulator or CI evidence:

1. Install the exact TestFlight build and accept notification permission.
2. Pair once using the current Mac code; confirm Keychain persistence across relaunch.
3. Approve and deny a real agent request over Wi-Fi, then repeat with Wi-Fi off over cellular Tailscale.
4. Answer a real multi-option question and verify the agent receives the exact response once.
5. Receive APNs while the app is backgrounded and terminated; tap through to the exact request.
6. Start/update/end the Live Activity and verify compact, expanded, Lock Screen, and Dynamic Island behavior on the physical device.
7. Verify Calendar and Location permission prompts, denial recovery, selected Reminders lists, manual ZIP fallback, and one-click meeting join.
8. Add a task and note from iPhone; verify both appear on the Mac and survive refresh.

## Source standards

- Apple Human Interface Guidelines, Accessibility: <https://developer.apple.com/design/human-interface-guidelines/accessibility>
- Apple Human Interface Guidelines, Live Activities: <https://developer.apple.com/design/human-interface-guidelines/live-activities>
- WCAG 2.2 target size: <https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum>

