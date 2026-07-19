#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  export XCRUN_BIN="$TEST_TMPDIR/xcrun"
  export OSASCRIPT_BIN="$TEST_TMPDIR/missing-osascript"
  export SCREENCAPTURE_BIN="$TEST_TMPDIR/missing-screencapture"
  export SWIFT_BIN="$TEST_TMPDIR/missing-swift"
  mkdir -p "$TEST_TMPDIR"
}

@test "reports simulator-only when devicectl sees no physical iPhone" {
  cat > "$XCRUN_BIN" <<'STUB'
#!/usr/bin/env bash
json_output=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --json-output)
      json_output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
cat > "$json_output" <<'JSON'
{
  "result": {
    "devices": [
      {
        "identifier": "ECC99681-C3ED-4452-B727-0F9E2C09C469",
        "properties": {
          "state": {"name": "OB1 Widget Proof iPhone 16"},
          "hardware": {"platform": "iOS", "deviceType": "iPhone", "marketingName": "iPhone 16", "productType": "iPhone17,3", "reality": "simulated"},
          "connection": {"state": "connected", "pairingState": "paired", "transportType": "sameMachine"}
        }
      }
    ]
  }
}
JSON
STUB
  chmod +x "$XCRUN_BIN"

  run "$REPO_ROOT/scripts/report-ios-direct-device-visibility.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .checked == true and
    .toolAvailable == true and
    .status == "simulator-only" and
    .physicalDeviceCount == 0 and
    .simulatorCount == 1 and
    .devices[0].identifierSuffix == "2C09C469" and
    .devices[0].isSimulator == true and
    (.nextAction | contains("cannot directly install/open the physical iPhone"))'
}

@test "reports iPhone Mirroring blocked when the phone is in use" {
  export MIRRORING_TEXT=$'iPhone in Use\niPhone Mirroring ended due to iPhone use.\nLock your iPhone to connect.\nConnect'
  cat > "$XCRUN_BIN" <<'STUB'
#!/usr/bin/env bash
json_output=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --json-output)
      json_output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
cat > "$json_output" <<'JSON'
{
  "result": {
    "devices": [
      {
        "identifier": "ECC99681-C3ED-4452-B727-0F9E2C09C469",
        "properties": {
          "state": {"name": "OB1 Widget Proof iPhone 16"},
          "hardware": {"platform": "iOS", "deviceType": "iPhone", "marketingName": "iPhone 16", "productType": "iPhone17,3", "reality": "simulated"},
          "connection": {"state": "connected", "pairingState": "paired", "transportType": "sameMachine"}
        }
      }
    ]
  }
}
JSON
STUB
  chmod +x "$XCRUN_BIN"

  run "$REPO_ROOT/scripts/report-ios-direct-device-visibility.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .status == "simulator-only" and
    .iphoneMirroring.checked == true and
    .iphoneMirroring.running == true and
    .iphoneMirroring.status == "iphone-in-use" and
    (.iphoneMirroring.observedText | contains("Lock your iPhone")) and
    (.nextAction | contains("Lock the iPhone"))'
}

@test "reports iPhone Mirroring waiting for Connect as a distinct recovery path" {
  export MIRRORING_TEXT=$'Connect'
  cat > "$XCRUN_BIN" <<'STUB'
#!/usr/bin/env bash
json_output=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --json-output)
      json_output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
cat > "$json_output" <<'JSON'
{
  "result": {
    "devices": [
      {
        "identifier": "ECC99681-C3ED-4452-B727-0F9E2C09C469",
        "properties": {
          "state": {"name": "OB1 Widget Proof iPhone 16"},
          "hardware": {"platform": "iOS", "deviceType": "iPhone", "marketingName": "iPhone 16", "productType": "iPhone17,3", "reality": "simulated"},
          "connection": {"state": "connected", "pairingState": "paired", "transportType": "sameMachine"}
        }
      }
    ]
  }
}
JSON
STUB
  chmod +x "$XCRUN_BIN"

  run "$REPO_ROOT/scripts/report-ios-direct-device-visibility.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .status == "simulator-only" and
    .iphoneMirroring.status == "waiting-connect" and
    (.nextAction | contains("waiting on Connect"))'
}

@test "reports physical-available when devicectl sees a real iPhone" {
  cat > "$XCRUN_BIN" <<'STUB'
#!/usr/bin/env bash
json_output=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --json-output)
      json_output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
cat > "$json_output" <<'JSON'
{
  "result": {
    "devices": [
      {
        "identifier": "00008101-REDACTED-FOR-TESTING",
        "properties": {
          "state": {"name": "Greg's iPhone"},
          "hardware": {"platform": "iOS", "deviceType": "iPhone", "marketingName": "iPhone 16 Pro", "productType": "iPhone17,1", "reality": "physical"},
          "connection": {"state": "connected", "pairingState": "paired", "transportType": "wired"}
        }
      }
    ]
  }
}
JSON
STUB
  chmod +x "$XCRUN_BIN"

  run "$REPO_ROOT/scripts/report-ios-direct-device-visibility.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .status == "physical-available" and
    .physicalDeviceCount == 1 and
    .simulatorCount == 0 and
    .devices[0].isPhysical == true and
    .devices[0].transportType == "wired" and
    (.nextAction | contains("direct install/open workflows"))'
}

@test "reports tool-unavailable when xcrun is missing" {
  run env XCRUN_BIN="$TEST_TMPDIR/missing-xcrun" "$REPO_ROOT/scripts/report-ios-direct-device-visibility.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .checked == true and
    .toolAvailable == false and
    .status == "tool-unavailable" and
    .physicalDeviceCount == 0'
}

@test "reports devicectl-error without failing the caller" {
  cat > "$XCRUN_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "CoreDevice timed out" >&2
exit 67
STUB
  chmod +x "$XCRUN_BIN"

  run "$REPO_ROOT/scripts/report-ios-direct-device-visibility.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .status == "devicectl-error" and
    .exitCode == 67 and
    (.logTail | contains("CoreDevice timed out"))'
}
