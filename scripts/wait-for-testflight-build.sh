#!/usr/bin/env bash

set -euo pipefail

: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_PRIVATE_KEY_PATH:?ASC_PRIVATE_KEY_PATH is required}"
: "${BUNDLE_ID:?BUNDLE_ID is required}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"

TIMEOUT_MINUTES="${TESTFLIGHT_PROCESSING_TIMEOUT_MINUTES:-20}"
POLL_SECONDS="${TESTFLIGHT_PROCESSING_POLL_SECONDS:-30}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq is required to inspect App Store Connect responses"
    exit 1
fi

asc_get() {
    local path="$1"
    shift
    local token
    token="$(ruby "$SCRIPT_DIR/app-store-connect-jwt.rb" \
        "$ASC_ISSUER_ID" \
        "$ASC_KEY_ID" \
        "$ASC_PRIVATE_KEY_PATH")"
    local args=(
        --fail
        --silent
        --show-error
        --get
        --header "Authorization: Bearer $token"
    )
    local parameter
    for parameter in "$@"; do
        args+=(--data-urlencode "$parameter")
    done
    curl "${args[@]}" "https://api.appstoreconnect.apple.com$path"
}

apps_response="$(asc_get "/v1/apps" \
    "filter[bundleId]=$BUNDLE_ID" \
    "fields[apps]=name,bundleId" \
    "limit=1")"
app_id="$(printf '%s' "$apps_response" | jq -r '.data[0].id // empty')"
app_name="$(printf '%s' "$apps_response" | jq -r '.data[0].attributes.name // empty')"
if [ -z "$app_id" ]; then
    echo "::error::No App Store Connect app found for bundle ID $BUNDLE_ID"
    exit 1
fi

groups_response="$(asc_get "/v1/apps/$app_id/betaGroups" \
    "fields[betaGroups]=name,isInternalGroup,hasAccessToAllBuilds" \
    "limit=200")"
internal_all_builds_count="$(printf '%s' "$groups_response" | jq \
    '[.data[] | select(.attributes.isInternalGroup == true and .attributes.hasAccessToAllBuilds == true)] | length')"
if [ "$internal_all_builds_count" -lt 1 ]; then
    echo "::error::$app_name has no internal TestFlight group with access to all builds"
    exit 1
fi
internal_group_names="$(printf '%s' "$groups_response" | jq -r \
    '[.data[] | select(.attributes.isInternalGroup == true and .attributes.hasAccessToAllBuilds == true) | .attributes.name] | join(", ")')"
echo "Internal TestFlight delivery group: $internal_group_names"

deadline=$(( $(date +%s) + (TIMEOUT_MINUTES * 60) ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    builds_response="$(asc_get "/v1/builds" \
        "filter[app]=$app_id" \
        "filter[version]=$BUILD_NUMBER" \
        "fields[builds]=version,uploadedDate,processingState,buildAudienceType,expired" \
        "limit=1")"
    build_id="$(printf '%s' "$builds_response" | jq -r '.data[0].id // empty')"
    processing_state="$(printf '%s' "$builds_response" | jq -r '.data[0].attributes.processingState // empty')"

    if [ -z "$build_id" ]; then
        echo "Build $BUILD_NUMBER is not visible in App Store Connect yet; checking again in ${POLL_SECONDS}s"
    else
        echo "TestFlight build $BUILD_NUMBER processing state: $processing_state"
        case "$processing_state" in
            VALID)
                audience="$(printf '%s' "$builds_response" | jq -r '.data[0].attributes.buildAudienceType // "unknown"')"
                uploaded_at="$(printf '%s' "$builds_response" | jq -r '.data[0].attributes.uploadedDate // "unknown"')"
                echo "TestFlight build $BUILD_NUMBER is valid, audience $audience, uploaded $uploaded_at"
                echo "Internal group $internal_group_names has access to all builds"
                exit 0
                ;;
            FAILED|INVALID)
                echo "::error::TestFlight build $BUILD_NUMBER finished with processing state $processing_state"
                exit 1
                ;;
        esac
    fi

    sleep "$POLL_SECONDS"
done

echo "::error::Timed out after ${TIMEOUT_MINUTES} minutes waiting for TestFlight build $BUILD_NUMBER"
exit 1
