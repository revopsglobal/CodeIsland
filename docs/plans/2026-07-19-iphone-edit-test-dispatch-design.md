# iPhone Edit-and-Test Dispatch Design

**Date:** 2026-07-19

**Status:** Approved by Greg

**Product:** CodeIsland Mac host and CodeIsland Buddy for iPhone

## Outcome

CodeIsland Buddy becomes a true away-from-Mac command surface, not merely a
status mirror. Greg can create a coding task from the iPhone, provide context,
and let a trusted Codex or Claude session inspect the selected workspace, edit
files, and run tests without waiting for another approval. Consequential
actions remain explicit gates.

The design is optimized for Greg as the only intended user. It reuses the
existing signed Mac host, paired-device authentication, Tailscale transport,
attention queue, push notifications, Live Activities, Dynamic Island, and
shared action/receipt model. It does not introduce a paid service, generic
remote shell, Telegram task store, or second control plane.

## Product context

Greg routinely runs several Codex and Claude tasks across different projects,
reviews their status on the Mac, and uses the iPhone for quick interruption,
approval, and away access. The missing cross-device job is the complete loop:

1. capture work from anywhere on the iPhone;
2. route it to the correct Mac workspace and agent;
3. let the agent edit and test safely;
4. intervene only for a real decision or consequential action; and
5. review trustworthy completion evidence without opening the Mac.

Adding another dashboard would not solve that job. The product must connect
capture, execution, attention, completion review, and handoff through the same
task identity.

## Chosen direction

### Native command center plus system capture surfaces

Buddy is the canonical mobile control surface. A native task composer is also
available through the iOS Share Sheet, App Intents, Siri, Spotlight, and the
Action Button. Every entry point creates the same typed task request and opens
the same Buddy review/status destination.

Two alternatives were rejected as primary architectures:

1. **App Intents only:** inexpensive and fast, but too shallow for workspace
   correction, attachments, failures, completion evidence, or steering several
   sessions.
2. **Telegram control:** universally reachable, but it would duplicate task
   state, weaken privacy and interaction quality, and become a second action
   system. Telegram remains an optional outbound alert and Buddy deep link.

## Authority model

The default authority profile for an iPhone-created coding task is
`Edit & Test`.

The agent may automatically:

- inspect the selected repository and its local instructions;
- read files and current Git/runtime state;
- create or switch to an isolated `codex/` branch or worktree when required by
  repository policy;
- edit files within the validated workspace;
- run formatters, builds, tests, and non-mutating diagnostics; and
- produce a completion review with exact evidence.

The agent must stop for explicit approval before:

- committing, pushing, merging, deploying, publishing, or releasing;
- changing credentials, authentication, secrets, permissions, or 2FA;
- mutating production data or invoking a destructive operation;
- spending money or increasing paid capacity;
- sending a human-facing external message; or
- expanding execution beyond the selected workspace and requested task.

Every approval is device-bound, request-bound, short-lived, single-use, and
revalidated against current host state. CodeIsland never exposes a generic
remote shell or accepts arbitrary command strings from the phone.

## Information architecture

### Now

`Now` is a stable signal-ranked surface:

1. exact approvals, questions, failures, or blocked decisions;
2. the deliberately followed active task;
3. a newly completed task awaiting review; and
4. a compact all-clear state.

Routine sessions never rotate through the main stage. Equal-priority work
stays pinned until Greg acts or deliberately selects another item.

### Sessions

`Sessions` is the complete portfolio of Codex and Claude work across projects.
It groups tasks as `Needs You`, `Running`, `Completed`, and `Failed`. Each task
supports:

- opening its current state and evidence;
- sending a follow-up instruction;
- pausing or stopping when the provider supports it;
- reviewing the completion result;
- continuing or revising the work; and
- opening the exact Mac session.

### Tools

`Tools` contains the Crest-class personal utilities: Calendar, tasks, notes,
Downloads, Shelf, Now Playing, weather, Bluetooth, camera/microphone preflight,
teleprompter, and configuration. `Hub` and `Glances` are not separate
user-facing destinations.

