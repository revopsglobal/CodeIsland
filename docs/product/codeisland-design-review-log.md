# CodeIsland design review log

Decision log for the `design-review` skill. One dated section per batch. Statuses:
`proposed` -> `accepted` / `maybe` / `rejected` -> `shipped`. `rejected` is closed
for good and must never be re-proposed. `maybe` may be re-surfaced only with the
objection addressed, never as a renamed near-duplicate.

---

## 2026-07-20 — Batch 02: after the redesign — pipeline, parity, and polish

**Artifact:** https://claude.ai/code/artifact/93b97243-9883-4dc1-af80-17a904756085

Ten proposals, ranked most-severe first, generated the same evening 1.0.62 shipped.
The through-line: Batch 01 changed what the island *says*; this batch closes the
places where the underlying system does not yet match what the redesign promises
(the risk gate, the invisible desktop sessions, the idle cost) plus the parity and
hygiene debts the redesign exposed. Artifact items are numbered 01–10; logged here
as B2-01…B2-10 to avoid colliding with Batch 01's M/I labels.

**Grounding method:**

- Live app: v1.0.62 running as PID 13771 on the notch Mac. Screen captures of the
  collapsed island and expanded panel (embedded in the artifact) taken 22:5x PST
  while two Claude Code Desktop sessions and one Codex CLI session were active —
  only the Codex session appeared. Island expanded/collapsed via real clicks
  (cliclick), machine left as found.
- Live measurement: `ps` (18–25% CPU at idle-collapsed) plus a 4-second `sample`
  of the process (hot frames: `__proc_info` 51, `__sysctl` 28, Foundation string
  search — the discovery process-scan) as evidence for B2-04.
- Hook config read from `~/.claude/settings.json` (CodeIsland hook v5 registered
  on all events; retired `claude-island-state.py` also still registered — live
  evidence for B2-05); `CLAUDE_CODE_ENTRYPOINT=claude-desktop` with empty
  `TERM_PROGRAM` confirmed from inside a ccd session for B2-02.
- Full source reads on main @ d078a77: NotchPanelView.swift (3,611 lines),
  AppState.swift (5,045), SettingsView.swift, NotchDesignTokens.swift, the 17 CLI
  mascot views, HookServer/ConfigInstaller, Sources/CodeIslandBridge/main.swift,
  Resources/codeisland-pi.ts, CodeIslandCore (CommandRisk, RemoteApprovalProtocol),
  ios/CodeIslandCompanion (ContentView, PersonalHubView, RemoteApprovalView,
  LiveActivityController, Watch app), .github/workflows, appcast.xml, scripts/.
- Mockups reuse NotchTokens values verbatim (#08090B–#1E222A surfaces, #FFB04D
  signal + #241505 onSignal, #FF6B5E danger + #2A0806 onDanger, #4DD966 live,
  SF Pro / SF Mono split). iOS claims cite CITheme/HubTheme values read from
  source; iOS surfaces still lack real renders because the simulator smoke path
  is broken — that is itself batch item B2-08.

**Deduplicated against:** Batch 01 and the visual-proof batch (M4 and DS2 remain
rejected-closed; light mode remains parked pending a physical-notch pass — nothing
here touches the wordmark, the badge rail, or appearance). Checked against all
in-flight worktrees before proposing: telegram-secure-approval-sheet (active
tonight), harden-app-intent-validation, stabilize-iphone-refresh,
physical-acceptance-verifier-fixes, harned-testflight-reinvite,
eventkit-health-diagnostics, completion-proof. No Telegram-approval, App Intent,
iPhone-refresh, or acceptance-verifier work is proposed.

### Status table

