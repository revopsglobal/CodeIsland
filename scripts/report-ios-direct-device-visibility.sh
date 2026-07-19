#!/usr/bin/env bash

set -euo pipefail

XCRUN_BIN="${XCRUN_BIN:-xcrun}"
DEVICECTL_TIMEOUT="${DEVICECTL_TIMEOUT:-15}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

if ! command -v "$XCRUN_BIN" >/dev/null 2>&1; then
    jq -n \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            generatedAt:$generatedAt,
            checked:true,
            toolAvailable:false,
            status:"tool-unavailable",
            physicalDeviceCount:0,
            simulatorCount:0,
            devices:[],
            nextAction:"xcrun/devicectl is unavailable on this Mac, so Codex cannot prove whether it can directly install or open the physical iPhone."
        }'
    exit 0
fi

json_output="$(mktemp -t codeisland-devicectl-devices)"
log_output="$(mktemp -t codeisland-devicectl-log)"
devicectl_exit=0

set +e
DEVELOPER_DIR="$DEVELOPER_DIR" "$XCRUN_BIN" devicectl list devices \
    --timeout "$DEVICECTL_TIMEOUT" \
    --json-output "$json_output" \
    --omit-deprecated-fields-in-json \
    >"$log_output" 2>&1
devicectl_exit=$?
set -e

log_tail="$(tail -n 40 "$log_output" 2>/dev/null || true)"

if [[ "$devicectl_exit" -ne 0 || ! -s "$json_output" ]] || ! jq -e . "$json_output" >/dev/null 2>&1; then
    jq -n \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson exitCode "$devicectl_exit" \
        --arg logTail "$log_tail" \
        '{
            generatedAt:$generatedAt,
            checked:true,
            toolAvailable:true,
            status:"devicectl-error",
            exitCode:$exitCode,
            physicalDeviceCount:0,
            simulatorCount:0,
            devices:[],
            logTail:$logTail,
            nextAction:"devicectl failed, so Codex cannot prove whether it can directly install or open the physical iPhone."
        }'
    exit 0
fi

devices="$(jq -c '
    (.result.devices // []) |
    map({
        name:(.properties.state.name // .name // null),
        identifierSuffix:(
            (.identifier // "") as $identifier |
            if ($identifier | length) > 8 then ($identifier | .[(length - 8):])
            elif ($identifier | length) > 0 then $identifier
            else null
            end
        ),
        platform:(.properties.hardware.platform // null),
        deviceType:(.properties.hardware.deviceType // null),
        model:(.properties.hardware.marketingName // null),
        productType:(.properties.hardware.productType // null),
        reality:(.properties.hardware.reality // null),
        state:(.properties.connection.state // null),
        pairingState:(.properties.connection.pairingState // null),
        transportType:(.properties.connection.transportType // null)
    }) |
    map(. + {
        isIOS:((.platform == "iOS") or (.deviceType == "iPhone") or (.deviceType == "iPad")),
        isSimulator:(.reality == "simulated"),
        isPhysical:(((.platform == "iOS") or (.deviceType == "iPhone") or (.deviceType == "iPad")) and (.reality != "simulated"))
    })
' "$json_output")"

physical_count="$(printf '%s' "$devices" | jq '[.[] | select(.isPhysical == true)] | length')"
simulator_count="$(printf '%s' "$devices" | jq '[.[] | select(.isIOS == true and .isSimulator == true)] | length')"
ios_count="$(printf '%s' "$devices" | jq '[.[] | select(.isIOS == true)] | length')"

status="no-ios-devices"
next_action="No iPhone or iPad is visible to devicectl on this Mac. Open the latest TestFlight build on the physical iPhone, or connect/trust the phone if you want Codex to direct-install/open it."
if [[ "$physical_count" -gt 0 ]]; then
    status="physical-available"
    next_action="A physical iOS device is visible to devicectl; Codex can attempt direct install/open workflows if the provisioning profile allows it."
elif [[ "$simulator_count" -gt 0 ]]; then
    status="simulator-only"
    next_action="Only Simulator iOS devices are visible to devicectl. Codex cannot directly install/open the physical iPhone from this Mac; open the latest TestFlight build on the iPhone, keep Tailscale connected, then rerun strict E2E."
fi

jq -n \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "$status" \
    --argjson devices "$devices" \
    --argjson physicalDeviceCount "$physical_count" \
    --argjson simulatorCount "$simulator_count" \
    --argjson iosDeviceCount "$ios_count" \
    --arg nextAction "$next_action" \
    '{
        generatedAt:$generatedAt,
        checked:true,
        toolAvailable:true,
        status:$status,
        iosDeviceCount:$iosDeviceCount,
        physicalDeviceCount:$physicalDeviceCount,
        simulatorCount:$simulatorCount,
        devices:$devices,
        nextAction:$nextAction
    }'
