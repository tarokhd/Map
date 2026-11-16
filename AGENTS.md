# Cross-platform product changes

The user requires Web, Android, iOS, and future clients to receive product changes together.

- Implement product UI, road/bridge rendering, routing, camera behavior and environment appearance in `web/` (the canonical World runtime).
- Mobile apps package that runtime with `scripts/package_world_assets.py`; they do not open the published website. Keep permission handling, GPS, lifecycle and OS navigation in platform hosts.
- Update `shared/runtime/native-bridge.js` and relevant hosts together for native capabilities. Request location only after an explicit user action.
- Every new platform must consume the canonical runtime or its shared contract, join the bundle checks, and build whenever `web/**` or `shared/**` changes. Do not silently create an independent feature fork.
- For shared behavior changes, run Node core tests, browser smoke tests, bundle identity checks, navigation parity, and Android unit/build/lint checks. Use macOS CI for iOS compilation and simulator tests; report any unavailable device validation honestly.
- Bridge geometry comes from map tags. Heights and centre markings in this renderer are schematic; never describe these as surveyed elevations or lane-level guidance. Camera anticipation must follow the chosen route while retaining the current road in view.
- Preserve existing edits and never put credentials or signing keys in Git.
