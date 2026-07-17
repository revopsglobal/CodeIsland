#!/usr/bin/env bash
set -euo pipefail

source_root="${1:-ios/CodeIslandCompanion}"
compiled_app="${2:-}"

if [ ! -d "$source_root" ]; then
  echo "::error::App Intent source root does not exist: $source_root"
  exit 2
fi

# App Store Connect rejects discoverable App Intent descriptions containing
# the platform name "Mac" with ITMS-90626 (Invalid Siri Support). Inspect the
# complete string literal so multiline IntentDescription declarations are
# covered as well as the common one-line form.
if matches="$(rg --line-number --multiline --pcre2 --ignore-case \
  --glob '*.swift' \
  --glob '!**/.build/**' \
  'IntentDescription\s*\(\s*"[^"]*mac[^"]*"' \
  "$source_root")"; then
  echo "::error::ITMS-90626 Invalid Siri Support: App Intent descriptions must not contain 'Mac'."
  printf '%s\n' "$matches"
  exit 1
fi

if [ -n "$compiled_app" ]; then
  metadata_file="$compiled_app/Metadata.appintents/extract.actionsdata"
  if [ ! -s "$metadata_file" ]; then
    echo "::error::Compiled App Intent metadata is missing: $metadata_file"
    exit 2
  fi
  if ! matches="$(jq --raw-output '
      .actions
      | to_entries[]
      | select((.value.descriptionMetadata.descriptionText.key // "") | test("mac"; "i"))
      | "\(.key): \(.value.descriptionMetadata.descriptionText.key)"
    ' "$metadata_file")"; then
    echo "::error::Compiled App Intent metadata is not valid JSON: $metadata_file"
    exit 2
  fi
  if [ -n "$matches" ]; then
    echo "::error::ITMS-90626 Invalid Siri Support in compiled App Intent metadata."
    printf '%s\n' "$matches"
    exit 1
  fi
fi

echo "App Intent metadata validation passed."
