# CodeIsland design review log

Decision log for the `design-review` skill. One dated section per batch. Statuses:
`proposed` -> `accepted` / `maybe` / `rejected` -> `shipped`. `rejected` is closed
for good and must never be re-proposed. `maybe` may be re-surfaced only with the
objection addressed, never as a renamed near-duplicate.

---

## 2026-07-19 — Batch 01: Mac notch panel + iPhone companion, benchmarked against Crest 4.9.0

**Artifact:** https://claude.ai/code/artifact/280d9d3e-6fe1-41ba-8fb6-03b9478b606d

**Scope escalated mid-session.** Greg asked for a full UX/UI redesign rather than
point fixes, so the artifact now leads with a redesign proposal: five stated
principles, a design-token system (neither app has one today), six shared
components, and **seven sequenced moves** that each close several of the ten
findings below. The findings remain the evidence and are traced to moves in the
artifact's mapping table. Stamps are now on the seven moves, not the ten
findings.

| Move | Closes | Platform | Effort |
| --- | --- | --- | --- |
| R1 Attention order + state bands | M1, M4, I4, M5 | Both | S |
| R2 Type split (SF Pro / SF Mono) + token file, **both appearances** | badge hues, radius sprawl, no Mac light mode, `.black` on-accent | Both | M |
| R3 One risk-driven DecisionCard | M2, M3, I2, I3 | Both | L |
| R4 Collapsed island names what needs you | collapsed bell, dead IdleIndicatorBar | Mac | M |
| R5 Rebuild iPhone Now + queue as rows | I1, I3, I4 | iOS | M |
| R6 Empty states + question-card keyboard | blank empty state, decorative option numbers | Mac | S |
| R7 One motion policy | I5, inert hover, dead code | Both | S |

### Implementation status (2026-07-20)

