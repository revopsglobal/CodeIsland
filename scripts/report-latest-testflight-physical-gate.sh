#!/usr/bin/env bash

set -euo pipefail

REPO="${REPO:-revopsglobal/CodeIsland}"
WORKFLOW="${WORKFLOW:-testflight-ios.yml}"
BRANCH="${BRANCH:-main}"
EXPECTED_MAC_VERSION="${EXPECTED_MAC_VERSION:-1.0.53}"
EXPECTED_CLIENT_VERSION="${EXPECTED_CLIENT_VERSION:-1.0.0}"
SYNC_MAC_EXPECTED_BUDDY_DEFAULTS="${SYNC_MAC_EXPECTED_BUDDY_DEFAULTS:-1}"
MAC_DEFAULTS_DOMAIN="${MAC_DEFAULTS_DOMAIN:-com.codeisland.app}"
BUDDY_TESTFLIGHT_URL="${BUDDY_TESTFLIGHT_URL:-itms-beta://}"
GH_BIN="${GH_BIN:-gh}"
DEFAULTS_BIN="${DEFAULTS_BIN:-defaults}"
REPORT_PHYSICAL_ACCEPTANCE_BIN="${REPORT_PHYSICAL_ACCEPTANCE_BIN:-$(dirname "$0")/report-physical-acceptance.sh}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

latest_run="$("$GH_BIN" run list \
    --repo "$REPO" \
    --workflow "$WORKFLOW" \
    --branch "$BRANCH" \
    --limit 20 \
    --json databaseId,status,conclusion,headSha,createdAt,url \
    | jq -c '[.[] | select(.status == "completed" and .conclusion == "success")] | first // empty')"

if [[ -z "$latest_run" ]]; then
    jq -n \
        --arg repo "$REPO" \
        --arg workflow "$WORKFLOW" \
        --arg branch "$BRANCH" \
        '{
            latestTestFlight:null,
            gate:{
                status:"missing-testflight-run",
                complete:false,
                nextAction:"Run the iOS TestFlight workflow successfully before physical acceptance."
            },
            query:{repo:$repo,workflow:$workflow,branch:$branch}
        }'
    exit 2
fi

run_id="$(printf '%s' "$latest_run" | jq -r '.databaseId')"
run_log="$("$GH_BIN" run view "$run_id" --repo "$REPO" --log)"

build_number="$(printf '%s\n' "$run_log" \
    | sed -nE 's/.*Building CodeIsland Buddy 1\.0\.0 \(([0-9]+)\).*/\1/p' \
    | tail -n 1)"
delivery_uuid="$(printf '%s\n' "$run_log" \
    | sed -nE 's/.*Delivery UUID: ([0-9a-fA-F-]+).*/\1/p' \
    | tail -n 1)"
apple_state="$(printf '%s\n' "$run_log" \
    | sed -nE 's/.*TestFlight build [0-9]+ processing state: ([A-Z_]+).*/\1/p' \
    | tail -n 1)"
audience="$(printf '%s\n' "$run_log" \
    | sed -nE 's/.*TestFlight build [0-9]+ is valid, audience ([A-Z_]+),.*/\1/p' \
    | tail -n 1)"
artifact_id="$(printf '%s\n' "$run_log" \
    | sed -nE 's/.*Artifact CodeIsland-Buddy-TestFlight-[0-9]+ has been successfully uploaded!.*Artifact ID is ([0-9]+).*/\1/p' \
    | tail -n 1)"

if [[ -z "$build_number" ]]; then
    jq -n \
        --argjson latestRun "$latest_run" \
        '{
            latestTestFlight:$latestRun,
            gate:{
                status:"missing-build-number",
                complete:false,
                nextAction:"Latest TestFlight run succeeded but the Buddy build number could not be extracted from its logs."
            }
        }'
    exit 2
fi

mac_settings_sync="$(jq -n \
    --argjson enabled false \
    --arg status "disabled" \
    '{enabled:$enabled,status:$status}')"
