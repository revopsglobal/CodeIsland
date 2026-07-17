#!/usr/bin/env bash

set -euo pipefail

: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_PRIVATE_KEY_PATH:?ASC_PRIVATE_KEY_PATH is required}"

TESTER_EMAIL="${TESTER_EMAIL:-gregharned@gmail.com}"
TESTER_FIRST_NAME="${TESTER_FIRST_NAME:-Greg}"
TESTER_LAST_NAME="${TESTER_LAST_NAME:-Harned}"
BUNDLE_ID="${BUNDLE_ID:-com.revopsglobal.codeisland.buddy}"
BETA_GROUP_NAME="${BETA_GROUP_NAME:-CodeIsland Internal}"
FORCE_NEW_INVITATION="${FORCE_NEW_INVITATION:-0}"
RESEND_TESTFLIGHT_INVITATION="${RESEND_TESTFLIGHT_INVITATION:-0}"
ASC_RECEIPT_PATH="${ASC_RECEIPT_PATH:-testflight-tester-receipt.json}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq is required"
    exit 1
fi

if [[ ! "$TESTER_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
    echo "::error::TESTER_EMAIL is not a valid email address"
    exit 1
fi

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
        "$ASC_ISSUER_ID" \
        "$ASC_KEY_ID" \
        "$ASC_PRIVATE_KEY_PATH")"

    local args=(
        --silent
        --show-error
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

write_receipt() {
    local state="$1"
    local app_id="$2"
    local group_id="$3"
    local tester_id="${4:-}"
    local invitation_id="${5:-}"
    local invitation_expiration="${6:-}"
    local temporary
    temporary="${ASC_RECEIPT_PATH}.tmp"
    mkdir -p "$(dirname "$ASC_RECEIPT_PATH")"
    jq -n -c \
        --arg state "$state" \
        --arg testerEmail "$TESTER_EMAIL" \
        --arg bundleId "$BUNDLE_ID" \
        --arg appId "$app_id" \
        --arg groupName "$BETA_GROUP_NAME" \
        --arg groupId "$group_id" \
        --arg testerId "$tester_id" \
        --arg invitationId "$invitation_id" \
        --arg invitationExpiration "$invitation_expiration" \
        --arg checkedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{state:$state,testerEmail:$testerEmail,bundleId:$bundleId,appId:$appId,groupName:$groupName,groupId:$groupId,testerId:$testerId,invitationId:$invitationId,invitationExpiration:$invitationExpiration,checkedAt:$checkedAt}' \
        > "$temporary"
    mv "$temporary" "$ASC_RECEIPT_PATH"
    jq -c . "$ASC_RECEIPT_PATH"
}

apps_response="$(asc_request GET /v1/apps "" \
    "filter[bundleId]=$BUNDLE_ID" \
    "fields[apps]=name,bundleId" \
    "limit=1")"
app_id="$(printf '%s' "$apps_response" | jq -r '.data[0].id // empty')"
if [[ -z "$app_id" ]]; then
    echo "::error::No App Store Connect app found for bundle ID $BUNDLE_ID"
    exit 1
fi

groups_response="$(asc_request GET "/v1/apps/$app_id/betaGroups" "" \
    "fields[betaGroups]=name,isInternalGroup,hasAccessToAllBuilds" \
    "limit=200")"
group_id="$(printf '%s' "$groups_response" | jq -r \
    --arg name "$BETA_GROUP_NAME" \
    '.data[] | select(.attributes.name == $name and .attributes.isInternalGroup == true) | .id' \
    | head -n 1)"
if [[ -z "$group_id" ]]; then
    echo "::error::No matching internal TestFlight group named $BETA_GROUP_NAME for $BUNDLE_ID"
    exit 1
fi

users_response="$(asc_request GET /v1/users "" \
    "filter[username]=$TESTER_EMAIL" \
    "fields[users]=username,firstName,lastName,roles,allAppsVisible" \
    "limit=1")"
user_id="$(printf '%s' "$users_response" | jq -r '.data[0].id // empty')"

if [[ -z "$user_id" ]]; then
    invitations_response="$(asc_request GET /v1/userInvitations "" \
        "filter[email]=$TESTER_EMAIL" \
        "fields[userInvitations]=email,firstName,lastName,expirationDate,roles,allAppsVisible" \
        "limit=200")"
    pending_count="$(printf '%s' "$invitations_response" | jq '.data | length')"

    if [[ "$pending_count" -gt 0 && "$FORCE_NEW_INVITATION" == "1" ]]; then
        while IFS= read -r pending_id; do
            [[ -n "$pending_id" ]] || continue
            asc_request DELETE "/v1/userInvitations/$pending_id" "" >/dev/null
        done < <(printf '%s' "$invitations_response" | jq -r '.data[].id')
        pending_count=0
    fi

    if [[ "$pending_count" -gt 0 ]]; then
        invitation_id="$(printf '%s' "$invitations_response" | jq -r '.data[0].id')"
        invitation_expiration="$(printf '%s' "$invitations_response" | jq -r '.data[0].attributes.expirationDate // empty')"
        write_receipt acceptance-required "$app_id" "$group_id" "" "$invitation_id" "$invitation_expiration"
        exit 0
    fi

    invitation_payload="$(jq -n -c \
        --arg email "$TESTER_EMAIL" \
        --arg firstName "$TESTER_FIRST_NAME" \
        --arg lastName "$TESTER_LAST_NAME" \
        --arg appId "$app_id" \
        '{data:{type:"userInvitations",attributes:{email:$email,firstName:$firstName,lastName:$lastName,roles:["DEVELOPER"],allAppsVisible:false,provisioningAllowed:false},relationships:{visibleApps:{data:[{type:"apps",id:$appId}]}}}}')"
    invitation_response="$(asc_request POST /v1/userInvitations "$invitation_payload")"
    invitation_id="$(printf '%s' "$invitation_response" | jq -r '.data.id // empty')"
    invitation_expiration="$(printf '%s' "$invitation_response" | jq -r '.data.attributes.expirationDate // empty')"
    if [[ -z "$invitation_id" ]]; then
        echo "::error::Apple did not return a user invitation ID"
        exit 1
    fi
    write_receipt acceptance-required "$app_id" "$group_id" "" "$invitation_id" "$invitation_expiration"
    exit 0
fi

all_apps_visible="$(printf '%s' "$users_response" | jq -r '.data[0].attributes.allAppsVisible // false')"
user_roles="$(printf '%s' "$users_response" | jq -r '[.data[0].attributes.roles[]?] | join(",")')"
echo "Existing App Store Connect user found; roles=${user_roles:-none}; allAppsVisible=$all_apps_visible."
if [[ "$all_apps_visible" != "true" ]]; then
    visible_apps="$(asc_request GET "/v1/users/$user_id/visibleApps" "" "fields[apps]=bundleId" "limit=200")"
    has_app="$(printf '%s' "$visible_apps" | jq --arg id "$app_id" '[.data[] | select(.id == $id)] | length')"
    if [[ "$has_app" -eq 0 ]]; then
        visible_payload="$(jq -n -c --arg id "$app_id" '{data:[{type:"apps",id:$id}]}')"
        asc_request POST "/v1/users/$user_id/relationships/visibleApps" "$visible_payload" >/dev/null
        echo "Granted the existing user access to CodeIsland Buddy."
    else
        echo "The existing user already has CodeIsland Buddy app access."
    fi
fi

testers_response="$(asc_request GET /v1/betaTesters "" \
    "filter[email]=$TESTER_EMAIL" \
    "fields[betaTesters]=email,firstName,lastName,state" \
    "limit=200")"
tester_email_lower="$(printf '%s' "$TESTER_EMAIL" | tr '[:upper:]' '[:lower:]')"
tester_id="$(printf '%s' "$testers_response" | jq -r \
    --arg email "$tester_email_lower" \
    '.data[] | select((.attributes.email // "" | ascii_downcase) == $email) | .id' \
    | head -n 1)"
tester_state="$(printf '%s' "$testers_response" | jq -r \
    --arg email "$tester_email_lower" \
    '.data[] | select((.attributes.email // "" | ascii_downcase) == $email) | .attributes.state // "UNKNOWN"' \
    | head -n 1)"
if [[ -n "$tester_id" ]]; then
    echo "Existing TestFlight tester found; state=${tester_state:-UNKNOWN}."
fi

if [[ -n "$tester_id" && "$FORCE_NEW_INVITATION" == "1" ]]; then
    echo "Resetting the existing TestFlight tester record for a fresh internal invitation."
    asc_request DELETE "/v1/betaTesters/$tester_id" "" >/dev/null
    tester_id=""
fi

if [[ -z "$tester_id" ]]; then
    tester_payload="$(jq -n -c \
        --arg email "$TESTER_EMAIL" \
        --arg firstName "$TESTER_FIRST_NAME" \
        --arg lastName "$TESTER_LAST_NAME" \
        --arg groupId "$group_id" \
        '{data:{type:"betaTesters",attributes:{email:$email,firstName:$firstName,lastName:$lastName},relationships:{betaGroups:{data:[{type:"betaGroups",id:$groupId}]}}}}')"
    tester_response=""
    for attempt in 1 2 3 4 5; do
        if tester_response="$(asc_request POST /v1/betaTesters "$tester_payload")"; then
            break
        fi
        if [[ "$attempt" -eq 5 ]]; then
            echo "::error::Apple did not accept the fresh TestFlight tester after $attempt attempts"
            exit 1
        fi
        echo "Apple is still clearing the prior TestFlight tester; retrying in 5 seconds."
        sleep 5
    done
    tester_id="$(printf '%s' "$tester_response" | jq -r '.data.id // empty')"
fi

if [[ -z "$tester_id" ]]; then
    echo "::error::Apple did not return a TestFlight beta tester ID"
    exit 1
fi

group_testers="$(asc_request GET "/v1/betaGroups/$group_id/betaTesters" "" \
    "fields[betaTesters]=email,state" \
    "limit=200")"
is_member="$(printf '%s' "$group_testers" | jq --arg id "$tester_id" '[.data[] | select(.id == $id)] | length')"
if [[ "$is_member" -eq 0 ]]; then
    linkage_payload="$(jq -n -c --arg id "$tester_id" '{data:[{type:"betaTesters",id:$id}]}')"
    asc_request POST "/v1/betaGroups/$group_id/relationships/betaTesters" "$linkage_payload" >/dev/null
fi

verified_group_testers="$(asc_request GET "/v1/betaGroups/$group_id/betaTesters" "" \
    "fields[betaTesters]=email,state" \
    "limit=200")"
verified_member="$(printf '%s' "$verified_group_testers" | jq --arg id "$tester_id" '[.data[] | select(.id == $id)] | length')"
if [[ "$verified_member" -ne 1 ]]; then
    echo "::error::$TESTER_EMAIL is still absent from $BETA_GROUP_NAME after update"
    exit 1
fi

testflight_invitation_id=""
if [[ "$RESEND_TESTFLIGHT_INVITATION" == "1" ]]; then
    testflight_invitation_payload="$(jq -n -c \
        --arg appId "$app_id" \
        --arg testerId "$tester_id" \
        '{data:{type:"betaTesterInvitations",relationships:{app:{data:{type:"apps",id:$appId}},betaTester:{data:{type:"betaTesters",id:$testerId}}}}}')"
    testflight_invitation_response="$(asc_request POST /v1/betaTesterInvitations "$testflight_invitation_payload")"
    testflight_invitation_id="$(printf '%s' "$testflight_invitation_response" | jq -r '.data.id // empty')"
    invitation_already_accepted="$(printf '%s' "$testflight_invitation_response" | jq -r '.meta.alreadyAccepted // false')"
    if [[ "$invitation_already_accepted" == "true" ]]; then
        echo "$TESTER_EMAIL already accepted the TestFlight invitation; no resend is needed."
    elif [[ -z "$testflight_invitation_id" ]]; then
        echo "::error::Apple did not return a TestFlight invitation ID"
        exit 1
    else
        echo "Apple sent a fresh TestFlight invitation to $TESTER_EMAIL."
    fi
fi

write_receipt ready "$app_id" "$group_id" "$tester_id" "$testflight_invitation_id"
