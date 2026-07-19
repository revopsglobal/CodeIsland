#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  export COMPLETION_AUDIT_BIN="$TEST_TMPDIR/completion-audit"
  export SLEEP_BIN="$TEST_TMPDIR/sleep"
  mkdir -p "$TEST_TMPDIR"
  cat > "$SLEEP_BIN" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$SLEEP_BIN"
}

write_audit_stub() {
  local mode="${1:-stale}"
  cat > "$COMPLETION_AUDIT_BIN" <<STUB
#!/usr/bin/env bash
state_file="$TEST_TMPDIR/polls"
polls=0
if [ -f "\$state_file" ]; then
  polls="\$(cat "\$state_file")"
fi
polls=\$((polls + 1))
printf '%s\n' "\$polls" > "\$state_file"
case "$mode" in
  complete)
    jq -n '{
      complete:true,
      status:"complete",
      requiredGates:[],
      requirements:[
        {id:"real-physical-e2e",complete:true,status:"complete"}
      ]
    }'
    exit 0
    ;;
  after-two)
    if [ "\$polls" -ge 2 ]; then
      jq -n '{
        complete:true,
        status:"complete",
        requiredGates:[],
        requirements:[
          {id:"real-physical-e2e",complete:true,status:"complete"}
        ]
      }'
      exit 0
    fi
    jq -n '{
      complete:false,
      status:"physical-e2e-incomplete",
      requiredGates:[
        {
          id:"physical-buddy-checkin",
          status:"stale",
          owner:"greg",
          nextAction:"Open latest Buddy from TestFlight."
        }
      ]
    }'
    exit 2
    ;;
  *)
    jq -n '{
      complete:false,
      status:"physical-e2e-incomplete",
      requiredGates:[
        {
          id:"physical-buddy-checkin",
          status:"stale",
          owner:"greg",
          nextAction:"Open latest Buddy from TestFlight."
        }
      ]
    }'
    exit 2
    ;;
esac
STUB
  chmod +x "$COMPLETION_AUDIT_BIN"
}

@test "passes immediately when completion audit is already complete" {
  write_audit_stub complete
  export TIMEOUT_SECONDS=60
  export POLL_INTERVAL_SECONDS=0
  export MAX_POLLS=3

  run "$REPO_ROOT/scripts/wait-for-codeisland-completion.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .complete == true and
    .status == "complete" and
    .attempts == 1 and
    .timedOut == false and
    .finalAudit.status == "complete" and
    (.remainingGates | length) == 0'
}

@test "fails closed with stale physical Buddy gate when max polls are exhausted" {
  write_audit_stub stale
  export TIMEOUT_SECONDS=60
  export POLL_INTERVAL_SECONDS=0
  export MAX_POLLS=2

  run "$REPO_ROOT/scripts/wait-for-codeisland-completion.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "max-polls-exhausted" and
    .attempts == 2 and
    .finalAudit.status == "physical-e2e-incomplete" and
    ([.remainingGates[] | select(.id == "physical-buddy-checkin" and .owner == "greg")] | length) == 1 and
    (.nextAction | contains("Open latest Buddy"))'
}

@test "keeps polling until a later completion audit passes" {
  write_audit_stub after-two
  export TIMEOUT_SECONDS=60
  export POLL_INTERVAL_SECONDS=0
  export MAX_POLLS=3

  run "$REPO_ROOT/scripts/wait-for-codeisland-completion.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .complete == true and
    .status == "complete" and
    .attempts == 2 and
    .finalAudit.complete == true'
}

@test "fails parseably when completion audit output is not JSON" {
  cat > "$COMPLETION_AUDIT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "not json"
exit 2
STUB
  chmod +x "$COMPLETION_AUDIT_BIN"
  export TIMEOUT_SECONDS=60
  export POLL_INTERVAL_SECONDS=0
  export MAX_POLLS=1

  run "$REPO_ROOT/scripts/wait-for-codeisland-completion.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "max-polls-exhausted" and
    .finalAudit.status == "completion-audit-invalid-json" and
    ([.remainingGates[] | select(.id == "completion-audit-report" and .status == "invalid-json")] | length) == 1'
}
