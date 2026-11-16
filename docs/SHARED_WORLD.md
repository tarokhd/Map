# One World runtime across platforms

The user's requirement is that Web, Android, iOS and future versions receive product changes together. `web/` is the canonical runtime for UI, routing, map appearance, road meshes, camera and environment behavior. Kotlin and Swift hosts provide OS permissions, foreground GPS, lifecycle, local asset serving and system navigation.

Mobile builds run `scripts/package_world_assets.py`. This copies the same modules, styles and vector vehicle assets, replaces renderer CDN URLs with integrity-verified local libraries, adds the shared GPS bridge and applies a restricted CSP. Application code is packaged in the mobile binary; only map/search/route data is fetched at runtime. Mobile service workers are disabled so APK/app updates cannot be shadowed by a stale browser cache.

`world-manifest.json` records SHA-256 of canonical sources and generated files. `verify_world_bundles.py` rejects stale bundles and divergent mobile runtime contents. The Android and iOS workflows both trigger on shared/Web changes. Native-only work must also update every affected host or explicitly document an OS-specific limitation. Add future platforms to these packaging, contract, test and build checks.

## Road and camera behavior

- Road width follows map road class, with separate alleys/service roads, edge treatment, illustrative centre markings and dashed underpasses. Names remain bilingual.
- 3D bridge decks and illuminated rails use actual `brunnel=bridge` transportation features. Railways and tunnels are excluded. `layer` provides stacking order; six metres per level is a schematic visual separation, not surveyed height. Bridge decks are translucent to keep route context visible. Mesh counts are bounded and duplicate tile geometry is suppressed.
- The navigation route stays tied to the selected route geometry. We do not infer a route's vertical level from the nearest crossing road. Lane counts, lane assignment and engineering-grade deck alignment are not claimed.
- Maneuvers use `begin_shape_index`, rather than the end of the following road segment. At an approaching decision, a bounded look-ahead rotates toward the chosen branch, highlights its geometry, and retains the present road in view. Speed changes the look-ahead distance; a walking route uses a shorter distance. Available exit sign text is shown with the instruction.
- The N compass rotates with the map; tapping it resets north and pauses camera following until the guidance panel is tapped.

## Verification

```sh
node --test web/tests/*.test.mjs scripts/android_bridge.test.cjs
python3 scripts/verify_navigation_parity.py
python3 scripts/package_world_assets.py --output android/app/build/generated/worldAssets/world
python3 scripts/package_world_assets.py --platform ios --output ios/build/World
python3 scripts/verify_world_bundles.py android/app/build/generated/worldAssets/world ios/build/World
```

Run `scripts/web_map_smoke.cjs` against the Web server and `scripts/android_world_smoke.cjs` against the generated mobile-shell server, using Playwright. These check actual renderer/RTL loading, WebGL bridge geometry, the compass, destination flow, camera, GPS bridge/cancellation, rejected permission, local libraries and CSP. Browser tests use controlled search/route fixtures; they do not establish physical-device GPS or lane-level accuracy. Android's unit, lint and APK builds and iOS's macOS simulator checks remain necessary platform checks.

The optional `publish_test_apk` workflow-dispatch input publishes a verified debug APK and checksum as a GitHub prerelease. Normal pushes upload build artifacts without creating releases. Production Android signing and Apple device signing are separate deployment requirements.
