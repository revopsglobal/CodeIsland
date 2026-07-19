#!/usr/bin/env bash

set -euo pipefail

: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_PRIVATE_KEY_PATH:?ASC_PRIVATE_KEY_PATH is required}"
: "${DISTRIBUTION_CERTIFICATE_SERIAL:?DISTRIBUTION_CERTIFICATE_SERIAL is required}"

BUNDLE_ID="${BUNDLE_ID:-com.revopsglobal.codeisland.buddy.share}"
BUNDLE_NAME="${BUNDLE_NAME:-CodeIsland Buddy Share}"
PROFILE_NAME="${PROFILE_NAME:-CodeIsland Buddy Share App Store}"
APP_GROUP_ID="${APP_GROUP_ID:-group.com.revopsglobal.codeisland.buddy}"
PROFILE_OUTPUT_PATH="${PROFILE_OUTPUT_PATH:-CodeIsland-Buddy-Share-App-Store.mobileprovision}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
    echo "::error::jq is required"
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
        echo "::error::App Store Connect $method $path returned HTTP $http_status" >&2
        printf '%s' "$body_response" | jq -r \
            '.errors[]? | "::error::\(.code // "APPLE_ERROR"): \(.title // "Request failed") — \(.detail // "No detail")"' \
            >&2 || true
        return 22
    fi
    printf '%s' "$body_response"
}

verify_profile() {
    if [[ -n "${PROFILE_VERIFY_COMMAND:-}" ]]; then
        "$PROFILE_VERIFY_COMMAND" "$PROFILE_OUTPUT_PATH" "$BUNDLE_ID" "$PROFILE_NAME" "$APP_GROUP_ID"
        return
    fi

    local plist_path="${PROFILE_OUTPUT_PATH}.plist"
    security cms -D -i "$PROFILE_OUTPUT_PATH" > "$plist_path"
    local actual_name
    local application_identifier
    actual_name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$plist_path")"
    application_identifier="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$plist_path")"
    [[ "$actual_name" == "$PROFILE_NAME" ]] || {
        echo "::error::Generated profile name is $actual_name, expected $PROFILE_NAME"
        exit 1
    }
    [[ "$application_identifier" == *".$BUNDLE_ID" ]] || {
        echo "::error::Generated profile does not target $BUNDLE_ID"
        exit 1
    }
    /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups' "$plist_path" \
        | grep -Fq "$APP_GROUP_ID" || {
            echo "::error::Generated profile does not include $APP_GROUP_ID"
            exit 1
        }
}

bundle_response="$(asc_request GET /v1/bundleIds "" \
    "filter[identifier]=$BUNDLE_ID" \
    "fields[bundleIds]=name,identifier,platform" \
    "limit=1")"
bundle_resource_id="$(printf '%s' "$bundle_response" | jq -r '.data[0].id // empty')"

if [[ -z "$bundle_resource_id" ]]; then
    bundle_payload="$(jq -n -c \
        --arg identifier "$BUNDLE_ID" \
        --arg name "$BUNDLE_NAME" \
        '{data:{type:"bundleIds",attributes:{identifier:$identifier,name:$name,platform:"IOS"}}}')"
    bundle_response="$(asc_request POST /v1/bundleIds "$bundle_payload")"
    bundle_resource_id="$(printf '%s' "$bundle_response" | jq -r '.data.id // empty')"
    [[ -n "$bundle_resource_id" ]] || {
        echo "::error::Apple did not return a bundle ID resource for $BUNDLE_ID"
        exit 1
    }
    echo "Registered $BUNDLE_ID."
else
    echo "Found registered bundle ID $BUNDLE_ID."
fi

capabilities_response="$(asc_request GET "/v1/bundleIds/$bundle_resource_id/bundleIdCapabilities" "" \
    "fields[bundleIdCapabilities]=capabilityType,settings" \
    "limit=200")"
app_groups_capability_id="$(printf '%s' "$capabilities_response" | jq -r \
    '.data[] | select(.attributes.capabilityType == "APP_GROUPS") | .id' \
    | head -n 1)"
capability_attributes="$(jq -n -c \
    --arg group "$APP_GROUP_ID" \
    '{capabilityType:"APP_GROUPS",settings:[{key:"APP_GROUP_IDS",options:[{key:$group,enabled:true}]}]}')"

