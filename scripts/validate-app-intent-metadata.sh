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
# covered as well as the common one-line form. Use system Perl rather than a
# developer-shell convenience such as ripgrep: signed archive runners must
# fail closed even when optional command-line tools are absent.
if ! command -v perl >/dev/null 2>&1; then
  echo "::error::Perl is required to validate App Intent source metadata."
  exit 2
fi

set +e
matches="$(find "$source_root" \
  -type f \
  -name '*.swift' \
  ! -path '*/.build/*' \
  -exec perl -0777 -ne '
    while (/IntentDescription\s*\(\s*"[^"]*mac[^"]*"/ig) {
      my $before = substr($_, 0, $-[0]);
      my $line = 1 + ($before =~ tr/\n/\n/);
      my $match = $&;
      $match =~ s/\s+/ /g;
      print "$ARGV:$line:$match\n";
    }
  ' {} +)"
search_status=$?
set -e

if [ "$search_status" -ne 0 ]; then
  echo "::error::App Intent source metadata scan failed."
  exit 2
fi

if [ -n "$matches" ]; then
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
  for required_action in \
    PrepareCodeIslandTaskIntent \
    OpenCodeIslandTaskIntent \
    OpenCodeIslandNeedsYouIntent \
    OpenCodeIslandSessionsIntent; do
    if ! jq --exit-status --arg name "$required_action" '.actions[$name] != null' "$metadata_file" >/dev/null; then
      echo "::error::Required App Intent metadata is missing: $required_action"
      exit 2
    fi
  done
fi

echo "App Intent metadata validation passed."