| # | Platform | Idea | Effort | Impact | Status |
|---|---|---|---|---|---|
| B2-01 | Pipeline | Close the destructive-command hole at the hook gate (pi/omp) | S | Very high | proposed |
| B2-02 | Mac | Make Claude Code Desktop sessions first-class citizens | M | Very high | proposed |
| B2-03 | Mac+iOS+Watch | One decision language: finish M3 on every deciding surface | M | Very high | proposed |
| B2-04 | Mac | Stop paying 20% CPU to look idle | M | High | proposed |
| B2-05 | Mac | Pipeline health surface + first-run checklist | M | High | proposed |
| B2-06 | Mac | Turn session rows into a control surface | M | High | proposed |
| B2-07 | iOS | Cut the dead iOS subtree; fix the three live tap targets | S | High | proposed |
| B2-08 | Ops | iOS verification gap: CI tests + working screenshot path | M | High | proposed |
| B2-09 | Ops | Retire the dead updater instead of shipping its ghost | S | Medium | proposed |
| B2-10 | Mac | Panel chrome hygiene: guard Quit, localize tabs, drop dead keys | S | Medium | proposed |
| B2-11 | iOS · Product | Tool relevance: Hub drifted from agent monitor to Mac dashboard | M | Very high | proposed |
| B2-12 | iOS · IA | Four-tab structure buries the one job; Capture wrongly holds the FAB | M | Very high | proposed |
| B2-13 | iOS | Quiet Now hero leads with calendar, not agent context | S | High | proposed |
| B2-14 | iOS | Give iOS the design system (tokens/type/accent) Batch 01 gave the Mac | M | High | proposed |
| B2-15 | iOS · Watch | Let Buddy act from where it notifies you (notification actions, LA buttons, Watch questions) | M | Very high | proposed |
| B2-16 | iOS · Watch | Tell the truth when the Mac is gone — one reachability state everywhere | M | High | proposed |

**Extension 2026-07-20 (same evening):** Greg asked the batch to also review the iOS
mobile app directly and to weigh information architecture and tool relevance to
UI/UX, then clarified the target is **CodeIsland Buddy for iOS**. Added B2-11…B2-16
as a dedicated Buddy review, grounded in live renders from the iPhone 16 Pro
simulator (beta toolchain, `-CodeIslandCompanionMockHub` / `-CodeIslandCompanionMockPairing`
/ `-CodeIslandCompanionMockAttention approval|question|multiple` / `-CodeIslandCompanionMockDeepLink <url>`
launch args — the mock deep link is applied at launch via `openDeepLink`,
RemoteApprovalClient.swift:180). Embedded captures: the paired "All clear" Now
surface and the unpaired pairing flow with the four-tab bar. Later captures
(approval surface, sessions) were blocked by an unresponsive simulator under
extreme host load (load avg ~500–980; Copilot.app + build swarm), so B2-15/B2-16
mockups are code-accurate reconstructions from the exact mock seed
(RemoteApprovalClient.swift:1015 — Codex / "Run release build" /
`xcodebuild -scheme CodeIslandCompanion archive`) rather than live renders. The
19-module catalog is `Sources/CodeIslandCore/PersonalHubProtocol.swift:19` (the
`// Crest 4.9 catalog` comment is verbatim). B2-11 is the premise item: B2-12 and
B2-13 are its screen-level expressions and shift shape if B2-11's framing is
rejected. B2-15 is scoped as Apple's notification/Live-Activity/Watch surface,
distinct from the in-flight telegram-secure-approval-sheet (shared authenticated-
action plumbing, coordinate; do not duplicate). Same artifact URL; the Mac/pipeline
items 01–10 are unchanged.

### Rationale

**B2-01 — Close the destructive-command hole at the hook gate.** The hook-side
gate (`Resources/codeisland-pi.ts:79-87`) checks 3 patterns and lets non-matches
run fire-and-forget (:496-505); the Mac's own classifier
(`CodeIslandCore/CommandRisk.swift:27-36`) knows 8 destructive patterns and
`CommandRiskTests.swift:35-44` asserts force-push / `reset --hard` /
`curl|sh` / `rm -fr` are destructive — but it is display-only. For pi/omp
sessions those commands never raise a blocking approval, so the 1.0.62 changelog's
"destructive Deny is the single filled action" holds only for Claude (whose engine
forwards all PermissionRequests). The hook regex also misses `rm -fr` / `rm -f` /
`rm --force`. Fix: mirror or codegen the CommandRisk pattern set into
`isDangerous()` plus a parity test.

