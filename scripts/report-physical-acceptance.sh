#!/usr/bin/env bash

set -euo pipefail

APP_PATH="${APP_PATH:-/Applications/CodeIsland.app}"
DEVICE_STORE="${DEVICE_STORE:-$HOME/Library/Application Support/CodeIsland/remote-approval-devices.json}"
LOCAL_HEALTH_URL="${LOCAL_HEALTH_URL:-http://127.0.0.1:43891/health}"
TAILSCALE_HEALTH_URL="${TAILSCALE_HEALTH_URL:-https://gregs-macbook-air.tail62f27c.ts.net:9443/health}"
EXPECTED_MAC_VERSION="${EXPECTED_MAC_VERSION:-}"
EXPECTED_CLIENT_VERSION="${EXPECTED_CLIENT_VERSION:-}"
EXPECTED_CLIENT_BUILD="${EXPECTED_CLIENT_BUILD:-}"
EXPECTED_TEAM_ID="${EXPECTED_TEAM_ID:-44JG2Y95CH}"
STRICT="${STRICT:-0}"

CURL_BIN="${CURL_BIN:-curl}"
CODESIGN_BIN="${CODESIGN_BIN:-codesign}"
LIPO_BIN="${LIPO_BIN:-lipo}"
PGREP_BIN="${PGREP_BIN:-pgrep}"
PLIST_BUDDY_BIN="${PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

bool_json() {
    if [[ "$1" == "true" ]]; then
        printf 'true'
    else
        printf 'false'
    fi
}

health_json() {
    local url="$1"
    local response=""
    local body=""
    local http_code="000"
    local reachable=false
    local running=false
    local pending_count=null

    if response="$($CURL_BIN \
        --max-time 15 \
        --silent \
        --show-error \
        --write-out $'\n%{http_code}' \
        "$url" 2>/dev/null)"; then
        http_code="${response##*$'\n'}"
        body="${response%$'\n'*}"
        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
            reachable=true
            if [[ "$(printf '%s' "$body" | jq -r '.running == true')" == "true" ]]; then
                running=true
            fi
            pending_count="$(printf '%s' "$body" | jq '.pendingCount // null')"
        fi
    fi

    jq -n -c \
        --arg url "$url" \
        --arg httpCode "$http_code" \
        --argjson reachable "$(bool_json "$reachable")" \
        --argjson running "$(bool_json "$running")" \
        --argjson pendingCount "$pending_count" \
        '{url:$url,httpCode:$httpCode,reachable:$reachable,running:$running,pendingCount:$pendingCount}'
}

mac_installed=false
mac_version=""
mac_build=""
mac_archs=""
mac_signature_valid=false
mac_team_id=""
mac_cdhash=""
mac_pid=""
mac_running=false

if [[ -d "$APP_PATH" ]]; then
    mac_installed=true
    info_plist="$APP_PATH/Contents/Info.plist"
    binary="$APP_PATH/Contents/MacOS/CodeIsland"
    mac_version="$($PLIST_BUDDY_BIN -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || true)"
    mac_build="$($PLIST_BUDDY_BIN -c 'Print :CFBundleVersion' "$info_plist" 2>/dev/null || true)"
    mac_archs="$($LIPO_BIN -archs "$binary" 2>/dev/null || true)"
    if "$CODESIGN_BIN" --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
        mac_signature_valid=true
    fi
    signing_details="$($CODESIGN_BIN -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
    mac_team_id="$(printf '%s\n' "$signing_details" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    mac_cdhash="$(printf '%s\n' "$signing_details" | awk -F= '/^CDHash=/{print $2; exit}')"
    mac_pid="$($PGREP_BIN -f "^$APP_PATH/Contents/MacOS/CodeIsland$" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$mac_pid" ]]; then
        mac_running=true
    fi
fi

mac_version_matches=true
if [[ -n "$EXPECTED_MAC_VERSION" && "$mac_version" != "$EXPECTED_MAC_VERSION" ]]; then
    mac_version_matches=false
fi

mac_team_matches=true
if [[ -n "$EXPECTED_TEAM_ID" && "$mac_team_id" != "$EXPECTED_TEAM_ID" ]]; then
    mac_team_matches=false
fi

local_health="$(health_json "$LOCAL_HEALTH_URL")"
tailscale_health="$(health_json "$TAILSCALE_HEALTH_URL")"