### Capture

A persistent `New Task` action opens the same composer used by the Share Sheet
and App Intents. It accepts:

- typed text;
- dictation or an attached voice note;
- Safari links;
- photos and screenshots;
- Files attachments; and
- text shared from another app.

The composer proposes a recent workspace and `Auto`, `Codex`, or `Claude`
routing. A confident match can be submitted in one action. An ambiguous match
requires workspace selection before the Mac accepts execution.

## Task contract

Each dispatch request contains:

- a client-generated stable task ID and idempotency key;
- prompt and structured attachment metadata;
- selected or inferred workspace identity;
- requested provider (`auto`, `codex`, or `claude`);
- authority profile (`edit-and-test`);
- requested proof/acceptance notes;
- originating paired-device ID; and
- client creation timestamp.

The host validates the device, task schema, workspace allow-list, attachment
limits, authority profile, and idempotency key before accepting the task. It
then returns a durable host task identity and an `Accepted` receipt.

## Lifecycle and receipts

The user-visible lifecycle is deliberately small:

- `Waiting for Mac`: retained on the iPhone but not accepted by the host;
- `Queued`: accepted and durably recorded by the Mac;
- `Working`: an agent session has started;
- `Needs You`: an exact approval, question, ambiguity, or blocker is pending;
- `Verified`: requested edits completed and required checks passed;
- `Failed`: execution stopped with a specific recoverable or terminal reason;
  and
- `Cancelled`: Greg or the host cancelled the task before completion.

The Mac emits append-only receipts for `accepted`, `started`, `changed`,
`tested`, `needs-approval`, `needs-answer`, `finished`, `failed`, and
`cancelled`. Buddy never infers a stronger state than the latest authenticated
receipt supports.

Each receipt includes task ID, event ID, monotonic sequence, timestamp,
provider/session handle where safe, concise redacted summary, and structured
evidence metadata. Sensitive details load only through the authenticated
Tailscale channel.

## Execution architecture

```text
iPhone composer / Share Sheet / Siri / Action Button
                         |
                         v
          Paired HTTPS request over Tailscale
                         |
                         v
       CodeIsland Mac validation and durable task queue
                         |
             +-----------+-----------+
             |                       |
             v                       v
       Codex session            Claude session
             |                       |
             +-----------+-----------+
                         |
                         v
          Shared events, evidence, and receipts
                         |
          +--------------+---------------+
          |              |               |
          v              v               v
        Buddy        Mac command       APNs and
                         center       ActivityKit
```

`/Applications/CodeIsland.app` remains the sole host and local executor. The
iPhone, private web fallback, push surfaces, and optional Telegram alert all
load or deep-link into the same task record and exact action contract.

The initial implementation should use a durable local host queue rather than a
new cloud database. The paired Mac is the execution authority, and Greg's
existing Tailscale connection is the private transport.

## Completion review

`Verified` opens a compact, evidence-first review containing:

- the requested outcome and final agent summary;
- workspace, provider, branch/worktree, and elapsed time;
- files added, changed, or removed;
- exact formatter/build/test commands and results;
- unresolved warnings or skipped verification;
- current Git and delivery state; and
- proposed next consequential action, if any.

Primary actions are `Continue`, `Revise`, `Open on Mac`, and `Archive`. A
contextual action such as `Approve Commit` or `Approve Push` appears only when
the task explicitly proposes that exact next action. Approval does not grant a
standing broader capability.

## Notifications and ambient surfaces

Immediate push is reserved for:

- approval or answer required;
- execution failure or an unrecoverable blocker;
- a specifically followed task completing; or
- loss of required host availability during an active task.

Routine progress updates the app quietly. A Live Activity represents at most
one deliberately followed task and may show `Working`, `Needs You`, `Verified`,
or `Failed`. Dynamic Island and Lock Screen actions deep-link to the exact
task; they do not execute sensitive actions from stale notification state.

An optional morning/evening digest summarizes completed, failed, and waiting
work. Telegram may send a redacted alert plus Buddy/private-web deep link but
cannot submit, approve, or mutate a task.

