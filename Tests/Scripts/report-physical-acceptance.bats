#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  export APP_PATH="$TEST_TMPDIR/CodeIsland.app"
  export DEVICE_STORE="$TEST_TMPDIR/remote-approval-devices.json"
  export EXPECTED_MAC_VERSION="1.0.46"
  export EXPECTED_CLIENT_VERSION="1.0.0"
  export EXPECTED_CLIENT_BUILD="20260718112841"
  export EXPECTED_TEAM_ID="44JG2Y95CH"
  export LOCAL_HEALTH_URL="http://local.test/health"
  export TAILSCALE_HEALTH_URL="https://tailscale.test/health"
  export CURL_BIN="$TEST_TMPDIR/curl"
  export CODESIGN_BIN="$TEST_TMPDIR/codesign"
  export LIPO_BIN="$TEST_TMPDIR/lipo"
  export PGREP_BIN="$TEST_TMPDIR/pgrep"

  mkdir -p "$APP_PATH/Contents/MacOS"
  plutil -create xml1 "$APP_PATH/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string 1.0.46 "$APP_PATH/Contents/Info.plist"
  plutil -insert CFBundleVersion -string 1.0.46 "$APP_PATH/Contents/Info.plist"
  : > "$APP_PATH/Contents/MacOS/CodeIsland"

  cat > "$CURL_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n%s' '{"pendingCount":0,"running":true,"serverName":"Test Mac","version":1}' '200'
STUB

  cat > "$CODESIGN_BIN" <<'STUB'
#!/usr/bin/env bash
if [[ " $* " == *" --verify "* ]]; then
  exit 0
fi
printf '%s\n' 'Identifier=com.codeisland.app' 'TeamIdentifier=44JG2Y95CH' >&2
STUB

  cat > "$LIPO_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' arm64
STUB

  cat > "$PGREP_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' 4321
STUB

  chmod +x "$CURL_BIN" "$CODESIGN_BIN" "$LIPO_BIN" "$PGREP_BIN"
}

@test "reports signed delivery and the exact physical client separately" {
  cat > "$DEVICE_STORE" <<'JSON'
{"devices":[{"id":"device-1","name":"iPhone","pairedAt":"2026-07-18T02:26:48Z","lastSeenAt":"2026-07-18T12:00:00Z","clientVersion":"1.0.0","clientBuild":"20260718112841","pushEnvironment":"production","pushToken":"secret-push-token","liveActivityPushToStartToken":"secret-start-token","liveActivityUpdateTokens":{"request-1":"secret-update-token"}}]}
JSON

  run "$REPO_ROOT/scripts/report-physical-acceptance.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .mac.version == "1.0.46" and
    .mac.signatureValid == true and
    .health.local.running == true and
    .health.tailscale.running == true and
    .gates.deliveryHealthy == true and
    .gates.physicalMatchCount == 1 and
    .gates.physicalBuildStatus.status == "matched" and
    .gates.physicalBuildStatus.newestObservedBuild == "20260718112841" and
    .gates.physicalBuildConfirmed == true and
    .gates.complete == true and
    .pairing.devices[0].hasPushToken == true and
    .pairing.devices[0].hasLiveActivityPushToStartToken == true and
    .pairing.devices[0].hasLiveActivityUpdateToken == true'
  [[ "$output" != *"secret-push-token"* ]]
  [[ "$output" != *"secret-start-token"* ]]
  [[ "$output" != *"secret-update-token"* ]]
}

@test "reports stale physical client when an older Buddy build last checked in" {
  cat > "$DEVICE_STORE" <<'JSON'
{"devices":[{"id":"device-1","name":"iPhone","lastSeenAt":"2026-07-18T12:00:00Z","clientVersion":"1.0.0","clientBuild":"20260718112840","pushEnvironment":"production","pushToken":"secret-push-token"},{"id":"device-2","name":"CodeIsland web acceptance","lastSeenAt":"2026-07-18T12:05:00Z","clientVersion":null,"clientBuild":null}]}
JSON
  export STRICT=1

  run "$REPO_ROOT/scripts/report-physical-acceptance.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .gates.deliveryHealthy == true and
    .gates.physicalBuildConfirmed == false and
    .gates.physicalBuildStatus.status == "stale" and
    .gates.physicalBuildStatus.expectedBuild == "20260718112841" and
    .gates.physicalBuildStatus.newestObservedDeviceID == "device-1" and
    .gates.physicalBuildStatus.newestObservedBuild == "20260718112840" and
    .gates.complete == false'
  [[ "$output" != *"secret-push-token"* ]]
}

@test "keeps delivery healthy while failing an absent physical build in strict mode" {
  cat > "$DEVICE_STORE" <<'JSON'
{"devices":[{"id":"device-1","name":"iPhone","clientVersion":null,"clientBuild":null,"pushEnvironment":"production","pushToken":"secret-push-token"}]}
JSON
  export STRICT=1

  run "$REPO_ROOT/scripts/report-physical-acceptance.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .gates.deliveryHealthy == true and
    .gates.physicalBuildStatus.status == "missing" and
    .gates.physicalBuildConfirmed == false and
    .gates.complete == false'
  [[ "$output" != *"secret-push-token"* ]]
}