if [[ "$SYNC_MAC_EXPECTED_BUDDY_DEFAULTS" == "1" ]]; then
    if command -v "$DEFAULTS_BIN" >/dev/null 2>&1; then
        if "$DEFAULTS_BIN" write "$MAC_DEFAULTS_DOMAIN" remoteApprovalExpectedClientVersion "$EXPECTED_CLIENT_VERSION" \
            && "$DEFAULTS_BIN" write "$MAC_DEFAULTS_DOMAIN" remoteApprovalExpectedClientBuild "$build_number"; then
            mac_settings_sync="$(jq -n \
                --argjson enabled true \
                --arg status "synced" \
                --arg domain "$MAC_DEFAULTS_DOMAIN" \
                --arg expectedClientVersion "$EXPECTED_CLIENT_VERSION" \
                --arg expectedClientBuild "$build_number" \
                '{enabled:$enabled,status:$status,domain:$domain,expectedClientVersion:$expectedClientVersion,expectedClientBuild:$expectedClientBuild}')"
        else
            mac_settings_sync="$(jq -n \
                --argjson enabled true \
                --arg status "failed" \
                --arg domain "$MAC_DEFAULTS_DOMAIN" \
                '{enabled:$enabled,status:$status,domain:$domain}')"
        fi
    else
        mac_settings_sync="$(jq -n \
            --argjson enabled true \
            --arg status "defaults-command-missing" \
            --arg domain "$MAC_DEFAULTS_DOMAIN" \
            '{enabled:$enabled,status:$status,domain:$domain}')"
    fi
fi

acceptance_report="$(EXPECTED_MAC_VERSION="$EXPECTED_MAC_VERSION" \
    EXPECTED_CLIENT_VERSION="$EXPECTED_CLIENT_VERSION" \
    EXPECTED_CLIENT_BUILD="$build_number" \
    STRICT=0 \
    "$REPORT_PHYSICAL_ACCEPTANCE_BIN")"

physical_status="$(printf '%s' "$acceptance_report" | jq -r '.gates.physicalBuildStatus.status')"
complete="$(printf '%s' "$acceptance_report" | jq -r '.gates.complete')"

case "$physical_status" in
    matched)
        next_action="Run strict physical E2E interaction acceptance for Buddy build $build_number."
        install_instruction="Newest CodeIsland Buddy build $EXPECTED_CLIENT_VERSION ($build_number) is physically registered. Continue with strict physical E2E interaction acceptance."
        ;;
    stale)
        next_action="Install and open CodeIsland Buddy build $build_number from TestFlight on the iPhone, then rerun strict physical acceptance."
        install_instruction="Open TestFlight on the iPhone, install CodeIsland Buddy $EXPECTED_CLIENT_VERSION ($build_number), then open Buddy for at least 10 seconds."
        ;;
    missing)
        next_action="Open CodeIsland Buddy build $build_number on the physical iPhone so it registers with the Mac, then rerun strict physical acceptance."
        install_instruction="Open TestFlight on the iPhone, install CodeIsland Buddy $EXPECTED_CLIENT_VERSION ($build_number), then open Buddy for at least 10 seconds."
        ;;
    *)
        next_action="Configure expected client build/version and rerun physical acceptance."
        install_instruction="Configure the expected Buddy version/build, then rerun physical acceptance."
        ;;
esac

install_copy_text="$install_instruction Leave Tailscale connected, then rerun scripts/report-latest-testflight-physical-gate.sh on the Mac."

jq -n \
    --argjson latestRun "$latest_run" \
    --arg buildNumber "$build_number" \
    --arg deliveryUUID "$delivery_uuid" \
    --arg appleState "$apple_state" \
    --arg audience "$audience" \
    --arg artifactID "$artifact_id" \
    --argjson macSettingsSync "$mac_settings_sync" \
    --argjson acceptance "$acceptance_report" \
    --arg status "$physical_status" \
    --argjson complete "$complete" \
    --arg nextAction "$next_action" \
    --arg testFlightURL "$BUDDY_TESTFLIGHT_URL" \
    --arg installInstruction "$install_instruction" \
    --arg installCopyText "$install_copy_text" \
    '{
        latestTestFlight:($latestRun + {
            buildNumber:$buildNumber,
            deliveryUUID:($deliveryUUID | select(length > 0) // null),
            appleState:($appleState | select(length > 0) // null),
            audience:($audience | select(length > 0) // null),
            artifactID:($artifactID | select(length > 0) // null)
        }),
        macSettingsSync:$macSettingsSync,
        physicalAcceptance:$acceptance,
        installGuide:{
            testFlightURL:$testFlightURL,
            instruction:$installInstruction,
            copyText:$installCopyText
        },
        gate:{
            status:$status,
            complete:$complete,
            nextAction:$nextAction
        }
    }'

if [[ "$complete" != "true" ]]; then
    exit 2
fi
