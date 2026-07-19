#!/usr/bin/env bash

set -euo pipefail

STRICT_E2E_BIN="${STRICT_E2E_BIN:-$(dirname "$0")/report-strict-physical-e2e.sh}"
DEFAULTS_BIN="${DEFAULTS_BIN:-defaults}"
DEFAULTS_DOMAIN="${DEFAULTS_DOMAIN:-com.codeisland.app}"
CURL_BIN="${CURL_BIN:-curl}"
WEB_SHELL_URL="${WEB_SHELL_URL:-}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

strict_output=""
strict_exit=0
set +e
strict_output="$("$STRICT_E2E_BIN" 2>&1)"
strict_exit=$?
set -e

if ! printf '%s' "$strict_output" | jq -e . >/dev/null 2>&1; then
    jq -n \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg output "$strict_output" \
        '{
            generatedAt:$generatedAt,
            complete:false,
            status:"strict-e2e-invalid-json",
            strictE2E:{exitCode:2, parseable:false, output:$output},
            requiredGates:[
                {
                    id:"strict-e2e-report",
                    status:"invalid-json",
                    owner:"codex",
                    nextAction:"Fix scripts/report-strict-physical-e2e.sh so away readiness can inspect the canonical strict E2E report."
                }
            ],
            optionalGates:[]
        }'
    exit 2
fi

defaults_read() {
    local key="$1"
    if ! command -v "$DEFAULTS_BIN" >/dev/null 2>&1; then
        return 0
    fi
    "$DEFAULTS_BIN" read "$DEFAULTS_DOMAIN" "$key" 2>/dev/null || true
}

boolish_true() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
        1|true|yes) return 0 ;;
        *) return 1 ;;
    esac
}

trim() {
    awk '{$1=$1};1'
}

telegram_enabled_raw="$(defaults_read remoteApprovalTelegramEnabled | trim)"
telegram_bot_token="$(defaults_read remoteApprovalTelegramBotToken | trim)"
telegram_chat_id="$(defaults_read remoteApprovalTelegramChatID | trim)"
tailnet_url="$(defaults_read remoteApprovalTailnetURL | trim)"

if [[ -z "$WEB_SHELL_URL" ]]; then
    health_url="$(printf '%s' "$strict_output" | jq -r '.remoteHostHealth.tailscale.url // empty')"
    if [[ -n "$health_url" ]]; then
        WEB_SHELL_URL="${health_url%/health}/"
    elif [[ -n "$tailnet_url" ]]; then
        WEB_SHELL_URL="${tailnet_url%/}/"
    fi
fi

telegram_enabled=false
if boolish_true "$telegram_enabled_raw"; then
    telegram_enabled=true
fi

telegram_has_bot_token=false
if [[ -n "$telegram_bot_token" ]]; then
    telegram_has_bot_token=true
fi

telegram_has_chat_id=false
if [[ -n "$telegram_chat_id" ]]; then
    telegram_has_chat_id=true
fi

tailnet_url_configured=false
if [[ -n "$tailnet_url" ]]; then
    tailnet_url_configured=true
fi

telegram_status="disabled"
telegram_available=false
telegram_next_action="Telegram fallback is optional and currently disabled; Buddy and the private web fallback remain the control surfaces."
if [[ "$telegram_enabled" == "true" && "$telegram_has_bot_token" == "true" && "$telegram_has_chat_id" == "true" ]]; then
    telegram_status="configured"
    telegram_available=true
    telegram_next_action="Telegram fallback is configured; use it only as a redacted alert and deep link into Buddy or the private web fallback."
elif [[ "$telegram_enabled" == "true" ]]; then
    telegram_status="incomplete"
    telegram_next_action="Telegram fallback is enabled but missing a bot token or chat ID; either finish Settings → Buddy → Telegram or disable the optional fallback."
fi

web_shell_output="$(mktemp -t codeisland-web-shell)"
web_shell_meta="$(mktemp -t codeisland-web-shell-meta)"
web_shell_checked=false
web_shell_reachable=false
web_shell_http_code=""
web_shell_content_type=""
web_shell_has_title=false
web_shell_has_tagline=false
web_shell_has_manifest=false
web_shell_has_icon=false
web_shell_has_questions=false
web_shell_has_approvals=false
web_shell_has_hub=false
web_shell_status="not-checked"
web_shell_next_action="No private web shell URL was available; verify Tailscale Serve and rerun away readiness."

