import Foundation
@testable import CodeIsland

/// AppState with the permission surface debounce disabled.
///
/// Production stages an incoming PermissionRequest for
/// `AppState.defaultPermissionSurfaceDebounce` before it becomes visible, so a CLI
/// that asks and instantly resolves never flashes an approval card. Tests that
/// assert on queue/surface state right after `handlePermissionRequest` want the
/// synchronous path; the debounce itself is covered by
/// `AppStatePermissionDebounceTests`.
@MainActor
func makeTestAppState(permissionSurfaceDebounce: TimeInterval = 0) -> AppState {
    let appState = AppState()
    appState.permissionSurfaceDebounce = permissionSurfaceDebounce
    return appState
}
