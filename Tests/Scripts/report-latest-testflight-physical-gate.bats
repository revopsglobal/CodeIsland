#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  export GH_BIN="$TEST_TMPDIR/gh"
  export DEFAULTS_BIN="$TEST_TMPDIR/defaults"
  export DEFAULTS_LOG="$TEST_TMPDIR/defaults.log"
  export REPORT_PHYSICAL_ACCEPTANCE_BIN="$TEST_TMPDIR/report-physical"
  mkdir -p "$TEST_TMPDIR"
  cat > "$DEFAULTS_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DEFAULTS_LOG"
STUB
  chmod +x "$DEFAULTS_BIN"
}

@test "reports stale physical build against the newest successful TestFlight run" {
  cat > "$GH_BIN" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2" == "run list" ]]; then
  cat <<'JSON'
[
  {"databaseId":29667770858,"status":"completed","conclusion":"success","headSha":"33fc732","createdAt":"2026-07-19T00:56:09Z","url":"https://github.com/revopsglobal/CodeIsland/actions/runs/29667770858"}
]
JSON
  exit 0
fi
if [[ "$1 $2" == "run view" ]]; then
  cat <<'LOG'
Resolve build number	Building CodeIsland Buddy 1.0.0 (20260719005630)
Upload to App Store Connect	Delivery UUID: 3a9151da-3662-407b-84c0-feb81de00b2f
Verify TestFlight processing and internal availability	TestFlight build 20260719005630 processing state: VALID
Verify TestFlight processing and internal availability	TestFlight build 20260719005630 is valid, audience APP_STORE_ELIGIBLE, uploaded 2026-07-18T17:58:45-07:00
Upload signed IPA artifact	Artifact CodeIsland-Buddy-TestFlight-20260719005630 has been successfully uploaded! Final size is 2956413 bytes. Artifact ID is 8436310864
LOG
  exit 0
fi
exit 99
STUB

  cat > "$REPORT_PHYSICAL_ACCEPTANCE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n \
  --arg expectedBuild "$EXPECTED_CLIENT_BUILD" \
  '{
    gates:{
      complete:false,
      physicalBuildStatus:{
        status:"stale",
        expectedBuild:$expectedBuild,
        newestObservedBuild:"20260718212803",
        newestObservedDeviceID:"device-1"
      }
    }
  }'
STUB
  chmod +x "$GH_BIN" "$REPORT_PHYSICAL_ACCEPTANCE_BIN"

  run "$REPO_ROOT/scripts/report-latest-testflight-physical-gate.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .latestTestFlight.databaseId == 29667770858 and
    .latestTestFlight.buildNumber == "20260719005630" and
    .latestTestFlight.deliveryUUID == "3a9151da-3662-407b-84c0-feb81de00b2f" and
    .latestTestFlight.appleState == "VALID" and
    .latestTestFlight.audience == "APP_STORE_ELIGIBLE" and
    .latestTestFlight.artifactID == "8436310864" and
    .physicalAcceptance.gates.physicalBuildStatus.expectedBuild == "20260719005630" and
    .macSettingsSync.status == "synced" and
    .macSettingsSync.expectedClientBuild == "20260719005630" and
    .gate.status == "stale" and
    .gate.complete == false and
    (.gate.nextAction | contains("Install and open CodeIsland Buddy build 20260719005630"))'
  grep -q 'write com.codeisland.app remoteApprovalExpectedClientVersion 1.0.0' "$DEFAULTS_LOG"
  grep -q 'write com.codeisland.app remoteApprovalExpectedClientBuild 20260719005630' "$DEFAULTS_LOG"
}

@test "passes when the newest TestFlight build is physically matched" {
  cat > "$GH_BIN" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2" == "run list" ]]; then
  cat <<'JSON'
[
  {"databaseId":1,"status":"completed","conclusion":"success","headSha":"abc","createdAt":"2026-07-19T00:00:00Z","url":"https://example.test/run/1"}
]
JSON
  exit 0
fi
if [[ "$1 $2" == "run view" ]]; then
  printf '%s\n' 'Resolve build number	Building CodeIsland Buddy 1.0.0 (20260719005630)'
  exit 0
fi
exit 99
STUB

  cat > "$REPORT_PHYSICAL_ACCEPTANCE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{gates:{complete:true,physicalBuildStatus:{status:"matched",expectedBuild:env.EXPECTED_CLIENT_BUILD}}}'
STUB
  chmod +x "$GH_BIN" "$REPORT_PHYSICAL_ACCEPTANCE_BIN"

  run "$REPO_ROOT/scripts/report-latest-testflight-physical-gate.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .latestTestFlight.buildNumber == "20260719005630" and
    .macSettingsSync.status == "synced" and
    .gate.status == "matched" and
    .gate.complete == true and
    (.gate.nextAction | contains("strict physical E2E interaction acceptance"))'
}

@test "can disable syncing the newest TestFlight build into Mac settings" {
  cat > "$GH_BIN" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2" == "run list" ]]; then
  cat <<'JSON'
[
  {"databaseId":1,"status":"completed","conclusion":"success","headSha":"abc","createdAt":"2026-07-19T00:00:00Z","url":"https://example.test/run/1"}
]
JSON
  exit 0
fi
if [[ "$1 $2" == "run view" ]]; then
  printf '%s\n' 'Resolve build number	Building CodeIsland Buddy 1.0.0 (20260719005630)'
  exit 0
fi
exit 99
STUB

  cat > "$REPORT_PHYSICAL_ACCEPTANCE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{gates:{complete:false,physicalBuildStatus:{status:"stale",expectedBuild:env.EXPECTED_CLIENT_BUILD}}}'
STUB
  chmod +x "$GH_BIN" "$REPORT_PHYSICAL_ACCEPTANCE_BIN"

  run env SYNC_MAC_EXPECTED_BUDDY_DEFAULTS=0 "$REPO_ROOT/scripts/report-latest-testflight-physical-gate.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .latestTestFlight.buildNumber == "20260719005630" and
    .macSettingsSync.status == "disabled"'
  [ ! -s "$DEFAULTS_LOG" ]
}

@test "fails clearly when no successful TestFlight run exists" {
  cat > "$GH_BIN" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2" == "run list" ]]; then
  printf '%s\n' '[]'
  exit 0
fi
exit 99
STUB
  chmod +x "$GH_BIN"

  run "$REPO_ROOT/scripts/report-latest-testflight-physical-gate.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .latestTestFlight == null and
    .gate.status == "missing-testflight-run" and
    .gate.complete == false'
}
