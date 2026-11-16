# Iran Navigator iOS — World

SwiftUI/WKWebView hosts the same packaged World renderer and product UI as Web and Android. CoreLocation handles permission-gated, foreground GPS. No published website is opened. A loopback-only asset server supplies bundled modules and workers with correct MIME types; the native bridge accepts only the current server origin and application path.

## Build on macOS

Requirements: Xcode 16+, Python 3 and XcodeGen (`brew install xcodegen`). From the repository root:

```sh
python3 scripts/package_world_assets.py --platform ios --output ios/build/World
python3 scripts/verify_world_bundles.py ios/build/World
cd ios
xcodegen generate
```

Open `IranNavigator.xcodeproj` and run the scheme on an iPhone simulator. The minimum OS is iOS 16; AbortSignal compatibility shims are packaged for older WebKit versions. First-party UI and pinned renderer libraries are included in the app; map/search/routing still need internet.

Shared compass, roads/alleys, schematic elevated bridges, destination-first journey flow, solar appearance and anticipatory camera come directly from `web/`. Native adapters for routing/models remain for contract compatibility; they do not implement a separate live UI.

`ios-build.yml` repackages the shared runtime on Web/shared changes, compiles tests, runs unit and local-shell UI tests on a simulator, and uploads a simulator `.app`. This is not an installable iPhone IPA. Physical-device distribution requires Apple signing/provisioning, and physical-device navigation has not been validated here.

Bridge heights and centre markings are schematic, not surveyed elevations or lane-level guidance. No offline maps, live traffic or background navigation are implemented. See [shared architecture](../docs/SHARED_WORLD.md).
