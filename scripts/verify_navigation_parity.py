#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
contract = json.loads((ROOT / "shared/models/navigation-contract.json").read_text(encoding="utf-8"))

sources = {
    "Android": {
        "models": (ROOT / "android/app/src/main/java/com/irannavigator/demo/NavigationModels.kt").read_text(encoding="utf-8"),
        "routing": (ROOT / "android/app/src/main/java/com/irannavigator/demo/RoutingEngine.kt").read_text(encoding="utf-8"),
        "map": (ROOT / "android/app/src/main/java/com/irannavigator/demo/MainActivity.kt").read_text(encoding="utf-8"),
    },
    "iOS": {
        "models": (ROOT / "ios/Sources/Models/NavigationModels.swift").read_text(encoding="utf-8"),
        "routing": (ROOT / "ios/Sources/Services/RoutingService.swift").read_text(encoding="utf-8"),
        "map": (ROOT / "ios/Sources/Map/MapLibreView.swift").read_text(encoding="utf-8"),
        "location": (ROOT / "ios/Sources/Services/LocationService.swift").read_text(encoding="utf-8"),
        "view": (ROOT / "ios/Sources/Views/ContentView.swift").read_text(encoding="utf-8"),
    },
    "Web": {
        "app": (ROOT / "web/index.html").read_text(encoding="utf-8"),
    },
}

errors = []

def require(platform, area, needle, label):
    if needle not in sources[platform][area]:
        errors.append(f"{platform}: missing {label} ({needle})")

for platform in sources:
    combined = "\n".join(sources[platform].values())
    for mode, spec in contract["travelModes"].items():
        if spec["valhallaCosting"] not in combined:
            errors.append(f"{platform}: missing {mode} costing {spec['valhallaCosting']}")
        for fallback in spec["fallbackCostings"]:
            if fallback not in combined:
                errors.append(f"{platform}: missing {mode} fallback costing {fallback}")

    for maneuver_type, instruction in contract["maneuvers"].items():
        if instruction not in combined:
            errors.append(f"{platform}: maneuver {maneuver_type} instruction differs or is missing")

    if contract["routeGeometry"]["shapeFormat"] not in combined:
        errors.append(f"{platform}: route geometry must use polyline6")

require("Android", "map", 'FillExtrusionLayer("iran-buildings-3d", "openmaptiles")', "3D building source")
require("Android", "map", 'buildings.sourceLayer = "building"', "3D building source-layer")
require("Android", "map", 'Expression.get("render_height")', "3D building height attribute")
require("Android", "map", '"user-accuracy-source"', "GPS accuracy radius")
require("Android", "map", "LocationManager.GPS_PROVIDER", "GPS provider")
require("Android", "map", "distanceAlongRoute", "distance-along-route guidance progress")
require("Android", "routing", 'put("shape_format", "polyline6")', "polyline6 route request")

require("iOS", "map", 'style.source(withIdentifier: "openmaptiles")', "3D building source")
require("iOS", "map", 'buildings.sourceLayerIdentifier = "building"', "3D building source-layer")
require("iOS", "map", 'forKeyPath: "render_height"', "3D building height attribute")
require("iOS", "map", '"iran-user-accuracy-fill"', "GPS accuracy radius")
require("iOS", "map", "pitch: show3DBuildings ? 50 : 0", "initial 3D camera pitch")
require("iOS", "location", "kCLLocationAccuracyBestForNavigation", "high-accuracy CoreLocation")
require("iOS", "routing", '"shape_format": "polyline6"', "polyline6 route request")
require("iOS", "location", "NavigationLocationQuality.isUsable", "fresh and accurate GPS validation")
require("iOS", "view", "distanceAlongRoute", "distance-along-route guidance progress")

require("Web", "app", '<script type="module">', "ES module application entry point")
require("Web", "app", 'import("https://unpkg.com/maplibre-gl@6.17.0/dist/maplibre-gl.mjs")', "MapLibre GL JS v6 ESM import")
require("Web", "app", "typeof maplibregl.Map", "MapLibre ESM namespace validation")
require("Web", "app", "کتابخانه نقشه بارگذاری نشد", "visible MapLibre import error")
if 'maplibre-gl.js' in sources["Web"]["app"] or 'window.maplibregl' in sources["Web"]["app"]:
    errors.append("Web: legacy UMD script/global reference must not be used with MapLibre GL JS v6")

require("Web", "app", 'source: "openfreemap"', "vector tile source")
require("Web", "app", '"source-layer": "building"', "3D building source-layer")
require("Web", "app", '"fill-extrusion-height"', "3D building height attribute")
require("Web", "app", '"fill-extrusion-base"', "3D building base height")
require("Web", "app", "zoom: 15.2", "default camera zoom that reveals 3D buildings")
require("Web", "app", "minzoom: 14", "building layer zoom threshold")
require("Web", "app", "Math.max(map.getZoom(), 15.0)", "automatic zoom-in when enabling 3D")
require("Web", "app", '"accuracy-source"', "GPS accuracy radius")
require("Web", "app", "navigator.geolocation.watchPosition", "continuous browser geolocation")
require("Web", "app", "distanceAlongRoute", "distance-along-route guidance progress")
require("Web", "app", 'shape_format: "polyline6"', "polyline6 route request")

if errors:
    print("Navigation parity checks FAILED:")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("Navigation parity checks passed for Android, iOS and Web.")
print(f"Verified {len(contract['travelModes'])} travel modes, {len(contract['maneuvers'])} shared maneuver instructions, 3D building data and polyline6 routing.")
