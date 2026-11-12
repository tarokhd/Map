import test from "node:test";
import assert from "node:assert/strict";
import {
  solarPosition,
  classifyEnvironment,
  worldPalette,
  mixColor,
} from "../environment.mjs";
import {
  distance,
  bearing,
  angleDelta,
  decodePolyline6,
  measureRoute,
  pointAt,
  matchRoute,
  normalizeTrip,
  usablePosition,
  calculateRoutes,
} from "../navigation.mjs";
function encode(points) {
  let lat = 0,
    lon = 0,
    text = "";
  for (const point of points) {
    for (let delta of [
      Math.round(point[1] * 1e6) - lat,
      Math.round(point[0] * 1e6) - lon,
    ]) {
      delta = delta < 0 ? ~(delta << 1) : delta << 1;
      while (delta >= 32) {
        text += String.fromCharCode((32 | (delta & 31)) + 63);
        delta >>>= 5;
      }
      text += String.fromCharCode(delta + 63);
    }
    lat = Math.round(point[1] * 1e6);
    lon = Math.round(point[0] * 1e6);
  }
  return text;
}
const points = [
  [51.4, 35.7],
  [51.4, 35.71],
  [51.41, 35.71],
];
const route = { points, cumulative: measureRoute(points) };
test("solar noon follows coordinates and date, rather than device clock labels", () => {
  const date = new Date("2026-03-20T12:00:00Z");
  assert.ok(solarPosition(date, 0, 0).elevation > 85);
  assert.ok(solarPosition(date, 0, 180).elevation < -85);
  const iran = solarPosition(new Date("2026-11-12T08:30:00Z"), 35.7, 51.4);
  assert.ok(iran.elevation > 30 && iran.elevation < 45);
  assert.ok(
    solarPosition(new Date("2026-11-12T20:30:00Z"), 35.7, 51.4).elevation < -30,
  );
});
test("biomes require actual local landcover evidence; urban form is independent", () => {
  const f = (sourceLayer, properties) => ({ sourceLayer, properties });
  assert.equal(classifyEnvironment([]).biome, "neutral");
  assert.equal(
    classifyEnvironment([f("landcover", { class: "wood" })]).biome,
    "forest",
  );
  assert.equal(
    classifyEnvironment([f("landcover", { class: "sand" })]).biome,
    "desert",
  );
  assert.equal(
    classifyEnvironment([f("water", { class: "ocean" })]).biome,
    "coast",
  );
  assert.equal(
    classifyEnvironment([f("landcover", { class: "rock" })]).biome,
    "mountain",
  );
  assert.equal(
    classifyEnvironment([f("landuse", { class: "farmland" })]).biome,
    "farmland",
  );
  const mixed = classifyEnvironment([
    f("landcover", { class: "wood" }),
    ...Array.from({ length: 4 }, () => f("building", { render_height: 60 })),
  ]);
  assert.equal(mixed.biome, "forest");
  assert.equal(mixed.urbanForm, "مرتفع");
});
test("world colors transition continuously at twilight and remain distinct across biomes", () => {
  const a = worldPalette("urban", -6),
    b = worldPalette("urban", -5.9);
  assert.ok(Math.abs(a.daylight - b.daylight) < 0.01);
  assert.notEqual(
    worldPalette("forest", 40).ground,
    worldPalette("desert", 40).ground,
  );
  assert.notEqual(
    worldPalette("urban", -18).building,
    worldPalette("urban", 55).building,
  );
  assert.equal(mixColor("#000000", "#ffffff", 0.5), "#808080");
});
test("polyline6 preserves lon/lat order and rejects truncated or invalid geometry", () => {
  assert.deepEqual(decodePolyline6(encode(points)), points);
  assert.throws(() => decodePolyline6("_"));
  assert.throws(() => decodePolyline6(""));
  assert.throws(() => decodePolyline6("~~~~~~~~~~~~"));
});
test("route sampling and matching use meters, including projection between vertices", () => {
  assert.ok(distance(points[0], points[1]) > 1100);
  assert.ok(Math.abs(bearing(points[0], points[1])) < 0.01);
  assert.equal(angleDelta(359, 1), 2);
  const mid = pointAt(route, route.cumulative[1] / 2);
  assert.ok(Math.abs(mid[1] - 35.705) < 0.00001);
  const match = matchRoute(route, [51.40001, 35.705]);
  assert.ok(
    match.offRoute < 2 &&
      match.distanceAlongRoute > 550 &&
      match.distanceAlongRoute < 565,
  );
  assert.deepEqual(pointAt(route, 1e8), points.at(-1));
});
test("multi-leg normalization joins geometry and offsets later maneuver indices", () => {
  const trip = {
    legs: [
      {
        shape: encode(points.slice(0, 2)),
        summary: { length: 1.1, time: 100 },
        maneuvers: [{ type: 10, end_shape_index: 1 }],
      },
      {
        shape: encode(points.slice(1)),
        summary: { length: 0.9, time: 80 },
        maneuvers: [{ type: 15, end_shape_index: 1 }],
      },
    ],
  };
  const result = normalizeTrip(trip);
  assert.deepEqual(result.points, points);
  assert.equal(result.maneuvers[1].endIndex, 2);
  assert.equal(result.duration, 180);
  assert.equal(result.distance, 2000);
});
test("stale and inaccurate GPS observations cannot move the navigation camera", () => {
  const now = Date.now();
  const p = {
    timestamp: now,
    coords: { latitude: 35.7, longitude: 51.4, accuracy: 10 },
  };
  assert.equal(usablePosition(p, now), true);
  assert.equal(usablePosition({ ...p, timestamp: now - 20000 }, now), false);
  assert.equal(
    usablePosition({ ...p, coords: { ...p.coords, accuracy: 150 } }, now),
    false,
  );
  assert.equal(
    usablePosition({ ...p, coords: { ...p.coords, latitude: 180 } }, now),
    false,
  );
});
test("motorcycle fallback is explicit and an aborted request cannot fall through to another profile", async () => {
  const original = globalThis.fetch;
  const costings = [];
  try {
    globalThis.fetch = async (_, options) => {
      const c = JSON.parse(options.body).costing;
      costings.push(c);
      return c === "motorcycle"
        ? new Response("{}", { status: 400 })
        : new Response(
            JSON.stringify({
              trip: {
                legs: [
                  { shape: encode(points), summary: { length: 2, time: 80 } },
                ],
              },
            }),
          );
    };
    const result = await calculateRoutes(
      points[0],
      points.at(-1),
      "motorcycle",
    );
    assert.deepEqual(costings, ["motorcycle", "motor_scooter"]);
    assert.equal(result[0].fallback, true);
    const controller = new AbortController();
    controller.abort();
    costings.length = 0;
    globalThis.fetch = async (_, options) => {
      costings.push("attempt");
      options.signal.throwIfAborted();
    };
    await assert.rejects(
      calculateRoutes(
        points[0],
        points.at(-1),
        "motorcycle",
        controller.signal,
      ),
    );
    assert.equal(costings.length, 1);
  } finally {
    globalThis.fetch = original;
  }
});

test("invalid provider summaries and disconnected legs never create a usable route", () => {
  assert.throws(() =>
    normalizeTrip({
      legs: [{ shape: encode(points), summary: { length: 0, time: 0 } }],
    }),
  );
  assert.throws(() =>
    normalizeTrip({
      legs: [
        { shape: encode(points.slice(0, 2)), summary: { length: 1, time: 60 } },
        {
          shape: encode([
            [52, 36],
            [52.01, 36.01],
          ]),
          summary: { length: 1, time: 60 },
        },
      ],
    }),
  );
});
