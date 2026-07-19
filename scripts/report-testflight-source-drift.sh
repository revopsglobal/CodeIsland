#!/usr/bin/env bash

set -euo pipefail

GIT_BIN="${GIT_BIN:-git}"
TESTFLIGHT_SHA="${TESTFLIGHT_SHA:-}"
CURRENT_SHA="${CURRENT_SHA:-}"
MAX_SAMPLE="${MAX_SAMPLE:-40}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

emit_unchecked() {
    local status="$1"
    local next_action="$2"
    jq -n \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg status "$status" \
        --arg testFlightHeadSha "$TESTFLIGHT_SHA" \
        --arg currentSha "$CURRENT_SHA" \
        --arg nextAction "$next_action" \
        '{
            generatedAt:$generatedAt,
            checked:false,
            status:$status,
            testFlightHeadSha:($testFlightHeadSha | select(length > 0) // null),
            currentSha:($currentSha | select(length > 0) // null),
            changedFileCount:null,
            buddyRelevantChanged:null,
            buddyRelevantFiles:[],
            changedFilesSample:[],
            nextAction:$nextAction
        }'
}

if [[ -z "$TESTFLIGHT_SHA" || "$TESTFLIGHT_SHA" == "null" ]]; then
    emit_unchecked "missing-testflight-sha" "Latest TestFlight run did not report a head SHA; inspect the TestFlight workflow run before deciding whether to upload another Buddy build."
    exit 0
fi

if ! command -v "$GIT_BIN" >/dev/null 2>&1; then
    emit_unchecked "git-unavailable" "Git is unavailable; rerun source drift from the CodeIsland checkout before deciding whether to upload another Buddy build."
    exit 0
fi

if [[ -z "$CURRENT_SHA" ]]; then
    if "$GIT_BIN" rev-parse --verify origin/main >/dev/null 2>&1; then
        CURRENT_SHA="$("$GIT_BIN" rev-parse origin/main)"
    else
        CURRENT_SHA="$("$GIT_BIN" rev-parse HEAD)"
    fi
fi

if ! "$GIT_BIN" rev-parse --verify "${TESTFLIGHT_SHA}^{commit}" >/dev/null 2>&1; then
    emit_unchecked "testflight-sha-unavailable" "Fetch repository history for the TestFlight head SHA, then rerun source drift before deciding whether to upload another Buddy build."
    exit 0
fi

if ! "$GIT_BIN" rev-parse --verify "${CURRENT_SHA}^{commit}" >/dev/null 2>&1; then
    emit_unchecked "current-sha-unavailable" "Current comparison SHA is unavailable; rerun source drift from a healthy CodeIsland checkout."
    exit 0
fi

changed_files="$("$GIT_BIN" diff --name-only "${TESTFLIGHT_SHA}..${CURRENT_SHA}")"

buddy_relevant_files="$(printf '%s\n' "$changed_files" | awk '
    /^ios\/CodeIslandCompanion\// { print; next }
    /^Sources\/CodeIslandCore\// { print; next }
    /^Tests\/CodeIslandCoreTests\// { print; next }
    /^Tests\/Scripts\/validate-app-intent-metadata\.bats$/ { print; next }
    /^scripts\/validate-app-intent-metadata\.sh$/ { print; next }
    /^scripts\/smoke-companion.*\.sh$/ { print; next }
    /^\.github\/workflows\/testflight-ios\.yml$/ { print; next }
')"

changed_count="$(printf '%s\n' "$changed_files" | sed '/^$/d' | wc -l | tr -d ' ')"
buddy_count="$(printf '%s\n' "$buddy_relevant_files" | sed '/^$/d' | wc -l | tr -d ' ')"

if [[ "$changed_count" == "0" ]]; then
    status="current"
    next_action="Latest TestFlight Buddy source matches the current comparison SHA; continue physical iPhone acceptance."
elif [[ "$buddy_count" == "0" ]]; then
    status="source-drift-non-buddy"
    next_action="Latest TestFlight Buddy build is still Buddy-current; install/open the existing TestFlight build on the iPhone instead of uploading another Buddy build."
else
    status="buddy-source-drift"
    next_action="Buddy-relevant source changed after the latest TestFlight build; upload a new internal TestFlight Buddy build before physical iPhone acceptance."
fi

jq -n \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "$status" \
    --arg testFlightHeadSha "$TESTFLIGHT_SHA" \
    --arg currentSha "$CURRENT_SHA" \
    --argjson changedFileCount "$changed_count" \
    --argjson buddyRelevantChanged "$([[ "$buddy_count" == "0" ]] && echo false || echo true)" \
    --argjson buddyRelevantFiles "$(printf '%s\n' "$buddy_relevant_files" | sed '/^$/d' | jq -R . | jq -s .)" \
    --argjson changedFilesSample "$(printf '%s\n' "$changed_files" | sed '/^$/d' | head -n "$MAX_SAMPLE" | jq -R . | jq -s .)" \
    --arg nextAction "$next_action" \
    '{
        generatedAt:$generatedAt,
        checked:true,
        status:$status,
        testFlightHeadSha:$testFlightHeadSha,
        currentSha:$currentSha,
        changedFileCount:$changedFileCount,
        buddyRelevantChanged:$buddyRelevantChanged,
        buddyRelevantFiles:$buddyRelevantFiles,
        changedFilesSample:$changedFilesSample,
        nextAction:$nextAction
    }'
