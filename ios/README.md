# Iran Navigator iOS

Native iOS client built with SwiftUI, CoreLocation and MapLibre Native.

## Current prototype scope

- MapLibre map using OpenFreeMap dark and light styles.
- 3D building extrusion where OpenMapTiles building-height attributes exist.
- Native CoreLocation location updates and current-location origin.
- Photon place search with Persian query language and location bias.
- Valhalla road routing for car, motorcycle (with motor-scooter fallback), and pedestrian modes.
- Persian turn instruction text generated from Valhalla maneuver types and street names.
- AVSpeechSynthesizer Persian voice when a Persian system voice is installed.
- Route polyline, origin/destination markers and live camera following while the app is active.

## Open and build on a Mac

1. Install Xcode 16 or newer and Homebrew.
2. Install XcodeGen with Homebrew.
3. From the repository root run: cd ios && xcodegen generate
4. Open ios/IranNavigator.xcodeproj in Xcode.
5. Select an iPhone simulator and run the IranNavigator scheme.

The project uses Swift Package Manager to resolve MapLibre Native from the official MapLibre distribution repository.

## GitHub Actions

The ios-build workflow runs on a macOS runner, generates the Xcode project, builds the iOS Simulator app without code signing, and uploads a zipped .app artifact.

The simulator artifact is for simulator testing only. It is not an installable iPhone IPA. Installing on a physical iPhone or distributing through TestFlight/App Store requires Apple code signing and the appropriate Apple Developer account and provisioning.

## Important prototype limitations

- Public OpenFreeMap, Photon and Valhalla services are used for prototype testing and have no production SLA.
- Motorcycle route quality depends on the public Valhalla profile and OpenStreetMap access tags; validate routes in Iran.
- Persian speech depends on a Persian voice being installed and available in iOS. Text guidance remains available when it is not.
- Location accuracy depends on device, environment and satellite visibility.
- Live camera tracking and rerouting are intended for foreground use in this prototype. Background navigation and a background location mode are not configured.
- This prototype does not provide live traffic, offline maps or guaranteed lane-level guidance.
- The app has not yet been tested on a physical iPhone; successful CI compilation is not a substitute for device testing.

## Attribution

Map rendering: MapLibre Native. Map styles and vector tiles: OpenFreeMap. Map data: OpenStreetMap contributors. Search: Photon. Routing: Valhalla.
