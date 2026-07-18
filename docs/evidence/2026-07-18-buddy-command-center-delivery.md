# Buddy command-center delivery receipt — 2026-07-18

This receipt keeps source, signed distribution, installed runtime, and physical
iPhone acceptance as separate proof states.

## Premium source and native acceptance

- Premium command-center pull request: `revopsglobal/CodeIsland#44`.
- Premium merge commit: `8c072442fbe1ee44e5c2db133f920cea534ae83d`.
- Mac version correction pull request: `revopsglobal/CodeIsland#45`.
- Away-host reliability pull request: `revopsglobal/CodeIsland#48`.
- Release-regression pull request: `revopsglobal/CodeIsland#49`.
- Current `main`: `2f6456bb1f16d8118b975f982ba6469e6b80647d`.
- Native iPhone Simulator scheme: 39 passed, 0 failed, 0 skipped, and 0
  runtime warnings.
- Result bundle: `/tmp/CodeIsland-premium-full-final-20260718-0415.xcresult`.
- Reproducible visual smoke: eight settled light/dark native renders from
  `scripts/smoke-companion-ui.sh`, including idle, approval, question,
  multiple-attention, Sessions, and Tools states.
- Mac/Core unit suite after the away-host fix: 483 app tests passed with two
  intentional skips; 221 core tests passed.
- Release build: passed.

## Mac distribution and installed runtime

- Internal Apple Development build workflow:
  `revopsglobal/CodeIsland` run `29643405438`.
- Workflow source: `62f2f8f43496577efcd2268c6c26804ff5c811aa`.
- Artifact: `CodeIsland-macos-arm64-dmg`, ID `8429339117`.
- Version/build: `1.0.47`.
- Downloaded DMG SHA-256:
  `4b7a893db6512cfeaa36bcf75884a017b6f5e2e0261f194c4e65da8980e1b519`.
- Installed app: `/Applications/CodeIsland.app`.
- Architecture: `arm64`.
- Bundle identifier: `com.codeisland.app`.
- Signing authority: `Apple Development: Greg Harned (BD6FD6Q8AS)`.
- Team identifier: `44JG2Y95CH`.
- Calendar entitlement: present.
- Runtime PID after replacement: `67615`, launched from the installed app.
- Runtime health after replacement: loopback `/health` on
  `127.0.0.1:43891` and private Tailscale `/health` on port `9443` both
  returned HTTP 200 with `running: true` and `pendingCount: 0`.
- Reversible prior bundle:
  `/Users/gregharned/Library/Application Support/CodeIsland/Install Backups/20260718T120149Z/CodeIsland.app`.
- Away-host power proof: with remote access enabled, AC power connected, and
  the MacBook lid open, `pmset -g assertions` attributed a live
  `PreventUserIdleSystemSleep` assertion to PID `67615` with reason
  `CodeIsland remote access is enabled`.

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

Confirmed after the Mac upgrade:

- the existing paired iPhone record remained present;
- the production APNs token remained registered;
- a privacy-preserving silent resolved-state probe was accepted by APNs;
- the physical iPhone returned a lifecycle receipt at `2026-07-18T10:40:31Z`;
- the receipt reached the newly installed Mac runtime.

Not yet confirmed:

- `clientVersion` and `clientBuild` remain absent from the paired-device record;
- therefore the physical iPhone is **not** proven to have installed build
  `20260718112841`;
- the Mac was locked, and computer-use could not open iPhone Mirroring or
  TestFlight without bypassing that lock;
- Calendar full-access status could not be read from TCC while the Mac was
  locked, although the signed entitlement and explicit grant/recovery UI are
  present.

## Remaining physical acceptance

After unlocking the Mac or iPhone:

1. Open TestFlight and update CodeIsland Buddy to build `20260718112841`.
2. Launch Buddy once and verify the Mac records `clientVersion = 1.0.0` and
   `clientBuild = 20260718112841`.
3. Observe the Now surface for longer than the former four-second polling
   interval and confirm that content does not flash or rotate.
4. Exercise a real approval and question, then verify task/note creation,
   Calendar and selected-list Reminders, one-click meeting join, and a complete
   Live Activity/Dynamic Island start-to-resolution lifecycle.
5. Repeat one approval away from local Wi-Fi over Tailscale/cellular before
   declaring full remote E2E acceptance.
