#!/usr/bin/env bash

set -euo pipefail

STRICT_E2E_BIN="${STRICT_E2E_BIN:-$(dirname "$0")/report-strict-physical-e2e.sh}"
AWAY_READINESS_BIN="${AWAY_READINESS_BIN:-$(dirname "$0")/report-away-readiness.sh}"
CREST_PARITY_BIN="${CREST_PARITY_BIN:-}"
SWIFT_BIN="${SWIFT_BIN:-swift}"
CREST_PARITY_TEST_FILTER="${CREST_PARITY_TEST_FILTER:-GlancesModelTests|PersonalHubProtocolTests|RemoteApprovalHTTPServerTests/testAuthenticatedHostLifecycleOverRealListener}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

json_or_failure() {
    local id="$1"
    local owner="$2"
    local next_action="$3"
    local raw="$4"
    if printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
        printf '%s' "$raw"
    else
        jq -n -c \
            --arg id "$id" \
            --arg owner "$owner" \
            --arg nextAction "$next_action" \
            --arg output "$raw" \
            '{
                complete:false,
                status:"invalid-json",
                parseable:false,
                output:$output,
                requiredGates:[
                    {
                        id:$id,
                        status:"invalid-json",
                        owner:$owner,
                        nextAction:$nextAction
                    }
                ]
            }'
    fi
}

strict_raw=""
strict_exit=0
set +e
strict_raw="$("$STRICT_E2E_BIN" 2>&1)"
strict_exit=$?
set -e
strict_json="$(json_or_failure \
    "strict-e2e-report" \
    "codex" \
    "Fix scripts/report-strict-physical-e2e.sh so the objective completion audit can inspect physical E2E state." \
    "$strict_raw")"

away_raw=""
away_exit=0
set +e
away_raw="$("$AWAY_READINESS_BIN" 2>&1)"
away_exit=$?
set -e
away_json="$(json_or_failure \
    "away-readiness-report" \
    "codex" \
    "Fix scripts/report-away-readiness.sh so the objective completion audit can inspect away-use readiness." \
    "$away_raw")"

crest_parity_json=""
if [[ -n "$CREST_PARITY_BIN" ]]; then
    crest_parity_raw=""
    set +e
    crest_parity_raw="$("$CREST_PARITY_BIN" 2>&1)"
    crest_parity_exit=$?
    set -e
    crest_parity_json="$(json_or_failure \
        "crest-parity-source-report" \
        "codex" \
        "Fix the Crest/source parity verifier so the objective completion audit can inspect Mac/iPhone/web parity coverage." \
        "$crest_parity_raw")"
    if printf '%s' "$crest_parity_json" | jq -e '.exitCode? == null' >/dev/null 2>&1; then
        crest_parity_json="$(printf '%s' "$crest_parity_json" | jq --argjson exitCode "$crest_parity_exit" '. + {exitCode:$exitCode}')"
    fi
else
    crest_parity_log="$(mktemp -t codeisland-crest-parity)"
    crest_parity_exit=0
    set +e
    DEVELOPER_DIR="$DEVELOPER_DIR" "$SWIFT_BIN" test --filter "$CREST_PARITY_TEST_FILTER" >"$crest_parity_log" 2>&1
    crest_parity_exit=$?
    set -e
    crest_parity_tail="$(tail -n 80 "$crest_parity_log")"
    crest_parity_json="$(jq -n -c \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg command "$SWIFT_BIN test --filter $CREST_PARITY_TEST_FILTER" \
        --arg filter "$CREST_PARITY_TEST_FILTER" \
        --argjson exitCode "$crest_parity_exit" \
        --arg logTail "$crest_parity_tail" \
        '{
            generatedAt:$generatedAt,
            checked:true,
            status:(if $exitCode == 0 then "passed" else "failed" end),
            complete:($exitCode == 0),
            command:$command,
            filter:$filter,
            exitCode:$exitCode,
            logTail:$logTail,
            nextAction:(
                if $exitCode == 0 then
                    "Crest/source parity tests passed; continue physical E2E acceptance."
                else
                    "Fix Crest/source parity tests before claiming CodeIsland matches the Mac/iPhone/web parity contract."
                end
            )
        }')"
fi

