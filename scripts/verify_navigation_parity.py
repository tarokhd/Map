#!/usr/bin/env python3
import json
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
contract = json.loads((ROOT / "shared/models/navigation-contract.json").read_text(encoding="utf-8"))
routing_contract = json.loads((ROOT / "shared/models/routing-provider-contract.json").read_text(encoding="utf-8"))
openapi = yaml.safe_load((ROOT / "shared/api-contracts/openapi.yaml").read_text(encoding="utf-8"))

sources = {
    "Android": {
        "models": (ROOT / "android/app/src/main/java/com/irannavigator/demo/NavigationModels.kt").read_text(encoding="utf-8"),
        "routing": (ROOT / "android/app/src/main/java/com/irannavigator/demo/RoutingEngine.kt").read_text(encoding="utf-8"),
        "map": (ROOT / "android/app/src/main/java/com/irannavigator/demo/MainActivity.kt").read_text(encoding="utf-8"),
        "world": "\n".join((ROOT / name).read_text(encoding="utf-8") for name in (
            "web/app.mjs", "web/navigation.mjs", "web/environment.mjs")),
        "bridge": (ROOT / "shared/runtime/native-bridge.js").read_text(encoding="utf-8"),
        "packaging": (ROOT / "scripts/package_world_assets.py").read_text(encoding="utf-8"),
    },
    "iOS": {
        "models": (ROOT / "ios/Sources/Models/NavigationModels.swift").read_text(encoding="utf-8"),
        "routing": (ROOT / "ios/Sources/Services/RoutingService.swift").read_text(encoding="utf-8"),
        "map": (ROOT / "ios/Sources/World/WorldServer.swift").read_text(encoding="utf-8"),
        "world": "\n".join((ROOT / name).read_text(encoding="utf-8") for name in ("web/app.mjs", "web/navigation.mjs", "web/environment.mjs", "web/roads.mjs")),
        "location": (ROOT / "ios/Sources/World/WorldCoordinator.swift").read_text(encoding="utf-8"),
        "view": (ROOT / "ios/Sources/Views/ContentView.swift").read_text(encoding="utf-8"),
    },
    "Web": {
        "app": "\n".join(
            (ROOT / name).read_text(encoding="utf-8")
            for name in ("web/index.html", "web/app.mjs", "web/navigation.mjs", "web/environment.mjs")
        ),
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

require("Android", "world", 'source: "openfreemap"', "shared 3D building source")
require("Android", "world", '"source-layer": "building"', "3D building source-layer")
require("Android", "world", "fill-extrusion-height", "3D building height attribute")
require("Android", "world", "accuracy-source", "GPS accuracy radius")
require("Android", "map", "LocationManager.GPS_PROVIDER", "GPS provider")
require("Android", "world", "distanceAlongRoute", "distance-along-route guidance progress")
require("Android", "world", 'shape_format: "polyline6"', "polyline6 route request")
require("Android", "map", "WorldHostPolicy.isTrustedUrl", "trusted local application origin")
require("Android", "map", "WorldHostPolicy.isFreshAccurateLocation", "fresh native GPS")
require("Android", "map", "WebViewAssetLoader", "packaged local renderer")
require("Android", "bridge", "native.requestLocation", "native GPS bridge")
require("Android", "packaging", "hashlib.sha512(payload)", "verified bundled renderer")

require("iOS", "world", 'source: "openfreemap"', "shared 3D source")
require("iOS", "world", '"source-layer": "building"', "3D building source-layer")
require("iOS", "world", "fill-extrusion-height", "3D building height")
require("iOS", "world", "accuracy-source", "GPS accuracy radius")
require("iOS", "location", "kCLLocationAccuracyBestForNavigation", "high-accuracy CoreLocation")
require("iOS", "world", 'shape_format: "polyline6"', "polyline6 request")
require("iOS", "location", "fresh(position)", "fresh and accurate GPS")
require("iOS", "location", "WorldHostPolicy.trusted", "trusted packaged origin")
require("iOS", "view", "WorldCoordinator", "shared World runtime host")
for platform in ("Android", "iOS"):
    require(platform, "world", "navigationVision", "early selected-route camera")
    require(platform, "world", "northCompass", "north compass")

# Provider contract: Neshan is traffic-aware only for the officially documented
# car and motorcycle Direction API. Credentials remain server-side.
neshan = routing_contract["providers"]["neshan"]
if neshan.get("requiresBackendProxy") is not True:
    errors.append("Routing contract: Neshan provider must be called through the backend proxy")
if neshan.get("apiKeyMayBeIncludedInClient") is not False:
    errors.append("Routing contract: Neshan API key must never be shipped in clients")
if set(neshan.get("supportedModes", [])) != {"car", "motorcycle"}:
    errors.append("Routing contract: Neshan traffic routing modes must match the verified provider documentation")
if neshan.get("trafficAware") is not True:
    errors.append("Routing contract: Neshan traffic provider must be marked traffic-aware")
if routing_contract["providerSelection"]["walking"]["trafficRequested"] != "valhalla":
    errors.append("Routing contract: walking must not be sent to the Neshan car/motorcycle traffic endpoint")

route_path = openapi.get("paths", {}).get("/api/v1/routes", {}).get("post")
if not route_path:
    errors.append("OpenAPI: POST /api/v1/routes endpoint is missing")
else:
    if route_path.get("x-implementation-status") != "implemented":
        errors.append("OpenAPI: route proxy status must match the FastAPI implementation")
    request_schema = route_path.get("requestBody", {}).get("content", {}).get("application/json", {}).get("schema", {})
    if request_schema.get("$ref") != "#/components/schemas/RouteRequest":
        errors.append("OpenAPI: route request must use the shared RouteRequest schema")

route_schemas = openapi.get("components", {}).get("schemas", {})
for schema_name in ("RouteRequest", "RouteResponse", "RouteOption", "RouteLeg", "RouteManeuver", "EncodedGeometry"):
    if schema_name not in route_schemas:
        errors.append(f"OpenAPI: missing normalized routing schema {schema_name}")

require("Web", "app", 'src="https://unpkg.com/maplibre-gl@5.24.0/dist/maplibre-gl.js"', "MapLibre GL JS 5.24 UMD script")
require("Web", "app", 'href="https://unpkg.com/maplibre-gl@5.24.0/dist/maplibre-gl.css"', "MapLibre 5.24 CSS")
require("Web", "app", "const maplibregl = window.maplibregl", "MapLibre UMD global namespace")

require("Web", "app", 'source: "openfreemap"', "vector tile source")
require("Web", "app", '"source-layer": "building"', "3D building source-layer")
require("Web", "app", "fill-extrusion-height", "3D building height attribute")
require("Web", "app", "fill-extrusion-base", "3D building base height")
require("Web", "app", "zoom: 15.2", "default camera zoom that reveals 3D buildings")
require("Web", "app", "minzoom: 14", "building layer zoom threshold")
require("Web", "app", "function beginMovement", "route-first immersive navigation")
require("Web", "app", "accuracy-source", "GPS accuracy radius")
require("Web", "app", "navigator.geolocation.watchPosition", "continuous browser geolocation")
require("Web", "app", "distanceAlongRoute", "distance-along-route guidance progress")
require("Web", "app", 'shape_format: \"polyline6\"', "polyline6 route request")

if errors:
    print("Navigation parity checks FAILED:")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("Navigation parity checks passed for Android, iOS and Web.")
print(f"Verified {len(contract['travelModes'])} travel modes, {len(contract['maneuvers'])} shared maneuver instructions, 3D building data and polyline6 routing.")
