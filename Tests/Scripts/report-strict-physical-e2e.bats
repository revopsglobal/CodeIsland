#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  export LATEST_GATE_BIN="$TEST_TMPDIR/latest-gate"
  export DIRECT_DEVICE_VISIBILITY_BIN="$TEST_TMPDIR/direct-device-visibility"
  export TESTFLIGHT_SOURCE_DRIFT_BIN="$TEST_TMPDIR/testflight-source-drift"
  export SWIFT_BIN="$TEST_TMPDIR/swift"
  mkdir -p "$TEST_TMPDIR"
  cat > "$DIRECT_DEVICE_VISIBILITY_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{checked:true,toolAvailable:true,status:"simulator-only",physicalDeviceCount:0,simulatorCount:1,devices:[],nextAction:"Only Simulator iOS devices are visible."}'
STUB
  chmod +x "$DIRECT_DEVICE_VISIBILITY_BIN"
  cat > "$TESTFLIGHT_SOURCE_DRIFT_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n --arg testFlightHeadSha "$TESTFLIGHT_SHA" '{checked:true,status:"source-drift-non-buddy",testFlightHeadSha:$testFlightHeadSha,currentSha:"current",changedFileCount:3,buddyRelevantChanged:false,buddyRelevantFiles:[],changedFilesSample:["README.md"],nextAction:"Latest TestFlight Buddy build is still Buddy-current."}'
STUB
  chmod +x "$TESTFLIGHT_SOURCE_DRIFT_BIN"
}

@test "fails closed when the latest TestFlight physical gate is stale" {
  cat > "$LATEST_GATE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{
  gate:{status:"stale",complete:false,nextAction:"Install and open the latest Buddy build."},
  latestTestFlight:{buildNumber:"20260719011702",headSha:"33fc732"},
  physicalAcceptance:{
    mac:{running:true},
    health:{
      local:{url:"http://local.test/health",running:true,pendingCount:0},
      tailscale:{url:"https://tailscale.test/health",running:true,pendingCount:0}
    },
    gates:{deliveryHealthy:true}
  }
}'
exit 2
STUB
  cat > "$SWIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "Executed 1 test, with 0 failures"
STUB
  chmod +x "$LATEST_GATE_BIN" "$SWIFT_BIN"

  run "$REPO_ROOT/scripts/report-strict-physical-e2e.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "physical-gate-incomplete" and
    .latestGate.status == "stale" and
    .remoteHostHealth.checked == true and
    .remoteHostHealth.deliveryHealthy == true and
    .remoteHostHealth.tailscale.running == true and
    .testFlightSourceDrift.status == "source-drift-non-buddy" and
    .testFlightSourceDrift.testFlightHeadSha == "33fc732" and
    .testFlightSourceDrift.buddyRelevantChanged == false and
    .directDeviceVisibility.status == "simulator-only" and
    .directDeviceVisibility.physicalDeviceCount == 0 and
    .interactionContract.passed == true and
    .readyForManualPhysicalAcceptance == true and
    (.remainingGates[] | select(.id == "physical-buddy-checkin" and .required == true and .owner == "greg")) and
    (.remainingGates[] | select(.id == "direct-device-visibility" and .required == false and .owner == "codex"))'
}

@test "passes only when physical gate and interaction contract both pass" {
  cat > "$LATEST_GATE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{
  gate:{status:"matched",complete:true,nextAction:"Run strict physical E2E interaction acceptance."},
  latestTestFlight:{buildNumber:"20260719011702",headSha:"33fc732"},
  physicalAcceptance:{
    mac:{running:true},
    health:{
      local:{url:"http://local.test/health",running:true,pendingCount:0},
      tailscale:{url:"https://tailscale.test/health",running:true,pendingCount:0}
    },
    gates:{deliveryHealthy:true}
  }
}'
STUB
  cat > "$SWIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "Executed 1 test, with 0 failures"
