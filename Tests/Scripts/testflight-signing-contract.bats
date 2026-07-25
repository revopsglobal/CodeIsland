#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export WORKFLOW="$REPO_ROOT/.github/workflows/testflight-ios.yml"
  export PROJECT_SPEC="$REPO_ROOT/ios/CodeIslandCompanion/project.yml"
  export XCODE_PROJECT="$REPO_ROOT/ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj/project.pbxproj"
  export EXPORT_OPTIONS="$REPO_ROOT/ios/CodeIslandCompanion/ExportOptions.plist"
}

@test "TestFlight deterministically signs app, widget, and share extension with App Store profiles" {
  [ "$(/usr/libexec/PlistBuddy -c 'Print :signingStyle' "$EXPORT_OPTIONS")" = "manual" ]
  [ "$(/usr/libexec/PlistBuddy -c 'Print :provisioningProfiles:com.revopsglobal.codeisland.buddy' "$EXPORT_OPTIONS")" = "CodeIsland Buddy App Store" ]
  [ "$(/usr/libexec/PlistBuddy -c 'Print :provisioningProfiles:com.revopsglobal.codeisland.buddy.widget' "$EXPORT_OPTIONS")" = "CodeIsland Buddy Widget App Store" ]
  [ "$(/usr/libexec/PlistBuddy -c 'Print :provisioningProfiles:com.revopsglobal.codeisland.buddy.share' "$EXPORT_OPTIONS")" = "CodeIsland Buddy Share App Store" ]

  [ "$(grep -c 'CODE_SIGN_STYLE: Manual' "$PROJECT_SPEC")" -eq 3 ]
  [ "$(grep -c 'PROVISIONING_PROFILE_SPECIFIER:' "$PROJECT_SPEC")" -eq 3 ]
  [ "$(grep -c 'CODE_SIGN_STYLE = Manual;' "$XCODE_PROJECT")" -eq 3 ]
  [ "$(grep -c 'PROVISIONING_PROFILE_SPECIFIER =' "$XCODE_PROJECT")" -eq 3 ]

  grep -Fq 'IOS_APPSTORE_PROFILE_BASE64' "$WORKFLOW"
  grep -Fq 'IOS_WIDGET_PROFILE_BASE64' "$WORKFLOW"
  grep -Fq 'IOS_SHARE_PROFILE_BASE64' "$WORKFLOW"
  grep -Fq 'Import distribution certificate and profiles' "$WORKFLOW"

  run grep -F -- '-allowProvisioningUpdates' "$WORKFLOW"
  [ "$status" -ne 0 ]
  run grep -F -- '-authenticationKeyPath' "$WORKFLOW"
  [ "$status" -ne 0 ]
  run grep -F -- 'REGISTER_APP_GROUPS=YES' "$WORKFLOW"
  [ "$status" -ne 0 ]
}

@test "TestFlight regenerates and tests AgentOps Voice before archive" {
  [ "$(tr -d '[:space:]' < "$REPO_ROOT/.xcodegen-version")" = "2.46.0" ]

  generate_line="$(grep -nF 'xcodegen generate --spec ios/CodeIslandCompanion/project.yml' "$WORKFLOW" | cut -d: -f1)"
  resolve_line="$(grep -nF -- '-resolvePackageDependencies' "$WORKFLOW" | cut -d: -f1)"
  voice_test_line="$(grep -nF 'Test AgentOps Voice before archive' "$WORKFLOW" | cut -d: -f1)"
  archive_line="$(grep -nF 'Archive signed iPhone app' "$WORKFLOW" | cut -d: -f1)"

  [ "$generate_line" -lt "$resolve_line" ]
  [ "$resolve_line" -lt "$voice_test_line" ]
  [ "$voice_test_line" -lt "$archive_line" ]

  grep -Fq -- '-onlyUsePackageVersionsFromResolvedFile' "$WORKFLOW"
  grep -Fq -- '-disableAutomaticPackageResolution' "$WORKFLOW"
  grep -Fq -- '-only-testing:CodeIslandCompanionTests' "$WORKFLOW"
}
