# Iran Navigator Web Preview

Static browser-based preview for Iran Navigator, published from the `web/` directory using GitHub Pages.

## Preview URL

https://tarokhd.github.io/Map/

## Publish setup (one time)

In the repository settings, open **Pages** and set **Build and deployment → Source** to **GitHub Actions**. The workflow `.github/workflows/deploy-web.yml` deploys the `web/` directory on pushes to `main`.

## Current preview features

- MapLibre GL JS map with OpenFreeMap vector tiles.
- Dark and light map styles.
- 3D building extrusions where building-height data is available.
- Photon place search with multiple suggestions.
- Origin and destination selection by search or map click.
- Valhalla road routing for car, motorcycle (with motor-scooter fallback), and walking.
- Persian turn descriptions generated from Valhalla maneuver types and street names.
- Browser geolocation, reported accuracy circle, live camera following, and browser speech synthesis where a Persian voice is available.
- Responsive desktop and mobile layout.

## Important prototype limitations

- This is a static front-end preview; no private backend or API key is included.
- Public OpenFreeMap, Photon, and Valhalla endpoints are for prototype use and may rate-limit, change, or be unavailable. A production launch should use owned/contracted services and an Iran-hosted routing backend if required.
- Browser geolocation requires HTTPS and user permission. Web tracking is not guaranteed while the tab is backgrounded or the screen is locked.
- Persian speech depends on the voices installed in the user's browser/operating system.
- Motorcycle route quality depends on Valhalla's motorcycle/motor-scooter profile and the underlying OpenStreetMap access tags; validate routes before relying on them.
- Map coverage and building detail depend on OpenStreetMap data; this is not imagery-based 3D.
- This preview is not a safety-certified navigation product and does not provide live traffic or offline maps.

## Attribution

Map data © OpenStreetMap contributors. Map rendering powered by MapLibre GL JS and OpenFreeMap. Search powered by Photon. Routing powered by Valhalla.
