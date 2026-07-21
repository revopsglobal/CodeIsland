# Telegram Secure Approval Sheet Design

Date: 2026-07-20
Status: Approved
Owner: Greg Harned

## Goal

Let Greg review and resolve consequential CodeIsland approvals from a focused sheet inside Telegram without opening CodeIsland Buddy. Telegram remains an escalation surface. CodeIsland on the paired Mac remains the only approval authority.

The chat message stays redacted. Private action details are fetched from the Mac over authenticated Tailscale HTTPS only after Telegram identity validation.

## Approved Experience

Telegram notifies only when CodeIsland needs Greg:

- a consequential action is waiting for approval;
- an agent question or decision blocks progress; or
- a failed task needs intervention.

Routine progress, successful completion, session changes, Glances data, telemetry, and repeated working-state updates remain silent.

For an actionable approval, the Telegram message contains one `Review securely` button. It opens a compact Telegram Mini App sheet with:

1. action, agent, workspace, risk, and changed scope;
2. exact command or tool input behind `Show details`;
3. `Deny` and `Approve once` actions;
4. a second confirmation showing the exact action fingerprint; and
5. a terminal result of approved, denied, expired, stale, or unavailable.

There is no `Always allow` action.

## Selected Approach

Build a thin Telegram Mini App over the existing CodeIsland remote approval service.

Rejected alternatives:

- Opening the full CodeIsland web app inside Telegram exposes unrelated Hub, Glances, and task UI and does not provide a focused escalation experience.
- Direct Telegram callback buttons require an inbound polling or webhook control path and remove the deliberate review step.

The selected design introduces no new daemon, scheduler, database, public server, or parallel approval implementation.

## Architecture

### Existing authority retained

`RemoteApprovalService`, `RemoteTaskCoordinator`, and `RemoteActionTokenVault` remain authoritative. The Telegram sheet never resolves an agent request directly. It submits through the same coordinator used by Buddy and the paired web client.

Existing invariants remain:

- decisions use POST, never GET;
- action tokens are short-lived, request-specific, identity-bound, and single-use;
- stale or already-resolved requests fail closed;
- the Mac records the decision through the existing coordinator and attention lifecycle.

### New components

#### Telegram approval launch vault

An in-memory vault maps a cryptographically random launch nonce to:

- the pending request ID;
- Telegram message and chat identifiers;
- creation and expiration timestamps; and
- the expected escalation kind.

The Telegram button URL contains only this launch nonce. It contains no request details, device bearer token, action token, command, path, or decision.

Launch records expire after ten minutes or immediately after the request resolves. Opening a launch URL never mutates approval state.

#### Telegram identity validator

The Mac validates the raw Telegram Mini App `initData` using Telegram's HMAC-SHA-256 contract and the configured bot token. Validation requires:

- a valid constant-time signature comparison;
- an `auth_date` no older than 60 seconds;
- the configured private chat and allowlisted Telegram user;
- a pending launch nonce; and
- Tailscale HTTPS transport.

Unsigned `initDataUnsafe` is never trusted.

#### Focused Mini App shell

The existing remote HTTP server serves a Telegram-specific HTML shell and narrowly scoped JSON endpoints. The shell is mobile-first and uses Telegram theme, safe-area, Dynamic Type, reduced-motion, and accessibility values.

It does not load the full Personal Hub application.

#### Telegram approval session

After Telegram identity and launch validation, CodeIsland creates a short-lived in-memory session bound to:

- Telegram user and chat;
- launch nonce and request ID;
- a fresh session nonce; and
- a maximum lifetime of five minutes.

The approval snapshot is generated for a deterministic Telegram device identity. This lets the existing action-token vault issue its normal 120-second, single-use action token for the exact request.

### Routes

- `GET /telegram/approval?launch=<nonce>` serves static shell HTML only.
- `POST /api/telegram/session` validates Telegram `initData` and returns the focused summary, session nonce, and exact-request action token.
- `POST /api/telegram/approvals/<id>/decision` validates Telegram identity, session nonce, launch binding, decision, and action token before calling the existing coordinator.

All API responses use `Cache-Control: no-store`. Security responses contain generic errors and never echo tokens or sensitive action details.

## Data Flow

1. A new approval enters CodeIsland's pending queue.
2. The existing attention pipeline asks `TelegramAttentionNotifier` to notify.
3. The notifier creates a launch nonce and sends a redacted Telegram message with a `Review securely` Mini App button.
4. Telegram returns the bot message ID, which CodeIsland retains in memory with the launch record.
5. Greg opens the sheet. Telegram supplies signed `initData` to the Mini App.
6. The sheet POSTs `initData` and launch nonce to the Mac over the private Tailscale URL.
7. CodeIsland validates identity, freshness, launch state, and pending-request state.
8. CodeIsland returns the summary and an existing-style 120-second action token.
9. `Show details` reveals already-fetched private detail in the sheet. Nothing is added to the chat transcript.
10. Greg taps `Approve once` or `Deny`, reviews the action fingerprint, and confirms.
11. The sheet POSTs the decision. CodeIsland consumes the single-use token and resolves through the existing coordinator.
12. The sheet shows the terminal result and closes after a short delay.
13. CodeIsland edits the original Telegram message to `Approved`, `Denied`, `Resolved elsewhere`, or `Expired` and removes its action button.

If the request is resolved from Buddy, the web app, or the Mac, the same Telegram message is edited instead of sending another notification.

## Information Design

### Summary state