STUB
  chmod +x "$LATEST_GATE_BIN" "$SWIFT_BIN"

  run "$REPO_ROOT/scripts/report-strict-physical-e2e.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .complete == true and
    .status == "complete" and
    .latestGate.complete == true and
    .remoteHostHealth.tailscale.running == true and
    .testFlightSourceDrift.checked == true and
    .directDeviceVisibility.checked == true and
    .interactionContract.passed == true and
    .readyForManualPhysicalAcceptance == true and
    ([.remainingGates[] | select(.required == true)] | length) == 0'
}

@test "fails when the interaction contract test fails even if physical gate matches" {
  cat > "$LATEST_GATE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{
  gate:{status:"matched",complete:true,nextAction:"Run strict physical E2E interaction acceptance."},
  latestTestFlight:{buildNumber:"20260719011702",headSha:"33fc732"},
  physicalAcceptance:{
    mac:{running:true},
    health:{
      local:{url:"http://local.test/health",running:true,pendingCount:0},
      tailscale:{url:"https://tailscale.test/health",running:true,pendingCount:0}
    },
    gates:{deliveryHealthy:true}
  }
}'
STUB
  cat > "$SWIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "RemoteApprovalHTTPServerTests failed"
exit 1
STUB
  chmod +x "$LATEST_GATE_BIN" "$SWIFT_BIN"

  run "$REPO_ROOT/scripts/report-strict-physical-e2e.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "interaction-contract-failed" and
    .latestGate.complete == true and
    .remoteHostHealth.deliveryHealthy == true and
    .testFlightSourceDrift.checked == true and
    .directDeviceVisibility.status == "simulator-only" and
    .interactionContract.passed == false and
    .readyForManualPhysicalAcceptance == false and
    (.remainingGates[] | select(.id == "interaction-contract" and .required == true and .owner == "codex")) and
    (.interactionContract.logTail | contains("failed"))'
}

@test "keeps strict report parseable when direct-device visibility returns invalid JSON" {
  cat > "$LATEST_GATE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{
  gate:{status:"stale",complete:false,nextAction:"Install and open the latest Buddy build."},
  latestTestFlight:{buildNumber:"20260719011702",headSha:"33fc732"},
  physicalAcceptance:{
    mac:{running:true},
    health:{
      local:{url:"http://local.test/health",running:true,pendingCount:0},
      tailscale:{url:"https://tailscale.test/health",running:true,pendingCount:0}
    },
    gates:{deliveryHealthy:true}
  }
}'
exit 2
STUB
  cat > "$DIRECT_DEVICE_VISIBILITY_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "devicectl exploded before JSON"
STUB
  cat > "$SWIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "Executed 1 test, with 0 failures"
STUB
  chmod +x "$LATEST_GATE_BIN" "$DIRECT_DEVICE_VISIBILITY_BIN" "$SWIFT_BIN"

  run "$REPO_ROOT/scripts/report-strict-physical-e2e.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .directDeviceVisibility.status == "visibility-report-invalid-json" and
    .readyForManualPhysicalAcceptance == true and
    (.remainingGates[] | select(.id == "direct-device-visibility" and .required == false)) and
    (.directDeviceVisibility.output | contains("devicectl exploded"))'
}

@test "keeps strict report parseable when TestFlight source drift returns invalid JSON" {
  cat > "$LATEST_GATE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{
  gate:{status:"stale",complete:false,nextAction:"Install and open the latest Buddy build."},
  latestTestFlight:{buildNumber:"20260719011702",headSha:"33fc732"},
  physicalAcceptance:{
    mac:{running:true},
    health:{
      local:{url:"http://local.test/health",running:true,pendingCount:0},
      tailscale:{url:"https://tailscale.test/health",running:true,pendingCount:0}
    },
    gates:{deliveryHealthy:true}
  }
}'
exit 2
STUB
  cat > "$TESTFLIGHT_SOURCE_DRIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "git exploded before JSON"
STUB
  cat > "$SWIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "Executed 1 test, with 0 failures"
STUB
  chmod +x "$LATEST_GATE_BIN" "$TESTFLIGHT_SOURCE_DRIFT_BIN" "$SWIFT_BIN"

  run "$REPO_ROOT/scripts/report-strict-physical-e2e.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .testFlightSourceDrift.status == "source-drift-report-invalid-json" and
    .status == "testflight-source-drift-incomplete" and
    .readyForManualPhysicalAcceptance == false and
    (.remainingGates[] | select(.id == "testflight-source" and .required == true and .owner == "codex")) and
    (.testFlightSourceDrift.output | contains("git exploded"))'
}

