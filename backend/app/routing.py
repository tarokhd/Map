from __future__ import annotations

import math
import os
from datetime import datetime, timezone
from typing import Literal

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, model_validator

router = APIRouter(prefix="/api/v1", tags=["routing"])

NESHAN_DIRECTION_URL = "https://api.neshan.org/v4/direction"
DEFAULT_VALHALLA_URL = "https://valhalla1.openstreetmap.de/route"


class Coordinates(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class RouteRequest(BaseModel):
    origin: Coordinates
    destination: Coordinates
    waypoints: list[Coordinates] = Field(default_factory=list)
    travel_mode: Literal["car", "motorcycle", "walking"]
    traffic_preference: Literal["live", "none"] = "live"
    alternatives: bool = True
    avoid_traffic_zone: bool = False
    avoid_odd_even_zone: bool = False
    allow_non_traffic_fallback: bool = False
    bearing: int | None = Field(default=None, ge=0, le=360)

    @model_validator(mode="after")
    def validate_provider_options(self) -> "RouteRequest":
        if (self.avoid_traffic_zone or self.avoid_odd_even_zone) and (
            self.traffic_preference != "live"
            or self.travel_mode not in ("car", "motorcycle")
        ):
            raise ValueError(
                "Traffic-zone avoidance requires live car or motorcycle routing."
            )
        return self


class EncodedGeometry(BaseModel):
    encoding: Literal["encoded-polyline", "polyline6"]
    precision: int | None = Field(default=None, ge=0, le=8)
    value: str


class RouteManeuver(BaseModel):
    instruction: str
    street_name: str | None = None
    type: str | None = None
    modifier: str | None = None
    end_shape_index: int | None = Field(default=None, ge=0)
    distance_m: float = Field(ge=0)
    duration_s: float = Field(ge=0)
    geometry: EncodedGeometry | None = None


class RouteLeg(BaseModel):
    summary: str | None = None
    distance_m: float = Field(ge=0)
    duration_s: float = Field(ge=0)
    geometry: EncodedGeometry | None = None
    steps: list[RouteManeuver]


class RouteOption(BaseModel):
    id: str
    provider: Literal["neshan", "valhalla"]
    traffic_aware: bool
    fallback_used: bool = False
    fallback_reason: str | None = None
    distance_m: float = Field(ge=0)
    duration_s: float = Field(ge=0)
    overview_geometry: EncodedGeometry
    legs: list[RouteLeg]


class RouteResponse(BaseModel):
    options: list[RouteOption]
    requested_traffic_preference: Literal["live", "none"]
    generated_at: datetime


class ProviderNotConfigured(Exception):
    pass


class ProviderRateLimited(Exception):
    pass


class ProviderFailure(Exception):
    pass


def decode_polyline(encoded: str, precision: int) -> list[tuple[float, float]]:
    """Decode an encoded polyline into (latitude, longitude) tuples."""
    index = 0
    latitude = 0
    longitude = 0
    points: list[tuple[float, float]] = []

    def read_delta() -> int:
        nonlocal index
        result = 0
        shift = 0
        while True:
            if index >= len(encoded) or shift > 30:
                raise ValueError("Malformed encoded polyline")
            byte = ord(encoded[index]) - 63
            index += 1
            if byte < 0:
                raise ValueError("Malformed encoded polyline")
            result |= (byte & 0x1F) << shift
            shift += 5
            if byte < 0x20:
                break
        return ~(result >> 1) if result & 1 else result >> 1

    factor = 10 ** precision
    while index < len(encoded):
        latitude += read_delta()
        longitude += read_delta()
        lat = latitude / factor
        lon = longitude / factor
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError("Encoded polyline contains an invalid coordinate")
        points.append((lat, lon))
    return points


def encode_polyline(points: list[tuple[float, float]], precision: int) -> str:
    factor = 10 ** precision
    previous_latitude = 0
    previous_longitude = 0
    output: list[str] = []

    def encode_delta(delta: int) -> str:
        value = ~(delta << 1) if delta < 0 else delta << 1
        chars: list[str] = []
        while value >= 0x20:
            chars.append(chr((0x20 | (value & 0x1F)) + 63))
            value >>= 5
        chars.append(chr(value + 63))
        return "".join(chars)

    for latitude, longitude in points:
        current_latitude = round(latitude * factor)
        current_longitude = round(longitude * factor)
        output.append(encode_delta(current_latitude - previous_latitude))
        output.append(encode_delta(current_longitude - previous_longitude))
        previous_latitude = current_latitude
        previous_longitude = current_longitude
    return "".join(output)


def _combine_encoded_shapes(
    shapes: list[str],
    precision: int,
) -> str:
    combined: list[tuple[float, float]] = []
    for shape in shapes:
        if not shape:
            continue
        points = decode_polyline(shape, precision)
        if combined and points and combined[-1] == points[0]:
            points = points[1:]
        combined.extend(points)
    if len(combined) < 2:
        raise ProviderFailure("Routing provider returned incomplete route geometry")
    return encode_polyline(combined, precision)


def _persian_valhalla_instruction(type_code: int, street_name: str) -> str:
    actions = {
        0: "به مسیر ادامه دهید",
        1: "حرکت را آغاز کنید",
        2: "از سمت راست حرکت را آغاز کنید",
        3: "از سمت چپ حرکت را آغاز کنید",
        4: "به مقصد رسیده‌اید",
        5: "از سمت راست به مقصد می‌رسید",
        6: "از سمت چپ به مقصد می‌رسید",
        7: "به مسیر مستقیم ادامه دهید",
        8: "به مسیر مستقیم ادامه دهید",
        9: "کمی به سمت راست متمایل شوید",
        10: "به راست بپیچید",
        11: "با زاویه تند به راست بپیچید",
        12: "دور بزنید و در جهت مخالف حرکت کنید",
        13: "دور بزنید و در جهت مخالف حرکت کنید",
        14: "با زاویه تند به چپ بپیچید",
        15: "به چپ بپیچید",
        16: "کمی به سمت چپ متمایل شوید",
        17: "از مسیر مستقیم وارد رمپ شوید",
        18: "از رمپ سمت راست وارد شوید",
        19: "از رمپ سمت چپ وارد شوید",
        20: "خروجی سمت راست را انتخاب کنید",
        21: "خروجی سمت چپ را انتخاب کنید",
        22: "به مسیر مستقیم ادامه دهید",
        23: "در سمت راست مسیر بمانید",
        24: "در سمت چپ مسیر بمانید",
        25: "به مسیر ادغام شوید",
        26: "وارد میدان شوید",
        27: "از میدان خارج شوید",
        28: "وارد مسیر کشتی شوید",
        29: "از مسیر کشتی خارج شوید",
        37: "از سمت راست به مسیر اصلی ادغام شوید",
        38: "از سمت چپ به مسیر اصلی ادغام شوید",
        39: "وارد آسانسور شوید",
        40: "از پله‌ها استفاده کنید",
        41: "از پله‌برقی استفاده کنید",
        42: "وارد ساختمان شوید",
        43: "از ساختمان خارج شوید",
        44: "به طبقه یا تراز دیگری بروید",
        45: "وسیله نقلیه را پارک کنید",
    }
    action = actions.get(type_code, "به مسیر ادامه دهید")
    street = street_name.strip()
    if type_code == 7 and street:
        return f"مسیر به {street} تبدیل می‌شود"
    streetless = {4, 5, 6, 28, 29, 39, 40, 41, 42, 43, 44, 45}
    if street and type_code not in streetless:
        return f"{action} و وارد {street} شوید"
    return action


class NeshanTrafficProvider:
    def __init__(self, api_key: str | None, endpoint: str = NESHAN_DIRECTION_URL):
        self.api_key = api_key
        self.endpoint = endpoint

    async def calculate(
        self,
        request: RouteRequest,
        client: httpx.AsyncClient,
    ) -> list[RouteOption]:
        if not self.api_key:
            raise ProviderNotConfigured("Neshan traffic routing is not configured")

        params: dict[str, str | int | bool] = {
            "type": request.travel_mode,
            "origin": f"{request.origin.latitude},{request.origin.longitude}",
            "destination": f"{request.destination.latitude},{request.destination.longitude}",
            "alternative": str(request.alternatives).lower(),
            "avoidTrafficZone": str(request.avoid_traffic_zone).lower(),
            "avoidOddEvenZone": str(request.avoid_odd_even_zone).lower(),
        }
        if request.waypoints:
            params["waypoints"] = "|".join(
                f"{point.latitude},{point.longitude}" for point in request.waypoints
            )
        if request.bearing is not None:
            params["bearing"] = request.bearing

        try:
            response = await client.get(
                self.endpoint,
                params=params,
                headers={"Api-Key": self.api_key, "Accept": "application/json"},
            )
        except httpx.TimeoutException as exc:
            raise ProviderFailure("Neshan routing request timed out") from exc
        except httpx.HTTPError as exc:
            raise ProviderFailure("Neshan routing service could not be reached") from exc

        if response.status_code in (481, 482):
            raise ProviderRateLimited("Neshan API quota or rate limit was exceeded")
        if response.status_code in (480, 483, 484):
            raise ProviderNotConfigured("Neshan API key is invalid or lacks permission")
        if response.status_code < 200 or response.status_code >= 300:
            raise ProviderFailure(f"Neshan routing returned HTTP {response.status_code}")

        try:
            payload = response.json()
        except ValueError as exc:
            raise ProviderFailure("Neshan returned invalid JSON") from exc

        raw_routes = payload.get("routes")
        if not isinstance(raw_routes, list) or not raw_routes:
            raise ProviderFailure("Neshan did not return a usable route")

        options: list[RouteOption] = []
        for route_index, raw_route in enumerate(raw_routes):
            raw_legs = raw_route.get("legs") or []
            overview = (raw_route.get("overview_polyline") or {}).get("points")
            if not raw_legs or not isinstance(overview, str) or not overview:
                raise ProviderFailure("Neshan route geometry or legs are missing")

            legs: list[RouteLeg] = []
            total_distance = 0.0
            total_duration = 0.0
            for raw_leg in raw_legs:
                distance = float((raw_leg.get("distance") or {}).get("value") or 0)
                duration = float((raw_leg.get("duration") or {}).get("value") or 0)
                total_distance += distance
                total_duration += duration
                steps: list[RouteManeuver] = []
                for raw_step in raw_leg.get("steps") or []:
                    step_distance = float((raw_step.get("distance") or {}).get("value") or 0)
                    step_duration = float((raw_step.get("duration") or {}).get("value") or 0)
                    step_geometry = raw_step.get("polyline")
                    steps.append(
                        RouteManeuver(
                            instruction=str(raw_step.get("instruction") or "به مسیر ادامه دهید"),
                            street_name=raw_step.get("name") or None,
                            type=raw_step.get("type"),
                            modifier=raw_step.get("modifier"),
                            distance_m=step_distance,
                            duration_s=step_duration,
                            geometry=(
                                EncodedGeometry(
                                    encoding="encoded-polyline",
                                    precision=5,
                                    value=step_geometry,
                                )
                                if isinstance(step_geometry, str) and step_geometry
                                else None
                            ),
                        )
                    )
                legs.append(
                    RouteLeg(
                        summary=raw_leg.get("summary") or None,
                        distance_m=distance,
                        duration_s=duration,
                        steps=steps,
                    )
                )

            options.append(
                RouteOption(
                    id=f"neshan-{route_index}",
                    provider="neshan",
                    traffic_aware=True,
                    fallback_used=False,
                    distance_m=total_distance,
                    duration_s=total_duration,
                    overview_geometry=EncodedGeometry(
                        encoding="encoded-polyline",
                        precision=5,
                        value=overview,
                    ),
                    legs=legs,
                )
            )
        return options


class ValhallaRoutingProvider:
    def __init__(self, endpoint: str = DEFAULT_VALHALLA_URL):
        self.endpoint = endpoint

    async def calculate(
        self,
        request: RouteRequest,
        client: httpx.AsyncClient,
    ) -> list[RouteOption]:
        costing_candidates = {
            "car": ["auto"],
            "motorcycle": ["motorcycle", "motor_scooter"],
            "walking": ["pedestrian"],
        }[request.travel_mode]
        locations = [request.origin, *request.waypoints, request.destination]
        last_error: Exception | None = None

        for candidate_index, costing in enumerate(costing_candidates):
            body = {
                "locations": [
                    {"lat": point.latitude, "lon": point.longitude}
                    for point in locations
                ],
                "costing": costing,
                "units": "kilometers",
                "language": "en-US",
                "shape_format": "polyline6",
                "directions_type": "instructions",
                "id": "iran-navigator-backend",
            }
            if request.bearing is not None:
                body["locations"][0]["heading"] = request.bearing
                body["locations"][0]["heading_tolerance"] = 60

            try:
                response = await client.post(
                    self.endpoint,
                    json=body,
                    headers={"Accept": "application/json"},
                )
            except httpx.TimeoutException as exc:
                last_error = ProviderFailure("Valhalla routing request timed out")
                if request.travel_mode != "motorcycle":
                    break
                continue
            except httpx.HTTPError as exc:
                last_error = ProviderFailure("Valhalla routing service could not be reached")
                if request.travel_mode != "motorcycle":
                    break
                continue

            if response.status_code < 200 or response.status_code >= 300:
                last_error = ProviderFailure(f"Valhalla returned HTTP {response.status_code}")
                if request.travel_mode != "motorcycle":
                    break
                continue

            try:
                payload = response.json()
            except ValueError as exc:
                last_error = ProviderFailure("Valhalla returned invalid JSON")
                if request.travel_mode != "motorcycle":
                    break
                continue

            trip = payload.get("trip") or {}
            raw_legs = trip.get("legs") or []
            if not raw_legs:
                last_error = ProviderFailure("Valhalla did not return a usable route")
                if request.travel_mode != "motorcycle":
                    break
                continue

            try:
                options = self._normalize_trip(raw_legs, candidate_index > 0)
            except (KeyError, TypeError, ValueError) as exc:
                last_error = ProviderFailure("Valhalla returned an invalid route geometry")
                if request.travel_mode != "motorcycle":
                    break
                continue
            return options

        if last_error:
            raise last_error
        raise ProviderFailure("Valhalla did not return a usable route")

    def _normalize_trip(
        self,
        raw_legs: list[dict],
        motorcycle_fallback: bool,
    ) -> list[RouteOption]:
        normalized_legs: list[RouteLeg] = []
        shapes: list[str] = []
        total_distance = 0.0
        total_duration = 0.0

        for raw_leg in raw_legs:
            shape = raw_leg.get("shape")
            if not isinstance(shape, str) or not shape:
                raise ValueError("Missing leg shape")
            shapes.append(shape)
            summary = raw_leg.get("summary") or {}
            distance = float(summary.get("length") or 0) * 1000
            duration = float(summary.get("time") or 0)
            total_distance += distance
            total_duration += duration

            maneuvers: list[RouteManeuver] = []
            for raw_maneuver in raw_leg.get("maneuvers") or []:
                type_code = int(raw_maneuver.get("type") or 0)
                street_names = raw_maneuver.get("street_names") or []
                street_name = "، ".join(str(name) for name in street_names if name)
                maneuver_distance = float(raw_maneuver.get("length") or 0) * 1000
                maneuver_duration = float(raw_maneuver.get("time") or 0)
                maneuvers.append(
                    RouteManeuver(
                        instruction=_persian_valhalla_instruction(type_code, street_name),
                        street_name=street_name or None,
                        type=str(type_code),
                        end_shape_index=raw_maneuver.get("end_shape_index"),
                        distance_m=maneuver_distance,
                        duration_s=maneuver_duration,
                    )
                )

            normalized_legs.append(
                RouteLeg(
                    summary=summary.get("name") or None,
                    distance_m=distance,
                    duration_s=duration,
                    geometry=EncodedGeometry(
                        encoding="polyline6",
                        precision=6,
                        value=shape,
                    ),
                    steps=maneuvers,
                )
            )

        overview = _combine_encoded_shapes(shapes, precision=6)
        fallback_reason = (
            "The motorcycle profile was unavailable; motor_scooter was used."
            if motorcycle_fallback
            else None
        )
        return [
            RouteOption(
                id="valhalla-0",
                provider="valhalla",
                traffic_aware=False,
                fallback_used=motorcycle_fallback,
                fallback_reason=fallback_reason,
                distance_m=total_distance,
                duration_s=total_duration,
                overview_geometry=EncodedGeometry(
                    encoding="polyline6",
                    precision=6,
                    value=overview,
                ),
                legs=normalized_legs,
            )
        ]


class RoutingService:
    def __init__(
        self,
        neshan_provider: NeshanTrafficProvider,
        valhalla_provider: ValhallaRoutingProvider,
    ):
        self.neshan_provider = neshan_provider
        self.valhalla_provider = valhalla_provider

    async def calculate(
        self,
        request: RouteRequest,
        client: httpx.AsyncClient,
    ) -> RouteResponse:
        now = datetime.now(timezone.utc)

        if request.traffic_preference == "live" and request.travel_mode in ("car", "motorcycle"):
            try:
                options = await self.neshan_provider.calculate(request, client)
                return RouteResponse(
                    options=options,
                    requested_traffic_preference=request.traffic_preference,
                    generated_at=now,
                )
            except (ProviderNotConfigured, ProviderRateLimited, ProviderFailure) as exc:
                if not request.allow_non_traffic_fallback:
                    raise
                if request.avoid_traffic_zone or request.avoid_odd_even_zone:
                    raise ProviderFailure(
                        "Cannot fall back to a non-traffic provider while traffic-zone avoidance is required."
                    ) from exc
                options = await self.valhalla_provider.calculate(request, client)
                options = [
                    option.model_copy(
                        update={
                            "fallback_used": True,
                            "fallback_reason": str(exc),
                        }
                    )
                    for option in options
                ]
                return RouteResponse(
                    options=options,
                    requested_traffic_preference=request.traffic_preference,
                    generated_at=now,
                )

        options = await self.valhalla_provider.calculate(request, client)
        if request.traffic_preference == "live":
            options = [
                option.model_copy(
                    update={
                        "fallback_used": True,
                        "fallback_reason": "Live traffic routing is not available for walking."
                    }
                )
                for option in options
            ]
        return RouteResponse(
            options=options,
            requested_traffic_preference=request.traffic_preference,
            generated_at=now,
        )


def build_routing_service() -> RoutingService:
    return RoutingService(
        neshan_provider=NeshanTrafficProvider(
            api_key=os.getenv("NESHAN_API_KEY"),
        ),
        valhalla_provider=ValhallaRoutingProvider(
            endpoint=os.getenv("VALHALLA_ROUTE_URL", DEFAULT_VALHALLA_URL),
        ),
    )


@router.post("/routes", response_model=RouteResponse)
async def calculate_route(request: RouteRequest) -> RouteResponse:
    timeout = httpx.Timeout(20.0, connect=5.0)
    async with httpx.AsyncClient(timeout=timeout) as client:
        service = build_routing_service()
        try:
            return await service.calculate(request, client)
        except ProviderNotConfigured as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except ProviderRateLimited as exc:
            raise HTTPException(status_code=429, detail=str(exc)) from exc
        except ProviderFailure as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
