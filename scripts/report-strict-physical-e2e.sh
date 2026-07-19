#!/usr/bin/env bash

set -euo pipefail

LATEST_GATE_BIN="${LATEST_GATE_BIN:-$(dirname "$0")/report-latest-testflight-physical-gate.sh}"
DIRECT_DEVICE_VISIBILITY_BIN="${DIRECT_DEVICE_VISIBILITY_BIN:-$(dirname "$0")/report-ios-direct-device-visibility.sh}"
TESTFLIGHT_SOURCE_DRIFT_BIN="${TESTFLIGHT_SOURCE_DRIFT_BIN:-$(dirname "$0")/report-testflight-source-drift.sh}"
SWIFT_BIN="${SWIFT_BIN:-swift}"
SWIFT_TEST_FILTER="${SWIFT_TEST_FILTER:-RemoteApprovalHTTPServerTests/testAuthenticatedHostLifecycleOverRealListener}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

latest_gate_output=""
latest_gate_exit=0
set +e
latest_gate_output="$("$LATEST_GATE_BIN" 2>&1)"
latest_gate_exit=$?
set -e

if ! printf '%s' "$latest_gate_output" | jq -e . >/dev/null 2>&1; then
    jq -n \
        --arg status "latest-gate-invalid-json" \
        --arg output "$latest_gate_output" \
        '{
            generatedAt:(now | todate),
            complete:false,
            status:$status,
            latestGate:{exitCode:2, parseable:false, output:$output}
        }'
    exit 2
fi

latest_gate_complete="$(printf '%s' "$latest_gate_output" | jq -r '.gate.complete == true')"
latest_testflight_sha="$(printf '%s' "$latest_gate_output" | jq -r '.latestTestFlight.headSha // empty')"

testflight_source_drift_output=""
set +e
testflight_source_drift_output="$(TESTFLIGHT_SHA="$latest_testflight_sha" "$TESTFLIGHT_SOURCE_DRIFT_BIN" 2>&1)"
set -e

if ! printf '%s' "$testflight_source_drift_output" | jq -e . >/dev/null 2>&1; then
    testflight_source_drift_output="$(jq -n -c \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg output "$testflight_source_drift_output" \
        '{
            generatedAt:$generatedAt,
            checked:false,
            status:"source-drift-report-invalid-json",
            testFlightHeadSha:null,
            currentSha:null,
            changedFileCount:null,
            buddyRelevantChanged:null,
            buddyRelevantFiles:[],
            changedFilesSample:[],
            output:$output,
            nextAction:"The TestFlight source-drift diagnostic did not return JSON; rerun scripts/report-testflight-source-drift.sh."
        }')"
fi

direct_device_visibility_output=""
set +e
direct_device_visibility_output="$(DEVELOPER_DIR="$DEVELOPER_DIR" "$DIRECT_DEVICE_VISIBILITY_BIN" 2>&1)"
set -e

if ! printf '%s' "$direct_device_visibility_output" | jq -e . >/dev/null 2>&1; then
    direct_device_visibility_output="$(jq -n -c \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg output "$direct_device_visibility_output" \
        '{
            generatedAt:$generatedAt,
            checked:true,
            toolAvailable:null,
            status:"visibility-report-invalid-json",
            physicalDeviceCount:0,
            simulatorCount:0,
            devices:[],
            output:$output,
            nextAction:"The direct-device visibility diagnostic did not return JSON; rerun scripts/report-ios-direct-device-visibility.sh."
        }')"
fi

interaction_log="$(mktemp -t codeisland-strict-e2e)"
interaction_exit=0
set +e
DEVELOPER_DIR="$DEVELOPER_DIR" "$SWIFT_BIN" test --filter "$SWIFT_TEST_FILTER" >"$interaction_log" 2>&1
interaction_exit=$?
set -e
interaction_tail="$(tail -n 60 "$interaction_log")"

interaction_passed=false
if [[ "$interaction_exit" -eq 0 ]]; then
    interaction_passed=true
fi

complete=false
status="physical-gate-incomplete"
if [[ "$latest_gate_complete" == "true" && "$interaction_passed" == "true" ]]; then
    complete=true
    status="complete"
elif [[ "$latest_gate_complete" == "true" && "$interaction_passed" != "true" ]]; then
    status="interaction-contract-failed"
fi

jq -n \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "$status" \
    --argjson complete "$complete" \
    --argjson latestGate "$latest_gate_output" \
    --argjson latestGateExit "$latest_gate_exit" \
    --argjson testFlightSourceDrift "$testflight_source_drift_output" \
    --argjson directDeviceVisibility "$direct_device_visibility_output" \
    --arg swiftTestFilter "$SWIFT_TEST_FILTER" \
    --argjson interactionExit "$interaction_exit" \
    --argjson interactionPassed "$interaction_passed" \
    --arg interactionLogTail "$interaction_tail" \
    '{
        generatedAt:$generatedAt,
        complete:$complete,
        status:$status,
        latestGate:{
            exitCode:$latestGateExit,
            complete:($latestGate.gate.complete == true),
            status:$latestGate.gate.status,
            nextAction:$latestGate.gate.nextAction,
            report:$latestGate
        },
        testFlightSourceDrift:$testFlightSourceDrift,
        directDeviceVisibility:$directDeviceVisibility,
        interactionContract:{
            command:"swift test --filter \($swiftTestFilter)",
            filter:$swiftTestFilter,
            exitCode:$interactionExit,
            passed:$interactionPassed,
            logTail:$interactionLogTail
        }
    }'

if [[ "$complete" != "true" ]]; then
    exit 2
fi