@test "surfaces missing host health without breaking strict JSON" {
  cat > "$LATEST_GATE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{
  gate:{status:"stale",complete:false,nextAction:"Install and open the latest Buddy build."},
  latestTestFlight:{buildNumber:"20260719011702",headSha:"33fc732"}
}'
exit 2
STUB
  cat > "$SWIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "Executed 1 test, with 0 failures"
STUB
  chmod +x "$LATEST_GATE_BIN" "$SWIFT_BIN"

  run "$REPO_ROOT/scripts/report-strict-physical-e2e.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "remote-host-health-incomplete" and
    .remoteHostHealth.checked == false and
    .remoteHostHealth.tailscale == null and
    .readyForManualPhysicalAcceptance == false and
    (.remainingGates[] | select(.id == "remote-host-health" and .required == true and .owner == "codex")) and
    (.remoteHostHealth.nextAction | contains("did not include host health"))'
}

@test "blocks manual physical acceptance when Tailscale host health is not running" {
  cat > "$LATEST_GATE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{
  gate:{status:"stale",complete:false,nextAction:"Install and open the latest Buddy build."},
  latestTestFlight:{buildNumber:"20260719011702",headSha:"33fc732"},
  physicalAcceptance:{
    mac:{running:true},
    health:{
      local:{url:"http://local.test/health",running:true,pendingCount:0},
      tailscale:{url:"https://tailscale.test/health",running:false,pendingCount:null,error:"curl failed"}
    },
    gates:{deliveryHealthy:false}
  }
}'
exit 2
STUB
  cat > "$SWIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "Executed 1 test, with 0 failures"
STUB
  chmod +x "$LATEST_GATE_BIN" "$SWIFT_BIN"

  run "$REPO_ROOT/scripts/report-strict-physical-e2e.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "remote-host-health-incomplete" and
    .readyForManualPhysicalAcceptance == false and
    .remoteHostHealth.tailscale.running == false and
    (.remainingGates[] | select(.id == "remote-host-health" and .required == true))'
}

@test "blocks completion when current source has Buddy-relevant TestFlight drift" {
  cat > "$LATEST_GATE_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n '{
  gate:{status:"matched",complete:true,nextAction:"Run strict physical E2E interaction acceptance."},
  latestTestFlight:{buildNumber:"20260719011702",headSha:"33fc732"},
  physicalAcceptance:{
    mac:{running:true},
    health:{
      local:{url:"http://local.test/health",running:true,pendingCount:0},
      tailscale:{url:"https://tailscale.test/health",running:true,pendingCount:0}
    },
    gates:{deliveryHealthy:true}
  }
}'
STUB
  cat > "$TESTFLIGHT_SOURCE_DRIFT_BIN" <<'STUB'
#!/usr/bin/env bash
jq -n --arg testFlightHeadSha "$TESTFLIGHT_SHA" '{checked:true,status:"source-drift-buddy",testFlightHeadSha:$testFlightHeadSha,currentSha:"current",changedFileCount:2,buddyRelevantChanged:true,buddyRelevantFiles:["ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift"],changedFilesSample:["ios/CodeIslandCompanion/CodeIslandCompanion/ContentView.swift"],nextAction:"Upload a fresh Buddy build."}'
STUB
  cat > "$SWIFT_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "Executed 1 test, with 0 failures"
STUB
  chmod +x "$LATEST_GATE_BIN" "$TESTFLIGHT_SOURCE_DRIFT_BIN" "$SWIFT_BIN"

  run "$REPO_ROOT/scripts/report-strict-physical-e2e.sh"

  [ "$status" -eq 2 ]
  printf '%s' "$output" | jq -e '
    .complete == false and
    .status == "testflight-source-drift-incomplete" and
    .readyForManualPhysicalAcceptance == false and
    .testFlightSourceDrift.buddyRelevantChanged == true and
    (.remainingGates[] | select(.id == "testflight-source" and .required == true))'
}
