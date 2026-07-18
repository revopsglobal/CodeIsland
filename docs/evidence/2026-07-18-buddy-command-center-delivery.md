# Buddy command-center delivery receipt — 2026-07-18

This receipt keeps source, signed distribution, installed runtime, and physical
iPhone acceptance as separate proof states.

## Premium source and native acceptance

- Premium command-center pull request: `revopsglobal/CodeIsland#44`.
- Premium merge commit: `8c072442fbe1ee44e5c2db133f920cea534ae83d`.
- Mac version correction pull request: `revopsglobal/CodeIsland#45`.
- Away-host reliability pull request: `revopsglobal/CodeIsland#48`.
- Release-regression pull request: `revopsglobal/CodeIsland#49`.
- Login-launch reliability pull requests: `revopsglobal/CodeIsland#51` and
  `revopsglobal/CodeIsland#52`.
- Installed-runtime source: `bf69f80f64ffbd9115cc433bf7d44854da3ee3a5`.
- Current `main`: `22bfdc6da74064380a63e7bfb95fb74feea06ac5`.
- Native iPhone Simulator scheme: 39 passed, 0 failed, 0 skipped, and 0
  runtime warnings.
- Result bundle: `/tmp/CodeIsland-premium-full-final-20260718-0415.xcresult`.
- Reproducible visual smoke: eight settled light/dark native renders from
  `scripts/smoke-companion-ui.sh`, including idle, approval, question,
  multiple-attention, Sessions, and Tools states.
- Mac/Core unit suite after the final login recovery: 489 app tests passed with
  two intentional skips; 223 core tests passed.
- Release build: passed.

## Mac distribution and installed runtime

- Internal Apple Development build workflow:
  `revopsglobal/CodeIsland` run `29644344626`.
- Workflow source: `bf69f80f64ffbd9115cc433bf7d44854da3ee3a5`.
- Artifact: `CodeIsland-macos-arm64-dmg`, ID `8429617233`.
- Version/build: `1.0.49`.
- Downloaded DMG SHA-256:
  `ad666a75dff15ac51cae16551602eaab8b13098c128dd8628dd8a77f74ab9982`.
- Installed app: `/Applications/CodeIsland.app`.
- Architecture: `arm64`.
- Bundle identifier: `com.codeisland.app`.
- Signing authority: `Apple Development: Greg Harned (BD6FD6Q8AS)`.
- Team identifier: `44JG2Y95CH`.
- Calendar entitlement: present.
- Runtime PID after replacement: `80804`, launched from the installed app.
- Runtime health after replacement: loopback `/health` on
  `127.0.0.1:43891` and private Tailscale `/health` on port `9443` both
  returned HTTP 200 with `running: true`, `pendingCount: 0`,
  `hostVersion: 1.0.49`, and `launchAtLoginStatus: enabled`.
- Reversible prior bundle:
  `/Users/gregharned/Library/Application Support/CodeIsland/Install Backups/20260718T123300Z/CodeIsland.app`.
- Away-host power proof: with remote access enabled, AC power connected, and
  the MacBook lid open, `pmset -g assertions` attributed a live
  `PreventUserIdleSystemSleep` assertion to PID `80804` with reason
  `CodeIsland remote access is enabled`.
- Login recovery proof: after stale historical copies were unregistered from
  LaunchServices without deleting their files, the installed bundle was the
  sole canonical `com.codeisland.app`. The first 1.0.49 launch recovered
  ServiceManagement from `notFound` to `enabled`, persisted the explicit
  preference, and reported no registration error.

The DMG is intentionally not Developer ID notarized. It is a private internal
build signed with the existing stable Apple Development identity, which
preserves the app's team and bundle identity without adding a paid or public
release boundary. Strict nested signature verification passed before and after
installation.

## TestFlight distribution