devices='[]'
store_readable=false
if [[ -r "$DEVICE_STORE" ]] && jq -e '.devices | arrays' "$DEVICE_STORE" >/dev/null 2>&1; then
    store_readable=true
    devices="$(jq -c '[.devices[] | {
        id,
        name,
        pairedAt,
        lastSeenAt,
        clientVersion,
        clientBuild,
        pushEnvironment,
        hasPushToken: (((.pushToken // "") | length) > 0),
        hasLiveActivityPushToStartToken: (((.liveActivityPushToStartToken // "") | length) > 0),
        hasLiveActivityUpdateToken: (((.liveActivityUpdateTokens // {}) | length) > 0),
        lastLiveActivityReceipt
    }]' "$DEVICE_STORE")"
fi

expected_client_configured=false
physical_match_count=0
newest_physical_device='null'
if [[ -n "$EXPECTED_CLIENT_VERSION" && -n "$EXPECTED_CLIENT_BUILD" ]]; then
    expected_client_configured=true
    physical_match_count="$(printf '%s' "$devices" | jq \
        --arg version "$EXPECTED_CLIENT_VERSION" \
        --arg build "$EXPECTED_CLIENT_BUILD" \
        '[.[] | select(.clientVersion == $version and .clientBuild == $build)] | length')"
    newest_physical_device="$(printf '%s' "$devices" | jq -c \
        '[.[] | select((.clientVersion // "") != "" or (.clientBuild // "") != "")] |
        sort_by(.lastSeenAt // "") |
        last // null')"
fi

physical_build_confirmed=false
if [[ "$expected_client_configured" == "true" && "$physical_match_count" -gt 0 ]]; then
    physical_build_confirmed=true
fi

physical_build_status="$(jq -n -c \
    --arg expectedClientVersion "$EXPECTED_CLIENT_VERSION" \
    --arg expectedClientBuild "$EXPECTED_CLIENT_BUILD" \
    --argjson expectedClientConfigured "$(bool_json "$expected_client_configured")" \
    --argjson physicalMatchCount "$physical_match_count" \
    --argjson newestPhysicalDevice "$newest_physical_device" \
    '{
        expectedVersion:$expectedClientVersion,
        expectedBuild:$expectedClientBuild,
        newestObservedVersion:($newestPhysicalDevice.clientVersion // null),
        newestObservedBuild:($newestPhysicalDevice.clientBuild // null),
        newestObservedDeviceID:($newestPhysicalDevice.id // null),
        newestObservedDeviceName:($newestPhysicalDevice.name // null),
        newestObservedLastSeenAt:($newestPhysicalDevice.lastSeenAt // null),
        status: (
            if ($expectedClientConfigured | not) then "not-configured"
            elif $physicalMatchCount > 0 then "matched"
            elif $newestPhysicalDevice == null then "missing"
            else "stale"
            end
        )
    }')"

delivery_healthy=false
if [[ "$mac_installed" == "true" \
    && "$mac_version_matches" == "true" \
    && "$mac_signature_valid" == "true" \
    && "$mac_team_matches" == "true" \
    && "$mac_running" == "true" \
    && "$(printf '%s' "$local_health" | jq -r '.running')" == "true" \
    && "$(printf '%s' "$tailscale_health" | jq -r '.running')" == "true" ]]; then
    delivery_healthy=true
fi

complete=false
if [[ "$delivery_healthy" == "true" && "$physical_build_confirmed" == "true" ]]; then
    complete=true
fi

report="$(jq -n \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg appPath "$APP_PATH" \
    --arg macVersion "$mac_version" \
    --arg macBuild "$mac_build" \
    --arg macArchitectures "$mac_archs" \
    --arg macTeamIdentifier "$mac_team_id" \
    --arg macCDHash "$mac_cdhash" \
    --arg macPid "$mac_pid" \
    --arg expectedMacVersion "$EXPECTED_MAC_VERSION" \
    --arg deviceStore "$DEVICE_STORE" \
    --arg expectedClientVersion "$EXPECTED_CLIENT_VERSION" \
    --arg expectedClientBuild "$EXPECTED_CLIENT_BUILD" \
    --arg expectedTeamIdentifier "$EXPECTED_TEAM_ID" \
    --argjson macInstalled "$(bool_json "$mac_installed")" \
    --argjson macVersionMatches "$(bool_json "$mac_version_matches")" \
    --argjson macSignatureValid "$(bool_json "$mac_signature_valid")" \
    --argjson macTeamMatches "$(bool_json "$mac_team_matches")" \
    --argjson macRunning "$(bool_json "$mac_running")" \
    --argjson localHealth "$local_health" \
    --argjson tailscaleHealth "$tailscale_health" \
    --argjson storeReadable "$(bool_json "$store_readable")" \
    --argjson devices "$devices" \
    --argjson expectedClientConfigured "$(bool_json "$expected_client_configured")" \
    --argjson physicalMatchCount "$physical_match_count" \
    --argjson physicalBuildConfirmed "$(bool_json "$physical_build_confirmed")" \
    --argjson physicalBuildStatus "$physical_build_status" \
    --argjson deliveryHealthy "$(bool_json "$delivery_healthy")" \
    --argjson complete "$(bool_json "$complete")" \
    '{
        generatedAt:$generatedAt,
        mac:{
            appPath:$appPath,
            installed:$macInstalled,
            version:$macVersion,
            build:$macBuild,
            architectures:$macArchitectures,
            signatureValid:$macSignatureValid,
            teamIdentifier:$macTeamIdentifier,
            cdhash:($macCDHash | select(length > 0) // null),
            pid:$macPid,
            running:$macRunning
        },
        health:{local:$localHealth,tailscale:$tailscaleHealth},
        pairing:{storePath:$deviceStore,storeReadable:$storeReadable,devices:$devices},
        expected:{
            macVersion:$expectedMacVersion,
            teamIdentifier:$expectedTeamIdentifier,
            clientVersion:$expectedClientVersion,
            clientBuild:$expectedClientBuild,
            clientConfigured:$expectedClientConfigured
        },
        gates:{
            macVersionMatches:$macVersionMatches,
            macTeamMatches:$macTeamMatches,
            deliveryHealthy:$deliveryHealthy,
            physicalMatchCount:$physicalMatchCount,
            physicalBuildStatus:$physicalBuildStatus,
            physicalBuildConfirmed:$physicalBuildConfirmed,
            complete:$complete
        }
    }')"

printf '%s\n' "$report"

if [[ "$STRICT" == "1" && "$complete" != "true" ]]; then
    exit 2
fi