## Reliability and recovery

- **Mac unreachable:** retain the task locally as `Waiting for Mac`; retry with
  bounded backoff and never display `Queued` or `Working` without a host
  receipt.
- **Duplicate submission:** reuse the idempotency key and return the existing
  host task rather than launching a second session.
- **Mac restart:** reload accepted non-terminal tasks and their latest receipt;
  mark uncertain provider state explicitly instead of inventing progress.
- **Agent crash:** emit `Failed` with `Retry`, `Continue with other provider`,
  and `Open on Mac` where safe.
- **Workspace ambiguity:** require selection from validated recent/allowed
  workspaces before execution.
- **Workspace unavailable or dirty:** explain the exact condition and propose a
  safe isolated worktree or a user decision.
- **Expired/stale action:** refresh the task, discard the proposal, and explain
  that host state changed.
- **Attachment failure:** preserve the draft, identify the rejected file, and
  allow resubmission without duplicating the task.
- **Out-of-order delivery:** order receipts by host sequence and ignore stale
  push/snapshot updates.

## Attachment and privacy boundaries

- Enforce configurable per-file and total-request size limits.
- Copy accepted files into a task-scoped private inbox; never execute from an
  arbitrary shared URL or user-supplied absolute path.
- Validate content type and filename separately from extension.
- Require explicit user choice before including a photo, screenshot, or file.
- Keep push payloads redacted and opaque.
- Do not upload task content to a new CodeIsland cloud service.
- Retain enough audit metadata to explain actions without logging secrets or
  full sensitive prompts.

## Accessibility and interaction quality

- Every primary flow works one-handed with 44-point minimum targets.
- The composer and completion review support Dynamic Type and VoiceOver.
- Status is conveyed through text and symbols, never color alone.
- Reduce Motion removes progress decoration and nonessential transitions.
- Routine polling is visually inert; only new attention may animate once.
- Dictation, keyboard entry, Share Sheet submission, and cold-launch deep links
  all converge on the same editable draft before submission.

## E2E acceptance

The feature is accepted only when all of these real flows pass:

1. Type a Buddy task; the Mac accepts it, starts an agent, edits code, runs the
   requested tests, and returns a verified completion.
2. Dictate a task and separately share a Safari link, photo, and file into a
   task.
3. Auto-select the correct recent workspace and recover safely from an
   ambiguous match.
4. Send a follow-up to a running Codex session and a running Claude session.
5. Trigger a real approval and question, answer on the iPhone, and prove the
   exact blocked session resumes.
6. Attempt commit, push, deploy, destructive, credential, production-data,
   paid, and external-message actions; prove each stops at the correct gate.
7. Disconnect Tailscale, restart CodeIsland, duplicate-submit, and terminate
   the provider; prove recovery without duplicate execution or false state.
8. Complete one full task over cellular Tailscale with iPhone Wi-Fi disabled.
9. Verify redacted push, Live Activity, Dynamic Island, cold launch,
   background refresh, out-of-order delivery, and expired action behavior.
10. Confirm Mac and iPhone show the same task identity, state, receipts,
    evidence, and terminal outcome.
11. Pass Dynamic Type, VoiceOver, dark mode, reduced motion, battery, and
    multi-poll visual-stability checks.
12. Record signed TestFlight build identity, physical-device receipts, native
    screenshots, and exact tests separately from source, CI, and Apple
    processing claims.

The final release gate is a real iPhone-created task that changes code, passes
tests, requests permission before committing, and returns a trustworthy
completion review while the phone is away from local Wi-Fi.

## Non-goals

- Pomodoro or Apple Watch work.
- Multi-user tenancy, shared teams, or a hosted task backend.
- A terminal emulator or arbitrary shell access on iPhone.
- Automatic commit, push, merge, deploy, publish, production mutation, or
  external messaging under `Edit & Test`.
- Replacing CodeIsland's Crest-class tools or turning every utility event into
  a notification.
- An inbound Telegram bot or always-on Telegram daemon.