if [[ -n "$WEB_SHELL_URL" && -x "$(command -v "$CURL_BIN" 2>/dev/null || true)" ]]; then
    web_shell_checked=true
    set +e
    "$CURL_BIN" -k -L -sS --max-time 10 \
        -o "$web_shell_output" \
        -w '%{http_code}\n%{content_type}\n' \
        "$WEB_SHELL_URL" >"$web_shell_meta" 2>/dev/null
    curl_exit=$?
    set -e
    web_shell_http_code="$(sed -n '1p' "$web_shell_meta" | trim)"
    web_shell_content_type="$(sed -n '2p' "$web_shell_meta" | trim)"
    if [[ "$curl_exit" -eq 0 && "$web_shell_http_code" == "200" ]]; then
        grep -q '<title>CodeIsland</title>' "$web_shell_output" && web_shell_has_title=true
        grep -q 'Your Mac, when it needs you' "$web_shell_output" && web_shell_has_tagline=true
        grep -q 'manifest.webmanifest' "$web_shell_output" && web_shell_has_manifest=true
        grep -q 'app-icon.svg' "$web_shell_output" && web_shell_has_icon=true
        grep -q '<section id="questions"' "$web_shell_output" && web_shell_has_questions=true
        grep -q '<section id="approvals"' "$web_shell_output" && web_shell_has_approvals=true
        grep -q '<section id="hub"' "$web_shell_output" && web_shell_has_hub=true
        if [[ "$web_shell_has_title" == "true" \
            && "$web_shell_has_tagline" == "true" \
            && "$web_shell_has_manifest" == "true" \
            && "$web_shell_has_icon" == "true" \
            && "$web_shell_has_questions" == "true" \
            && "$web_shell_has_approvals" == "true" \
            && "$web_shell_has_hub" == "true" ]]; then
            web_shell_reachable=true
            web_shell_status="ready"
            web_shell_next_action="Private web fallback shell is reachable and renders attention-first sections."
        else
            web_shell_status="marker-mismatch"
            web_shell_next_action="Private web fallback root responded but did not contain the expected CodeIsland shell markers; inspect the served web app."
        fi
    else
        web_shell_status="unreachable"
        web_shell_next_action="Private web fallback shell did not return HTTP 200; restore Tailscale Serve/root routing and rerun away readiness."
    fi
elif [[ -n "$WEB_SHELL_URL" ]]; then
    web_shell_status="curl-unavailable"
    web_shell_next_action="curl is unavailable; install curl or set CURL_BIN before running away readiness."
fi

