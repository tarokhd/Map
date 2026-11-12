const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const APP = process.env.APP_URL || "http://127.0.0.1:4173/";
const ORIGIN = [51.405, 35.7006],
  DESTINATION = [51.417, 35.719];
const points = [
  ORIGIN,
  [51.405, 35.702],
  [51.405, 35.705],
  [51.408, 35.705],
  [51.412, 35.705],
  [51.412, 35.71],
  [51.417, 35.71],
  DESTINATION,
];
function encode(points) {
  let lat = 0,
    lon = 0,
    text = "";
  for (const p of points) {
    for (let n of [
      Math.round(p[1] * 1e6) - lat,
      Math.round(p[0] * 1e6) - lon,
    ]) {
      n = n < 0 ? ~(n << 1) : n << 1;
      while (n >= 32) {
        text += String.fromCharCode((32 | (n & 31)) + 63);
        n >>>= 5;
      }
      text += String.fromCharCode(n + 63);
    }
    lat = Math.round(p[1] * 1e6);
    lon = Math.round(p[0] * 1e6);
  }
  return text;
}
function trip(time = 600) {
  return {
    summary: { length: 3.5, time },
    legs: [
      {
        shape: encode(points),
        summary: { length: 3.5, time },
        maneuvers: [
          { type: 1, street_names: ["ولیعصر"], end_shape_index: 2 },
          { type: 10, street_names: ["انقلاب"], end_shape_index: 4 },
          { type: 15, street_names: ["مقصد"], end_shape_index: 7 },
        ],
      },
    ],
  };
}
async function captureMap(page) {
  await page.addInitScript(() => {
    let lib;
    window.mapErrors = [];
    Object.defineProperty(window, "maplibregl", {
      configurable: true,
      get: () => lib,
      set(v) {
        lib = v;
        const M = v.Map;
        v.Map = class extends M {
          constructor(o) {
            super(o);
            window.smokeMap = this;
            this.on("error", (e) =>
              mapErrors.push(e.error?.message || "Map error"),
            );
          }
        };
      },
    });
  });
}
async function services(page, failSearch = false) {
  const costings = [];
  let failures = failSearch ? 1 : 0;
  await page.route("https://photon.komoot.io/api/**", (r) => {
    if (failures-- > 0) return r.fulfill({ status: 503, body: "unavailable" });
    const origin = new URL(r.request().url()).searchParams
      .get("q")
      .includes("مبدأ");
    return r.fulfill({
      contentType: "application/json",
      body: JSON.stringify({
        features: [
          {
            type: "Feature",
            geometry: {
              type: "Point",
              coordinates: origin ? ORIGIN : DESTINATION,
            },
            properties: {
              name: origin ? "مبدأ آزمایشی" : "موزه هنرهای معاصر",
              city: "تهران",
              country: "ایران",
            },
          },
        ],
      }),
    });
  });
  await page.route("https://valhalla1.openstreetmap.de/route", (r) => {
    const b = r.request().postDataJSON();
    costings.push(b.costing);
    assert.equal(b.shape_format, "polyline6");
    if (b.costing === "motorcycle")
      return r.fulfill({
        status: 400,
        contentType: "application/json",
        body: '{"error":"profile unavailable"}',
      });
    const time = b.costing === "pedestrian" ? 2400 : 600;
    return r.fulfill({
      contentType: "application/json",
      body: JSON.stringify({
        trip: trip(time),
        alternates: [{ trip: trip(time + 120) }],
      }),
    });
  });
  return costings;
}
async function ready(p) {
  await p.waitForFunction(
    () => document.querySelector("#mapMessage").hidden,
    null,
    { timeout: 60000 },
  );
  await p.waitForFunction(() => smokeMap.loaded());
}
async function searchPlace(p, q) {
  await p.locator("#searchInput").fill(q);
  await p.locator("#searchInput").press("Enter");
  await p.locator(".search-result").first().waitFor();
  await p.locator(".search-result").first().click();
}
async function routeReady(p) {
  await p.waitForFunction(
    () => !document.querySelector("#previewRoute").disabled,
  );
}
(async () => {
  const browser = await chromium.launch({
    headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
  });
  try {
    const p = await browser.newPage({
      viewport: { width: 1440, height: 1000 },
      geolocation: { longitude: ORIGIN[0], latitude: ORIGIN[1], accuracy: 8 },
      permissions: ["geolocation"],
    });
    const errors = [];
    p.on("pageerror", (e) => errors.push(e.message));
    await captureMap(p);
    const costings = await services(p, true);
    await p.goto(APP, { waitUntil: "domcontentloaded" });
    await ready(p);
    assert.equal(await p.locator("#homeDock").isVisible(), true);
    assert.equal(await p.locator("#travelModes").isVisible(), false);
    const initial = await p.evaluate(() => ({
      rtl: maplibregl.getRTLTextPluginStatus(),
      buildings: smokeMap.queryRenderedFeatures({ layers: ["world-buildings"] })
        .length,
      sources: Object.values(smokeMap.getStyle().sources).filter(
        (s) => s.type === "vector",
      ).length,
    }));
    assert.equal(initial.rtl, "loaded");
    assert.ok(initial.buildings > 0);
    assert.equal(initial.sources, 1);
    await p.screenshot({ path: "iran-navigator-web-smoke.png" });
    await p.setViewportSize({ width: 390, height: 844 });
    await p.waitForFunction(() => smokeMap.loaded());
    assert.equal(
      await p.evaluate(() => document.documentElement.scrollWidth > innerWidth),
      false,
    );
    await p.screenshot({ path: "iran-navigator-web-mobile-smoke.png" });
    await p.setViewportSize({ width: 1440, height: 1000 });
    console.log(
      "PASS: Minimal home, real vector map/buildings, RTL and mobile layout.",
    );
    await p.locator("#openSearch").click();
    await p.locator("#searchInput").fill("موزه");
    await p.locator("#searchInput").press("Enter");
    await p.waitForFunction(() =>
      document
        .querySelector("#searchStatus")
        .textContent.includes("دسترس نیست"),
    );
    assert.equal(await p.locator(".search-result").count(), 0);
    await searchPlace(p, "موزه");
    await routeReady(p);
    assert.equal(await p.locator("#homeDock").isVisible(), false);
    assert.equal(await p.locator("#travelModes").isVisible(), true);
    assert.equal(
      await p.locator("#changeOrigin").textContent(),
      "موقعیت فعلی من",
    );
    assert.equal(await p.locator("[data-route]").count(), 2);
    console.log(
      "PASS: Search failure recovery, destination-first travel options, GPS origin and alternatives.",
    );
    await p.locator("#openAppearance").click();
    await p.locator('[data-biome="forest"]').click();
    await p.locator('[data-light="night"]').click();
    await p.waitForFunction(
      () =>
        document
          .querySelector("#environmentLabel")
          .textContent.includes("جنگلی") &&
        document.querySelector("#environmentLabel").textContent.includes("شب"),
    );
    await p.waitForTimeout(2500);
    const night = await p.evaluate(() =>
      smokeMap.getPaintProperty("world-buildings", "fill-extrusion-color"),
    );
    await p.locator('[data-light="noon"]').click();
    await p.waitForTimeout(2500);
    assert.notEqual(
      await p.evaluate(() =>
        smokeMap.getPaintProperty("world-buildings", "fill-extrusion-color"),
      ),
      night,
    );
    await p.locator('[data-light="night"]').click();
    await p.locator("#closeAppearance").click();
    await p.locator("#previewRoute").click();
    await p.waitForFunction(
      () =>
        document.body.dataset.screen === "preview" && smokeMap.getPitch() > 70,
    );
    assert.ok(
      (await p.locator("#navigationBadge").textContent()).includes("شبیه‌سازی"),
    );
    await p.waitForFunction(async () => {
      const { state } = await import("./app.mjs");
      return state.demoDistance > 10;
    });
    assert.ok(
      (await p.locator("#cockpit").getAttribute("src")).endsWith("/car.svg"),
    );
    assert.equal(
      await p.evaluate(() =>
        smokeMap.getLayoutProperty("world-places", "visibility"),
      ),
      "none",
    );
    await p.screenshot({ path: "iran-navigator-first-person.png" });
    await p.locator("#stopNavigation").click();
    console.log(
      "PASS: Biome/noon/night transitions, labeled first-person preview and local car asset.",
    );
    await p.locator('[data-mode="motorcycle"]').click();
    await routeReady(p);
    assert.ok(
      costings.includes("motorcycle") && costings.includes("motor_scooter"),
    );
    assert.ok(
      (await p.locator("#routeStatus").textContent()).includes("جایگزین"),
    );
    await p.locator("#previewRoute").click();
    assert.ok(
      (await p.locator("#cockpit").getAttribute("src")).endsWith(
        "/motorcycle.svg",
      ),
    );
    await p.locator("#stopNavigation").click();
    await p.locator('[data-mode="walking"]').click();
    await routeReady(p);
    assert.ok(costings.includes("pedestrian"));
    await p.locator("#previewRoute").click();
    assert.ok(
      (await p.locator("#cockpit").getAttribute("src")).endsWith(
        "/walking.svg",
      ),
    );
    await p.locator("#navigationAppearance").click();
    await p.locator("#cockpitToggle").uncheck();
    assert.equal(await p.locator("#cockpit").isVisible(), false);
    await p.locator("#closeAppearance").click();
    await p.locator("#stopNavigation").click();
    await p.locator('[data-mode="car"]').click();
    await routeReady(p);
    await p.locator("#startNavigation").click();
    await p.waitForFunction(
      () =>
        document.body.dataset.screen === "navigation" &&
        document.querySelector("#navigationStatus").textContent.includes("GPS"),
    );
    await p
      .context()
      .setGeolocation({ longitude: 51.405, latitude: 35.7015, accuracy: 8 });
    await p.waitForFunction(async () => {
      const { state } = await import("./app.mjs");
      return state.distanceAlongRoute > 70;
    });
    await p.locator("#stopNavigation").click();
    assert.equal(await p.locator("#journeySheet").isVisible(), true);
    console.log(
      "PASS: Motorcycle fallback, walking mode, optional cockpit and live GPS navigation.",
    );
    await p.evaluate(async () => {
      await navigator.serviceWorker.ready;
    });
    const cached = await p.evaluate(async () => {
      const c = await caches.open("navigator-world-v1");
      return (await c.keys()).map((r) => new URL(r.url).pathname);
    });
    assert.ok(
      cached.some((x) => x.endsWith("/assets/car.svg")) &&
        cached.some((x) => x.endsWith("/environment.mjs")),
    );
    await p.context().setOffline(true);
    const offline = await p.evaluate(async () => {
      const r = await fetch("./assets/car.svg?offline-check");
      return r.ok && (await r.text()).includes("<svg");
    });
    await p.context().setOffline(false);
    assert.equal(offline, true);
    assert.deepEqual(await p.evaluate(() => mapErrors), []);
    assert.deepEqual(errors, []);
    console.log(
      "PASS: Cached visual assets work offline; no page or map-worker errors.",
    );
    const denied = await browser.newPage({
      viewport: { width: 390, height: 844 },
      permissions: [],
    });
    await captureMap(denied);
    await services(denied);
    await denied.addInitScript(() => {
      navigator.geolocation.getCurrentPosition = (_, reject) =>
        reject({ code: 1 });
    });
    await denied.goto(APP, { waitUntil: "domcontentloaded" });
    await ready(denied);
    await denied.locator("#openSearch").click();
    await searchPlace(denied, "موزه");
    await denied.waitForFunction(() =>
      document
        .querySelector("#routeStatus")
        .textContent.includes("اجازه موقعیت"),
    );
    assert.equal(await denied.locator("#startNavigation").isDisabled(), true);
    await denied.locator("#changeOrigin").click();
    await searchPlace(denied, "مبدأ");
    await routeReady(denied);
    assert.equal(
      await denied.locator("#changeOrigin").textContent(),
      "مبدأ آزمایشی",
    );
    await denied.close();
    console.log(
      "PASS: Denied GPS uses an explicit manual origin, with no invented position.",
    );
    await p.locator("#clearDestination").click();
    await p.route("https://tiles.openfreemap.org/styles/positron", (r) =>
      r.fulfill({ status: 503, body: "unavailable" }),
    );
    await p.reload({ waitUntil: "domcontentloaded" });
    await p.locator("#retryMap").waitFor({ state: "visible" });
    await p.unroute("https://tiles.openfreemap.org/styles/positron");
    await p.locator("#retryMap").click();
    await ready(p);
    console.log("PASS: Map style failure recovers after Retry.");
    const stalled = await browser.newPage({
      viewport: { width: 390, height: 844 },
    });
    await captureMap(stalled);
    let pluginRequests = 0;
    await stalled.route("**/@mapbox/mapbox-gl-rtl-text@0.3.0/**", (route) => {
      pluginRequests++;
      if (pluginRequests > 1) return route.fallback();
    });
    await stalled.clock.install();
    await stalled.goto(APP, { waitUntil: "domcontentloaded" });
    await stalled.waitForFunction(
      () => maplibregl.getRTLTextPluginStatus() === "loading",
    );
    await stalled.clock.fastForward(21000);
    await stalled.locator("#retryMap").waitFor({ state: "visible" });
    await stalled.clock.resume();
    await Promise.all([
      stalled.waitForEvent("domcontentloaded"),
      stalled.locator("#retryMap").click(),
    ]);
    await ready(stalled);
    assert.ok(pluginRequests >= 2);
    assert.deepEqual(await stalled.evaluate(() => mapErrors), []);
    await stalled.close();
    console.log(
      "PASS: A stalled RTL download restarts and recovers after Retry.",
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
