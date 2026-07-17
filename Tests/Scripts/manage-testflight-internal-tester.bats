#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  mkdir -p "$TEST_TMPDIR"
  export ASC_REQUEST_LOG="$TEST_TMPDIR/requests.log"
  export ASC_REQUEST_STATE="$TEST_TMPDIR/state"
  export ASC_REQUEST_COMMAND="$TEST_TMPDIR/mock-asc"
  export ASC_ISSUER_ID="issuer-secret-marker"
  export ASC_KEY_ID="key-secret-marker"
  export ASC_PRIVATE_KEY_PATH="$TEST_TMPDIR/AuthKey.p8"
  export TESTER_EMAIL="gregharned@gmail.com"
  export BUNDLE_ID="com.revopsglobal.codeisland.buddy"
  export BETA_GROUP_NAME="CodeIsland Internal"
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
    printf '%s\n' '{"data":[{"type":"apps","id":"app-1","attributes":{"name":"CodeIsland Buddy","bundleId":"com.revopsglobal.codeisland.buddy"}}]}'
    ;;
  /v1/apps/app-1/betaGroups)
    if [[ "${MOCK_SCENARIO:-}" == "wrong-group" ]]; then
      printf '%s\n' '{"data":[{"type":"betaGroups","id":"group-2","attributes":{"name":"External","isInternalGroup":false,"hasAccessToAllBuilds":true}}]}'
    else
      printf '%s\n' '{"data":[{"type":"betaGroups","id":"group-1","attributes":{"name":"CodeIsland Internal","isInternalGroup":true,"hasAccessToAllBuilds":true}}]}'
    fi
    ;;
  /v1/users)
    if [[ "${MOCK_SCENARIO:-}" == "existing-user" ]]; then
      printf '%s\n' '{"data":[{"type":"users","id":"user-1","attributes":{"username":"gregharned@gmail.com","firstName":"Greg","lastName":"Harned","allAppsVisible":true}}]}'
    else
      printf '%s\n' '{"data":[]}'
    fi
    ;;
  /v1/userInvitations)
    if [[ "$method" == "POST" ]]; then
      printf '%s\n' '{"data":{"type":"userInvitations","id":"invite-new","attributes":{"email":"gregharned@gmail.com","expirationDate":"2099-01-01T00:00:00Z"}}}'
    elif [[ "${MOCK_SCENARIO:-}" == "pending" ]]; then
      printf '%s\n' '{"data":[{"type":"userInvitations","id":"invite-old","attributes":{"email":"gregharned@gmail.com","expirationDate":"2099-01-01T00:00:00Z"}}]}'
    else
      printf '%s\n' '{"data":[]}'
    fi
    ;;
  /v1/userInvitations/invite-old)
    printf '%s\n' '{}'
    ;;
  /v1/betaTesters)
    if [[ "$method" == "POST" ]]; then
      printf '%s' 'tester-new' > "$ASC_REQUEST_STATE"
      printf '%s\n' '{"data":{"type":"betaTesters","id":"tester-new","attributes":{"email":"gregharned@gmail.com"}}}'
    else
      printf '%s\n' '{"data":[{"type":"betaTesters","id":"tester-1","attributes":{"email":"gregharned@gmail.com"}}]}'
    fi
    ;;
  /v1/betaTesters/tester-1)
    rm -f "$ASC_REQUEST_STATE"
    printf '%s\n' '{}'
    ;;
  /v1/betaGroups/group-1/betaTesters)
    if [[ -f "$ASC_REQUEST_STATE" ]]; then
      tester_id="$(cat "$ASC_REQUEST_STATE")"
      printf '{"data":[{"type":"betaTesters","id":"%s","attributes":{"email":"gregharned@gmail.com","state":"ACCEPTED"}}]}\n' "$tester_id"
    else
      printf '%s\n' '{"data":[]}'
    fi
    ;;
  /v1/betaGroups/group-1/relationships/betaTesters)
    printf '%s' 'tester-1' > "$ASC_REQUEST_STATE"
    printf '%s\n' '{}'
    ;;
  *)
    printf 'unexpected request: %s %s\n' "$method" "$path" >&2
    exit 64
    ;;
esac
MOCK
  chmod +x "$ASC_REQUEST_COMMAND"
}

@test "links an existing App Store Connect user to the internal group" {
  export MOCK_SCENARIO="existing-user"

  run "$REPO_ROOT/scripts/manage-testflight-internal-tester.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"state":"ready"'* ]]
  grep -q $'POST\t/v1/betaGroups/group-1/relationships/betaTesters' "$ASC_REQUEST_LOG"
  jq -e '.state == "ready" and .testerEmail == "gregharned@gmail.com"' "$ASC_RECEIPT_PATH"
}

@test "replaces a pending team invitation when a fresh invitation is requested" {
  export MOCK_SCENARIO="pending"
  export FORCE_NEW_INVITATION="1"

  run "$REPO_ROOT/scripts/manage-testflight-internal-tester.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"state":"acceptance-required"'* ]]
  grep -q $'DELETE\t/v1/userInvitations/invite-old' "$ASC_REQUEST_LOG"
  grep -q $'POST\t/v1/userInvitations' "$ASC_REQUEST_LOG"
  grep -q '"roles":\["DEVELOPER"\]' "$ASC_REQUEST_LOG"
  grep -q '"type":"apps","id":"app-1"' "$ASC_REQUEST_LOG"
}

@test "recreates a stale beta tester for a fresh internal invitation" {
  export MOCK_SCENARIO="existing-user"
  export FORCE_NEW_INVITATION="1"

  run "$REPO_ROOT/scripts/manage-testflight-internal-tester.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"state":"ready"'* ]]
  grep -q $'DELETE\t/v1/betaTesters/tester-1' "$ASC_REQUEST_LOG"
  grep -q $'POST\t/v1/betaTesters' "$ASC_REQUEST_LOG"
  jq -e '.testerId == "tester-new"' "$ASC_RECEIPT_PATH"
}

@test "creates a scoped team invitation for a missing user" {
  export MOCK_SCENARIO="missing"

  run "$REPO_ROOT/scripts/manage-testflight-internal-tester.sh"

  [ "$status" -eq 0 ]
  jq -e '.state == "acceptance-required" and .invitationId == "invite-new"' "$ASC_RECEIPT_PATH"
  grep -q $'POST\t/v1/userInvitations' "$ASC_REQUEST_LOG"
}

@test "refuses a non-internal or mismatched group" {
  export MOCK_SCENARIO="wrong-group"

  run "$REPO_ROOT/scripts/manage-testflight-internal-tester.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"No matching internal TestFlight group"* ]]
  ! grep -q $'POST\t/v1/userInvitations' "$ASC_REQUEST_LOG"
}

@test "does not print App Store Connect credentials" {
  export MOCK_SCENARIO="missing"

  run "$REPO_ROOT/scripts/manage-testflight-internal-tester.sh"

  [ "$status" -eq 0 ]
  [[ "$output" != *"issuer-secret-marker"* ]]
  [[ "$output" != *"key-secret-marker"* ]]
}
