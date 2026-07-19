#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  export STRICT_E2E_BIN="$TEST_TMPDIR/strict-e2e"
  export DEFAULTS_BIN="$TEST_TMPDIR/defaults"
  mkdir -p "$TEST_TMPDIR"

  cat > "$DEFAULTS_BIN" <<'STUB'
#!/usr/bin/env bash
key="${3:-}"
case "$key" in
  remoteApprovalTelegramEnabled) printf '%s\n' "${TEST_TELEGRAM_ENABLED:-0}" ;;
  remoteApprovalTelegramBotToken) printf '%s\n' "${TEST_TELEGRAM_BOT_TOKEN:-}" ;;
  remoteApprovalTelegramChatID) printf '%s\n' "${TEST_TELEGRAM_CHAT_ID:-}" ;;
  remoteApprovalTailnetURL) printf '%s\n' "${TEST_TAILNET_URL:-}" ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$DEFAULTS_BIN"
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
    local:{running:$web,pendingCount:0},
    tailscale:{running:$web,pendingCount:0},
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
    .telegramFallback.enabled == false and
    .telegramFallback.controlPlane == false and
    ([.requiredGates[] | select(.id == "physical-buddy-checkin" and .owner == "greg")] | length) == 1 and
    ([.optionalGates[] | select(.id == "telegram-fallback" and .status == "disabled")] | length) == 1'
}

@test "reports configured Telegram fallback without exposing credentials" {
  export TEST_TELEGRAM_ENABLED=1
  export TEST_TELEGRAM_BOT_TOKEN="123:secret"
  export TEST_TELEGRAM_CHAT_ID="987654"
  export TEST_TAILNET_URL="https://gregs-mac.tailnet.example"
  write_strict_report

  run "$REPO_ROOT/scripts/report-away-readiness.sh"

  [ "$status" -eq 2 ]
  [[ "$output" != *"123:secret"* ]]
  [[ "$output" != *"987654"* ]]
  printf '%s' "$output" | jq -e '
    .telegramFallback.status == "configured" and
    .telegramFallback.available == true and
    .telegramFallback.hasBotToken == true and
    .telegramFallback.hasChatID == true and
    ([.optionalGates[] | select(.id == "private-tailnet-url" and .configured == true)] | length) == 1'
}

@test "reports incomplete Telegram as optional configuration issue" {
  export TEST_TELEGRAM_ENABLED=1
  export TEST_TELEGRAM_BOT_TOKEN=""
  export TEST_TELEGRAM_CHAT_ID="987654"
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
