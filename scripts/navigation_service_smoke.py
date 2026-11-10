#!/usr/bin/env python3
import json
import math
import time
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = "IranNavigator-Navigation-SmokeTest/0.3"
TEHRAN_START = {"lat": 35.7006, "lon": 51.4050}
TEHRAN_END = {"lat": 35.7219, "lon": 51.3347}

def request_json(url, payload=None, attempts=3):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    last_error = None
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, data=data, headers=headers)
            with urllib.request.urlopen(req, timeout=35) as response:
                if not 200 <= response.status < 300:
                    raise RuntimeError(f"HTTP {response.status} from {url}")
                return json.loads(response.read().decode("utf-8"))
        except Exception as error:
            last_error = error
            if attempt + 1 < attempts:
                time.sleep(2 ** attempt)
    raise RuntimeError(f"Request failed for {url}: {last_error}")

def decode_polyline6(encoded):
    index = 0
    latitude = 0
    longitude = 0
    points = []

    def read_delta():
        nonlocal index
        result = 0
        shift = 0
        while True:
            if index >= len(encoded) or shift > 30:
                raise ValueError("Malformed polyline6")
            byte = ord(encoded[index]) - 63
            index += 1
            if byte < 0:
                raise ValueError("Malformed polyline6")
            result |= (byte & 0x1f) << shift
            shift += 5
            if byte < 0x20:
                break
        return ~(result >> 1) if result & 1 else (result >> 1)

    while index < len(encoded):
        latitude += read_delta()
        longitude += read_delta()
        lat = latitude / 1_000_000
        lon = longitude / 1_000_000
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError("Decoded coordinate is out of range")
        points.append((lat, lon))
    return points

def check_styles():
    for name in ("dark", "positron"):
        style = request_json(f"https://tiles.openfreemap.org/styles/{name}")
        sources = style.get("sources", {})
        source = sources.get("openmaptiles")
        assert source and source.get("type") == "vector", f"{name}: openmaptiles vector source missing"
        assert "planet" in source.get("url", ""), f"{name}: unexpected vector tile URL"

        building_layers = [
            layer for layer in style.get("layers", [])
            if layer.get("source") == "openmaptiles" and layer.get("source-layer") == "building"
        ]
        assert building_layers, f"{name}: style does not reference the building vector layer"

        tilejson = request_json(source["url"])
        vector_layers = tilejson.get("vector_layers", [])
        if vector_layers:
            building = next((layer for layer in vector_layers if layer.get("id") == "building"), None)
            assert building, "OpenFreeMap TileJSON does not advertise the building layer"
            fields = building.get("fields", {})
            if fields:
                assert "render_height" in fields, "Building height attribute render_height is missing"

        tile_templates = tilejson.get("tiles", [])
        if tile_templates:
            zoom = min(15, int(tilejson.get("maxzoom", 15)))
            tile_x = int((TEHRAN_START["lon"] + 180) / 360 * (2 ** zoom))
            latitude_radians = math.radians(TEHRAN_START["lat"])
            tile_y = int((1 - math.asinh(math.tan(latitude_radians)) / math.pi) / 2 * (2 ** zoom))
            if tilejson.get("scheme") == "tms":
                tile_y = (2 ** zoom - 1) - tile_y
            tile_url = tile_templates[0].replace("{z}", str(zoom)).replace("{x}", str(tile_x)).replace("{y}", str(tile_y))
            tile_url = tile_url.replace("{-y}", str((2 ** zoom - 1) - tile_y))
            tile_request = urllib.request.Request(tile_url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(tile_request, timeout=30) as tile_response:
                tile_bytes = tile_response.read()
                tile_status = tile_response.status
            print(f"INFO OpenFreeMap tile request: zoom={zoom}, scheme={tilejson.get('scheme', 'xyz')}, status={tile_status}, bytes={len(tile_bytes)}")
            if len(tile_bytes) > 100:
                print(f"PASS OpenFreeMap Tehran vector tile ({len(tile_bytes)} bytes)")
            else:
                print("WARN OpenFreeMap tile payload was empty; style and building-layer metadata were still validated")

        print(f"PASS OpenFreeMap {name} style and 3D building-layer metadata")

def check_photon():
    query = urllib.parse.urlencode({
        "q": "Azadi Tower Tehran",
        "limit": "3",
        "lat": str(TEHRAN_START["lat"]),
        "lon": str(TEHRAN_START["lon"]),
        "lang": "en",
    })
    result = request_json("https://photon.komoot.io/api/?" + query)
    assert result.get("features"), "Photon returned no Tehran search candidates"
    print("PASS Photon geocoding endpoint")

def check_route(costing):
    payload = {
        "locations": [TEHRAN_START, TEHRAN_END],
        "costing": costing,
        "units": "kilometers",
        "language": "en-US",
        "shape_format": "polyline6",
        "directions_type": "instructions",
        "id": "iran-navigator-smoke-test",
    }
    result = request_json("https://valhalla1.openstreetmap.de/route", payload)
    trip = result.get("trip") or {}
    legs = trip.get("legs") or []
    assert legs, f"{costing}: route response has no legs"
    leg = legs[0]
    points = decode_polyline6(leg.get("shape", ""))
    assert len(points) >= 2, f"{costing}: route geometry has fewer than two points"
    summary = trip.get("summary") or leg.get("summary") or {}
    assert summary.get("length", 0) > 0, f"{costing}: route distance is missing"
    assert summary.get("time", 0) > 0, f"{costing}: route duration is missing"
    assert leg.get("maneuvers"), f"{costing}: route maneuvers are missing"
    assert all(24 <= lat <= 41 and 43 <= lon <= 64 for lat, lon in points), f"{costing}: route left Iran bounds"
    print(f"PASS Valhalla {costing}: {len(points)} geometry points, {len(leg['maneuvers'])} maneuvers")

def check_valhalla():
    check_route("auto")
    check_route("pedestrian")
    try:
        check_route("motorcycle")
    except Exception as motorcycle_error:
        print(f"INFO motorcycle profile unavailable; trying motor_scooter ({motorcycle_error})")
        check_route("motor_scooter")

if __name__ == "__main__":
    # MapLibre is vendored into the GitHub Pages artifact by web-deploy.yml.
    check_styles()
    check_photon()
    check_valhalla()
    print("All public navigation service smoke checks passed.")
