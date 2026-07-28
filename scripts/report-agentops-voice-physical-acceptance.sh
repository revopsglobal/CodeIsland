#!/usr/bin/env bash

set -euo pipefail

BUILD=""
DEVICE=""
IOS_VERSION=""
GATEWAY_VERSION=""
TESTFLIGHT_RUN=""
TESTFLIGHT_SHA=""
APPLE_STATE=""
TESTER_VERDICT=""
TESTED_AT=""
SCENARIO_FILE=""
MARKDOWN_OUTPUT=""

usage() {
    cat <<'EOF'
Usage:
  report-agentops-voice-physical-acceptance.sh \
    --build BUILD \
    --device DEVICE \
    --ios-version IOS_VERSION \
    --gateway-version GIT_SHA \
    --testflight-run URL \
    --testflight-sha GIT_SHA \
    --apple-state VALID \
    --tester-verdict pass \
    --tested-at RFC3339 \
    --scenario-file PATH \
    [--markdown PATH]

The scenario file must be JSON with:
  - exactly the six required physical scenarios;
  - every scenario verdict set to "pass";
  - the scenario-specific AgentOps handles described by --example;
  - all supplemental physical checks set to true;
  - at least one successful dispatch-response receipt; and
  - the corresponding orch_events UUIDs.

The command exits 0 only when the complete physical gate passes.
EOF
}

example() {
    cat <<'EOF'
{
  "scenarios": [
    {
      "id": "wiki-context",
      "verdict": "pass",
      "evidence": ["physical:<handle>"],
      "sourceHandles": ["https://agentops.revopsglobal.com/<source>"]
    },
    {
      "id": "durable-read-only",
      "verdict": "pass",
      "evidence": ["physical:<handle>"],
      "taskId": "00000000-0000-4000-8000-000000000000"
    },
    {
      "id": "locked-codex",
      "verdict": "pass",
      "evidence": ["physical:<handle>"],
      "taskId": "00000000-0000-4000-8000-000000000000",
      "routingMode": "locked",
      "implementer": "codex",
      "allowFallback": false
    },
    {
      "id": "receipt-verification",
      "verdict": "pass",
      "evidence": ["physical:<handle>"],
      "taskId": "00000000-0000-4000-8000-000000000000",
      "receiptRunId": "<swarm_runs.run_id>",
      "receiptVerdict": "PASS",
      "workerStatementAloneVerified": false
    },
    {
      "id": "explicit-tap-approval",
      "verdict": "pass",
      "evidence": ["physical:<handle>"],
      "taskId": "00000000-0000-4000-8000-000000000000",
      "approvalId": "00000000-0000-4000-8000-000000000000",
      "actionDigest": "<64 lowercase hex characters>",
      "spokenYesChangedState": false,
      "visibleTapResolved": true
    },
    {
      "id": "idempotent-replay",
      "verdict": "pass",
      "evidence": ["physical:<handle>"],
      "taskId": "00000000-0000-4000-8000-000000000000",
      "turnId": "00000000-0000-4000-8000-000000000000",
      "taskCount": 1
    }
  ],
  "checks": {
    "loudspeaker": true,
    "receiverRoute": true,
    "bluetoothRoute": true,
    "cancelPlayback": true,
    "singleResponsePerTurn": true,
    "backgroundForeground": true,
    "notificationDedupe": true,
    "liveActivityStart": true,
    "liveActivityUpdate": true,
    "liveActivityEnd": true,
    "maxUnavailableNoFallback": true,
    "localDraftRetention": true
  },
  "eventIds": [
    "00000000-0000-4000-8000-000000000000"
  ],
  "dispatchReceipts": [
    {
      "eventId": "00000000-0000-4000-8000-000000000000",
      "requestId": 1,
      "httpStatus": 200
    }
  ]
}
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build)
            BUILD="${2:-}"
            shift 2
            ;;
        --device)
            DEVICE="${2:-}"
            shift 2
            ;;
        --ios-version)
            IOS_VERSION="${2:-}"
            shift 2
            ;;
        --gateway-version)
            GATEWAY_VERSION="${2:-}"
            shift 2
            ;;
        --testflight-run)
            TESTFLIGHT_RUN="${2:-}"
            shift 2
            ;;
        --testflight-sha)
            TESTFLIGHT_SHA="${2:-}"
            shift 2
            ;;
        --apple-state)
            APPLE_STATE="${2:-}"
            shift 2
            ;;
        --tester-verdict)
            TESTER_VERDICT="${2:-}"
            shift 2
            ;;
        --tested-at)
            TESTED_AT="${2:-}"
            shift 2
            ;;
        --scenario-file)
            SCENARIO_FILE="${2:-}"
            shift 2
            ;;
        --markdown)
            MARKDOWN_OUTPUT="${2:-}"
            shift 2
            ;;
        --example)
            example
            exit 0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 2
fi

