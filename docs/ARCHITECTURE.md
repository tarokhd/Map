# Iran Navigator Architecture and Quality Gates

## Product scope

The Persian product feature-parity specification and phased roadmap live in docs/PRODUCT_FEATURE_PARITY_FA.md. It separates implemented prototype capabilities from product goals and external data dependencies.

## Web map renderer

The Web client is pinned to MapLibre GL JS 5.24.0 using the UMD browser bundle. Version 6 is ESM-only and removed the UMD file; do not restore a v6 UMD script URL. Any renderer upgrade must validate the matching JS, CSS and worker assets and be tested in a real browser before deployment.

## Monorepo

- android/: Kotlin + MapLibre Native Android app.
- ios/: SwiftUI + MapLibre Native iOS app using CoreLocation and AVSpeechSynthesizer.
- web/: static MapLibre GL JS preview, deployed independently to GitHub Pages.
- backend/: FastAPI and PostgreSQL/PostGIS development scaffold.
- shared/models/navigation-contract.json: canonical travel modes, key maneuver instructions, 3D attributes and route geometry format.
- scripts/: cross-platform parity and live service smoke checks.

## Cross-platform navigation contract

Android, iOS and Web must use the same travel mode identifiers and Valhalla costing profiles:
- car -> auto
- motorcycle -> motorcycle, with motor_scooter fallback
- walking -> pedestrian

Route geometry is requested as polyline6. GeoJSON coordinates use [longitude, latitude]; Valhalla route locations use named latitude and longitude fields. The shared navigation contract is checked by scripts/verify_navigation_parity.py.

## Quality gates

- Android: JUnit tests run before the APK build.
- iOS: XCTest unit tests and XCUITest interface tests run on an iPhone simulator. CI grants simulated location permission and sets a Tehran simulator location before tests.
- Web: GitHub Pages deploy validates the inline application JavaScript.
- Platform parity: static contract checks compare critical travel modes, maneuver instructions, GPS and 3D building integration across the three clients.
- Navigation service smoke tests: live OpenFreeMap styles, Photon geocoding and Valhalla route profiles are checked on navigation-related pushes and manual dispatch.

## Shared data flow

Android, iOS and Web should communicate with the Backend over HTTPS REST APIs. The Backend authenticates the caller, enforces per-user authorization, validates inputs, and reads/writes PostgreSQL/PostGIS. Client apps must never contain database credentials or connect directly to PostgreSQL.

The current backend only implements /healthz and /readyz. Saved-place and route-history endpoints are planned in the OpenAPI contract and database schema but are not implemented yet. Cross-device synchronization is therefore not active.

## iOS signing

The CI artifact is an unsigned iOS Simulator .app bundle, not a device-installable IPA. A physical-device or TestFlight/App Store release requires Apple code signing, certificates, provisioning profiles and the appropriate Apple Developer account.

## Production work still required

1. Implement JWT/OIDC authentication and authorization.
2. Implement saved-place and route-history CRUD endpoints.
3. Add Alembic migrations.
4. Deploy Backend and PostGIS to a secured server.
5. Add rate limiting, backups, monitoring, privacy/retention policies, and secrets management.
6. Configure Android, iOS and Web API base URLs to the deployed backend.
7. Select reliable map tile, geocoding, and routing services with appropriate Iran coverage and terms.
8. Test GPS, route guidance, Persian voice, and map rendering on physical Android and iPhone devices before relying on navigation in real traffic.