away_report="$(jq -n \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson strictE2E "$strict_output" \
    --argjson strictExit "$strict_exit" \
    --argjson telegramEnabled "$telegram_enabled" \
    --argjson telegramHasBotToken "$telegram_has_bot_token" \
    --argjson telegramHasChatID "$telegram_has_chat_id" \
    --argjson telegramAvailable "$telegram_available" \
    --arg telegramStatus "$telegram_status" \
    --arg telegramNextAction "$telegram_next_action" \
    --argjson tailnetURLConfigured "$tailnet_url_configured" \
    --arg webShellURL "$WEB_SHELL_URL" \
    --argjson webShellChecked "$web_shell_checked" \
    --argjson webShellReachable "$web_shell_reachable" \
    --arg webShellStatus "$web_shell_status" \
    --arg webShellHTTPCode "$web_shell_http_code" \
    --arg webShellContentType "$web_shell_content_type" \
    --argjson webShellHasTitle "$web_shell_has_title" \
    --argjson webShellHasTagline "$web_shell_has_tagline" \
    --argjson webShellHasManifest "$web_shell_has_manifest" \
    --argjson webShellHasIcon "$web_shell_has_icon" \
    --argjson webShellHasQuestions "$web_shell_has_questions" \
    --argjson webShellHasApprovals "$web_shell_has_approvals" \
    --argjson webShellHasHub "$web_shell_has_hub" \
    --arg webShellNextAction "$web_shell_next_action" \
    '
    def gate($id; $status; $owner; $nextAction):
        {id:$id,status:$status,owner:$owner,nextAction:$nextAction};
    def strict_required:
        [
            ($strictE2E.remainingGates // [])[]
            | select(.required == true)
            | {id,status,owner,nextAction}
        ];
    def web_ready:
        ($strictE2E.remoteHostHealth.deliveryHealthy == true) and
        ($strictE2E.remoteHostHealth.tailscale.running == true);
    def web_shell_ready:
        $webShellReachable == true;
    def testflight_ready:
        ($strictE2E.latestGate.report.latestTestFlight.appleState == "VALID") and
        ($strictE2E.testFlightSourceDrift.buddyRelevantChanged != true);
    def optional_gates:
        [
            gate(
                "telegram-fallback";
                $telegramStatus;
                "greg";
                $telegramNextAction
            ) + {
                enabled:$telegramEnabled,
                available:$telegramAvailable,
                hasBotToken:$telegramHasBotToken,
                hasChatID:$telegramHasChatID
            },
            gate(
                "private-tailnet-url";
                (if $tailnetURLConfigured then "configured" else "not-configured" end);
                "greg";
                (if $tailnetURLConfigured then
                    "Tailnet URL is configured for fallback copy."
                 else
                    "Optional: set the private Tailnet URL in CodeIsland Settings so Telegram alerts can include the Web fallback label."
                 end)
            ) + {configured:$tailnetURLConfigured}
        ];
    {
        generatedAt:$generatedAt,
        complete:(
            ($strictE2E.complete == true) and
            web_ready and
            web_shell_ready and
            testflight_ready
        ),
        status:(
            if (($strictE2E.complete == true) and web_ready and web_shell_ready and testflight_ready) then
                "complete"
            elif testflight_ready and web_ready and web_shell_ready and ($strictE2E.readyForManualPhysicalAcceptance == true) then
                "ready-for-manual-physical-acceptance"
            elif (testflight_ready | not) then
                "testflight-not-ready"
            elif (web_ready | not) then
                "web-fallback-unreachable"
            elif (web_shell_ready | not) then
                "web-fallback-shell-unavailable"
            else
                "incomplete"
            end
        ),
        readyForAwayManualAcceptance:(
            testflight_ready and
            web_ready and
            web_shell_ready and
            ($strictE2E.readyForManualPhysicalAcceptance == true)
        ),
        strictE2E:{
            exitCode:$strictExit,
            status:$strictE2E.status,
            complete:$strictE2E.complete,
            readyForManualPhysicalAcceptance:$strictE2E.readyForManualPhysicalAcceptance
        },
        nativeBuddy:{
            latestBuild:$strictE2E.latestGate.report.latestTestFlight.buildNumber,
            appleState:$strictE2E.latestGate.report.latestTestFlight.appleState,
            sourceCurrent:($strictE2E.testFlightSourceDrift.buddyRelevantChanged != true),
            physicalAccepted:$strictE2E.latestGate.complete
        },
        webFallback:{
            reachable:web_ready,
            deliveryHealthy:$strictE2E.remoteHostHealth.deliveryHealthy,
            tailscaleRunning:$strictE2E.remoteHostHealth.tailscale.running,
            localRunning:$strictE2E.remoteHostHealth.local.running,
            pendingCount:$strictE2E.remoteHostHealth.tailscale.pendingCount,
            shell:{
                checked:$webShellChecked,
                reachable:$webShellReachable,
                status:$webShellStatus,
                urlConfigured:($webShellURL != ""),
                httpCode:$webShellHTTPCode,
                contentType:$webShellContentType,
                markers:{
                    title:$webShellHasTitle,
                    tagline:$webShellHasTagline,
                    manifest:$webShellHasManifest,
                    icon:$webShellHasIcon,
                    questions:$webShellHasQuestions,
                    approvals:$webShellHasApprovals,
                    hub:$webShellHasHub
                }
            }
        },
        telegramFallback:{
            enabled:$telegramEnabled,
            status:$telegramStatus,
            available:$telegramAvailable,
            hasBotToken:$telegramHasBotToken,
            hasChatID:$telegramHasChatID,
            redacted:true,
            controlPlane:false
        },
        requiredGates:(
            []
            + (if testflight_ready then [] else [
                gate(
                    "latest-testflight-current";
                    ($strictE2E.testFlightSourceDrift.status // "unknown");
                    "codex";
                    ($strictE2E.testFlightSourceDrift.nextAction // "Upload a current internal TestFlight Buddy build.")
                )
            ] end)
            + (if web_ready then [] else [
                gate(
                    "private-web-fallback";
                    "unreachable";
                    "codex";
                    ($strictE2E.remoteHostHealth.nextAction // "Restore local and Tailscale host health, then rerun away readiness.")
                )
            ] end)
            + (if web_shell_ready then [] else [
                gate(
                    "private-web-shell";
                    $webShellStatus;
                    "codex";
                    $webShellNextAction
                )
            ] end)
            + strict_required
        ),
        optionalGates:optional_gates
    }')"

printf '%s\n' "$away_report"

if [[ "$(printf '%s' "$away_report" | jq -r '.complete == true')" != "true" ]]; then
    exit 2
fi
