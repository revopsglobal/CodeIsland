#!/usr/bin/env bash

set -euo pipefail

: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_PRIVATE_KEY_PATH:?ASC_PRIVATE_KEY_PATH is required}"

TESTER_EMAIL="${TESTER_EMAIL:-gregharned@gmail.com}"
ADD_BUNDLE_ID="${ADD_BUNDLE_ID:-com.harned.estate}"
REMOVE_APP_NAME="${REMOVE_APP_NAME:-Orca IDE}"
FORCE_READD="${FORCE_READD:-0}"
RESEND_TESTFLIGHT_INVITATION="${RESEND_TESTFLIGHT_INVITATION:-0}"
ASC_RECEIPT_PATH="${ASC_RECEIPT_PATH:-testflight-membership-receipt.json}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

asc_request() {
    local method="$1"
    local path="$2"
    local body="${3:-}"
    shift 3 || true

    if [[ -n "${ASC_REQUEST_COMMAND:-}" ]]; then
        "$ASC_REQUEST_COMMAND" "$method" "$path" "$body" "$@"
        return
    fi

    local token
    token="$(ruby "$SCRIPT_DIR/app-store-connect-jwt.rb" \
        "$ASC_ISSUER_ID" "$ASC_KEY_ID" "$ASC_PRIVATE_KEY_PATH")"
    local args=(
        --silent --show-error
        --request "$method"
        --header "Authorization: Bearer $token"
        --header "Accept: application/json"
    )
    if [[ -n "$body" ]]; then
        args+=(--header "Content-Type: application/json" --data "$body")
    fi
    local parameter
    for parameter in "$@"; do
        args+=(--get --data-urlencode "$parameter")
    done
    local response
    local body_response
    local http_status
    response="$(curl "${args[@]}" --write-out $'\n%{http_code}' "https://api.appstoreconnect.apple.com$path")"
    http_status="${response##*$'\n'}"
    body_response="${response%$'\n'*}"
    if [[ ! "$http_status" =~ ^2[0-9][0-9]$ ]]; then
        if [[ "$method" == "POST" && "$path" == "/v1/betaTesterInvitations" ]] &&
            printf '%s' "$body_response" | jq -e \
                '[.errors[]?.code] | any(. == "STATE_ERROR.TESTER_INVITE.ALREADY_ACCEPTED")' \
                >/dev/null 2>&1; then
            printf '%s' '{"data":null,"meta":{"alreadyAccepted":true}}'
            return 0
        fi
        echo "::error::App Store Connect $method $path returned HTTP $http_status" >&2
        printf '%s' "$body_response" | jq -r \
            '.errors[]? | "::error::\(.code // "APPLE_ERROR"): \(.title // "Request failed") — \(.detail // "No detail")"' \
            >&2 || true
        return 22
    fi
    printf '%s' "$body_response"
}

apps="$(asc_request GET /v1/apps "" "fields[apps]=name,bundleId" "limit=200")"
add_app_id="$(printf '%s' "$apps" | jq -r --arg bundle "$ADD_BUNDLE_ID" \
    '.data[] | select(.attributes.bundleId == $bundle) | .id' | head -n 1)"
add_app_name="$(printf '%s' "$apps" | jq -r --arg bundle "$ADD_BUNDLE_ID" \
    '.data[] | select(.attributes.bundleId == $bundle) | .attributes.name' | head -n 1)"
remove_app_id="$(printf '%s' "$apps" | jq -r --arg name "$REMOVE_APP_NAME" \
    '.data[] | select(.attributes.name == $name) | .id' | head -n 1)"

[[ -n "$add_app_id" ]] || { echo "::error::No app found for $ADD_BUNDLE_ID"; exit 1; }
remove_app_state="removed"
if [[ -z "$remove_app_id" ]]; then
    remove_app_state="not-visible"
    echo "::warning::$REMOVE_APP_NAME is not visible to this App Store Connect team; remove it from its TestFlight detail page."
fi

testers="$(asc_request GET /v1/betaTesters "" \
    "filter[email]=$TESTER_EMAIL" "filter[apps]=$add_app_id" \
    "fields[betaTesters]=email,state" "limit=200")"
tester_email_lower="$(printf '%s' "$TESTER_EMAIL" | tr '[:upper:]' '[:lower:]')"
tester_id="$(printf '%s' "$testers" | jq -r --arg email "$tester_email_lower" \
    '.data[] | select((.attributes.email // "" | ascii_downcase) == $email) | .id' | head -n 1)"
[[ -n "$tester_id" ]] || { echo "::error::No $add_app_name TestFlight tester found for $TESTER_EMAIL"; exit 1; }

add_groups="$(asc_request GET "/v1/apps/$add_app_id/betaGroups" "" \
    "fields[betaGroups]=name,isInternalGroup,hasAccessToAllBuilds" "limit=200")"
add_group_id="$(printf '%s' "$add_groups" | jq -r \
    '[.data[] | select(.attributes.isInternalGroup == true)]
     | sort_by(if .attributes.hasAccessToAllBuilds == true then 0 else 1 end)
     | .[0].id // empty')"
add_group_name="$(printf '%s' "$add_groups" | jq -r --arg id "$add_group_id" \
    '.data[] | select(.id == $id) | .attributes.name' | head -n 1)"
[[ -n "$add_group_id" ]] || { echo "::error::$add_app_name has no internal TestFlight group"; exit 1; }

add_group_testers="$(asc_request GET "/v1/betaGroups/$add_group_id/betaTesters" "" \
    "fields[betaTesters]=email,state" "limit=200")"
add_member_count="$(printf '%s' "$add_group_testers" | jq --arg id "$tester_id" \
    '[.data[] | select(.id == $id)] | length')"