if [[ -z "$app_groups_capability_id" ]]; then
    capability_payload="$(jq -n -c \
        --argjson attributes "$capability_attributes" \
        --arg bundleId "$bundle_resource_id" \
        '{data:{type:"bundleIdCapabilities",attributes:$attributes,relationships:{bundleId:{data:{type:"bundleIds",id:$bundleId}}}}}')"
    asc_request POST /v1/bundleIdCapabilities "$capability_payload" >/dev/null
    echo "Enabled the App Groups capability for $BUNDLE_ID."
else
    existing_group_enabled="$(printf '%s' "$capabilities_response" | jq -r \
        --arg id "$app_groups_capability_id" \
        --arg group "$APP_GROUP_ID" \
        '[.data[] | select(.id == $id) | .attributes.settings[]?.options[]? | select(.key == $group and .enabled == true)] | length')"
    if [[ "$existing_group_enabled" -eq 0 ]]; then
        capability_payload="$(jq -n -c \
            --arg id "$app_groups_capability_id" \
            --argjson attributes "$capability_attributes" \
            '{data:{type:"bundleIdCapabilities",id:$id,attributes:$attributes}}')"
        asc_request PATCH "/v1/bundleIdCapabilities/$app_groups_capability_id" "$capability_payload" >/dev/null
        echo "Bound $APP_GROUP_ID to $BUNDLE_ID."
    else
        echo "$APP_GROUP_ID is already bound to $BUNDLE_ID."
    fi
fi

normalized_serial="$(printf '%s' "$DISTRIBUTION_CERTIFICATE_SERIAL" | tr -d '[:space:]:' | tr '[:lower:]' '[:upper:]')"
certificates_response="$(asc_request GET /v1/certificates "" \
    "filter[certificateType]=IOS_DISTRIBUTION" \
    "fields[certificates]=name,certificateType,displayName,serialNumber,expirationDate,activated" \
    "limit=200")"
certificate_id="$(printf '%s' "$certificates_response" | jq -r \
    --arg serial "$normalized_serial" \
    '.data[] | select(.attributes.activated == true and ((.attributes.serialNumber // "") | ascii_upcase | gsub(":"; "")) == $serial) | .id' \
    | head -n 1)"
[[ -n "$certificate_id" ]] || {
    echo "::error::No active iOS distribution certificate matches the configured P12 serial"
    exit 1
}

profiles_response="$(asc_request GET /v1/profiles "" \
    "filter[name]=$PROFILE_NAME" \
    "filter[profileType]=IOS_APP_STORE" \
    "fields[profiles]=name,profileType,profileState,profileContent,uuid,expirationDate,bundleId,certificates" \
    "include=bundleId,certificates" \
    "limit=200")"
matching_profile_content="$(printf '%s' "$profiles_response" | jq -r \
    --arg bundleId "$bundle_resource_id" \
    --arg certificateId "$certificate_id" \
    '.data[] | select(
        .attributes.profileState == "ACTIVE" and
        .relationships.bundleId.data.id == $bundleId and
        ([.relationships.certificates.data[]?.id] | index($certificateId)) != null
    ) | .attributes.profileContent // empty' \
    | head -n 1)"

if [[ -z "$matching_profile_content" ]]; then
    while IFS= read -r profile_id; do
        [[ -n "$profile_id" ]] || continue
        asc_request DELETE "/v1/profiles/$profile_id" "" >/dev/null
    done < <(printf '%s' "$profiles_response" | jq -r '.data[].id')

    profile_payload="$(jq -n -c \
        --arg name "$PROFILE_NAME" \
        --arg bundleId "$bundle_resource_id" \
        --arg certificateId "$certificate_id" \
        '{data:{type:"profiles",attributes:{name:$name,profileType:"IOS_APP_STORE"},relationships:{bundleId:{data:{type:"bundleIds",id:$bundleId}},certificates:{data:[{type:"certificates",id:$certificateId}]}}}}')"
    profile_response="$(asc_request POST /v1/profiles "$profile_payload")"
    matching_profile_content="$(printf '%s' "$profile_response" | jq -r '.data.attributes.profileContent // empty')"
    [[ -n "$matching_profile_content" ]] || {
        echo "::error::Apple did not return profile content for $PROFILE_NAME"
        exit 1
    }
    echo "Created $PROFILE_NAME."
else
    echo "Reusing active $PROFILE_NAME."
fi

mkdir -p "$(dirname "$PROFILE_OUTPUT_PATH")"
printf '%s' "$matching_profile_content" | base64 --decode > "$PROFILE_OUTPUT_PATH"
[[ -s "$PROFILE_OUTPUT_PATH" ]] || {
    echo "::error::Generated provisioning profile is empty"
    exit 1
}
verify_profile
echo "Provisioning profile ready at $PROFILE_OUTPUT_PATH."
