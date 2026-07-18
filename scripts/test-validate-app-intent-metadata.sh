#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
validator="$repo_root/scripts/validate-app-intent-metadata.sh"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/codeisland-app-intents.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

mkdir -p "$fixture_root/clean" "$fixture_root/invalid"

printf '%s\n' \
  'import AppIntents' \
  'let description = IntentDescription("Continue the selected coding session")' \
  > "$fixture_root/clean/CleanIntent.swift"

printf '%s\n' \
  'import AppIntents' \
  'let description = IntentDescription(' \
  '    "Continue this session on your Mac"' \
  ')' \
  > "$fixture_root/invalid/InvalidIntent.swift"

"$validator" "$fixture_root/clean"

set +e
invalid_output="$("$validator" "$fixture_root/invalid" 2>&1)"
invalid_status=$?
set -e

if [ "$invalid_status" -ne 1 ]; then
  echo "Expected invalid metadata to exit 1; got $invalid_status"
  printf '%s\n' "$invalid_output"
  exit 1
fi

if ! printf '%s\n' "$invalid_output" | grep -Fq 'ITMS-90626 Invalid Siri Support'; then
  echo "Expected ITMS-90626 diagnostic was missing"
  printf '%s\n' "$invalid_output"
  exit 1
fi

if ! printf '%s\n' "$invalid_output" | grep -Fq 'InvalidIntent.swift:2:'; then
  echo "Expected multiline source location was missing"
  printf '%s\n' "$invalid_output"
  exit 1
fi

echo "App Intent metadata validator self-test passed."
