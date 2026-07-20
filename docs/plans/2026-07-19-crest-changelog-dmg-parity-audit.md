# Crest Changelog and 4.9.0 DMG Parity Audit

**Date:** 2026-07-19

**Scope:** CodeIsland Mac host and CodeIsland Buddy for Greg's iPhone

**Sources:** [Official Crest changelog](https://crestnotch.app/changelog) and the
notarized `Crest-4.9.0.dmg` supplied by Greg.

## Decision

CodeIsland should reach practical parity with the Crest features that support
Greg's real Mac and away-from-Mac workflow, but it should not clone Crest's
information architecture or add low-value breadth. The product remains an
attention-first command center with three stable destinations:

- **Now:** only work that needs Greg, the deliberately followed task, or a new
  completion awaiting review;
- **Sessions:** the complete Codex and Claude portfolio; and
- **Tools:** the useful personal modules and configuration.

The mobile product adds dispatch, evidence, follow-up, push, Live Activities,
and Dynamic Island. Crest is a Mac-only quality and behavior reference, not the
remote-control architecture.

## Evidence from Crest 4.9.0

The supplied DMG was mounted read-only and inspected without changing its
preferences. It is a notarized universal application signed by `Developer ID
Application: Zakaria Swaidan (SA6A94K2Y4)`, bundle ID `com.zack40x.crest`, build
`4.9.0 (63)`, with a macOS 14 minimum. Its SHA-256 is
`e9da0a362f0262531e93189ecbac7ed42d6e778dcf554295b01183ccd8a8a66a`.

Native inspection confirmed:

- a compact `Auto / Home / Work / Code` mode rail and a separate 16-module
  catalog;
- a focused module presentation with restrained controls and strong hierarchy;
- a coding module that lists Claude Code and Codex sessions and exposes a
  session-wide allow control;
- a permission center with current state, plain-language purpose, and an
  `Allow` or `Open Settings` recovery action for each listed capability; and
- a closed-notch window whose automation-visible surface is much larger than
  the visible control in 4.9.0, matching the defect Crest says it fixed in
  4.9.1.

CodeIsland will copy the focused hierarchy and permission recovery model. It
will not copy session-wide `Allow everything` authority. Exact approvals and
questions stay request-bound, device-bound, short-lived, and single-use.

## Changelog disposition

| Crest release | Relevant change family | CodeIsland decision |
| --- | --- | --- |
| 4.9.1 | Closed-notch automation and screen-reader hit area | Adopt as a release-blocking accessibility and focus test. |
| 4.9.0 | Sticky coding approvals, notification/chime, task and note capture, unified calendar and meeting links, fresh-install permission prompts | Adopt, but replace broad session authority with exact request authority and keep notifications signal-only. |
| 4.8.x | Quiet header, stable battery layout, keypress-only brightness HUD, destination-aware quick jot and conflict-safe notes | Adopt the quiet layout and honest event semantics; place notes in Tools. |
| 4.7.x | Focused module catalog, calendar colors/join, task checkboxes, Shelf thumbnails and clipboard persistence, inline approvals | Adopt the useful modules and persistence requirements; keep Now signal-ranked. |
| 4.6.x-4.5.x | Read-only assistant actions without confirmation, explicit write confirmation, on-device speech, teleprompter, weather, notification, coding-session, and camera preflight modules | Adopt safe read/write distinction and personal Tools; do not add a second generic AI chat surface. |
| 4.0.x | Auto/Home/Work/Code modes, truthful permission state, hover/focus/fullscreen behavior, draft restore, contextual landing | Adopt the interaction and recovery quality bar while retaining Now/Sessions/Tools as the primary IA. |
| 3.17-3.10 | Custom module rail, full calendar editing, manual weather city, task reorder/archive/restore, signal-only agent attention, exact prompts, honest player limitations, reminder-list and due-date support | Adopt. These directly address Greg's current calendar, reminders, weather, coding attention, and one-click-join needs. |
| 3.9-3.3 | Clipboard, Shelf, downloads, Bluetooth/battery, audio, toggles, world clocks, converter, color tools, event-driven refresh | Adopt Downloads, Shelf/clipboard, Bluetooth/battery, audio, and essential toggles. Defer world clocks, converter, and color tools unless usage evidence creates a need. |
| Pomodoro/watch-related items | Focus timer and watch surfaces | Exclude by Greg's explicit direction. |

## Adopt now: completion requirements

### Signal and coding attention

- An idle or healthy session is silent. Only an approval, exact question,
  blocker, failure, or deliberately followed completion interrupts Greg.
- Attention is sticky until Greg acts; equal-priority sessions never rotate on
  a timer.
- The Mac closed state, every display, push, Live Activity, and Dynamic Island
  all represent the same authenticated task/action identity.
- Approval and question answers route back to the exact provider session and
  terminal turn.
- A closed or collapsed window accepts pointer and accessibility interaction
  only inside its visible hit region and never steals focus while merely
  hovering.

### Calendar, reminders, weather, and permissions

- Calendar supports a useful list and month view, event add/edit/delete where
  the source calendar permits it, calendar colors, and one-click meeting join.
- Join appears only for a valid URL and produces clear success/failure feedback.
- Reminders can be filtered by an explicit selected-list setting; `nil` or
  all-list loading is not an acceptable default.
- Quick task capture supports a destination list, natural-language deadline,
  multiline entry, completion, reorder, archive, and restore.
- Weather has exact Location permission state plus a manual city or ZIP
  fallback and locale-correct units.
- Calendar, Reminders, Location, Camera, Microphone, Speech Recognition,
  Bluetooth, Downloads, Screen Recording, Accessibility, and Notifications
  each have an honest status, purpose, grant/recovery action, and restricted or
  denied explanation. The shipped app must request the correct permission on a
  fresh install rather than relying on a stale TCC grant.

### Personal utility modules

- Downloads show current progress and a safe open/reveal action.
- Bluetooth shows device identity, connection state, battery, and charging
  state when the hardware reports them honestly.
- Now Playing shows source, art, title, progress, transport, volume, and queue
  only to the degree the active player API supports them.
- Shelf accepts files and screenshots, keeps previews and clipboard history
  stable across reopen, and never crashes on a corrupt or missing item.
- Notes support quick jot, a selected destination, multiline/list continuation,
  append, copy, undo, and conflict-safe persistence.
- Camera/microphone preflight and teleprompter remain Tools, never a primary
  navigation destination.

### Reliability and polish

- Prefer event-driven refresh. Polling must not flash, alternate cards, restart
  playback art, leak across sleep/wake, or show brightness HUD changes caused
  by an ambient sensor.
- The app restores its prior mode, module, draft, and followed task after
  reopen.
- External displays and fullscreen spaces receive deliberate behavior rather
  than duplicate noise.
- Empty, unavailable, denied, read-only, and offline states explain the exact
  condition and the next recovery action.
- Controls have Apple-quality hit targets, keyboard and VoiceOver labels,
  Dynamic Type behavior on iPhone, restrained motion, and no decorative status
  animation that implies work is changing when it is not.

## Mobile additions beyond Crest

- Native task creation from Buddy, Share Sheet, Siri, Spotlight, and Action
  Button, with the same typed request and durable outbox.
- Workspace selection, Codex/Claude routing, attachments, follow-up, stop, and
  completion review from iPhone over paired Tailscale transport.
- Push only for `Needs You`, failure, loss of an active host, or a deliberately
  followed completion.
- One Live Activity at a time for the deliberately followed task; all actions
  deep-link to current authenticated state before execution.
- A private read-only web fallback for status and deep links, not a second task
  store or generic remote shell.

## Explicitly excluded

- Pomodoro and Apple Watch work.
- A generic AI chat surface or a duplicate Claude assistant inside Tools.
- Inbound Telegram as a task store or control plane. Telegram may send a quiet
  outbound alert that opens the exact Buddy task.
- Broad notification mirroring, session-wide approval bypasses, arbitrary shell
  execution, and UI animation that rotates routine sessions for novelty.
- Paid infrastructure or a hosted database unless a later, evidenced limitation
  of paired Mac plus Tailscale requires it and Greg separately approves cost.

## Final parity oracle

Parity is accepted only when every adopted item is either physically verified
on the signed Mac and iPhone builds or explicitly recorded as unavailable with
the exact platform/API limitation. A source file, unit test, Simulator image,
TestFlight upload, healthy card, or changelog claim is not by itself physical
end-to-end proof.
