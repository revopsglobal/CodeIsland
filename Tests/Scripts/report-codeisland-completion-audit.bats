#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  export STRICT_E2E_BIN="$TEST_TMPDIR/strict-e2e"
  export AWAY_READINESS_BIN="$TEST_TMPDIR/away-readiness"
  mkdir -p "$TEST_TMPDIR"
}

write_strict_report() {
  local complete="${1:-false}"
  local status="${2:-physical-gate-incomplete}"
  local physical_gate_status="${3:-stale}"
  cat > "$STRICT_E2E_BIN" <<STUB
#!/usr/bin/env bash
jq -n '{
  generatedAt:"2026-07-19T07:10:00Z",
  complete:$complete,
  status:"$status",
  readyForManualPhysicalAcceptance:true,
  latestGate:{
    report:{
      latestTestFlight:{
        buildNumber:"20260719063154",
        appleState:"VALID"
      }
    }
  },
  directDeviceVisibility:{
    status:"simulator-only",
    physicalDeviceCount:0,
    iphoneMirroring:{status:"iphone-in-use"}
  },
  remainingGates:(
    if $complete then []
    else [
      {
        id:"physical-buddy-checkin",
        status:"$physical_gate_status",
        required:true,
        owner:"greg",
        nextAction:"Open latest Buddy from TestFlight."
      },
      {
        id:"direct-device-visibility",
        status:"simulator-only",
        required:false,
        owner:"codex",
        nextAction:"Lock iPhone and connect iPhone Mirroring."
      }
    ]
    end
  )
}'
exit $(if [ "$complete" = "true" ]; then printf 0; else printf 2; fi)
STUB
  chmod +x "$STRICT_E2E_BIN"
}

write_away_report() {
  local complete="${1:-false}"
  local physical_accepted="${2:-false}"
  local apple_state="${3:-VALID}"
  local source_current="${4:-true}"
  cat > "$AWAY_READINESS_BIN" <<STUB
#!/usr/bin/env bash
jq -n '{
  generatedAt:"2026-07-19T07:10:00Z",
  complete:$complete,
  status:(if $complete then "complete" else "ready-for-manual-physical-acceptance" end),
  readyForAwayManualAcceptance:true,
  nativeBuddy:{
    latestBuild:"20260719063154",
    appleState:"$apple_state",
    sourceCurrent:$source_current,
    physicalAccepted:$physical_accepted
  },
  webFallback:{
    reachable:true,
    shell:{
      reachable:true,
      status:"ready",
      markers:{
        questions:true,
        approvals:true,
        hub:true,
        mobileViewport:true,
        iosPWA:true,
        safeArea:true,
        touchTargets:true,
        liveFeedback:true,
        inlineReview:true,
        noBrowserDialogs:true
      }
    }
  },
  telegramFallback:{
    enabled:false,
    status:"disabled",
    available:false,
    controlPlane:false
  },
  requiredGates:(
    if $complete then []
    else [
      {
        id:"physical-buddy-checkin",
        status:"stale",
        owner:"greg",
        nextAction:"Open latest Buddy from TestFlight."
      }
    ]
    end
  ),
  optionalGates:[
    {
      id:"telegram-fallback",
      status:"disabled",
      owner:"greg",
      nextAction:"Telegram is optional."
    }
  ]
}'
exit $(if [ "$complete" = "true" ]; then printf 0; else printf 2; fi)
STUB
  chmod +x "$AWAY_READINESS_BIN"
}

@test "fails closed while physical iPhone Buddy check-in is stale" {
  write_strict_report false physical-gate-incomplete stale
  write_away_report false false

  run "$REPO_ROOT/scripts/report-codeisland-completion-audit.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "physical-e2e-incomplete" and
    ([.requirements[] | select(.id == "signed-testflight-delivery" and .complete == true)] | length) == 1 and
    ([.requirements[] | select(.id == "private-web-mobile-fallback" and .complete == true)] | length) == 1 and
    ([.requirements[] | select(.id == "real-physical-e2e" and .complete == false)] | length) == 1 and
    ([.requiredGates[] | select(.id == "physical-buddy-checkin" and .owner == "greg")] | length) == 1'
}

@test "passes only when strict E2E and away readiness both complete" {
  write_strict_report true complete matched
  write_away_report true true

  run "$REPO_ROOT/scripts/report-codeisland-completion-audit.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .complete == true and
    .status == "complete" and
    ([.requirements[] | select(.complete == false)] | length) == 0 and
    (.requiredGates | length) == 0'
}

@test "blocks completion when away readiness is not parseable" {
  write_strict_report true complete matched
  cat > "$AWAY_READINESS_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "not-json"
exit 2
STUB
  chmod +x "$AWAY_READINESS_BIN"

  run "$REPO_ROOT/scripts/report-codeisland-completion-audit.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    ([.requiredGates[] | select(.id == "away-readiness-report" and .status == "invalid-json")] | length) == 1'
}

@test "blocks completion when TestFlight is not valid or source-current" {
  write_strict_report true complete matched
  write_away_report true true PROCESSING false

  run "$REPO_ROOT/scripts/report-codeisland-completion-audit.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "testflight-incomplete" and
    ([.requirements[] | select(.id == "signed-testflight-delivery" and .complete == false)] | length) == 1 and
    ([.requiredGates[] | select(.id == "signed-testflight-delivery" and .owner == "codex")] | length) == 1'
}
