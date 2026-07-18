# Buddy command-center delivery receipt — 2026-07-18

This receipt keeps source, signed distribution, installed runtime, and physical
iPhone acceptance as separate proof states.

## Source and native acceptance

- Pull request: `revopsglobal/CodeIsland#42`
- Merge commit: `c1ae7c62a0f829a4fa288b67750e5aad06ff8f60`
- Native iPhone Simulator scheme: 39 passed, 0 failed, 0 skipped.
- Result bundle: `/tmp/CodeIsland-buddy-full3-20260718-030951.xcresult`.
- Reproducible visual smoke: eight settled light/dark native renders from
  `scripts/smoke-companion-ui.sh`.

## Mac distribution and installed runtime

- Internal Apple Development build workflow:
  `revopsglobal/CodeIsland` run `29640882441`.
- Version: `1.0.45`.
- Downloaded DMG SHA-256:
  `5d85da9308bc308dad8a8e972f37adcf0c1203ca9df7b78e6a4715cc646673d5`.
- Installed app: `/Applications/CodeIsland.app`.
- Architecture: `arm64`.
- Bundle identifier: `com.codeisland.app`.
- Signing authority: `Apple Development: Greg Harned (BD6FD6Q8AS)`.
- Team identifier: `44JG2Y95CH`.
- Calendar entitlement: present.
- Runtime health: the loopback service on `127.0.0.1:43891` returned HTTP 200;
  the private Tailscale route on port `9443` returned the same healthy service.
- Reversible prior bundle:
  `/tmp/CodeIsland-1.0.44.backup-29640882441.app`.

The first Mac workflow attempt (`29640772344`) intentionally remains recorded
as failed. It requested Developer ID notarization, but the private repository
does not have those credentials. The successful replacement used the existing
stable Apple Development identity, which is the intended personal/internal
distribution path and preserves macOS privacy identity without another paid or
public-release boundary.

## TestFlight distribution

- Workflow: `revopsglobal/CodeIsland` run `29640773036`.
- Version/build: `1.0.0 (20260718102347)`.
- Bundle identifier: `com.revopsglobal.codeisland.buddy`.
- Apple delivery UUID: `cee034b4-ddea-43e5-b0ee-465d55db7002`.
- Apple processing state: `VALID`.
- Audience: `APP_STORE_ELIGIBLE`.
- Internal group: `CodeIsland Internal`, with all-build access.
- Tester: `gregharned@gmail.com`, state `ready`.
- Signed IPA artifact: `CodeIsland-Buddy-TestFlight-20260718102347`, artifact
  ID `8428573093`.

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
  `20260718102347`;
- the Mac was locked, and computer-use could not open iPhone Mirroring or
  TestFlight without bypassing that lock;
- Calendar full-access status could not be read from TCC while the Mac was
  locked, although the signed entitlement and explicit grant/recovery UI are
  present.

## Remaining physical acceptance

After unlocking the Mac or iPhone:

1. Open TestFlight and update CodeIsland Buddy to build `20260718102347`.
2. Launch Buddy once and verify the Mac records `clientVersion = 1.0.0` and
   `clientBuild = 20260718102347`.
3. Observe the Now surface for longer than the former four-second polling
   interval and confirm that content does not flash or rotate.
4. Exercise a real approval and question, then verify task/note creation,
   Calendar and selected-list Reminders, one-click meeting join, and a complete
   Live Activity/Dynamic Island start-to-resolution lifecycle.
5. Repeat one approval away from local Wi-Fi over Tailscale/cellular before
   declaring full remote E2E acceptance.