audit="$(jq -n \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson strict "$strict_json" \
    --argjson strictExit "$strict_exit" \
    --argjson away "$away_json" \
    --argjson awayExit "$away_exit" \
    --argjson crestParity "$crest_parity_json" \
    '
    def bool($v): $v == true;
    def gate($id; $status; $owner; $nextAction):
        {id:$id,status:$status,owner:$owner,nextAction:$nextAction};
    def strict_required:
        [
            ($strict.remainingGates // [])[]
            | select(.required != false)
            | {id,status,owner,nextAction}
        ];
    def away_required:
        [
            ($away.requiredGates // [])[]
            | {id,status,owner,nextAction}
        ];
    def dedupe_gates:
        reduce (.[]) as $gate ([];
            if any(.[]; .id == $gate.id) then . else . + [$gate] end
        );
    def latest_build:
        $away.nativeBuddy.latestBuild //
        $strict.latestGate.report.latestTestFlight.buildNumber //
        $strict.latestGate.report.latestGate.report.latestTestFlight.buildNumber //
        null;
    def signed_testflight_ready:
        ($away.nativeBuddy.appleState == "VALID") and
        ($away.nativeBuddy.sourceCurrent == true) and
        ((latest_build // "") | length > 0);
    def private_web_ready:
        ($away.webFallback.reachable == true) and
        ($away.webFallback.shell.reachable == true) and
        ($away.webFallback.shell.markers.questions == true) and
        ($away.webFallback.shell.markers.approvals == true) and
        ($away.webFallback.shell.markers.hub == true) and
        ($away.webFallback.shell.markers.mobileViewport == true) and
        ($away.webFallback.shell.markers.iosPWA == true) and
        ($away.webFallback.shell.markers.safeArea == true) and
        ($away.webFallback.shell.markers.touchTargets == true) and
        ($away.webFallback.shell.markers.liveFeedback == true) and
        ($away.webFallback.shell.markers.inlineReview == true) and
        ($away.webFallback.shell.markers.noBrowserDialogs == true);
    def away_surface_ready:
        ($away.readyForAwayManualAcceptance == true) and private_web_ready;
    def crest_parity_ready:
        ($crestParity.checked == true) and
        ($crestParity.complete == true or $crestParity.status == "passed") and
        ($crestParity.exitCode == 0);
    def physical_e2e_complete:
        ($strict.complete == true) and
        ($away.nativeBuddy.physicalAccepted == true or $away.complete == true);
    def overclaim_guardrails_ready:
        ($strict.status? != null) and
        ($away.status? != null) and
        (physical_e2e_complete or (($strict.complete != true) and (($strict.remainingGates // []) | length > 0)));
    def requirement($id; $label; $status; $complete; $evidence; $nextAction):
        {
            id:$id,
            label:$label,
            status:$status,
            complete:$complete,
            evidence:$evidence,
            nextAction:$nextAction
        };
    def missing_signed_gate:
        if signed_testflight_ready then []
        else [gate(
            "signed-testflight-delivery";
            ($away.nativeBuddy.appleState // "unknown");
            "codex";
            "Upload or repair a valid internal TestFlight Buddy build and ensure current Buddy-relevant source matches it."
        )]
        end;
    def missing_web_gate:
        if private_web_ready then []
        else [gate(
            "private-web-mobile-fallback";
            ($away.webFallback.shell.status // $away.status // "unknown");
            "codex";
            "Restore the authenticated private web fallback and mobile/PWA shell markers, then rerun away readiness."
        )]
        end;
    def missing_crest_parity_gate:
        if crest_parity_ready then []
        else [gate(
            "crest-source-parity";
            ($crestParity.status // "unknown");
            "codex";
            ($crestParity.nextAction // "Run and fix the focused Crest/source parity tests.")
        )]
        end;
    {
        generatedAt:$generatedAt,
        complete:(signed_testflight_ready and crest_parity_ready and away_surface_ready and physical_e2e_complete and overclaim_guardrails_ready),
        status:(
            if (signed_testflight_ready and crest_parity_ready and away_surface_ready and physical_e2e_complete and overclaim_guardrails_ready) then
                "complete"
            elif (signed_testflight_ready | not) then
                "testflight-incomplete"
            elif (crest_parity_ready | not) then
                "crest-parity-incomplete"
            elif (away_surface_ready | not) then
                "away-surface-incomplete"
            elif (physical_e2e_complete | not) then
                "physical-e2e-incomplete"
            else
                "incomplete"
            end
        ),
        objective:"Finish CodeIsland end to end: Crest-class Mac feature parity, actionable iPhone parity over Tailscale with native Buddy push for away use, signed TestFlight delivery, and real end-to-end verification without overstating any untested surface.",
        requirements:[
            requirement(
                "signed-testflight-delivery";
                "Signed TestFlight Buddy delivery is valid and source-current";
                (if signed_testflight_ready then "ready" else "incomplete" end);
                signed_testflight_ready;
                {
                    latestBuild:latest_build,
                    appleState:$away.nativeBuddy.appleState,
                    sourceCurrent:$away.nativeBuddy.sourceCurrent
                };
                (if signed_testflight_ready then
                    "Continue physical iPhone acceptance on the current build."
                 else
                    "Repair TestFlight delivery/source drift before physical acceptance."
                 end)
            ),
            requirement(
                "crest-source-parity";
                "Crest-class Mac parity and Mac/iPhone/web action contract are source-verified";
                (if crest_parity_ready then "passed" else ($crestParity.status // "incomplete") end);
                crest_parity_ready;
                {
                    command:$crestParity.command,
                    filter:$crestParity.filter,
                    exitCode:$crestParity.exitCode
                };
                (if crest_parity_ready then
                    "Continue physical E2E acceptance on the source-verified parity contract."
                 else
                    ($crestParity.nextAction // "Fix Crest/source parity before claiming completion.")
                 end)
            ),
            requirement(
                "private-web-mobile-fallback";
                "Private web fallback is reachable and phone-usable over Tailscale";
                (if private_web_ready then "ready" else "incomplete" end);
                private_web_ready;
                {
                    reachable:$away.webFallback.reachable,
                    shell:$away.webFallback.shell
                };
                (if private_web_ready then
                    "Use as fallback while physical iPhone browser/cellular acceptance remains separate."
                 else
                    "Restore Tailscale/web shell readiness."
                 end)
            ),
            requirement(
                "native-iphone-away-surface";
                "Native iPhone away surface is ready for manual physical acceptance";
                (if away_surface_ready then "ready-for-manual-physical-acceptance" else "incomplete" end);
                away_surface_ready;
                {
                    readyForAwayManualAcceptance:$away.readyForAwayManualAcceptance,
                    physicalAccepted:$away.nativeBuddy.physicalAccepted
                };
                (if away_surface_ready then
                    "Open the latest TestFlight build on the physical iPhone and rerun strict E2E."
                 else
                    "Repair away readiness before physical acceptance."
                 end)
            ),
            requirement(
                "real-physical-e2e";
                "Real physical E2E acceptance is complete on the latest build";
                (if physical_e2e_complete then "complete" else "incomplete" end);
                physical_e2e_complete;
                {
                    strictStatus:$strict.status,
                    strictComplete:$strict.complete,
                    physicalAccepted:$away.nativeBuddy.physicalAccepted,
                    latestBuild:latest_build,
                    directDeviceVisibility:$strict.directDeviceVisibility
                };
                (if physical_e2e_complete and (($strict.directDeviceVisibility.status // "unknown") == "physical-available") then
                    "No remaining physical E2E action."
                 elif physical_e2e_complete then
                    "Core physical acceptance is complete. Optional direct-device visual verification remains when the iPhone is visible to devicectl or unobscured in iPhone Mirroring."
                 else
                    "Install/open the latest TestFlight Buddy build on the physical iPhone, keep Tailscale connected, then rerun strict E2E."
                 end)
            ),
            requirement(
                "no-overclaim-guardrails";
                "Reports stay fail-closed and separate unverified physical surfaces";
                (if overclaim_guardrails_ready then "ready" else "incomplete" end);
                overclaim_guardrails_ready;
                {
                    strictStatus:$strict.status,
                    awayStatus:$away.status,
                    strictRemainingGateCount:(($strict.remainingGates // []) | length),
                    awayRequiredGateCount:(($away.requiredGates // []) | length)
                };
                "Keep using this audit plus strict E2E before claiming completion."
            )
        ],
        requiredGates:(
            []
            + missing_signed_gate
            + missing_crest_parity_gate
            + missing_web_gate
            + strict_required
            + away_required
            | dedupe_gates
        ),
        optionalGates:($away.optionalGates // []),
        reports:{
            strictE2E:{
                exitCode:$strictExit,
                status:$strict.status,
                complete:$strict.complete,
                readyForManualPhysicalAcceptance:$strict.readyForManualPhysicalAcceptance
            },
            awayReadiness:{
                exitCode:$awayExit,
                status:$away.status,
                complete:$away.complete,
                readyForAwayManualAcceptance:$away.readyForAwayManualAcceptance
            },
            crestParity:{
                exitCode:$crestParity.exitCode,
                status:$crestParity.status,
                complete:$crestParity.complete,
                filter:$crestParity.filter
            }
        }
    }')"

printf '%s\n' "$audit"

if [[ "$(printf '%s' "$audit" | jq -r '.complete == true')" != "true" ]]; then
    exit 2
fi
