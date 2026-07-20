#!/usr/bin/env bash

set -euo pipefail

XCRUN_BIN="${XCRUN_BIN:-xcrun}"
DEVICECTL_TIMEOUT="${DEVICECTL_TIMEOUT:-15}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/gregharned/Downloads/Xcode-beta.app/Contents/Developer}"
OSASCRIPT_BIN="${OSASCRIPT_BIN:-osascript}"
SCREENCAPTURE_BIN="${SCREENCAPTURE_BIN:-screencapture}"
SWIFT_BIN="${SWIFT_BIN:-swift}"
MIRRORING_TEXT="${MIRRORING_TEXT:-}"
MIRRORING_WINDOW_EXPOSED="${MIRRORING_WINDOW_EXPOSED:-}"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

json_bool() {
    if [[ "$1" == "true" ]]; then
        printf 'true'
    else
        printf 'false'
    fi
}

read_mirroring_text_from_window() {
    if [[ -n "$MIRRORING_TEXT" ]]; then
        printf '%s' "$MIRRORING_TEXT"
        return 0
    fi
    if ! command -v "$OSASCRIPT_BIN" >/dev/null 2>&1 \
        || ! command -v "$SCREENCAPTURE_BIN" >/dev/null 2>&1 \
        || ! command -v "$SWIFT_BIN" >/dev/null 2>&1; then
        return 1
    fi

    local bounds image swift_file
    bounds="$("$OSASCRIPT_BIN" <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  if not (exists process "iPhone Mirroring") then return ""
  tell process "iPhone Mirroring"
    if (count of windows) is 0 then return ""
    set pos to position of window 1
    set sz to size of window 1
    return ((item 1 of pos) as text) & "," & ((item 2 of pos) as text) & "," & ((item 1 of sz) as text) & "," & ((item 2 of sz) as text)
  end tell
end tell
APPLESCRIPT
)"
    [[ -n "$bounds" ]] || return 1

    image="$(mktemp -t codeisland-iphone-mirroring).png"
    if ! "$SCREENCAPTURE_BIN" -x -R "$bounds" "$image" >/dev/null 2>&1; then
        rm -f "$image"
        return 1
    fi

    swift_file="$(mktemp -t codeisland-vision-ocr).swift"
    cat > "$swift_file" <<'SWIFT'
import Foundation
import Vision
import AppKit

let path = CommandLine.arguments.dropFirst().first ?? ""
guard let image = NSImage(contentsOfFile: path),
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let cgImage = bitmap.cgImage else {
    exit(2)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try handler.perform([request])
let text = (request.results ?? [])
    .compactMap { $0.topCandidates(1).first?.string }
    .joined(separator: "\n")
print(text)
SWIFT
    "$SWIFT_BIN" "$swift_file" "$image" 2>/dev/null || true
    rm -f "$image" "$swift_file"
}