missing_inputs=()
[[ -n "$BUILD" ]] || missing_inputs+=("build")
[[ -n "$DEVICE" ]] || missing_inputs+=("device")
[[ -n "$IOS_VERSION" ]] || missing_inputs+=("ios-version")
[[ -n "$GATEWAY_VERSION" ]] || missing_inputs+=("gateway-version")
[[ -n "$TESTFLIGHT_RUN" ]] || missing_inputs+=("testflight-run")
[[ -n "$TESTFLIGHT_SHA" ]] || missing_inputs+=("testflight-sha")
[[ -n "$APPLE_STATE" ]] || missing_inputs+=("apple-state")
[[ -n "$TESTER_VERDICT" ]] || missing_inputs+=("tester-verdict")
[[ -n "$TESTED_AT" ]] || missing_inputs+=("tested-at")
[[ -n "$SCENARIO_FILE" ]] || missing_inputs+=("scenario-file")

if [[ ${#missing_inputs[@]} -gt 0 ]]; then
    printf 'Missing required arguments: %s\n' "$(IFS=,; echo "${missing_inputs[*]}")" >&2
    exit 2
fi

if [[ ! -r "$SCENARIO_FILE" ]] || ! jq -e 'type == "object"' "$SCENARIO_FILE" >/dev/null 2>&1; then
    echo "Scenario file must be readable JSON object: $SCENARIO_FILE" >&2
    exit 2
fi

required_scenarios="$(
    jq -n -c '[
        "wiki-context",
        "durable-read-only",
        "locked-codex",
        "receipt-verification",
        "explicit-tap-approval",
        "idempotent-replay"
    ]'
)"

required_checks="$(
    jq -n -c '[
        "loudspeaker",
        "receiverRoute",
        "bluetoothRoute",
        "cancelPlayback",
        "singleResponsePerTurn",
        "backgroundForeground",
        "notificationDedupe",
        "liveActivityStart",
        "liveActivityUpdate",
        "liveActivityEnd",
        "maxUnavailableNoFallback",
        "localDraftRetention"
    ]'
)"

