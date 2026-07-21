#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  export STRICT_E2E_BIN="$TEST_TMPDIR/strict-e2e"
  export DEFAULTS_BIN="$TEST_TMPDIR/defaults"
  export CURL_BIN="$TEST_TMPDIR/curl"
  export SECURITY_BIN="$TEST_TMPDIR/security"
  mkdir -p "$TEST_TMPDIR"

  cat > "$DEFAULTS_BIN" <<'STUB'
#!/usr/bin/env bash
key="${3:-}"
case "$key" in
  remoteApprovalTelegramEnabled) printf '%s\n' "${TEST_TELEGRAM_ENABLED:-0}" ;;
  remoteApprovalTelegramChatID) printf '%s\n' "${TEST_TELEGRAM_CHAT_ID:-}" ;;
  remoteApprovalTelegramUserID) printf '%s\n' "${TEST_TELEGRAM_USER_ID:-}" ;;
  remoteApprovalTailnetURL) printf '%s\n' "${TEST_TAILNET_URL:-}" ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$DEFAULTS_BIN"
  cat > "$SECURITY_BIN" <<'STUB'
#!/usr/bin/env bash
if [[ "${TEST_TELEGRAM_TOKEN_STORED:-0}" == "1" ]]; then
  exit 0
fi
exit 44
STUB
  chmod +x "$SECURITY_BIN"
  cat > "$CURL_BIN" <<'STUB'
#!/usr/bin/env bash
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
case "${TEST_WEB_SHELL_CASE:-ready}" in
  unreachable)
    printf '503\ntext/plain\n'
    printf '%s\n' 'service unavailable' > "$output"
    ;;
  marker-mismatch)
    printf '200\ntext/html; charset=utf-8\n'
    printf '%s\n' '<html><title>Wrong</title></html>' > "$output"
    ;;
  mobile-missing)
    printf '200\ntext/html; charset=utf-8\n'
    cat > "$output" <<'HTML'
<html>
<head>
<title>CodeIsland</title>
<link rel="manifest" href="/manifest.webmanifest">
<link rel="icon" href="/app-icon.svg">
</head>
<body>
<h1>Your Mac, when it needs you</h1>
<section id="questions"></section>
<section id="approvals"></section>
<section id="hub"></section>
</body>
</html>
HTML
    ;;
  *)
    printf '200\ntext/html; charset=utf-8\n'
    cat > "$output" <<'HTML'
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<title>CodeIsland</title>
<link rel="manifest" href="/manifest.webmanifest">
<link rel="icon" href="/app-icon.svg">
<style>
main { padding:max(22px,env(safe-area-inset-top)) 16px max(28px,env(safe-area-inset-bottom)); }
button { min-height:44px; }
</style>
</head>
<body>
<h1>Your Mac, when it needs you</h1>
<div role="status" aria-live="polite"></div>
<section id="questions"></section>
<section id="approvals"></section>
<section id="hub"></section>
<div id="reviewDialog"></div>
</body>
</html>
HTML
    ;;
esac
STUB
  chmod +x "$CURL_BIN"
}