mirroring_window_is_exposed() {
    if [[ -n "$MIRRORING_WINDOW_EXPOSED" ]]; then
        [[ "$MIRRORING_WINDOW_EXPOSED" == "true" ]]
        return
    fi

    # Explicit text is a deterministic test fixture and is authoritative unless
    # the fixture also marks the window as occluded.
    if [[ -n "$MIRRORING_TEXT" ]]; then
        return 0
    fi

    command -v "$OSASCRIPT_BIN" >/dev/null 2>&1 || return 1
    [[ "$("$OSASCRIPT_BIN" <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events"
  if not (exists process "iPhone Mirroring") then return "false"
  tell process "iPhone Mirroring"
    if (count of windows) is 0 then return "false"
    if frontmost is false then return "false"
    try
      if value of attribute "AXMinimized" of window 1 is true then return "false"
    end try
    return "true"
  end tell
end tell
APPLESCRIPT
)" == "true" ]]
}

mirroring_process_running=false
if command -v "$OSASCRIPT_BIN" >/dev/null 2>&1 \
    && [[ "$("$OSASCRIPT_BIN" -e 'tell application "System Events" to exists process "iPhone Mirroring"' 2>/dev/null || true)" == "true" ]]; then
    mirroring_process_running=true
fi
if [[ -n "$MIRRORING_TEXT" ]]; then
    mirroring_process_running=true
fi

mirroring_exposed=false
if mirroring_window_is_exposed; then
    mirroring_exposed=true
fi

mirroring_text=""
if [[ "$mirroring_exposed" == "true" ]]; then
    mirroring_text="$(read_mirroring_text_from_window | tr '\r' '\n' | sed '/^[[:space:]]*$/d' | head -n 30 || true)"
fi
mirroring_text_lower="$(printf '%s' "$mirroring_text" | tr '[:upper:]' '[:lower:]')"
mirroring_report_text="$(printf '%s\n' "$mirroring_text" \
    | grep -Ei 'iphone|mirroring|lock|connect|testflight|codeisland|buddy' \
    | sed -E '/Unable to find|Expected :|GetE5PathFromCompositeBundle/d' \
    | head -n 12 || true)"
mirroring_status="not-running"
mirroring_checked=false
mirroring_next_action="iPhone Mirroring is not running; use TestFlight directly on the iPhone, or open iPhone Mirroring after the phone is locked."

if [[ "$mirroring_process_running" == "true" ]]; then
    mirroring_checked=true
    mirroring_status="unknown"
    mirroring_next_action="iPhone Mirroring is running, but CodeIsland could not classify whether the mirrored phone is controllable."
    if [[ "$mirroring_exposed" != "true" ]]; then
        mirroring_status="occluded"
        mirroring_next_action="iPhone Mirroring is running behind another app; bring iPhone Mirroring to the front before using OCR as physical-device evidence."
    elif [[ "$mirroring_text_lower" == *"iphone in use"* || "$mirroring_text_lower" == *"lock your iphone to connect"* ]]; then
        mirroring_status="iphone-in-use"
        mirroring_next_action="iPhone Mirroring is open but blocked because the iPhone is in use; lock the iPhone, click Connect, then open the latest TestFlight Buddy build."
    elif [[ "$mirroring_text_lower" == *"connect"* ]]; then
        mirroring_status="waiting-connect"
        mirroring_next_action="iPhone Mirroring is waiting on Connect; click Connect after the iPhone is locked, then open the latest TestFlight Buddy build."
    elif [[ -n "$mirroring_text" ]]; then
        mirroring_status="visible"
        mirroring_next_action="iPhone Mirroring has visible phone content; Codex may be able to operate the phone UI if accessibility actions are available."
    fi
fi

mirroring_json="$(jq -n \
    --argjson checked "$(json_bool "$mirroring_checked")" \
    --argjson running "$(json_bool "$mirroring_process_running")" \
    --arg status "$mirroring_status" \
    --arg observedText "$mirroring_report_text" \
    --arg nextAction "$mirroring_next_action" \
    '{
        checked:$checked,
        running:$running,
        status:$status,
        observedText:($observedText | select(length > 0) // null),
        nextAction:$nextAction
    }')"

if ! command -v "$XCRUN_BIN" >/dev/null 2>&1; then
    jq -n \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson iphoneMirroring "$mirroring_json" \
        '{
            generatedAt:$generatedAt,
            checked:true,
            toolAvailable:false,
            status:"tool-unavailable",
            physicalDeviceCount:0,
            simulatorCount:0,
            devices:[],
            iphoneMirroring:$iphoneMirroring,
            nextAction:"xcrun/devicectl is unavailable on this Mac, so Codex cannot prove whether it can directly install or open the physical iPhone."
        }'
    exit 0
fi

json_output="$(mktemp -t codeisland-devicectl-devices)"
log_output="$(mktemp -t codeisland-devicectl-log)"
devicectl_exit=0

set +e
DEVELOPER_DIR="$DEVELOPER_DIR" "$XCRUN_BIN" devicectl list devices \
    --timeout "$DEVICECTL_TIMEOUT" \
    --json-output "$json_output" \
    --omit-deprecated-fields-in-json \
    >"$log_output" 2>&1
devicectl_exit=$?
set -e

log_tail="$(tail -n 40 "$log_output" 2>/dev/null || true)"

if [[ "$devicectl_exit" -ne 0 || ! -s "$json_output" ]] || ! jq -e . "$json_output" >/dev/null 2>&1; then
    jq -n \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson exitCode "$devicectl_exit" \
        --arg logTail "$log_tail" \
        --argjson iphoneMirroring "$mirroring_json" \
        '{
            generatedAt:$generatedAt,
            checked:true,
            toolAvailable:true,
            status:"devicectl-error",
            exitCode:$exitCode,
            physicalDeviceCount:0,
            simulatorCount:0,
            devices:[],
            iphoneMirroring:$iphoneMirroring,
            logTail:$logTail,
            nextAction:"devicectl failed, so Codex cannot prove whether it can directly install or open the physical iPhone."
        }'
    exit 0
