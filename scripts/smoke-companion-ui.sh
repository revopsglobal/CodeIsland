#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for candidate in \
    "/Applications/Xcode.app/Contents/Developer" \
    "$HOME/Downloads/Xcode-beta.app/Contents/Developer"; do
    if [[ -x "$candidate/usr/bin/xcodebuild" ]]; then
      export DEVELOPER_DIR="$candidate"
      break
    fi
  done
fi

SIM_NAME="${1:-}"
PROJECT="ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj"
SCHEME="CodeIslandCompanion"
DERIVED_DATA="$ROOT/.build/CompanionUISmokeDerivedData"
BUNDLE_ID="com.revopsglobal.codeisland.buddy"

available_devices="$(xcrun simctl list devices available)"
if [[ -n "$SIM_NAME" ]]; then
  UDID="$(
    printf '%s\n' "$available_devices" |
      grep -m 1 "    ${SIM_NAME} (" |
      sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' || true
  )"
else
  UDID="$(
    printf '%s\n' "$available_devices" |
      grep -m 1 -E '^    .*iPhone.*\([A-F0-9-]+\) \(Booted\)' |
      sed -E 's/.*\(([A-F0-9-]+)\) \(Booted\).*/\1/' || true
  )"
  if [[ -z "$UDID" ]]; then
    UDID="$(
      printf '%s\n' "$available_devices" |
        grep -m 1 -E '^    .*iPhone.*\([A-F0-9-]+\)' |
        sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' || true
    )"
  fi
fi

if [[ -z "${UDID}" ]]; then
  printf 'No available iPhone simulator%s.\n' "${SIM_NAME:+ named \"$SIM_NAME\"}" >&2
  exit 1
fi

xcodebuild \
  -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/CodeIslandCompanion.app"
if [[ ! -d "$APP" ]]; then
  printf 'Built app was not found at %s\n' "$APP" >&2
  exit 1
fi

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

capture() {
  local name="$1"
  local appearance="$2"
  shift 2
  local screenshot="$ROOT/.build/companion-ui-${name}.png"

  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" >/dev/null
  # Simulator launch crossfades can outlast the app's own first frame.
  # Give the system transition time to settle so the receipt is not a
  # partially faded status bar or presence header.
  sleep 6
  xcrun simctl io "$UDID" screenshot "$screenshot"
  printf 'Companion UI smoke screenshot (%s): %s\n' "$name" "$screenshot"
}

COMMON_ARGS=(
  -CodeIslandCompanionMockState idle
  -CodeIslandCompanionMockHub
  -CodeIslandCompanionMockHubMode code
)

capture now-light light "${COMMON_ARGS[@]}"
capture approval-light light "${COMMON_ARGS[@]}" -CodeIslandCompanionMockAttention approval
capture question-light light "${COMMON_ARGS[@]}" -CodeIslandCompanionMockAttention question
capture multiple-light light "${COMMON_ARGS[@]}" -CodeIslandCompanionMockAttention multiple
capture sessions-light light "${COMMON_ARGS[@]}" -CodeIslandCompanionMockDestination sessions
capture more-light light "${COMMON_ARGS[@]}" -CodeIslandCompanionMockMore
capture now-dark dark "${COMMON_ARGS[@]}"
capture more-dark dark "${COMMON_ARGS[@]}" -CodeIslandCompanionMockMore

xcrun simctl ui "$UDID" appearance light