scenario_audit="$(
    jq -c \
        --argjson required "$required_scenarios" \
        '
        def uuid:
            type == "string"
            and test("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$");
        def evidence:
            (.evidence | type == "array" and length > 0)
            and all(.evidence[]; type == "string" and length > 0);
        def base:
            (.verdict == "pass") and evidence;
        def valid_for($id):
            if $id == "wiki-context" then
                base
                and (.sourceHandles | type == "array" and length > 0)
                and all(.sourceHandles[]; type == "string" and length > 0)
            elif $id == "durable-read-only" then
                base and (.taskId | uuid)
            elif $id == "locked-codex" then
                base
                and (.taskId | uuid)
                and .routingMode == "locked"
                and .implementer == "codex"
                and .allowFallback == false
            elif $id == "receipt-verification" then
                base
                and (.taskId | uuid)
                and (.receiptRunId | type == "string" and length > 0)
                and .receiptVerdict == "PASS"
                and .workerStatementAloneVerified == false
            elif $id == "explicit-tap-approval" then
                base
                and (.taskId | uuid)
                and (.approvalId | uuid)
                and (.actionDigest | type == "string" and test("^[0-9a-f]{64}$"))
                and .spokenYesChangedState == false
                and .visibleTapResolved == true
            elif $id == "idempotent-replay" then
                base
                and (.taskId | uuid)
                and (.turnId | uuid)
                and .taskCount == 1
            else
                false
            end;
        (.scenarios // null) as $rows
        | {
            expectedIds: $required,
            observedIds: (
                if ($rows | type) == "array"
                then [$rows[]?.id] | sort
                else []
                end
            ),
            results: [
                $required[] as $id
                | (
                    if ($rows | type) == "array"
                    then [$rows[] | select(.id == $id)]
                    else []
                    end
                ) as $matches
                | {
                    id: $id,
                    occurrenceCount: ($matches | length),
                    passed: (
                        ($matches | length) == 1
                        and ($matches[0] | valid_for($id))
                    ),
                    record: ($matches[0] // null)
                }
            ]
        }
        | .complete = (
            (.observedIds == (.expectedIds | sort))
            and all(.results[]; .passed)
        )
        ' "$SCENARIO_FILE"
)"

supplemental_audit="$(
    jq -c \
        --argjson required "$required_checks" \
        '
        {
            required: $required,
            results: [
                $required[] as $id
                | {id:$id, passed: ((.checks // {})[$id] == true)}
            ]
        }
        | .complete = all(.results[]; .passed)
        ' "$SCENARIO_FILE"
)"

ledger_audit="$(
    jq -c '
        def uuid:
            type == "string"
            and test("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$");
        {
            eventIds: (.eventIds // []),
            dispatchReceipts: (.dispatchReceipts // [])
        }
        | .eventsValid = (
            (.eventIds | type == "array" and length > 0)
            and all(.eventIds[]; uuid)
            and ((.eventIds | unique | length) == (.eventIds | length))
        )
        | .dispatchValid = (
            (.dispatchReceipts | type == "array" and length > 0)
            and all(
                .dispatchReceipts[];
                (.eventId | uuid)
                and (.requestId | type == "number" and . > 0 and floor == .)
                and (.httpStatus | type == "number" and . >= 200 and . < 300)
            )
        )
        | .complete = (.eventsValid and .dispatchValid)
        ' "$SCENARIO_FILE"
)"

metadata_complete=true
[[ "$BUILD" =~ ^[0-9]+$ ]] || metadata_complete=false
[[ "$GATEWAY_VERSION" =~ ^[0-9a-f]{40}$ ]] || metadata_complete=false
[[ "$TESTFLIGHT_SHA" =~ ^[0-9a-f]{40}$ ]] || metadata_complete=false
[[ "$TESTFLIGHT_RUN" =~ ^https://github\.com/[^/]+/[^/]+/actions/runs/[0-9]+$ ]] || metadata_complete=false
[[ "$APPLE_STATE" == "VALID" ]] || metadata_complete=false
[[ "$TESTER_VERDICT" == "pass" ]] || metadata_complete=false
[[ "$TESTED_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || metadata_complete=false

complete=false
if [[ "$metadata_complete" == "true" \
    && "$(printf '%s' "$scenario_audit" | jq -r '.complete')" == "true" \
    && "$(printf '%s' "$supplemental_audit" | jq -r '.complete')" == "true" \
    && "$(printf '%s' "$ledger_audit" | jq -r '.complete')" == "true" ]]; then
    complete=true
fi

report="$(
    jq -n \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg build "$BUILD" \
        --arg device "$DEVICE" \
        --arg iosVersion "$IOS_VERSION" \
        --arg gatewayVersion "$GATEWAY_VERSION" \
        --arg testFlightRun "$TESTFLIGHT_RUN" \
        --arg testFlightSha "$TESTFLIGHT_SHA" \
        --arg appleState "$APPLE_STATE" \
        --arg testerVerdict "$TESTER_VERDICT" \
        --arg testedAt "$TESTED_AT" \
        --argjson metadataComplete "$metadata_complete" \
        --argjson scenarios "$scenario_audit" \
        --argjson supplemental "$supplemental_audit" \
        --argjson ledger "$ledger_audit" \
        --argjson complete "$complete" \
        '{
            generatedAt:$generatedAt,
            complete:$complete,
            release:{
                build:$build,
                testFlightRun:$testFlightRun,
                testFlightSha:$testFlightSha,
                appleState:$appleState,
                gatewayVersion:$gatewayVersion
            },
            physicalDevice:{
                model:$device,
                iosVersion:$iosVersion,
                testerVerdict:$testerVerdict,
                testedAt:$testedAt
            },
            gates:{
                metadata:$metadataComplete,
                scenarios:$scenarios,
                supplemental:$supplemental,
                ledger:$ledger
            }
        }'
)"

printf '%s\n' "$report"

if [[ -n "$MARKDOWN_OUTPUT" ]]; then
    mkdir -p "$(dirname "$MARKDOWN_OUTPUT")"
    printf '%s' "$report" | jq -r '
        def mark($value): if $value then "PASS" else "FAIL" end;
        "# AgentOps Voice physical acceptance\n\n"
        + "- Status: **" + (mark(.complete)) + "**\n"
        + "- Tested: `" + .physicalDevice.testedAt + "`\n"
        + "- Device: `" + .physicalDevice.model + "` on iOS `" + .physicalDevice.iosVersion + "`\n"
        + "- TestFlight build: `" + .release.build + "`\n"
        + "- TestFlight run: " + .release.testFlightRun + "\n"
        + "- TestFlight SHA: `" + .release.testFlightSha + "`\n"
        + "- Apple processing: `" + .release.appleState + "`\n"
        + "- Gateway version: `" + .release.gatewayVersion + "`\n"
        + "- Tester verdict: `" + .physicalDevice.testerVerdict + "`\n\n"
        + "## Required scenarios\n\n"
        + (
            [.gates.scenarios.results[]
                | "- " + .id + ": **" + mark(.passed) + "**"
                + (if .record.taskId then " task `" + .record.taskId + "`" else "" end)
                + (if .record.receiptRunId then " receipt `" + .record.receiptRunId + "`" else "" end)
                + (if .record.approvalId then " approval `" + .record.approvalId + "`" else "" end)
                + (if .record.actionDigest then " digest `" + .record.actionDigest + "`" else "" end)
            ] | join("\n")
        )
        + "\n\n## Supplemental checks\n\n"
        + (
            [.gates.supplemental.results[]
                | "- " + .id + ": **" + mark(.passed) + "**"
            ] | join("\n")
        )
        + "\n\n## Durable handles\n\n"
        + "- orch_events: "
        + (
            if (.gates.ledger.eventIds | length) == 0
            then "none"
            else ([.gates.ledger.eventIds[] | "`" + . + "`"] | join(", "))
            end
        )
        + "\n- dispatch responses: "
        + (
            if (.gates.ledger.dispatchReceipts | length) == 0
            then "none"
            else (
                [.gates.ledger.dispatchReceipts[]
                    | "event `" + .eventId + "`, request `" + (.requestId | tostring)
                    + "`, HTTP `" + (.httpStatus | tostring) + "`"
                ] | join("; ")
            )
            end
        )
        + "\n"
    ' >"$MARKDOWN_OUTPUT"
fi

if [[ "$complete" != "true" ]]; then
    exit 2
fi
