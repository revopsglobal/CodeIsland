# Private remote approvals

CodeIsland can expose pending Mac approvals to Greg's iPhone without a public
relay or paid backend. The Mac remains the only process that can resume a hook.

## Runtime path

1. CodeIsland listens on `127.0.0.1:43891` only.
2. CodeIsland configures Tailscale Serve on private HTTPS port `9443`.
3. Buddy or the private web app pairs with a rotating six-digit code from
   **Settings → Buddy**.
4. The paired device receives a bearer token. Buddy keeps it in the iOS
   Keychain; the web fallback keeps it in Safari local storage.
5. An authenticated approval fetch returns a two-minute action token bound to
   the exact device and request ID.
6. The Mac consumes that token once, re-checks that the same request is still
   pending, and only then resumes the original continuation.

The default private URL for this Mac is:

`https://gregs-macbook-air.tail62f27c.ts.net:9443`

Both the Mac and iPhone must be connected to the same tailnet. Tailscale Serve
is tailnet-only; this feature does not enable Funnel or publish a public URL.

## iPhone options

- **Buddy app:** foreground polling every four seconds, Keychain pairing,
  approve/deny confirmation, and APNs refresh when configured.
- **Safari fallback:** open the same private URL while Tailscale is connected,
  pair once, and optionally add it to the Home Screen.

The iOS project targets iPhone only. Apple Watch targets and WatchConnectivity
are not part of the generated project.

## Notifications

Polling and the Safari fallback work without any notification credentials.
Optional APNs uses the existing Apple Developer membership and no additional
service:

1. Create an APNs authentication key in the Apple Developer portal.
2. In **Settings → Buddy → iPhone notifications**, enter the key ID and select
   the downloaded `.p8` file.
3. Keep the topic as `com.revopsglobal.codeisland.buddy` and the team ID as
   `44JG2Y95CH`.

The `.p8` key stays on the Mac. Push payloads contain only opaque request
metadata and state; Buddy fetches current details over Tailscale.

## Local security and recovery

- Pairing codes expire after ten minutes and rotate after successful pairing.
- Pairing failures are rate-limited to eight attempts per five minutes.
- Device tokens are stored as SHA-256 hashes on the Mac with mode `0600`.
- Decisions are appended to
  `~/Library/Application Support/CodeIsland/remote-approval-audit.jsonl`.
- The Mac can prevent idle sleep only while an approval is actually pending.
- Revoke an iPhone or rotate the pairing code from **Settings → Buddy**.
- Disabling remote approvals stops the loopback listener. Tailscale may retain
  the inactive Serve route, but it has no reachable local target.

This direct Tailscale design remains the lowest-cost primary architecture.
Buddy native APNs and Live Activities are the only away-attention channel.
The private web fallback remains an authenticated Tailscale access path, not a
second notification surface. There are no Telegram credentials, notifier,
settings, fallback alerts, inbound bot, second queue, or durable Telegram state.

## Away readiness report

Use the strict physical report for final acceptance, and use the away readiness
report when deciding whether Greg can safely leave the Mac and finish the last
tap from his phone:

```bash
scripts/report-away-readiness.sh
```

The report combines the latest TestFlight/physical gate, local and Tailscale
host health, source-drift status, private web shell proof, and native Buddy
away-attention readiness. The private web shell check fetches the root Tailscale
URL without printing the body and verifies the CodeIsland title, tagline,
manifest/icon links, and the Questions, Approvals, and Hub sections. It exits
`2` until physical Buddy acceptance is complete, but
`status = ready-for-manual-physical-acceptance` means the Mac host, private web
fallback shell, and current TestFlight build are ready and the remaining
required gate is the physical iPhone opening the named Buddy build.
