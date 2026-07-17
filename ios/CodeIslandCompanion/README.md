# Code Island Buddy

This is the Xcode project for the iPhone-only CodeIsland Buddy, including Live
Activity, Dynamic Island, StandBy, Bluetooth status, and private remote
approvals over Tailscale.

For the product overview, setup guide, protocol notes, and screenshots, see:

- [`../../apple-companion/README.md`](../../apple-companion/README.md)

## Project Contents

- `CodeIslandCompanion/` - iPhone app
- `CodeIslandCompanionWidget/` - iPhone Live Activity, Dynamic Island, and StandBy UI
- `Shared/` - shared models, display helpers, and mascot views
- `project.yml` - XcodeGen project definition

The upstream Watch source folders remain as reference files, but `project.yml`
does not generate Watch targets or link WatchConnectivity.

Remote approval setup and security details are in
[`../../docs/remote-approvals.md`](../../docs/remote-approvals.md).

## Open in Xcode

```bash
cd ios/CodeIslandCompanion
xcodegen generate
open CodeIslandCompanion.xcodeproj
```