if [[ "$add_member_count" -gt 0 && "$FORCE_READD" == "1" ]]; then
    tester_linkage="$(jq -n -c --arg id "$tester_id" '{data:[{type:"betaTesters",id:$id}]}')"
    asc_request DELETE "/v1/betaGroups/$add_group_id/relationships/betaTesters" "$tester_linkage" >/dev/null
    add_member_count=0
fi
if [[ "$add_member_count" -eq 0 ]]; then
    tester_linkage="$(jq -n -c --arg id "$tester_id" '{data:[{type:"betaTesters",id:$id}]}')"
    asc_request POST "/v1/betaGroups/$add_group_id/relationships/betaTesters" "$tester_linkage" >/dev/null
fi

remove_groups='{"data":[]}'
if [[ -n "$remove_app_id" ]]; then
    remove_groups="$(asc_request GET "/v1/apps/$remove_app_id/betaGroups" "" \
        "fields[betaGroups]=name,isInternalGroup,hasAccessToAllBuilds" "limit=200")"
fi
removed_group_ids=()
while IFS= read -r group_id; do
    [[ -n "$group_id" ]] || continue
    group_testers="$(asc_request GET "/v1/betaGroups/$group_id/betaTesters" "" \
        "fields[betaTesters]=email,state" "limit=200")"
    member_count="$(printf '%s' "$group_testers" | jq --arg id "$tester_id" \
        '[.data[] | select(.id == $id)] | length')"
    if [[ "$member_count" -gt 0 ]]; then
        tester_linkage="$(jq -n -c --arg id "$tester_id" '{data:[{type:"betaTesters",id:$id}]}')"
        asc_request DELETE "/v1/betaGroups/$group_id/relationships/betaTesters" "$tester_linkage" >/dev/null
        removed_group_ids+=("$group_id")
    fi
done < <(printf '%s' "$remove_groups" | jq -r '.data[].id')

verified_add="$(asc_request GET "/v1/betaGroups/$add_group_id/betaTesters" "" \
    "fields[betaTesters]=email,state" "limit=200")"
[[ "$(printf '%s' "$verified_add" | jq --arg id "$tester_id" '[.data[] | select(.id == $id)] | length')" -eq 1 ]] || {
    echo "::error::$TESTER_EMAIL was not added to $add_app_name"; exit 1;
}

while IFS= read -r group_id; do
    [[ -n "$group_id" ]] || continue
    verified_remove="$(asc_request GET "/v1/betaGroups/$group_id/betaTesters" "" \
        "fields[betaTesters]=email,state" "limit=200")"
    [[ "$(printf '%s' "$verified_remove" | jq --arg id "$tester_id" '[.data[] | select(.id == $id)] | length')" -eq 0 ]] || {
        echo "::error::$TESTER_EMAIL is still assigned to $REMOVE_APP_NAME"; exit 1;
    }
done < <(printf '%s' "$remove_groups" | jq -r '.data[].id')

testflight_invitation_id=""
testflight_invitation_state="not-requested"
if [[ "$RESEND_TESTFLIGHT_INVITATION" == "1" ]]; then
    testflight_invitation_payload="$(jq -n -c \
        --arg appId "$add_app_id" \
        --arg testerId "$tester_id" \
        '{data:{type:"betaTesterInvitations",relationships:{app:{data:{type:"apps",id:$appId}},betaTester:{data:{type:"betaTesters",id:$testerId}}}}}')"
    testflight_invitation_response="$(asc_request POST /v1/betaTesterInvitations "$testflight_invitation_payload")"
    testflight_invitation_id="$(printf '%s' "$testflight_invitation_response" | jq -r '.data.id // empty')"
    if [[ "$(printf '%s' "$testflight_invitation_response" | jq -r '.meta.alreadyAccepted // false')" == "true" ]]; then
        testflight_invitation_state="already-accepted"
    elif [[ -n "$testflight_invitation_id" ]]; then
        testflight_invitation_state="sent"
    else
        echo "::error::Apple did not return a TestFlight invitation ID"
        exit 1
    fi
fi

removed_groups_json="$(printf '%s\n' "${removed_group_ids[@]:-}" | jq -R -s 'split("\n") | map(select(length > 0))')"
mkdir -p "$(dirname "$ASC_RECEIPT_PATH")"
jq -n \
    --arg state ready \
    --arg testerEmail "$TESTER_EMAIL" \
    --arg testerId "$tester_id" \
    --arg addedApp "$add_app_name" \
    --arg addedBundleId "$ADD_BUNDLE_ID" \
    --arg addedGroup "$add_group_name" \
    --arg removedApp "$REMOVE_APP_NAME" \
    --arg removedAppState "$remove_app_state" \
    --arg invitationId "$testflight_invitation_id" \
    --arg invitationState "$testflight_invitation_state" \
    --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson removedGroupIds "$removed_groups_json" \
    '{state:$state,testerEmail:$testerEmail,testerId:$testerId,addedApp:$addedApp,addedBundleId:$addedBundleId,addedGroup:$addedGroup,removedApp:$removedApp,removedAppState:$removedAppState,removedGroupIds:$removedGroupIds,invitationId:$invitationId,invitationState:$invitationState,checkedAt:$checkedAt}' \
    > "$ASC_RECEIPT_PATH"

if [[ "$remove_app_state" == "removed" ]]; then
    echo "Added $TESTER_EMAIL to $add_app_name / $add_group_name and removed it from $REMOVE_APP_NAME."
else
    echo "Added $TESTER_EMAIL to $add_app_name / $add_group_name. $REMOVE_APP_NAME requires Stop Testing in its owning account."
fi
jq -c . "$ASC_RECEIPT_PATH"
