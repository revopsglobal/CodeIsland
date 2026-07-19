#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/profile"
  export ASC_REQUEST_COMMAND="$TEST_TMPDIR/asc-request"
  export PROFILE_VERIFY_COMMAND="$TEST_TMPDIR/verify-profile"
  export ASC_ISSUER_ID="issuer"
  export ASC_KEY_ID="key"
  export ASC_PRIVATE_KEY_PATH="$TEST_TMPDIR/key.p8"
  export DISTRIBUTION_CERTIFICATE_SERIAL="aa:bb:cc"
  export PROFILE_OUTPUT_PATH="$TEST_TMPDIR/share.mobileprovision"
  export ASC_CALLS_PATH="$TEST_TMPDIR/calls.ndjson"
  mkdir -p "$TEST_TMPDIR"

  printf '%s\n' 'test-key' > "$ASC_PRIVATE_KEY_PATH"
  printf '%s' 'fake-profile' | base64 > "$TEST_TMPDIR/profile-content.txt"
  export TEST_PROFILE_CONTENT="$(tr -d '\n' < "$TEST_TMPDIR/profile-content.txt")"

  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'method="$1"; path="$2"; body="${3:-}"' \
    'jq -n -c --arg method "$method" --arg path "$path" --arg body "$body" '\''{method:$method,path:$path,body:$body}'\'' >> "$ASC_CALLS_PATH"' \
    'case "$method $path" in' \
    '  "GET /v1/bundleIds") printf '\''%s'\'' '\''{"data":[]}'\'' ;;' \
    '  "POST /v1/bundleIds") printf '\''%s'\'' '\''{"data":{"type":"bundleIds","id":"bundle-1"}}'\'' ;;' \
    '  "GET /v1/bundleIds/bundle-1/bundleIdCapabilities") printf '\''%s'\'' '\''{"data":[]}'\'' ;;' \
    '  "POST /v1/bundleIdCapabilities") printf '\''%s'\'' '\''{"data":{"type":"bundleIdCapabilities","id":"cap-1"}}'\'' ;;' \
    '  "GET /v1/certificates") printf '\''{"data":[{"type":"certificates","id":"cert-1","attributes":{"activated":true,"serialNumber":"AABBCC"}}]}'\'' ;;' \
    '  "GET /v1/profiles") printf '\''%s'\'' '\''{"data":[]}'\'' ;;' \
    '  "POST /v1/profiles") jq -n -c --arg content "$TEST_PROFILE_CONTENT" '\''{data:{type:"profiles",id:"profile-1",attributes:{profileContent:$content}}}'\'' ;;' \
    '  *) exit 99 ;;' \
    'esac' > "$ASC_REQUEST_COMMAND"
  chmod +x "$ASC_REQUEST_COMMAND"

  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    '[[ "$(<"$1")" == "fake-profile" ]]' \
    '[[ "$2" == "com.revopsglobal.codeisland.buddy.share" ]]' \
    '[[ "$3" == "CodeIsland Buddy Share App Store" ]]' \
    '[[ "$4" == "group.com.revopsglobal.codeisland.buddy" ]]' > "$PROFILE_VERIFY_COMMAND"
  chmod +x "$PROFILE_VERIFY_COMMAND"
}

@test "registers the share bundle, binds the app group, and creates the matching profile" {
  run "$REPO_ROOT/scripts/bootstrap-ios-app-store-profile.sh"

  [ "$status" -eq 0 ]
  [ -s "$PROFILE_OUTPUT_PATH" ]
  jq -e -s '
    ([.[] | select(.method == "POST" and .path == "/v1/bundleIds" and (.body | contains("com.revopsglobal.codeisland.buddy.share")))] | length) == 1 and
    ([.[] | select(.method == "POST" and .path == "/v1/bundleIdCapabilities" and (.body | contains("APP_GROUP_IDS")) and (.body | contains("group.com.revopsglobal.codeisland.buddy")))] | length) == 1 and
    ([.[] | select(.method == "POST" and .path == "/v1/profiles" and (.body | contains("bundle-1")) and (.body | contains("cert-1")))] | length) == 1
  ' "$ASC_CALLS_PATH"
}
