#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/test"
  export GIT_BIN="$TEST_TMPDIR/git"
  export TESTFLIGHT_SHA="testflight"
  export CURRENT_SHA="current"
  export CHANGED_FILES=""
  export TRACKED_DIRTY_FILES=""
  export UNTRACKED_FILES=""
  mkdir -p "$TEST_TMPDIR"
  cat > "$GIT_BIN" <<'STUB'
#!/usr/bin/env bash
if [[ "$1 $2" == "rev-parse --verify" ]]; then
  exit 0
fi
if [[ "$1 $2" == "rev-parse origin/main" ]]; then
  printf '%s\n' "current"
  exit 0
fi
if [[ "$1 $2" == "rev-parse HEAD" ]]; then
  printf '%s\n' "current"
  exit 0
fi
if [[ "$1" == "rev-parse" && "$2" == "current" ]]; then
  printf '%s\n' "current"
  exit 0
fi
if [[ "$1 $2" == "diff --name-only" ]]; then
  if [[ "${3:-}" == "--cached" ]]; then
    printf '%s\n' "$TRACKED_DIRTY_FILES"
    exit 0
  fi
  if [[ "${3:-}" == testflight..current ]]; then
    printf '%s\n' "$CHANGED_FILES"
    exit 0
  fi
  if [[ $# -eq 2 ]]; then
    printf '%s\n' "$TRACKED_DIRTY_FILES"
    exit 0
  fi
  printf '%s\n' "$CHANGED_FILES"
  exit 0
fi
if [[ "$1 $2" == "ls-files --others" ]]; then
  printf '%s\n' "$UNTRACKED_FILES"
  exit 0
fi
exit 99
STUB
  chmod +x "$GIT_BIN"
}

@test "reports current when TestFlight source has no drift" {
  run "$REPO_ROOT/scripts/report-testflight-source-drift.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .checked == true and
    .status == "current" and
    .changedFileCount == 0 and
    .buddyRelevantChanged == false and
    .workingTree.dirty == false and
    (.nextAction | contains("continue physical iPhone acceptance"))'
}

@test "classifies Mac and proof-only drift as non-Buddy" {
  export CHANGED_FILES=$'Sources/CodeIsland/AppDelegate.swift\nscripts/report-strict-physical-e2e.sh\nTests/Scripts/report-strict-physical-e2e.bats\nTests/Scripts/validate-app-intent-metadata.bats\nREADME.md'

  run "$REPO_ROOT/scripts/report-testflight-source-drift.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .checked == true and
    .status == "source-drift-non-buddy" and
    .changedFileCount == 5 and
    .buddyRelevantChanged == false and
    .workingTree.dirty == false and
    (.changedFilesSample | index("Sources/CodeIsland/AppDelegate.swift")) and
    (.nextAction | contains("install/open the existing TestFlight build"))'
}

@test "classifies iPhone app drift as Buddy-relevant" {
  export CHANGED_FILES=$'ios/CodeIslandCompanion/CodeIslandCompanion/CompanionHomeView.swift\nREADME.md'

  run "$REPO_ROOT/scripts/report-testflight-source-drift.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .checked == true and
    .status == "buddy-source-drift" and
    .changedFileCount == 2 and
    .buddyRelevantChanged == true and
    (.buddyRelevantFiles | index("ios/CodeIslandCompanion/CodeIslandCompanion/CompanionHomeView.swift")) and
    (.nextAction | contains("upload a new internal TestFlight Buddy build"))'
}

@test "classifies uncommitted tracked iPhone app edits as Buddy-relevant" {
  export TRACKED_DIRTY_FILES=$'ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalClient.swift\ndocs/crest-mobile-parity.md'

  run "$REPO_ROOT/scripts/report-testflight-source-drift.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .status == "buddy-source-drift" and
    .changedFileCount == 2 and
    .buddyRelevantChanged == true and
    .workingTree.dirty == true and
    .workingTree.buddyRelevantChanged == true and
    (.workingTree.buddyRelevantFiles | index("ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalClient.swift")) and
    (.buddyRelevantFiles | index("ios/CodeIslandCompanion/CodeIslandCompanion/RemoteApprovalClient.swift"))'
}

@test "classifies untracked Buddy source files without counting unrelated local tool folders" {
  export UNTRACKED_FILES=$'ios/CodeIslandCompanion/CodeIslandCompanion/NewBuddySurface.swift\n.playwright-cli/cache.json\ngraphify-out/GRAPH_REPORT.md'

  run "$REPO_ROOT/scripts/report-testflight-source-drift.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .status == "buddy-source-drift" and
    .changedFileCount == 1 and
    .workingTree.changedFileCount == 1 and
    .workingTree.buddyRelevantChanged == true and
    (.changedFilesSample | index("ios/CodeIslandCompanion/CodeIslandCompanion/NewBuddySurface.swift")) and
    (.changedFilesSample | index(".playwright-cli/cache.json") | not) and
    (.changedFilesSample | index("graphify-out/GRAPH_REPORT.md") | not)'
}

@test "classifies shared core protocol drift as Buddy-relevant" {
  export CHANGED_FILES=$'Sources/CodeIslandCore/RemoteApprovalProtocol.swift\nSources/CodeIsland/AppDelegate.swift'

  run "$REPO_ROOT/scripts/report-testflight-source-drift.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .status == "buddy-source-drift" and
    .buddyRelevantChanged == true and
    (.buddyRelevantFiles | index("Sources/CodeIslandCore/RemoteApprovalProtocol.swift"))'
}

@test "fails parseably when latest TestFlight head SHA is missing" {
  export TESTFLIGHT_SHA=""

  run "$REPO_ROOT/scripts/report-testflight-source-drift.sh"

  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .checked == false and
    .status == "missing-testflight-sha" and
    .buddyRelevantChanged == null and
    (.nextAction | contains("did not report a head SHA"))'
}