- Workflow: `revopsglobal/CodeIsland` run `29642614681`.
- Source: `8c072442fbe1ee44e5c2db133f920cea534ae83d`.
- Version/build: `1.0.0 (20260718112841)`.
- Bundle identifier: `com.revopsglobal.codeisland.buddy`.
- Apple delivery UUID: `ec60c2ab-002b-4884-818f-3f24bd9e2370`.
- Apple processing state: `VALID`.
- Audience: `APP_STORE_ELIGIBLE`.
- Internal group: `CodeIsland Internal`, with all-build access.
- Tester: `gregharned@gmail.com`, state `ready`.
- Signed IPA artifact: `CodeIsland-Buddy-TestFlight-20260718112841`, artifact
  ID `8429103078`.
- Downloaded IPA SHA-256:
  `b79dd62bae8b98794e60be7195a93f04ac7a50aa737a88f142fcb6ee98b2f54c`.

This is internal TestFlight distribution only. No public App Store release was
submitted.

## Physical iPhone proof

Confirmed on the unlocked physical pair:

- TestFlight showed CodeIsland Buddy `1.0.0 (20260718112841)` as installed and
  opened it on Greg's physical iPhone.
- The paired-device record immediately advanced to
  `lastSeenAt = 2026-07-18T17:05:55Z` with `clientVersion = 1.0.0` and
  `clientBuild = 20260718112841`. Strict
  `scripts/report-physical-acceptance.sh` then passed
  every gate with `physicalMatchCount = 1`, `physicalBuildConfirmed = true`,
  and `complete = true`.
- Three settled captures at 0, 8, and 16 seconds showed the same Now surface;
  only the system clock changed. The former four-second full-surface flash did
  not recur.
- Sessions rendered authenticated host data (`2 running`, later `1 running`)
  and `no decisions waiting`; it did not substitute Bluetooth discovery or a
  reconnect/loading card.
- The physical Calendar module read Greg's real July 2026 store, `40 upcoming`,
  the month grid, and the selected-day `Tutu at coast` event. The Now surface
  also rendered `66 degrees, Clear, Ridgefield, Washington`.
- Work Tools rendered the real Tasks count (`10 open`), Notes, Prompter,
  Camera, Shelf (`20 recent items`), Notifications, and Downloads (`12 recent
  downloads`). The New Task route opened its focused quick-jot composer and
  accepted typed text; that acceptance draft was intentionally cancelled so it
  did not leave test data. The earlier physical add/store/cleanup receipt still
  proves the actual Reminders write path.

The production attention lifecycle also passed on this exact build:

- A real hook-socket `AskUserQuestion` produced physical request
  `decbb81a-45a0-4edf-9e0c-eda2e6aef703`. Buddy replaced routine content with
  one `Decision needed` card showing the exact prompt and choices.
- The iPhone selected `Continue`, displayed the single-use review confirmation,
  and returned `behavior: allow` with the exact answer through the blocked Unix
  socket.
- ActivityKit reported `activeActivityCount = 1`, `activityState = active`, and
  `source = activityStarted` at `2026-07-18T17:13:52Z`, then
  `activeActivityCount = 0`, `state = resolved`, and `source = notification` at
  `2026-07-18T17:15:22Z` after the answer.
- A second visual probe, request
  `28b8bdcf-dff7-4981-b3ca-2b15c686e637`, again reached active ActivityKit
  state and then `activityState = dismissed` with zero active activities at
  `2026-07-18T17:16:55Z` after its socket was cancelled. No pending request or
  test data remained.

iPhone Mirroring rendered the Home-screen Dynamic Island as the plain black
hardware cutout even while ActivityKit reported the request active. That is
valid physical lifecycle proof, but not visual acceptance of CodeIsland's
compact or expanded Dynamic Island artwork. The device still has no per-
activity update token, so token-based remote update remains a separate gate.

## Remaining physical acceptance

1. Observe the compact and expanded Dynamic Island or Lock Screen artwork
   directly on the physical phone, outside iPhone Mirroring, and capture a per-
   activity update token plus token-based update/end.
2. Repeat one approval away from local Wi-Fi over Tailscale/cellular. Changing
   Wi-Fi/VPN state is intentionally left for an explicit network-setting test.
3. Run the remaining real-data mutation matrices: Calendar add/edit/delete,
   recurrence, and Join; selected-list Reminders lifecycle; Notes conflict,
   checklist, and undo; Shelf/Downloads transfer; and device-control modules.