write_strict_report() {
  local status="${1:-physical-gate-incomplete}"
  local complete="${2:-false}"
  local ready="${3:-true}"
  local web="${4:-true}"
  local source_drift="${5:-false}"
  cat > "$STRICT_E2E_BIN" <<STUB
#!/usr/bin/env bash
jq -n '{
  generatedAt:"2026-07-19T06:12:00Z",
  status:"$status",
  complete:$complete,
  readyForManualPhysicalAcceptance:$ready,
  latestGate:{
    status:"stale",
    complete:false,
    report:{
      latestTestFlight:{
        buildNumber:"20260719060201",
        headSha:"868e52a",
        appleState:"VALID",
        audience:"APP_STORE_ELIGIBLE"
      }
    }
  },
  remoteHostHealth:{
    deliveryHealthy:$web,
    local:{url:"http://local.test/health",running:$web,pendingCount:0},
    tailscale:{url:"https://tailscale.test/health",running:$web,pendingCount:0},
    nextAction:"Restore Tailscale host health."
  },
  testFlightSourceDrift:{
    status:(if $source_drift then "buddy-source-drift" else "current" end),
    buddyRelevantChanged:$source_drift,
    nextAction:"Upload a current internal TestFlight Buddy build."
  },
  remainingGates:[
    {
      id:"physical-buddy-checkin",
      status:"stale",
      required:true,
      owner:"greg",
      nextAction:"Open latest Buddy in TestFlight."
    },
    {
      id:"direct-device-visibility",
      status:"simulator-only",
      required:false,
      owner:"codex",
      nextAction:"Manual TestFlight open required."
    }
  ]
}'
exit 2
STUB
  chmod +x "$STRICT_E2E_BIN"
}

@test "reports away path ready for manual physical acceptance with Telegram optional disabled" {
  write_strict_report

  run "$REPO_ROOT/scripts/report-away-readiness.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "ready-for-manual-physical-acceptance" and
    .readyForAwayManualAcceptance == true and
    .nativeBuddy.latestBuild == "20260719060201" and
    .nativeBuddy.sourceCurrent == true and
    .nativeBuddy.physicalAccepted == false and
    .webFallback.reachable == true and
    .webFallback.shell.reachable == true and
    .webFallback.shell.markers.questions == true and
    .webFallback.shell.markers.approvals == true and
    .webFallback.shell.markers.hub == true and
    .webFallback.shell.markers.mobileViewport == true and
    .webFallback.shell.markers.iosPWA == true and
    .webFallback.shell.markers.safeArea == true and
    .webFallback.shell.markers.touchTargets == true and
    .webFallback.shell.markers.liveFeedback == true and
    .webFallback.shell.markers.inlineReview == true and
    .webFallback.shell.markers.noBrowserDialogs == true and
    .telegramFallback.enabled == false and
    .telegramFallback.controlPlane == false and
    ([.requiredGates[] | select(.id == "physical-buddy-checkin" and .owner == "greg")] | length) == 1 and
    ([.optionalGates[] | select(.id == "telegram-fallback" and .status == "disabled")] | length) == 1'
}

@test "reports configured Telegram fallback without exposing credentials" {
  export TEST_TELEGRAM_ENABLED=1
  export TEST_TELEGRAM_TOKEN_STORED=1
  export TEST_TELEGRAM_CHAT_ID="987654"
  export TEST_TELEGRAM_USER_ID="987654"
  export TEST_TAILNET_URL="https://gregs-mac.tailnet.example"
  write_strict_report

  run "$REPO_ROOT/scripts/report-away-readiness.sh"

  [ "$status" -eq 2 ]
  [[ "$output" != *"987654"* ]]
  printf '%s' "$output" | jq -e '
    .telegramFallback.status == "configured" and
    .telegramFallback.available == true and
    .telegramFallback.hasBotToken == true and
    .telegramFallback.hasChatID == true and
    .telegramFallback.hasUserID == true and
    .telegramFallback.privateIdentity == true and
    .telegramFallback.keychainProtected == true and
    .telegramFallback.secureApprovalSheet == true and
    ([.optionalGates[] | select(.id == "private-tailnet-url" and .configured == true)] | length) == 1'
}

@test "reports incomplete Telegram as optional configuration issue" {
  export TEST_TELEGRAM_ENABLED=1
  export TEST_TELEGRAM_TOKEN_STORED=0
  export TEST_TELEGRAM_CHAT_ID="987654"
  export TEST_TELEGRAM_USER_ID="987654"
  write_strict_report

  run "$REPO_ROOT/scripts/report-away-readiness.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .status == "ready-for-manual-physical-acceptance" and
    .telegramFallback.status == "incomplete" and
    .telegramFallback.available == false and
    ([.requiredGates[] | select(.id == "telegram-fallback")] | length) == 0 and
    ([.optionalGates[] | select(.id == "telegram-fallback" and .status == "incomplete")] | length) == 1'
}

