#!/usr/bin/env bats

setup() {
  fixture_dir="$(mktemp -d)"
  validator="$BATS_TEST_DIRNAME/../../scripts/validate-app-intent-metadata.sh"
}

teardown() {
  rm -rf "$fixture_dir"
}

@test "rejects Mac in an App Intent description" {
  cat > "$fixture_dir/RejectedIntent.swift" <<'SWIFT'
struct RejectedIntent: AppIntent {
    static var description = IntentDescription("Opens a Mac-backed module.")
}
SWIFT

  run "$validator" "$fixture_dir"

  [ "$status" -eq 1 ]
  [[ "$output" == *"ITMS-90626 Invalid Siri Support"* ]]
  [[ "$output" == *"RejectedIntent.swift"* ]]
}

@test "rejects Mac in a multiline App Intent description" {
  cat > "$fixture_dir/RejectedIntent.swift" <<'SWIFT'
struct RejectedIntent: AppIntent {
    static var description = IntentDescription(
        "Sends the task to your Mac."
    )
}
SWIFT

  run "$validator" "$fixture_dir"

  [ "$status" -eq 1 ]
  [[ "$output" == *"ITMS-90626 Invalid Siri Support"* ]]
}

@test "accepts device-neutral App Intent descriptions" {
  cat > "$fixture_dir/AcceptedIntent.swift" <<'SWIFT'
struct AcceptedIntent: AppIntent {
    static var description = IntentDescription("Sends the task to your paired computer.")
}
SWIFT

  run "$validator" "$fixture_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"metadata validation passed"* ]]
}

@test "rejects forbidden wording in compiled App Intent metadata" {
  mkdir -p "$fixture_dir/source" "$fixture_dir/CodeIslandCompanion.app/Metadata.appintents"
  cat > "$fixture_dir/source/AcceptedIntent.swift" <<'SWIFT'
struct AcceptedIntent: AppIntent {
    static var description = IntentDescription("Opens the task editor.")
}
SWIFT
  cat > "$fixture_dir/CodeIslandCompanion.app/Metadata.appintents/extract.actionsdata" <<'JSON'
{"actions":{"RejectedIntent":{"descriptionMetadata":{"descriptionText":{"key":"Opens a Mac-backed module."}}}}}
JSON

  run "$validator" "$fixture_dir/source" "$fixture_dir/CodeIslandCompanion.app"

  [ "$status" -eq 1 ]
  [[ "$output" == *"compiled App Intent metadata"* ]]
  [[ "$output" == *"RejectedIntent"* ]]
}

@test "accepts compiled device-neutral App Intent metadata" {
  mkdir -p "$fixture_dir/source" "$fixture_dir/CodeIslandCompanion.app/Metadata.appintents"
  cat > "$fixture_dir/source/AcceptedIntent.swift" <<'SWIFT'
struct AcceptedIntent: AppIntent {
    static var description = IntentDescription("Opens the task editor.")
}
SWIFT
  cat > "$fixture_dir/CodeIslandCompanion.app/Metadata.appintents/extract.actionsdata" <<'JSON'
{"actions":{"AcceptedIntent":{"descriptionMetadata":{"descriptionText":{"key":"Opens the task editor."}}}}}
JSON

  run "$validator" "$fixture_dir/source" "$fixture_dir/CodeIslandCompanion.app"

  [ "$status" -eq 0 ]
  [[ "$output" == *"metadata validation passed"* ]]
}

@test "rejects malformed compiled App Intent metadata" {
  mkdir -p "$fixture_dir/source" "$fixture_dir/CodeIslandCompanion.app/Metadata.appintents"
  cat > "$fixture_dir/source/AcceptedIntent.swift" <<'SWIFT'
struct AcceptedIntent: AppIntent {
    static var description = IntentDescription("Opens the task editor.")
}
SWIFT
  printf '{not-json}\n' > "$fixture_dir/CodeIslandCompanion.app/Metadata.appintents/extract.actionsdata"

  run "$validator" "$fixture_dir/source" "$fixture_dir/CodeIslandCompanion.app"

  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid JSON"* ]]
}
