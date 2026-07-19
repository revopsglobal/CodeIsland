#!/usr/bin/env bash

set -euo pipefail

COMPLETION_AUDIT_BIN="${COMPLETION_AUDIT_BIN:-$(dirname "$0")/report-codeisland-completion-audit.sh}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-10}"
MAX_POLLS="${MAX_POLLS:-0}"
SLEEP_BIN="${SLEEP_BIN:-sleep}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

epoch_now() {
    date +%s
}

json_or_failure() {
    local raw="$1"
    if printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
        printf '%s' "$raw"
    else
        jq -n -c \
            --arg output "$raw" \
            '{
                complete:false,
                status:"completion-audit-invalid-json",
                requiredGates:[
                    {
                        id:"completion-audit-report",
                        status:"invalid-json",
                        owner:"codex",
                        nextAction:"Fix scripts/report-codeisland-completion-audit.sh so the waiter can inspect objective state."
                    }
                ],
                output:$output
            }'
    fi
}

emit_wait_report() {
    local status="$1"
    local complete="$2"
    local attempts="$3"
    local timed_out="$4"
    local final_audit="$5"
    jq -n \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg status "$status" \
        --argjson complete "$complete" \
        --argjson attempts "$attempts" \
        --argjson timedOut "$timed_out" \
        --argjson timeoutSeconds "$TIMEOUT_SECONDS" \
        --argjson pollIntervalSeconds "$POLL_INTERVAL_SECONDS" \
        --argjson maxPolls "$MAX_POLLS" \
        --argjson finalAudit "$final_audit" \
        '{
            generatedAt:$generatedAt,
            complete:$complete,
            status:$status,
            attempts:$attempts,
            timedOut:$timedOut,
            timeoutSeconds:$timeoutSeconds,
            pollIntervalSeconds:$pollIntervalSeconds,
            maxPolls:$maxPolls,
            finalAudit:$finalAudit,
            remainingGates:($finalAudit.requiredGates // []),
            nextAction:(
                if $complete then
                    "CodeIsland completion audit is complete; preserve this JSON as the final E2E receipt."
                elif $timedOut then
                    (($finalAudit.requiredGates // [])[0].nextAction // "Completion did not pass before timeout; rerun after the physical iPhone is ready.")
                else
                    (($finalAudit.requiredGates // [])[0].nextAction // "Continue waiting for the completion audit to pass.")
                end
            )
        }'
}

start_epoch="$(epoch_now)"
deadline_epoch=$((start_epoch + TIMEOUT_SECONDS))
attempts=0
last_audit='{"complete":false,"status":"not-run","requiredGates":[]}'

while true; do
    attempts=$((attempts + 1))
    audit_raw=""
    set +e
    audit_raw="$("$COMPLETION_AUDIT_BIN" 2>&1)"
    audit_exit=$?
    set -e
    last_audit="$(json_or_failure "$audit_raw")"

    if [[ "$(printf '%s' "$last_audit" | jq -r '.complete == true')" == "true" && "$audit_exit" -eq 0 ]]; then
        emit_wait_report "complete" true "$attempts" false "$last_audit"
        exit 0
    fi

    now_epoch="$(epoch_now)"
    if [[ "$MAX_POLLS" -gt 0 && "$attempts" -ge "$MAX_POLLS" ]]; then
        emit_wait_report "max-polls-exhausted" false "$attempts" false "$last_audit"
        exit 2
    fi
    if [[ "$now_epoch" -ge "$deadline_epoch" ]]; then
        emit_wait_report "timeout" false "$attempts" true "$last_audit"
        exit 2
    fi

    "$SLEEP_BIN" "$POLL_INTERVAL_SECONDS"
done
