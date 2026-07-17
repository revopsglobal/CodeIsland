#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  mkdir -p "$TEST_TMPDIR"
  export ASC_REQUEST_LOG="$TEST_TMPDIR/requests.log"
  export ASC_REQUEST_COMMAND="$TEST_TMPDIR/mock-asc"
  export ASC_ISSUER_ID="issuer"
  export ASC_KEY_ID="key"
  export ASC_PRIVATE_KEY_PATH="$TEST_TMPDIR/AuthKey.p8"
  export TESTER_EMAIL="gregharned@gmail.com"
  export ADD_BUNDLE_ID="com.harned.estate"
  export REMOVE_APP_NAME="Orca IDE"
  export FORCE_READD="0"
  export RESEND_TESTFLIGHT_INVITATION="0"
  export ASC_RECEIPT_PATH="$TEST_TMPDIR/receipt.json"
  : > "$ASC_PRIVATE_KEY_PATH"

  cat > "$ASC_REQUEST_COMMAND" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
method="$1"
path="$2"
body="${3:-}"
printf '%s\t%s\t%s\n' "$method" "$path" "$body" >> "$ASC_REQUEST_LOG"

case "$path" in
  /v1/apps)
    if [[ "${MOCK_SCENARIO:-}" == "missing-orca" ]]; then
      printf '%s\n' '{"data":[{"id":"app-h","attributes":{"name":"Harned Estate","bundleId":"com.harned.estate"}}]}'
    else
      printf '%s\n' '{"data":[{"id":"app-h","attributes":{"name":"Harned Estate","bundleId":"com.harned.estate"}},{"id":"app-o","attributes":{"name":"Orca IDE","bundleId":"com.orca.ide"}}]}'
    fi
    ;;
  /v1/betaTesters)
    printf '%s\n' '{"data":[{"id":"tester-1","attributes":{"email":"gregharned@gmail.com","state":"ACCEPTED"}}]}'
    ;;
  /v1/apps/app-h/betaGroups)
    printf '%s\n' '{"data":[{"id":"group-h","attributes":{"name":"Harned Internal","isInternalGroup":true,"hasAccessToAllBuilds":true}}]}'
    ;;
  /v1/apps/app-o/betaGroups)
    printf '%s\n' '{"data":[{"id":"group-o","attributes":{"name":"Orca Internal","isInternalGroup":true,"hasAccessToAllBuilds":true}}]}'
    ;;
  /v1/betaGroups/group-h/betaTesters)
    if [[ "${MOCK_SCENARIO:-}" == "force-readd" && ! -f "$TEST_TMPDIR/harned-removed" ]] ||
       [[ -f "$TEST_TMPDIR/harned-added" ]]; then
      printf '%s\n' '{"data":[{"id":"tester-1","attributes":{"email":"gregharned@gmail.com"}}]}'
    else
      printf '%s\n' '{"data":[]}'
    fi
    ;;
  /v1/betaGroups/group-o/betaTesters)
    if [[ -f "$TEST_TMPDIR/orca-removed" ]]; then
      printf '%s\n' '{"data":[]}'
    else
      printf '%s\n' '{"data":[{"id":"tester-1","attributes":{"email":"gregharned@gmail.com"}}]}'
    fi
    ;;
  /v1/betaGroups/group-h/relationships/betaTesters)
    if [[ "$method" == "DELETE" ]]; then
      : > "$TEST_TMPDIR/harned-removed"
    else
      [[ "$method" == "POST" ]]
      : > "$TEST_TMPDIR/harned-added"
    fi
    printf '%s\n' '{}'
    ;;
  /v1/betaGroups/group-o/relationships/betaTesters)
    [[ "$method" == "DELETE" ]]
    : > "$TEST_TMPDIR/orca-removed"
    printf '%s\n' '{}'
    ;;
  /v1/betaTesterInvitations)
    [[ "$method" == "POST" ]]
    if [[ "${MOCK_SCENARIO:-}" == "already-accepted" ]]; then
      printf '%s\n' '{"data":null,"meta":{"alreadyAccepted":true}}'
    else
      printf '%s\n' '{"data":{"type":"betaTesterInvitations","id":"invite-harned-1"}}'
    fi
    ;;
  *)
    echo "unexpected request: $method $path" >&2
    exit 64
    ;;
esac
MOCK
  chmod +x "$ASC_REQUEST_COMMAND"
}

@test "force re-adds Harned Estate and sends an app-specific invitation" {
  export MOCK_SCENARIO="force-readd"
  export FORCE_READD="1"
  export RESEND_TESTFLIGHT_INVITATION="1"

  run "$REPO_ROOT/scripts/relocate-testflight-tester.sh"

  [ "$status" -eq 0 ]
  grep -q $'DELETE\t/v1/betaGroups/group-h/relationships/betaTesters' "$ASC_REQUEST_LOG"
  grep -q $'POST\t/v1/betaGroups/group-h/relationships/betaTesters' "$ASC_REQUEST_LOG"
  grep -q $'POST\t/v1/betaTesterInvitations' "$ASC_REQUEST_LOG"
  jq -e '.state == "ready" and .invitationState == "sent" and .invitationId == "invite-harned-1"' "$ASC_RECEIPT_PATH"
}

@test "keeps Harned Estate ready when Apple says the invitation is already accepted" {
  export MOCK_SCENARIO="already-accepted"
  export RESEND_TESTFLIGHT_INVITATION="1"

  run "$REPO_ROOT/scripts/relocate-testflight-tester.sh"

  [ "$status" -eq 0 ]
  jq -e '.state == "ready" and .invitationState == "already-accepted" and .invitationId == ""' "$ASC_RECEIPT_PATH"
}

@test "restores Harned Estate and removes Orca IDE with verification" {
  run "$REPO_ROOT/scripts/relocate-testflight-tester.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Added gregharned@gmail.com to Harned Estate / Harned Internal"* ]]
  grep -q $'POST\t/v1/betaGroups/group-h/relationships/betaTesters' "$ASC_REQUEST_LOG"
  grep -q $'DELETE\t/v1/betaGroups/group-o/relationships/betaTesters' "$ASC_REQUEST_LOG"
  jq -e '.state == "ready" and .addedBundleId == "com.harned.estate" and .removedApp == "Orca IDE"' "$ASC_RECEIPT_PATH"
}

@test "restores Harned Estate when Orca belongs to another Apple team" {
  export MOCK_SCENARIO="missing-orca"

  run "$REPO_ROOT/scripts/relocate-testflight-tester.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Orca IDE requires Stop Testing"* ]]
  grep -q $'POST\t/v1/betaGroups/group-h/relationships/betaTesters' "$ASC_REQUEST_LOG"
  jq -e '.state == "ready" and .removedAppState == "not-visible"' "$ASC_RECEIPT_PATH"
}
