# Adaptive native acceptance proof

Date: 2026-07-19 PDT  
Branch: `codex/completion-hardening-20260719`  
Base: `e597c4f2d346bd2a79ecb4b8f4984b188af07824`

This record keeps implementation, signed delivery, installed runtime, and
physical-device proof separate. Simulator or source-level evidence is never
treated as physical iPhone acceptance.

## Implemented hardening

- Immediate-attention counts now include only approvals, questions, failed
  work, and tasks that explicitly need Greg. Routine work, followed tasks,
  verified tasks, and Mac queueing no longer inflate the badge.
- The exact approval or decision appears before the generic signal summary.
- Reviewed verified-task state persists across app launches.
- The native action dock and approval chrome remain readable at the largest
  accessibility text size. Approval actions use a vertical layout at
  accessibility sizes.
- The direct-device verifier refuses to OCR an occluded iPhone Mirroring
  window.
- The Mac hardened-runtime entitlement set now includes camera and audio input
  in addition to Bluetooth and calendar access.
- Swift 6 concurrency, isolation, deprecated API, and unsafe Core Audio pointer
  warnings observed in the release build were removed.

## Automated proof

| Surface | Result | Evidence |
| --- | --- | --- |
| Mac app XCTest | 581 passed, 2 intentional skips, 0 failed | `/private/tmp/codeisland-swift-full-tests.log` |
| Shared core XCTest | 238 passed, 0 failed | `/private/tmp/codeisland-swift-full-tests.log` |
| Acceptance scripts | 69 passed, 0 failed | `/private/tmp/codeisland-all-bats.log` |
| Companion model checks | 25 passed, 0 failed | `/private/tmp/codeisland-model-tests.log` |
| iPhone unit and UI suite | 79 total, 78 passed, 1 opt-in physical test skipped, 0 failed | `/private/tmp/CodeIsland-completion-clean-0719-2.xcresult` |
| UI and protocol static guard | Passed | `/private/tmp/codeisland-ui-regressions.log` |
| Shell and entitlement syntax | Passed | `shellcheck` and `plutil -lint CodeIsland.entitlements` |

The full iPhone suite ran on the `CodeIsland Clean Acceptance` iPhone 16
Simulator, iOS 26.5, device ID
`FE390564-DC30-4460-AA6D-05430B5ED107`. The only skipped test is the explicitly
opt-in live paired Mac test.

## Adaptive visual proof

- Largest accessibility text size: the decision and approval flows remained
  selectable and their primary controls remained hittable.
- Dark appearance, increased contrast, reduced transparency, and Reduce Motion:
  the approval and question tests both passed together.
- Manual rendered captures were inspected at:
  - `/private/tmp/codeisland-question-axxxl-after.png`
  - `/private/tmp/codeisland-approval-axxxl.png`
  - `/private/tmp/codeisland-question-dark-contrast-reduced.png`

## Mac release-candidate proof

The ARM64 `1.0.56` local candidate was produced through
`scripts/build-dmg.sh`, mounted, and passed strict nested code-signature
verification. The packaged app contains the camera and audio-input
entitlements and the DMG is UDZO read-only compressed. This candidate is
ad-hoc signed and not notarized; it is build proof, not the install artifact.

Signed internal delivery must come from the GitHub workflow and must be
verified again after download.

## Live private transport proof

Tailscale reported `Running` for
`gregs-macbook-air.tail62f27c.ts.net` at `100.84.86.6`. After the installed Mac
app was running, both endpoints returned HTTP 200 with `running:true`:

- `http://127.0.0.1:43891/health`
- `https://gregs-macbook-air.tail62f27c.ts.net:9443/health`

The installed app at this stage was still version `1.0.55`; this proves the
existing private route, not the new release candidate.

## Remaining release gates

These rows must be updated with current evidence before the work is described
as fully delivered:

| Gate | Current state | Required proof |
| --- | --- | --- |
| Pull request and CI | Pending | Green required checks and merged commit |
| Signed Mac artifact | Pending | Workflow run, downloaded DMG, signature, entitlement, version, install, and both health endpoints |
| Internal TestFlight build | Pending | Workflow run, Apple `VALID`, tester availability, exact build number, and delivery receipt |
| Physical iPhone acceptance | Pending for the new build | Exact-build check-in plus pairing, task, approval, question, push, Live Activity, and away-use evidence |
| Direct-device visual proof | Optional and currently occluded | Unobscured iPhone Mirroring or a physical device visible to `devicectl` |

