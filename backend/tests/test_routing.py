import unittest

import httpx

from app.routing import (
    NeshanTrafficProvider,
    ProviderNotConfigured,
    RouteRequest,
    RoutingService,
    ValhallaRoutingProvider,
    decode_polyline,
    encode_polyline,
)


class RoutingProviderTests(unittest.IsolatedAsyncioTestCase):
    def test_neshan_documented_polyline_example_uses_precision_five(self):
        points = decode_polyline("kz{xEggtxHHBRAPGPMJSDS", precision=5)
        self.assertGreaterEqual(len(points), 2)
        self.assertAlmostEqual(points[0][0], 35.701021, places=4)
        self.assertAlmostEqual(points[0][1], 51.390755, places=4)

    async def test_neshan_provider_normalizes_live_route_and_keeps_key_server_side(self):
        captured = {}

        def handler(request: httpx.Request) -> httpx.Response:
            captured["url"] = request.url
            captured["api_key"] = request.headers.get("Api-Key")
            return httpx.Response(
                200,
                json={
                    "routes": [
                        {
                            "overview_polyline": {"points": "kz{xEggtxHHBRAPGPMJSDS"},
                            "legs": [
                                {
                                    "summary": "ولیعصر",
                                    "distance": {"value": 1000, "text": "۱ کیلومتر"},
                                    "duration": {"value": 120, "text": "۲ دقیقه"},
                                    "steps": [
                                        {
                                            "name": "ولیعصر",
                                            "instruction": "به چپ بپیچید و وارد ولیعصر شوید",
                                            "type": "turn",
                                            "modifier": "left",
                                            "distance": {"value": 100, "text": "۱۰۰ متر"},
                                            "duration": {"value": 30, "text": "کمتر از ۱ دقیقه"},
                                            "polyline": "kz{xEggtxHHBRAPGPMJSDS",
                                        }
                                    ],
                                }
                            ],
                        }
                    ]
                },
            )

        transport = httpx.MockTransport(handler)
        async with httpx.AsyncClient(transport=transport) as client:
            provider = NeshanTrafficProvider(
                api_key="test-secret",
                endpoint="https://api.neshan.org/v4/direction",
            )
            request = RouteRequest(
                origin={"latitude": 35.70, "longitude": 51.40},
                destination={"latitude": 35.71, "longitude": 51.39},
                waypoints=[{"latitude": 35.705, "longitude": 51.395}],
                travel_mode="car",
                traffic_preference="live",
                alternatives=True,
                avoid_traffic_zone=True,
            )
            routes = await provider.calculate(request, client)

        self.assertEqual(captured["api_key"], "test-secret")
        self.assertEqual(captured["url"].params["type"], "car")
        self.assertEqual(captured["url"].params["avoidTrafficZone"], "true")
        self.assertEqual(captured["url"].params["alternative"], "true")
        self.assertIn("|", captured["url"].params["waypoints"])
        self.assertEqual(len(routes), 1)
        self.assertEqual(routes[0].provider, "neshan")
        self.assertTrue(routes[0].traffic_aware)
        self.assertFalse(routes[0].fallback_used)
        self.assertEqual(routes[0].distance_m, 1000)
        self.assertEqual(routes[0].overview_geometry.precision, 5)
        self.assertEqual(routes[0].legs[0].steps[0].instruction, "به چپ بپیچید و وارد ولیعصر شوید")

    async def test_live_traffic_requires_configured_neshan_key(self):
        provider = NeshanTrafficProvider(api_key=None)
        request = RouteRequest(
            origin={"latitude": 35.70, "longitude": 51.40},
            destination={"latitude": 35.71, "longitude": 51.39},
            travel_mode="car",
            traffic_preference="live",
        )
        async with httpx.AsyncClient() as client:
            with self.assertRaises(ProviderNotConfigured):
                await provider.calculate(request, client)

    async def test_valhalla_fallback_is_explicit_and_never_claimed_as_live_traffic(self):
        shape = encode_polyline(
            [(35.7000, 51.4000), (35.7050, 51.3950), (35.7100, 51.3900)],
            precision=6,
        )

        def handler(request: httpx.Request) -> httpx.Response:
            if request.url.host == "api.neshan.org":
                return httpx.Response(503, json={"error": "temporarily unavailable"})
            return httpx.Response(
                200,
                json={
                    "trip": {
                        "legs": [
                            {
                                "shape": shape,
                                "summary": {"length": 1.2, "time": 180},
                                "maneuvers": [
                                    {
                                        "type": 10,
                                        "street_names": ["ولیعصر"],
                                        "length": 0.5,
                                        "time": 60,
                                        "end_shape_index": 1,
                                    }
                                ],
                            }
                        ]
                    }
                },
            )

        transport = httpx.MockTransport(handler)
        async with httpx.AsyncClient(transport=transport) as client:
            service = RoutingService(
                neshan_provider=NeshanTrafficProvider("test-secret"),
                valhalla_provider=ValhallaRoutingProvider("https://valhalla.test/route"),
            )
            request = RouteRequest(
                origin={"latitude": 35.70, "longitude": 51.40},
                destination={"latitude": 35.71, "longitude": 51.39},
                travel_mode="car",
                traffic_preference="live",
                allow_non_traffic_fallback=True,
            )
            response = await service.calculate(request, client)

        self.assertEqual(len(response.options), 1)
        option = response.options[0]
        self.assertEqual(option.provider, "valhalla")
        self.assertFalse(option.traffic_aware)
        self.assertTrue(option.fallback_used)
        self.assertTrue(option.fallback_reason)
        self.assertEqual(option.overview_geometry.encoding, "polyline6")
        self.assertEqual(option.legs[0].steps[0].instruction, "به راست بپیچید و وارد ولیعصر شوید")

    async def test_live_walking_route_is_rejected_without_fallback_consent(self):
        service = RoutingService(
            neshan_provider=NeshanTrafficProvider("test-secret"),
            valhalla_provider=ValhallaRoutingProvider("https://valhalla.test/route"),
        )
        request = RouteRequest(
            origin={"latitude": 35.70, "longitude": 51.40},
            destination={"latitude": 35.71, "longitude": 51.39},
            travel_mode="walking",
            traffic_preference="live",
            allow_non_traffic_fallback=False,
        )
        async with httpx.AsyncClient() as client:
            with self.assertRaises(ProviderNotConfigured):
                await service.calculate(request, client)

    async def test_live_walking_route_requires_explicit_non_traffic_fallback(self):
        shape = encode_polyline(
            [(35.7000, 51.4000), (35.7100, 51.3900)],
            precision=6,
        )

        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(
                200,
                json={
                    "trip": {
                        "legs": [
                            {
                                "shape": shape,
                                "summary": {"length": 1.0, "time": 600},
                                "maneuvers": [],
                            }
                        ]
                    }
                },
            )

        transport = httpx.MockTransport(handler)
        async with httpx.AsyncClient(transport=transport) as client:
            service = RoutingService(
                neshan_provider=NeshanTrafficProvider("test-secret"),
                valhalla_provider=ValhallaRoutingProvider("https://valhalla.test/route"),
            )
            request = RouteRequest(
                origin={"latitude": 35.70, "longitude": 51.40},
                destination={"latitude": 35.71, "longitude": 51.39},
                travel_mode="walking",
                traffic_preference="live",
                allow_non_traffic_fallback=True,
            )
            response = await service.calculate(request, client)

        self.assertFalse(response.options[0].traffic_aware)
        self.assertTrue(response.options[0].fallback_used)
        self.assertIn("not available for walking", response.options[0].fallback_reason)


if __name__ == "__main__":
    unittest.main()