@test "blocks away readiness when private web fallback is unreachable" {
  write_strict_report "remote-host-health-incomplete" false false false false

  run "$REPO_ROOT/scripts/report-away-readiness.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .status == "web-fallback-unreachable" and
    .readyForAwayManualAcceptance == false and
    .webFallback.reachable == false and
    ([.requiredGates[] | select(.id == "private-web-fallback" and .owner == "codex")] | length) == 1'
}

@test "blocks away readiness when latest TestFlight source is stale" {
  write_strict_report "testflight-source-drift-incomplete" false false true true

  run "$REPO_ROOT/scripts/report-away-readiness.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .status == "testflight-not-ready" and
    .readyForAwayManualAcceptance == false and
    .nativeBuddy.sourceCurrent == false and
    ([.requiredGates[] | select(.id == "latest-testflight-current" and .owner == "codex")] | length) == 1'
}

@test "blocks away readiness when private web fallback shell is missing expected markers" {
  export TEST_WEB_SHELL_CASE=marker-mismatch
  write_strict_report

  run "$REPO_ROOT/scripts/report-away-readiness.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .status == "web-fallback-shell-unavailable" and
    .readyForAwayManualAcceptance == false and
    .webFallback.reachable == true and
    .webFallback.shell.status == "marker-mismatch" and
    .webFallback.shell.reachable == false and
    ([.requiredGates[] | select(.id == "private-web-shell" and .owner == "codex")] | length) == 1'
}

@test "blocks away readiness when private web fallback lacks mobile PWA markers" {
  export TEST_WEB_SHELL_CASE=mobile-missing
  write_strict_report

  run "$REPO_ROOT/scripts/report-away-readiness.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .status == "web-fallback-shell-unavailable" and
    .readyForAwayManualAcceptance == false and
    .webFallback.shell.status == "marker-mismatch" and
    .webFallback.shell.markers.title == true and
    .webFallback.shell.markers.hub == true and
    .webFallback.shell.markers.mobileViewport == false and
    .webFallback.shell.markers.iosPWA == false and
    .webFallback.shell.markers.safeArea == false and
    .webFallback.shell.markers.touchTargets == false and
    .webFallback.shell.markers.liveFeedback == false and
    .webFallback.shell.markers.inlineReview == false and
    ([.requiredGates[] | select(.id == "private-web-shell" and .owner == "codex")] | length) == 1'
}

@test "blocks away readiness when private web fallback shell does not return HTTP 200" {
  export TEST_WEB_SHELL_CASE=unreachable
  write_strict_report

  run "$REPO_ROOT/scripts/report-away-readiness.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .status == "web-fallback-shell-unavailable" and
    .webFallback.shell.status == "unreachable" and
    .webFallback.shell.httpCode == "503" and
    ([.requiredGates[] | select(.id == "private-web-shell")] | length) == 1'
}

@test "fails closed from combined readiness even when strict report is complete" {
  export TEST_WEB_SHELL_CASE=marker-mismatch
  write_strict_report "complete" true true true false

  run "$REPO_ROOT/scripts/report-away-readiness.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "web-fallback-shell-unavailable" and
    .strictE2E.complete == true and
    ([.requiredGates[] | select(.id == "private-web-shell")] | length) == 1'
}

@test "fails closed when strict E2E output is not JSON" {
  cat > "$STRICT_E2E_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "not json"
exit 2
STUB
  chmod +x "$STRICT_E2E_BIN"

  run "$REPO_ROOT/scripts/report-away-readiness.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .status == "strict-e2e-invalid-json" and
    .complete == false and
    .requiredGates[0].id == "strict-e2e-report"'
}
