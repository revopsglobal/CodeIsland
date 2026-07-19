#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  export LATEST_GATE_BIN="$TEST_TMPDIR/latest-gate"
  export SWIFT_BIN="$TEST_TMPDIR/swift"
  mkdir -p "$TEST_TMPDIR"
}

@test "fails closed when the latest TestFlight physical gate is stale" {
  cat > "$LATEST_GATE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{
  gate:{status:"stale",complete:false,nextAction:"Install and open the latest Buddy build."},
  latestTestFlight:{buildNumber:"20260719011702"}
}'
exit 2
STUB
  cat > "$SWIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "Executed 1 test, with 0 failures"
STUB
  chmod +x "$LATEST_GATE_BIN" "$SWIFT_BIN"

  run "$REPO_ROOT/scripts/report-strict-physical-e2e.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "physical-gate-incomplete" and
    .latestGate.status == "stale" and
    .interactionContract.passed == true'
}

@test "passes only when physical gate and interaction contract both pass" {
  cat > "$LATEST_GATE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{
  gate:{status:"matched",complete:true,nextAction:"Run strict physical E2E interaction acceptance."},
  latestTestFlight:{buildNumber:"20260719011702"}
}'
STUB
  cat > "$SWIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "Executed 1 test, with 0 failures"
STUB
  chmod +x "$LATEST_GATE_BIN" "$SWIFT_BIN"

  run "$REPO_ROOT/scripts/report-strict-physical-e2e.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .complete == true and
    .status == "complete" and
    .latestGate.complete == true and
    .interactionContract.passed == true'
}

@test "fails when the interaction contract test fails even if physical gate matches" {
  cat > "$LATEST_GATE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{
  gate:{status:"matched",complete:true,nextAction:"Run strict physical E2E interaction acceptance."},
  latestTestFlight:{buildNumber:"20260719011702"}
}'
STUB
  cat > "$SWIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "RemoteApprovalHTTPServerTests failed"
exit 1
STUB
  chmod +x "$LATEST_GATE_BIN" "$SWIFT_BIN"

  run "$REPO_ROOT/scripts/report-strict-physical-e2e.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "interaction-contract-failed" and
    .latestGate.complete == true and
    .interactionContract.passed == false and
    (.interactionContract.logTail | contains("failed"))'
}
