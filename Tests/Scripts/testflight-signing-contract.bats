#!/usr/bin/env bats

setup() {
  export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  export WORKFLOW="$REPO_ROOT/.github/workflows/testflight-ios.yml"
  export PROJECT_SPEC="$REPO_ROOT/ios/CodeIslandCompanion/project.yml"
  export XCODE_PROJECT="$REPO_ROOT/ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj/project.pbxproj"
  export EXPORT_OPTIONS="$REPO_ROOT/ios/CodeIslandCompanion/ExportOptions.plist"
}

@test "TestFlight uses one Xcode-managed signing path for app, widget, and share extension" {
  [ "$(/usr/libexec/PlistBuddy -c 'Print :signingStyle' "$EXPORT_OPTIONS")" = "automatic" ]
  run /usr/libexec/PlistBuddy -c 'Print :provisioningProfiles' "$EXPORT_OPTIONS"
  [ "$status" -ne 0 ]

  run grep -E 'CODE_SIGN_STYLE:[[:space:]]+Manual|PROVISIONING_PROFILE_SPECIFIER' "$PROJECT_SPEC"
  [ "$status" -ne 0 ]
  run grep -E 'CODE_SIGN_STYLE = Manual|PROVISIONING_PROFILE_SPECIFIER' "$XCODE_PROJECT"
  [ "$status" -ne 0 ]
  [ "$(grep -c 'REGISTER_APP_GROUPS: YES' "$PROJECT_SPEC")" -eq 2 ]
  [ "$(grep -c 'REGISTER_APP_GROUPS = YES;' "$XCODE_PROJECT")" -eq 2 ]

  grep -Fq -- '-allowProvisioningUpdates' "$WORKFLOW"
  grep -Fq -- '-authenticationKeyPath' "$WORKFLOW"
  grep -Fq -- '-authenticationKeyID' "$WORKFLOW"
  grep -Fq -- '-authenticationKeyIssuerID' "$WORKFLOW"

  run grep -E 'IOS_(APPSTORE|WIDGET|SHARE)_PROFILE_BASE64' "$WORKFLOW"
  [ "$status" -ne 0 ]
}