Greg stamped R1, R3, R4, R5, R6, R7 accept and R2 maybe. All six accepted moves
are **implemented and committed** on branch `redesign/attention-first`, gathered
in [PR #142](https://github.com/revopsglobal/CodeIsland/pull/142):

| Move | Commit | Status |
| --- | --- | --- |
| R1 | 52328fc | shipped — order by attention, bands, lastActivity age |
| R6 | 45e25e1 | shipped — empty state, real option-number shortcuts |
| R4 | 10733c6 | shipped — collapsed island names the blocked project |
| R7 | fb72f16 | shipped — Reduce Motion at the transition, hover fix (dead-code sweep deferred) |
| R3 Mac | 5eeab10 | shipped — CommandRiskClassifier, DESTRUCTIVE pill, unified button order |
| R3 iOS | 213f453 | shipped — risk on the wire, emphasis flips by risk |
| R5 | d90a3be | shipped — iPhone Now states the answer, queue as rows |

**R2 remains `maybe`** and is deliberately excluded, so everything shipped sits
inside the existing SF Mono vocabulary — the panel behaves differently but does
not yet look different. R2 is what changes the look.

New code: `Sources/CodeIslandCore/CommandRisk.swift` (classifier, 9 tests) and
`SessionAttentionBand` / `bandedSessionIDs` (4 tests). Eight L10n keys across all
seven languages, parity verified.

**Verification environment.** Earlier claims that the machine could not build the
app were wrong: Xcode 27 beta is at `~/Downloads/Xcode-beta.app`, and
`DEVELOPER_DIR=…/Xcode-beta.app/Contents/Developer swift build|test` works. Two
defects were caught only because the local toolchain was finally used:

1. The R3 risk field broke `run-model-tests.sh` (bare `swiftc` with an explicit
   file list that lacked `CommandRisk.swift`); `swift build` and `xcodebuild` both
   masked it. Fixed by adding the file to the list.
2. R5 broke the `testMultipleAttentionItemsDoNotRotateAutomatically` UI test,
   which asserted the removed "1 of N" dropdown. Rewritten to the new design's
   invariant. **This test runs only under `xcodebuild … test`, which the DMG CI
   workflow does not invoke** — so it is caught locally or not at all.

### Corrections to the 07-19 review made during implementation

- `queuePosition: 1` on the Mac approval card was reported as a hardcoded lie. It
  is correct: `pendingPermission` is `permissionQueue.first`, so the card only
  ever shows the queue head. No change made.
- Crest's approval UI was never observed, only inferred from binary strings; the
  live captures Greg supplied showed Crest's AI Coding module is a two-line
  roster, so CodeIsland's session row is richer than the competitor's. The
  redesign keeps CodeIsland's depth and borrows only Crest's restraint.

Proposed delivery: four PRs — (1) tokens and type, lowest risk and unblocks the
rest; (2) attention order, collapsed island, empty states; (3) DecisionCard alone
with its own tests, since it is the security-sensitive path and needs a risk
field added to `RemoteApprovalItem`; (4) iPhone Now and motion, needing physical
device acceptance.

**Light appearance (added 2026-07-19, second pass).** The first redesign draft was
dark-only. Two facts made that wrong:

- The Mac app has **no appearance handling at all** — across all 112 Swift files
  the only `.light` is `scrollView.scrollerKnobStyle` (NotchPanelView.swift:2088).
  No `NSAppearance` read, no `colorScheme` environment value. The panel is
  hardcoded black regardless of system setting.
- iPhone already ships a full light theme: `CITheme` (ContentView.swift:2260–2281)
  defines background `#F6F6F9`, surface `#FFFFFF`, foreground `#17171B` for light.

The non-obvious part is that the accent cannot simply invert. Measured contrast on
white: signal `#FFB04D` **1.82:1**, danger `#FF6B5E` **2.79:1**, live `#4DD966`
**1.84:1** — all far below the 4.5:1 AA threshold for text. The same colours pass
comfortably *as fills* because a fill carries near-black text (9.77:1 and 6.62:1).

So the accent splits by **role**, not by theme:

| Token | As fill (both modes) | As text / border / meter, light |
| --- | --- | --- |
| signal | `#FFB04D` unchanged | `#9A5A00` (5.47:1) |
| danger | `#FF6B5E` unchanged | `#B3261E` (6.54:1) |
| live | n/a | `#1E8F45` (4.14:1 — clears the 3:1 non-text-graphic bar) |

Text opacity is also not mirrored: 38% white on black reads about like 45% black on
white, so the light tertiary ramp is set independently.

Appearance decision recorded: **the collapsed island stays dark in both modes** —
it abuts a physical black cutout and Apple's Dynamic Island is permanently dark for
the same reason. **The expanded panel follows the system**, since it extends well
past the notch and on external displays there is no physical black to match; it
keeps a short dark cap at the hardware junction.

Related defect this closes: `.black` is hardcoded as the on-accent foreground at six
iOS sites (CompanionCommandCenterView:302, :333; RemoteApprovalView:390;
PersonalHubView:2194, :2216; ContentView:512). It does not flip with appearance and
only works because `Color.orange` happens to stay light in both — any accent change
silently breaks the label. Replaced by `onSignal` / `onDanger` tokens pinned to each
fill.

Explicitly out of scope and preserved: the 18 pixel mascots. They are the
product's differentiator against Crest, which has none. The redesign moves them
out of the session row's information hierarchy and into the collapsed island and
session detail, where identity helps rather than competing with state.

**Scope:** `Sources/CodeIsland/NotchPanelView.swift` (Mac notch session list and
approval/question cards) and `ios/CodeIslandCompanion/` (command center, personal
hub, remote approval surface) as they stand after PR #44.

**Grounding method:**

- Full source read of `NotchPanelView.swift` plus token extraction across all 112
  Swift files (colors, radii, fills, type scale, motion constants). Confirmed
  there is no centralised design-token file on either platform — every value is
  an inline literal at point of use.
- iOS surfaces read post-remediation so already-fixed 07-17 findings are excluded.
- Live confirmation the signed Mac app was running (PID 53430) plus a screen
  capture of the built-in notch display; the panel was collapsed with no active
  sessions, so expanded-state mockups are reconstructed from source tokens and
  `docs/images/notch-panel.png`.
- Verified via `git show --stat 8c07244` that PR #44 touched `GlancesView`,
  `PersonalHubMacView` and the iPhone companion but **not** `NotchPanelView.swift`.
- **Crest 4.9.0** (`com.zack40x.crest`) installed to `/Applications` from Greg's
  supplied `~/Downloads/Crest-4.9.0.dmg` and reviewed by bundle inspection and
  binary string extraction. Screen-control access was declined mid-session, so
  Crest's UI was **not driven interactively**; every Crest claim in the artifact
  is quoted from its shipped strings, not observed on screen. A future pass with
  computer-use granted could confirm the rendered layouts.

**Deduplicated against:** `docs/completion-ui-audit-2026-07-17.md` and
`docs/evidence/2026-07-18-crest-parity-and-premium-ui-audit.md`. Excluded because
already recorded or already fixed: Sessions/Glances/Hub peer nav (fixed — the live
Mac labels are now `Now / Today / Tools`), the beige cast (fixed — `CITheme` is
now neutral near-grey with a faint blue lean), the soft mascot at header size, the
Capture accent, iOS tap targets in the command center (fixed — now 44–52pt), and
the iPhone information hierarchy.

### Status table

| # | Platform | Idea | Effort | Impact | Status |
|---|---|---|---|---|---|
| M1 | Mac | Order the session list by attention, not UUID | S | Very high | proposed |
| M2 | Mac | Show project identity + risk tier on the approval card | M | Very high | proposed |
| M3 | Mac | Unify approve/deny order; scope ALWAYS to the session | S | Very high | proposed |
| M4 | Mac | Reverse the idle/working line cap | S | High | proposed |
| M5 | Mac | Time badge measures last activity, not session age | S | High | proposed |
| I1 | iOS | Fix the Now subhead fallback and duplicate empty string | S | Very high | proposed |
| I2 | iOS | Invert approve/deny weight by risk; drop orange for decisions | S | Very high | proposed |
| I3 | iOS | Show the attention queue as rows, not a dropdown | M | High | proposed |
| I4 | iOS | Render session age; stop collapsing idle to one row | S | High | proposed |
| I5 | iOS | Apply Reduce Motion to blurFade and the approval surface | S | Medium | proposed |

### What Crest decided differently

Recorded because it is the most useful part of this batch for future work. All
quotes verbatim from the Crest 4.9.0 binary. Crest is not an adjacent utility: it
ships its own Claude Code and Codex permission hooks, answers agent prompts from
the notch, and types replies back into the terminal.

- **Persistent allow:** Crest offers only `"Allow everything from this session
  without asking (until it ends)"` — session-scoped, self-expiring. CodeIsland's
  `ALWAYS` writes a permanent rule and is the calmest-styled of four buttons.
- **Button count:** `"Claude Code and Codex sessions land here with Allow and
  Deny."` Two. CodeIsland has four on the Mac card, the same four reordered
  inline, and two differently-coloured ones on iPhone.
- **Idle sessions:** `"A session that just finished its turn and is sitting idle
  no longer shows a standing prompt, so you can leave as many open as you like."`
  and `"A quieter notch when your sessions are idle."` This is the exact inverse
  of CodeIsland's uncapped-idle / clipped-working rule (M4).
- **Attention hierarchy, stated:** `"Music, volume, and a running timer stay
  ambient. They never redirect you."` and `"It only steps in when a session
  actually needs you."`
- **Destructive actions:** `"Every delete button is bigger, clearer, and turns red
  before it acts; bulk clears ask for a second click."`
- **Empty states:** every module has one, e.g. `"Claude Code and Codex sessions
  appear here while they run."`
- **Permission recovery:** `"A Screen Time or device-profile restriction is called
  out by name, since it silently blocks the permission prompt from ever
  appearing."`
- **Deep linking:** `"opening the notch now lands right where you act on it, the
  same way agent prompts already did."`
- Crest ships the identical string `"Nothing needs you right now."` that CodeIsland
  uses on iOS, so the copy itself is fine; CodeIsland's problem is the fallback
  ordering around it (I1).

### Rationale

**M1 — Order the session list by attention, not UUID.** Default grouping mode is
`"all"` (Settings.swift:196), returning `appState.sessions.keys.sorted()`
unchanged (NotchPanelView.swift:1869, :1943). The one mode that buckets by status
ranks `[.running]` above `[.waitingApproval, .waitingQuestion]` (:1874–1879).
`SessionAttentionRouter.orderedSessionIDs` already computes correct priority with
hysteresis and four tests, but is wired only to the collapsed bar
(AppState.swift:660–706).

**M2 — Project identity and risk tier on the approval card.** `ApprovalBar`
(:1180–1229) renders tool, optional server and basename, but no project, cwd or
branch; the question card does render that context (:1362–1380). No risk signal
reaches the UI — the only classifier is `DANGEROUS_PATTERNS` in
`Resources/codeisland-pi.ts:79`, which gates emission and is never carried on the
event. Also: `queuePosition` is the literal `1` at both card call sites (:217,
:239) while the inline variant passes the real `idx + 1` (:2413).

**M3 — Unify approve/deny order and hierarchy.** Card order is
`DENY · DISMISS · ALLOW ONCE · ALWAYS` (:1225–1228); inline is
`Details · ALLOW ONCE · ALWAYS · DENY` (:2419–2446). The leading control is
destructive in one and permissive in the other. `ALWAYS` has the lowest-contrast
styling despite persisting a rule. Supporting: hover fill is `bg.opacity(1.5)` on
opaque colors, a no-op (:1842); `.approve`/`.deny`/`.approveAlways` ship
`defaultEnabled: false` (Settings.swift:637), suppressing the hint badges the
v1.0.29 changelog announced. Recommend adopting Crest's session-scoped allow.

**M4 — Reverse the idle/working line cap.** `visibleMessages` clips working
sessions to `suffix(2)` while idle renders the full array uncapped (:2503–2505).
Compounds with M1 because the list scrolls past `maxVisibleSessions` (default 5).

**M5 — Time badge from last activity.** `SessionTag(timeAgo(session.startTime))`
(:2403). `lastActivity` is on the model and already used by
`SessionAttentionRouter` for tie-breaking. Note three time formats currently
coexist: Mac `timeAgo(startTime)`, iOS StandBy `standbyTimeAgo(updatedAt)`, and
the iOS approval card's live `.relative` style.

**I1 — Now subhead fallback and duplicate empty string.** The subhead is
`weatherSummary ?? (hasAgentAttention ? "An agent is waiting for your decision."
: "Nothing needs you right now.")` (CompanionCommandCenterView.swift:416–418).
Weather wins first, so the attention branch is unreachable whenever any weather
summary resolves. With no weather and nothing pending, the same sentence renders
as both subhead and empty row (:434–437).

**I2 — Approve/deny weight inverted against risk.** "Approve once" is
`.borderedProminent` + `.tint(.orange)` spanning remaining width; "Deny" is
`.bordered` + `.tint(.red)` at 116–128pt (RemoteApprovalView.swift:522–579).
Orange is `HubTheme.accent` (PersonalHubView.swift:8) and is used for Capture,
pairing, and every card gradient, so it carries no decision meaning. Mac uses
green for the affirmative. `RemoteApprovalItem`
(`RemoteApprovalProtocol.swift:113`) has no risk field, and
`RemoteApprovalDecision` (:108) is only `approve`/`deny`, so the wire format
cannot express "always" — a protocol change is required for full parity.

**I3 — Attention queue behind a dropdown.** `RemoteApprovalSurface` renders one
card; additional items are reachable only through a `Menu` labelled
`"\(selectedIndex + 1) of \(attentionItems.count)"` (RemoteApprovalView.swift:24–48).
No list, no stack, no swipe.

**I4 — No session age on iOS; idle collapses to one row.** The Mac builds
`detail: String(describing: session.status)` (PersonalHubService.swift:1291) and
`PersonalHubItemRow` (PersonalHubView.swift:1735) renders only title and subtitle.
No row shows any time. Separately `visibleIDs` filters to `priority > 0` and falls
back to `Array(recentIDs.prefix(1))` when nothing is active (:1288), so an idle
Mac shows exactly one session. Priority ties break on *most recent* activity, so
the stalest waiting item sinks.

**I5 — Reduce Motion gates one dot.** `CompanionMotionPolicy`
(ContentView.swift:2037) is tested and governs only `PulseDot`. Eleven
`.transition(.blurFade)` sites run unconditionally (`blurFade` at :2189 has no
environment access), several combined with `.scale` or `.move`.
`RemoteApprovalView` never reads `accessibilityReduceMotion` at all.

### Also found, not written up as batch items

- Mac: zero-session empty state renders nothing; Glances has six considered
  strings, the primary surface none.
- Mac: tab labels `ALL / STA / CLI` are hardcoded English literals (:585) with no
  `L10n.shared` lookup, in an app shipping seven localisations.
- Mac: quit is a one-click unconfirmed `NSApplication.shared.terminate(nil)`
  22pt from Settings (:691–693).
- Mac: badge rail runs four accent hues (:2390–2404) against the "one signal
  accent" direction adopted in the 07-18 remediation.
- Mac dead code: `showIdleIndicator` hardcoded `false` (:121–123) orphaning
  `IdleIndicatorBar` (:932–980); `isCompletion` passed but never read (:2297);
  `scroll_for_more` / `scroll_hidden` localised everywhere but referenced nowhere.
- iOS dead code: `PortraitIslandView`, `PersonalNowOverview`, `AppearanceMenu` and
  `PersonalHubSurface` are all unreachable after #44 — two parallel "Now overview"
  implementations remain in the tree.
- iOS: remaining sub-44pt targets — the remove-attachment `xmark`
  (PersonalHubView.swift:1257) has no frame at all, `HubSecondaryButtonStyle`
  (:2202) has no intrinsic `minHeight`, `submitButton` (ContentView.swift:751) is 40.
- iOS: stale copy `"Tap the top-right to keep searching"` (ContentView.swift:1120)
  — discovery moved into the ellipsis menu in #44.
- iOS: no spacing or type scale. Corner radii span 7–28; font sizes mix semantic
  styles with hardcoded 9–24pt that do not scale with Dynamic Type; `.black` is
  hardcoded as the on-accent foreground at six sites; `Color.ciSurface` is used as
  a foreground at ContentView.swift:1273, inverting the token's meaning.
- Neither platform has a centralised design-token file, which is why the 07-18
  "one accent" direction could be applied to the Hub without reaching the notch
  panel.