The initial sheet shows:

- a plain-language action headline;
- agent and source application;
- workspace and session context;
- deterministic risk level and reason;
- changed files, external destination, credential boundary, or other affected scope when available; and
- request age and expiration state.

Risk uses text and symbols in addition to color. Risk classification is deterministic and testable. It does not use an LLM.

### Expanded details

`Show details` reveals the exact available command, arguments, tool input, paths, network destination, and captured rationale in a selectable monospaced region. Empty fields are omitted rather than represented as guesses.

### Decision state

`Deny` is visually quiet but always available. `Approve once` is the primary action. A compact confirmation sheet repeats the action fingerprint before submission.

The current request stays pinned. If multiple escalations exist, resolution advances to the next highest-risk request. There is no timer carousel, automatic switching, or decorative flashing.

## Escalation Policy

One Telegram message is created per escalation ID. Duplicate pending events update or reuse the existing message.

The secure approval sheet is available only for a pending actionable approval. Agent questions continue to use the existing private web review path in this release. Failed tasks receive a review link but no approval control unless a real pending approval exists.

Resolution edits the existing message. It does not create a second completion notification.

## Security and Privacy

- Chat text remains redacted and contains no private command detail.
- The launch URL contains only a random nonce.
- Telegram-signed `initData` is verified server-side and checked for freshness.
- Only the configured private chat and allowlisted Telegram user are accepted.
- Details travel only between the Telegram client and the Mac over Tailscale HTTPS.
- Approval is a POST protected by a Telegram session nonce and the existing single-use action token.
- Link previews, scanners, browser prefetch, and GET requests cannot approve.
- Action and session tokens never appear in URLs, Telegram messages, logs, UserDefaults, or error text.
- Bot-token persistence moves from UserDefaults to macOS Keychain with a one-time migration and deletion of the legacy preference value.
- The Mini App origin is allowlisted in BotFather for the configured Tailscale HTTPS host.
- No public ingress is added.

## Failure Handling

| Condition | User experience | System behavior |
| --- | --- | --- |
| Mac or Tailscale unavailable | `Mac unavailable. Retry when connected.` | No decision attempted |
| Invalid Telegram identity | `This approval is not available for this account.` | HTTP 403, no details returned |
| Expired launch | `This review link expired.` | Button removed on next message reconciliation |
| Expired action token | `Approval expired. Refresh to review again.` | Fresh snapshot required |
| Already resolved | Terminal resolved state | Original message edited, no duplicate action |
| Token replay | `Approval is no longer available.` | HTTP 403 or 409, token remains unusable |
| Telegram message edit failure | Sheet still shows authoritative result | Logged without changing approval outcome |
| Bot API unavailable | APNs, Live Activity, Buddy, and web remain unaffected | Retry is bounded; no alert loop |

## Settings

The Buddy settings section gains:

- `Telegram secure approvals` status;
- configured bot and private-chat validation state;
- allowlisted Telegram user identity;
- Mini App origin readiness;
- `Send test escalation`;
- `Open test approval sheet`; and
- last successful delivery and last failure.

No secrets are displayed. Bot token entry is Keychain-backed.

## Testing

### Unit tests

- Telegram `initData` HMAC validation with official-style valid and invalid vectors.
- Freshness, wrong-user, wrong-chat, malformed-data, and constant-time failure paths.
- Launch-nonce generation, expiration, lookup, and resolved-request cleanup.
- Message payload redaction and `web_app` button construction.
- Risk classification and action fingerprint stability.
- Telegram session binding and expiration.
- Action-token single use, replay rejection, request binding, and identity binding.
- Keychain migration deletes the legacy UserDefaults token only after successful storage.

### Integration tests

- Shell GET has no sensitive data and cannot mutate state.
- Valid session creation returns the exact pending approval summary.
- Approve and deny resolve through the existing coordinator.
- Stale, expired, mismatched, and replayed decisions fail closed.
- Resolution from another surface edits or disables the existing Telegram message.
- Duplicate attention events do not create duplicate Telegram messages.
- Telegram API failures do not affect APNs, Live Activity, Buddy, or web approval paths.

### Manual and physical acceptance

1. Trigger a real harmless approval from Codex or Claude.
2. Confirm one redacted escalation arrives in the existing private Telegram chat on Mac and iPhone.
3. Open `Review securely` on the physical iPhone with Tailscale connected.
4. Verify summary hierarchy, expandable exact details, dark/light appearance, Dynamic Type, VoiceOver labels, and reduced motion.
5. Approve once and prove the exact waiting hook receives the allow response.
6. Repeat with deny, expired link, stale request, wrong Telegram identity, offline Mac, and token replay.
7. Resolve once from Buddy or the existing web app and prove the Telegram message updates without a second alert.
8. Record physical-device evidence separately from unit, integration, CI, signing, and install proof.

## Rollout and Cost

The feature is disabled until bot identity, chat identity, Mini App origin, Keychain token, and Tailscale health all validate. Existing alert-only behavior remains the fallback.

No paid service, public hosting, App Store submission, new bot, or iOS binary is required. The Mac app update and BotFather Mini App origin configuration are sufficient. Expected incremental service cost is $0.

## Non-Goals

- General chat-based task control.
- Routine progress notifications.
- Permanent or blanket approval.
- Public Internet access to the Mac.
- A Telegram webhook or always-on polling daemon.
- Replacing Buddy, Live Activities, APNs, or the private web app.
- Answering agent questions inside the Telegram sheet in this first release.