**B2-02 — Make Claude Code Desktop sessions first-class.** Live observation, not
inference: two active ccd sessions, island shows only the Codex CLI. Hooks
verifiably fire in ccd (this session's own hook receipts), the bridge only drops
events without a session_id, but discovery binds sessions to CLI processes via
proc/sysctl arg scans (AppState.swift:2288+, :3001-3005 tightens unknown-process
freshness to 30s) and jump/Smart-Suppress are terminal-centric
(bridge main.swift:414). Proposal: accept `entrypoint=claude-desktop` as a
session source, badge it DESKTOP, jump activates the Claude app. The exact
drop point (discovery binding vs display filter) needs an instrumented debugging
hour first — effort M includes it.

**B2-03 — One decision language everywhere.** M3's consequence-matched emphasis
shipped to the Mac auto-card and iPhone approval card only. Still contradicting
it: the Mac inline card's raw-RGB rainbow with no risk tier
(NotchPanelView.swift:2572-2592), ApprovalBar re-typing dangerFill/onDanger/
signalFill as literals (:1170-1185), the Watch's fixed filled-orange Approve on
destructive commands (WatchContentView.swift:385-400), and every glanceable
surface — Live Activity, Dynamic Island, StandBy, widgets — because
`CompanionStatePayload` (CompanionModels.swift:268) and
`ActivityAttributes.ContentState` (:60-74) carry no risk field even though
`RemoteApprovalItem.risk` already rides the authenticated path
(RemoteApprovalProtocol.swift:168). Additive wire change + reuse of existing
components.

**B2-04 — Stop paying 20% CPU to look idle.** Measured tonight: 25.5% CPU
collapsed-idle; sample shows proc_info/sysctl churn. Three mechanical causes:
`MascotAnimationGate.animationsActive = isPanelVisible && isAwake`
(MascotAnimationGate.swift:34-47) never pauses visible-but-idle, so the default
config redraws the pixel mascot at ~8fps forever (SheldonView.swift:11-19,
PixelCharacterView.swift:128-141, two layers); `autoScreenPoller` runs
`CGWindowListCopyWindowInfo` every 5s default-on (PanelWindowController.swift:442,
its own comment cites Energy Impact #92); and 17 CLI mascot views kept the raw
`.repeatForever` glow the #225 fix removed from Clawd/Sheldon (StepFunView:162,
DroidView:223, CursorView:247, GeminiView:218, et al.). Fix: idle-timeout freeze
in the gate, NSWorkspace/NSScreen notifications instead of the poll, sweep the 17
glows onto gatedTimeline. Verify with the same ps/sample method.

**B2-05 — Pipeline health + first-run checklist.** Every core failure mode is
silent: HookServer listener failures only log (HookServer.swift:38-41, 58-60),
no hookHealth/lastEventAt state exists anywhere in AppState, ConfigInstaller
installs/repairs silently (AppDelegate.swift:104, :327), the status-item menu is
Settings+Quit and hidden by default (StatusItemController.swift:89-111), and
there is zero onboarding code. Glances has GRANT/PRIVACY recovery buttons; the
agent pipeline — the actual product — has none. Live proof of the class of
failure this would catch: the retired Claude Island app's
`claude-island-state.py` hook is still registered on this Mac, spawning python3
on every hook event of every session to hit a socket that no longer exists.
(Cleaned up 2026-07-20: the 11 stale entries were removed from
`~/.claude/settings.json` (backup: `settings.json.backup-20260720-claude-island-removal`)
and the script archived to `~/.claude/hooks/archive/`. The proposal itself
remains open; stale-foreign-hook detection would have flagged this
automatically instead of it surviving 12 days.)
Proposal: tri-state health rows (socket/hooks/Accessibility/notifications) in
Tools + status-menu diagnostics + stale-foreign-hook detection; same checklist
doubles as first-run.

**B2-06 — Session rows become a control surface.** `.contextMenu` appears
nowhere in the codebase; the only row verbs are click-to-jump
(NotchPanelView.swift:2695-2740) and project-name-to-Finder; keyboard reach is
one digit handler in QuestionBar (:1530); remote rows do nothing (:2706). The
live card also says "revops-global" twice (header subtitle + identity-line chip,
observed in tonight's capture). Proposal: context menu (Jump / Reveal / Copy cwd
/ Dismiss / confirm-gated Kill), arrow-Return-Esc keys, identity line owns
project·branch once.

**B2-07 — Cut the dead iOS subtree; fix the live tap targets.** ~740 unreachable
lines across the two biggest iOS files: PortraitIslandView (ContentView:114-278),
PersonalNowOverview (:409-551), PersonalHubSurface (PersonalHubView:439-704),
CompanionPrimaryNavigation, CompactIslandBar, DiscoveryFill — a full parallel
Now/Hub implementation. Demo mode's only entry point is inside the dead
DiscoveryFill (:777-784); the stale copy "Tap the top-right to keep searching"
(:1123) points at a control that now exists only in dead code. Correction to the
07-19 note: AppearanceMenu is NOT dead (live via StandByIsland, ContentView:1471).
Live sub-44pt targets: submitButton minHeight 40 (ContentView:754), attachment
xmark with no frame (PersonalHubView:1276-1281), HubSecondaryButtonStyle lacking
the intrinsic 44 its siblings bake in (:2251-2258).

**B2-08 — Close the iOS verification gap.** `build-macos-arm-dmg.yml:147-154`
builds the companion but never runs `xcodebuild test`; the log above (:64-67)
records a regression that shipped through exactly that gap.
`scripts/smoke-companion-ui.sh` fails before its first capture because its
DEVELOPER_DIR autodetect prefers stable Xcode over the beta toolchain the
companion requires — the reason iOS findings still have no real renders.
TelegramAttentionNotifier, TailscaleServeManager, and UpdateChecker have zero
tests. Proposal: beta-first toolchain detection, a companion test lane in the DMG
workflow, seed tests for the transports.

**B2-09 — Retire the dead updater.** Sparkle 2.9.1 is bundled but Info.plist has
no SUFeedURL and no SUPublicEDKey; appcast.xml is frozen at 1.0.30 with all URLs
pointing at wxtsky; release.yml downloads from and pushes to wxtsky repos.
CHANGELOG jumps 1.0.58 → 1.0.30 (1.0.31–57 undocumented). The real ship path —
CI DMG artifact installed over /Applications with the same identity so TCC
persists — is sound; make reality the design. Recommended: remove Sparkle +
appcast + release.yml, add a lightweight "latest CI build" check, mark the
CHANGELOG gap. Documented alternative if in-app updates ever matter: fork-owned
appcast + EdDSA key (M).

**B2-10 — Panel chrome hygiene.** The red power button one icon from the gear is
an unconfirmed `NSApplication.shared.terminate(nil)`
(NotchPanelView.swift:707-712) — the one interaction that silently ends the
product's passive vigilance. ALL/STA/CLI are English literals with no L10n
(:575) and the newer Now/Today/Tools tabs repeat the same class of bug
(GlancesView.swift:527-529) in a 7-locale app; `scroll_for_more`/`scroll_hidden`
are localized in all locales and referenced nowhere. Confirmation popover reuses
the B2-03 decision language; M4/DS2 stay untouched.

**B2-11 — Tool relevance: the Hub drifted from agent monitor to Mac dashboard.**
`PersonalHubModuleID` (PersonalHubProtocol.swift:19) exposes 19 leaf modules under
a literal `// Crest 4.9 catalog` comment. Only four relate to AI coding agents
(claude, agents, github, notifications); eleven are the Crest personal-dashboard
catalog (nowPlaying, shelf, calendar, reminders, notes, system, weather, audio,
bluetooth, battery, quickToggles) and four are "Personal parity extensions"
(downloads, camera, teleprompter, windowManager). Each is a maintained,
server-driven module with permission/loading/unavailable states, localization, and
Mac-side services. The recommendation is not deletion but an explicit identity
call: commit to the coding command center (demote the personal hub to a labeled
secondary or ship it off by default) or give the hub its own tab identity so the
agent signal stops competing with bluetooth battery. This is the batch's headline;
every other iOS item is downstream.

**B2-12 — Four-tab IA buries the one job.** The live tab bar is
Now · Sessions · **Capture (elevated center FAB)** · Tools. The primary-action
pedestal holds Capture (quick-jot/shelf), while Sessions — the live agent list,
the mobile reason-to-exist — is a flat tab that overlaps with Now (Now already
aggregates the attention triad + a session strip via
CompanionCommandCenterView.swift). Proposal: merge Now+Sessions into one "Agents"
home, return Capture to a contextual + action. Scoped M because the right tab set
depends on B2-11 (demoting the hub frees a tab).

**B2-13 — Quiet Now hero leads with the calendar.** On the paired all-clear Now
(live render), the signal triad (0 approvals / 0 questions / Mac online) is correct
and glanceable, but the hero below it is the calendar/reminders timeline — the
biggest element is "Next: Design review · 2:00 PM" with a "Join" button — pulled
from personal-hub data (nowContent / CompanionTodayTimeline). Nothing about recent
sessions, completions, or what's running. Small self-contained change to the
quiet-state hero: lead with agent context (recent/running/shipped), keep the
calendar one tap away. Clearest screen-level expression of the B2-11 call.

**B2-14 — Give iOS the design system.** CITheme (ContentView.swift:2264-2285)
defines only bg/surface/fg — no accent, no type scale, no radius scale. Result:
two competing accents (submit blue #61ADFF ContentView:606 vs HubTheme orange
PersonalHubView:8), 16 hardcoded `.system(size:)` values 8→32pt that ignore
Dynamic Type, 12 corner radii 5→28, and `ciSurface` used as a foreground
(:1276). Batch 01's R2 gave the Mac NotchTokens; the plan
(docs/plans/2026-07-19-adaptive-native-product.md) specced
`Shared/CodeIslandDesignSystem.swift` and it was never built. This item is that
file plus migrating the accents, type scale, and radius scale onto it (Watch
adopts it too). Foundation for B2-03's risk colors and B2-12/B2-13's new surfaces;
do it after/with B2-07's dead-code cut.

**B2-15 — Let Buddy act from where it notifies you.** A phone companion's core
value is acting without opening it; on iOS every notification and glanceable
surface is tap-to-open. No `UNNotificationCategory`/`UNNotificationAction` is
registered anywhere (`didReceive response` only opens the app,
CompanionAppDelegate.swift:59-66); the Live Activity / Dynamic Island / lock
screen have only `.widgetURL` deep links, no `Button(intent:)`
(CodeIslandLiveActivityWidget.swift:11,31), and the App Intents are all *Open…*
intents (CodeIslandAppIntents.swift); the Watch can approve/deny
(WatchContentView.swift:385-400) but questions say "Answer on iPhone" (:405). The
fix preserves the content-free APNS design: notification actions and LA buttons
trigger the same authenticated fetch-then-act the app runs on open (the push
carries no token). Add iOS notification actions + LA `Button(intent:)`; let the
Watch answer questions. Shares the remote-action plumbing with the in-flight
Telegram approval sheet — build the authenticated-action layer once. Depends on
B2-03 so the risk emphasis is already on those surfaces.

**B2-16 — One reachability truth when the Mac is gone.** Three transports fail in
three voices: Multipeer watchdog "Connected but no status updates for a while;
reconnecting to Mac" (CompanionConnection.swift:18-19), Tailscale offline "Remote
Mac unavailable" + Retry/Pair again (RemoteApprovalView.swift:518-538),
followed-task loss LA "Waiting for your Mac to reconnect" + local notification
(LiveActivityController.swift:118-143). With the Mac asleep and no followed task /
active pairing, only the generic reconnect string or the discovery card shows, so
"quiet" and "offline" look alike — the ambiguity bites exactly when the user is
away. Live Activity `staleDate` is itself inconsistent (300/180/90s at
LiveActivityController.swift:128/:215/:377). Consolidate behind one reachability
state with a "last seen" timestamp, rendered identically on Now, approvals, LA, and
Watch, plus one staleDate constant. Pairs with B2-13 (reachability inline in the
quiet hero) and B2-15 (unreachable Mac visibly disables the new action buttons).

### Also found, not written up as batch items

- Mac: ~70 persisted settings keys across 11 pages with five overlapping
  visibility toggles (`hideWhenNoSession`, `hideInFullscreen`, `smartSuppress`,
  `collapseOnMouseLeave`, `autoCollapseAfterSessionJump`) and a sidebar group
  confusingly titled "CodeIsland"; legacy `autoExpandOnCompletion` key persists
  alongside its successor. A Settings IA pass is a future candidate.
- iOS: Live Activity `staleDate` has three different values (300/180/90s —
  LiveActivityController.swift:128/:215/:377); no unified "Mac is asleep" state
  across the three transports; no accent token in CITheme (submit blue #61ADFF
  vs HubTheme orange, both ad hoc); `ciSurface` used as a foreground
  (ContentView:1276); broken `#Preview` (missing RemoteApprovalClient env object).
- Notifications are tap-to-open only (no UNNotificationCategory anywhere).
  Actionable approve/deny from a notification is deliberately NOT proposed while
  the telegram-secure-approval-sheet work is in flight — same surface area;
  revisit after it lands (push → authenticated refresh → local actionable
  notification would preserve the content-free APNS design).
- Doc drift: `docs/remote-approvals.md:33` still says watch targets don't exist;
  they do. `CODEX_HANDOFF.md` describes 1.0.52.
- The `sample` also showed multipeerconnectivity threads alive at idle;
  not investigated further (B2-04 covers the measured burn).

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
| R2 Type split (SF Pro / SF Mono) + token file (light mode **reverted**, see below) | badge hues, radius sprawl | Both | M |
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

### Visual-proof batch — 2026-07-20, shipped v1.0.62

After R1–R7 and R2 (type split + token file) landed, Greg asked to *see* the
remaining findings as real before/after renders, not prose. A follow-up
"visual-proof" batch was rendered from the actual code (its own labels M2–M5 /
DS2, distinct from the 07-19 findings above). Stamp:

| Label | What it is | Stamp | Ship |
| --- | --- | --- | --- |
| M2 | Type split reaches prose — SF Pro for prompts/chat text, mono only for commands/IDs/paths + the `$` sigil | **accept** | v1.0.62 |
| M3 | Risk-aware approval buttons — one filled action matched to consequence (Deny on destructive, Allow on safe); the four-colour row is gone | **accept** | v1.0.62 |
| M5 | Today (Glances) + Tools (Hub) onto the token system — 113 inline literals and two ad-hoc accents collapse to one signal amber; `.black`-on-accent → pinned `onSignal`; Now/Today/Tools nav drops the alert colour for neutral ink | **accept** | v1.0.62 |
| M4 | Collapsed island shows a "CodeIsland" wordmark at rest instead of "0" | **reject** | — |
| DS2 | Neutral one-accent badge rail (`@host`/`+Sub`/`YOLO` → grey) | **reject** | — |

`M4` and `DS2` are **rejected → closed for good.** DS2's rejection is a
deliberate call to keep the badge rail's distinct hues rather than fold them into
the one-accent system; do not re-propose either.

Shipped as a clean fast-forward to `main` (`aecfc3f`) then cut as `1.0.62`
(`86ad1ce`), signed with the internal Apple Development identity via
`build-macos-arm-dmg.yml` and installed in place over `/Applications/CodeIsland.app`
(same identity, so TCC permissions persist). M5's before/after was produced with a
DEBUG `--render-snapshot` path that renders `GlancesToggleRow` / `GlancesView` /
`PersonalHubMacView` headlessly; the iOS findings (I1/I2/I4) still lack real
renders because the Simulator smoke path (`scripts/smoke-companion-ui.sh`) exits
non-zero and produces no PNGs.

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

> **REVERTED 2026-07-20 (v1.0.60).** Light mode shipped in v1.0.59 and was
> **unreadable on the real notch** — Greg: "I can't see anything." It was
> "verified" only by a headless `NSHostingView` snapshot at a forced
> `NSAppearance`, which did **not** reproduce the failure of the live panel (an
> `NSPanel` floating over the desktop resolves the dynamic colours differently).
> All token resolvers are now pinned to their dark values; the panel is always
> dark again, and the rest of the redesign (R1, R3–R7, the SF Pro / SF Mono
> split) is untouched. **Lesson, twice-learned this session:** verifying a
> representation — an HTML mockup rendered in a browser, then an isolated
> SwiftUI view rendered headless — is not verifying the live surface. A light
> mode only returns after it is confirmed on a physical notch, not a render.
> The design below is retained as the *intended* palette for that future
> attempt, not as a shipped or validated result.

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