fi

devices="$(jq -c '
    (.result.devices // []) |
    map({
        name:(.properties.state.name // .name // null),
        identifierSuffix:(
            (.identifier // "") as $identifier |
            if ($identifier | length) > 8 then ($identifier | .[(length - 8):])
            elif ($identifier | length) > 0 then $identifier
            else null
            end
        ),
        platform:(.properties.hardware.platform // null),
        deviceType:(.properties.hardware.deviceType // null),
        model:(.properties.hardware.marketingName // null),
        productType:(.properties.hardware.productType // null),
        reality:(.properties.hardware.reality // null),
        state:(.properties.connection.state // null),
        pairingState:(.properties.connection.pairingState // null),
        transportType:(.properties.connection.transportType // null)
    }) |
    map(. + {
        isIOS:((.platform == "iOS") or (.deviceType == "iPhone") or (.deviceType == "iPad")),
        isSimulator:(.reality == "simulated"),
        isPhysical:(((.platform == "iOS") or (.deviceType == "iPhone") or (.deviceType == "iPad")) and (.reality != "simulated"))
    })
' "$json_output")"

physical_count="$(printf '%s' "$devices" | jq '[.[] | select(.isPhysical == true)] | length')"
simulator_count="$(printf '%s' "$devices" | jq '[.[] | select(.isIOS == true and .isSimulator == true)] | length')"
ios_count="$(printf '%s' "$devices" | jq '[.[] | select(.isIOS == true)] | length')"

status="no-ios-devices"
next_action="No iPhone or iPad is visible to devicectl on this Mac. Open the latest TestFlight build on the physical iPhone, or connect/trust the phone if you want Codex to direct-install/open it."
if [[ "$physical_count" -gt 0 ]]; then
    status="physical-available"
    next_action="A physical iOS device is visible to devicectl; Codex can attempt direct install/open workflows if the provisioning profile allows it."
elif [[ "$simulator_count" -gt 0 ]]; then
    status="simulator-only"
    next_action="Only Simulator iOS devices are visible to devicectl. Codex cannot directly install/open the physical iPhone from this Mac; open the latest TestFlight build on the iPhone, keep Tailscale connected, then rerun strict E2E."
fi

if [[ "$status" != "physical-available" && "$mirroring_status" == "iphone-in-use" ]]; then
    next_action="Only Simulator iOS devices are visible to devicectl, and iPhone Mirroring is blocked because the iPhone is in use. Lock the iPhone, click Connect in iPhone Mirroring, open the latest TestFlight Buddy build, keep Tailscale connected, then rerun strict E2E."
elif [[ "$status" != "physical-available" && "$mirroring_status" == "waiting-connect" ]]; then
    next_action="Only Simulator iOS devices are visible to devicectl, but iPhone Mirroring is waiting on Connect. Click Connect after the iPhone is locked, open the latest TestFlight Buddy build, keep Tailscale connected, then rerun strict E2E."
elif [[ "$status" != "physical-available" && "$mirroring_status" == "occluded" ]]; then
    next_action="Only Simulator iOS devices are visible to devicectl, and iPhone Mirroring is occluded. Bring iPhone Mirroring to the front before treating its pixels as physical-device evidence."
fi

jq -n \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "$status" \
    --argjson devices "$devices" \
    --argjson physicalDeviceCount "$physical_count" \
    --argjson simulatorCount "$simulator_count" \
    --argjson iosDeviceCount "$ios_count" \
    --argjson iphoneMirroring "$mirroring_json" \
    --arg nextAction "$next_action" \
    '{
        generatedAt:$generatedAt,
        checked:true,
        toolAvailable:true,
        status:$status,
        iosDeviceCount:$iosDeviceCount,
        physicalDeviceCount:$physicalDeviceCount,
        simulatorCount:$simulatorCount,
        devices:$devices,
        iphoneMirroring:$iphoneMirroring,
        nextAction:$nextAction
    }'
