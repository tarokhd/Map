const { chromium } = require("playwright");

(async () => {
  const browser = await chromium.launch({
    headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage"]
  });

  try {
    const page = await browser.newPage({
      viewport: { width: 1440, height: 1000 },
      deviceScaleFactor: 1
    });
    const pageErrors = [];
    page.on("pageerror", error => pageErrors.push(error.message));
    // Capture the real map without adding a test API to the application.
    await page.addInitScript(() => {
      let library;
      Object.defineProperty(window, "maplibregl", {
        configurable: true,
        get: () => library,
        set(value) {
          library = value;
          const Map = value.Map;
          value.Map = class extends Map {
            constructor(options) {
              super(options);
              window.smokeMap = this;
              window.smokeMapErrors = [];
              this.on("error", event => window.smokeMapErrors.push(event.error?.message || "Unknown map error"));
            }
          };
        }
      });
    });

    const darkStyleUrl = "https://tiles.openfreemap.org/styles/dark";
    await page.route(darkStyleUrl, route => route.fulfill({status: 503, body: "Unavailable"}));
    await page.goto(process.env.APP_URL || "http://127.0.0.1:4173/", {
      waitUntil: "domcontentloaded",
      timeout: 30000
    });
    await page.locator("#retryMap").waitFor({state: "visible"});
    await page.unroute(darkStyleUrl);
    await page.locator("#retryMap").click();

    await page.waitForFunction(() => {
      const status = document.querySelector("#connectionStatus");
      return status && status.textContent.trim() === "نقشه آماده است";
    }, null, { timeout: 60000 });

    const initialMap = await page.evaluate(() => {
      const map = window.smokeMap;
      const layers = map.getStyle().layers;
      return {
        readyMs: Math.round(performance.now()),
        rtl: maplibregl.getRTLTextPluginStatus(),
        vectorSources: Object.values(map.getStyle().sources).filter(source => source.type === "vector").length,
        background: map.getPaintProperty("background", "background-color"),
        loadingHidden: document.querySelector("#mapLoading").hidden,
        bilingualNames: layers.filter(layer => layer.type === "symbol" && layer.layout?.["text-field"])
          .some(layer => {
            const field = layer.layout["text-field"];
            const expression = JSON.stringify(field);
            return field[0] === "concat" && expression.includes('"name:fa"') &&
              /name:latin|name_en|name:en/.test(expression) && expression.includes('\\n');
          }),
        extrusionAboveFill: layers.findIndex(layer => layer.id === "iran-buildings-3d") >
          layers.findIndex(layer => layer.id === "building"),
        buildings: map.queryRenderedFeatures({layers: ["iran-buildings-3d"]}).length,
        hiddenBuildings: map.queryRenderedFeatures({layers: ["iran-buildings-3d"]})
          .filter(feature => [true, 1, "true", "1"].includes(feature.properties.hide_3d)).length
      };
    });
    if (initialMap.rtl !== "loaded" || !initialMap.bilingualNames || initialMap.vectorSources !== 1 ||
        initialMap.background !== "#303438" || !initialMap.loadingHidden ||
        !initialMap.extrusionAboveFill || !initialMap.buildings || initialMap.hiddenBuildings) {
      throw new Error("Map language, theme or building regression: " + JSON.stringify(initialMap));
    }

    const canvas = page.locator("#map canvas").first();
    await canvas.waitFor({ state: "visible", timeout: 15000 });
    const bounds = await canvas.boundingBox();
    if (!bounds || bounds.width < 300 || bounds.height < 300) {
      throw new Error("Map canvas is not visible at a usable size.");
    }

    // Use a real rendered shop from the live vector tiles, not a synthetic fixture.
    await page.waitForFunction(() => window.smokeMap.getLayer("iran-places") &&
      window.smokeMap.queryRenderedFeatures({layers: ["iran-places"]}).length > 0, null, {timeout: 60000});
    const originalCamera = await page.evaluate(() => {
      const map = window.smokeMap;
      const camera = {center: map.getCenter().toArray(), zoom: map.getZoom(), pitch: map.getPitch(), bearing: map.getBearing()};
      const place = map.queryRenderedFeatures({layers: ["iran-places"]})
        .find(feature => feature.geometry.type === "Point");
      if (!place) throw new Error("No point geometry for a rendered business.");
      map.jumpTo({center: place.geometry.coordinates, zoom: Math.max(map.getZoom(), 16.2), pitch: 0});
      return camera;
    });
    await page.waitForFunction(() => window.smokeMap.loaded());
    const placePoint = await page.evaluate(() => {
      const map = window.smokeMap;
      const center = map.project(map.getCenter());
      return {x: center.x, y: center.y};
    });
    await page.mouse.click(placePoint.x, placePoint.y);
    await page.locator("#placeCard").waitFor({state: "visible"});
    const placeTitle = (await page.locator("#placeTitle").textContent()).trim();
    if (!placeTitle || !(await page.locator("#placeCategory").textContent()).trim()) {
      throw new Error("A real business did not provide a readable name and category.");
    }
    await page.locator("#placeDestination").click();
    if ((await page.locator("#destinationInput").inputValue()).trim() !== placeTitle) {
      throw new Error("Selecting a business did not set it as the route destination.");
    }
    await page.evaluate(camera => window.smokeMap.jumpTo(camera), originalCamera);
    await page.waitForFunction(() => window.smokeMap.loaded());

    const toggle = page.locator("#threeDButton");
    await toggle.waitFor({ state: "visible" });
    await toggle.click();
    await page.waitForFunction(() => {
      const button = document.querySelector("#threeDButton");
      return button && button.textContent.trim() === "2D";
    }, null, { timeout: 5000 });
    if (await page.evaluate(() => !!window.smokeMap.getLayer("iran-buildings-3d"))) {
      throw new Error("2D mode still contains the extrusion layer.");
    }

    await toggle.click();
    await page.waitForFunction(() => {
      const button = document.querySelector("#threeDButton");
      return button && button.textContent.trim() === "3D";
    }, null, { timeout: 5000 });
    await page.waitForFunction(() => window.smokeMap.loaded());

    await page.locator("#placesButton").click();
    await page.waitForFunction(() => window.smokeMap.queryRenderedFeatures({layers: ["iran-places"]}).length === 0);
    if (await page.locator("#placesButton").getAttribute("aria-pressed") !== "false") {
      throw new Error("The places toggle did not hide business markers.");
    }

    // A failed style request must be recoverable through the visible retry control.
    const styleUrl = "https://tiles.openfreemap.org/styles/positron";
    await page.route(styleUrl, route => route.fulfill({status: 503, body: "Unavailable"}));
    await page.locator("#themeTop").click();
    await page.locator("#retryMap").waitFor({state: "visible"});
    if (await page.locator("#mapLoading").isHidden()) throw new Error("Map failure was hidden.");
    await page.unroute(styleUrl);
    await page.locator("#retryMap").click();
    await page.waitForFunction(() => document.querySelector("#mapLoading").hidden, null, {timeout: 60000});
    if (!(await page.locator("body").evaluate(body => body.classList.contains("light")))) {
      throw new Error("Light theme did not apply after retry.");
    }
    if (await page.locator("#placesButton").getAttribute("aria-pressed") !== "false" ||
        await page.evaluate(() => window.smokeMap.queryRenderedFeatures({layers: ["iran-places"]}).length > 0)) {
      throw new Error("Changing the map theme reset the disabled places toggle.");
    }
    await page.locator("#placesButton").click();
    await page.waitForFunction(() => window.smokeMap.queryRenderedFeatures({layers: ["iran-places"]}).length > 0);

    // Quick switches must keep the latest selected theme and one copy of each overlay.
    await page.locator("#themeTop").click();
    await page.locator("#themeTop").click();
    await page.locator("#themeTop").click();
    await page.waitForFunction(() => document.querySelector("#mapLoading").hidden &&
      window.smokeMap.getPaintProperty("background", "background-color") === "#303438", null, {timeout: 60000});

    const overlayIds = await page.evaluate(() => window.smokeMap.getStyle().layers
      .filter(layer => /^(iran-places|iran-buildings-3d|route-line|user-dot)$/.test(layer.id))
      .map(layer => layer.id));
    if (overlayIds.length !== 4 || new Set(overlayIds).size !== 4) {
      throw new Error("Theme switching lost or duplicated application layers: " + overlayIds.join(", "));
    }

    const mapErrors = await page.evaluate(() => window.smokeMapErrors);
    if (pageErrors.length || mapErrors.length) {
      throw new Error("Browser/MapLibre errors: " + [...pageErrors, ...mapErrors].join(" | "));
    }

    const diagnostics = await page.evaluate(() => {
      const resources = performance.getEntriesByType("resource")
        .filter(entry => /unpkg.com|openfreemap.org/.test(entry.name))
        .map(entry => ({
          host: new URL(entry.name).host,
          durationMs: Math.round(entry.duration),
          transferBytes: entry.transferSize || 0
        }))
        .sort((a, b) => b.durationMs - a.durationMs)
        .slice(0, 8);
      const canvas = document.querySelector("#map canvas");
      return {
        canvasWidth: canvas ? canvas.width : 0,
        canvasHeight: canvas ? canvas.height : 0,
        webgl2: !!(canvas && canvas.getContext("webgl2")),
        resources
      };
    });

    await page.screenshot({
      path: "iran-navigator-web-smoke.png",
      fullPage: false
    });

    console.log(
      "PASS: MapLibre loaded, initial map canvas rendered, and 2D/3D controls toggled."
    );
    console.log("PASS: Persian RTL and bilingual labels, single vector source, building visibility/order, themes and failed-style retry.");
    console.log("PASS: Real business markers, details, destination selection and visibility persistence.");
    await page.setViewportSize({width: 390, height: 844});
    await page.waitForFunction(() => window.smokeMap.loaded());
    if (!(await page.locator("#threeDButton").isVisible()) ||
        await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)) {
      throw new Error("Mobile layout overflows or hides map controls.");
    }
    await page.screenshot({path: "iran-navigator-web-mobile-smoke.png"});
    console.log("PASS: Mobile layout and map controls.");
    console.log(
      "Map canvas: " + Math.round(bounds.width) + "x" + Math.round(bounds.height)
    );
    console.log("Initial map ready after navigation start: " + initialMap.readyMs + " ms");
    console.log("WebGL2 available: " + diagnostics.webgl2);
    console.log("Slowest map resources: " + JSON.stringify(diagnostics.resources));

    // A hung RTL download must start a fresh request when the user retries.
    const stalledPage = await browser.newPage({viewport: {width: 1440, height: 1000}});
    const stalledErrors = [];
    stalledPage.on("pageerror", error => stalledErrors.push(error.message));
    let pluginRequests = 0;
    await stalledPage.route("**/@mapbox/mapbox-gl-rtl-text@0.3.0/**", route => {
      pluginRequests++;
      if (pluginRequests > 1) return route.fallback();
      // Leave only this first request unresolved, as with a stalled connection.
    });
    await stalledPage.clock.install();
    await stalledPage.goto(process.env.APP_URL || "http://127.0.0.1:4173/", {waitUntil: "domcontentloaded"});
    await stalledPage.waitForFunction(() => window.maplibregl?.getRTLTextPluginStatus() === "loading");
    await stalledPage.clock.fastForward(26000);
    await stalledPage.locator("#retryMap").waitFor({state: "visible"});
    await stalledPage.clock.resume();
    await Promise.all([
      stalledPage.waitForEvent("domcontentloaded"),
      stalledPage.locator("#retryMap").click()
    ]);
    await stalledPage.waitForFunction(() => document.querySelector("#mapLoading").hidden, null, {timeout: 60000});
    if (pluginRequests < 2 || stalledErrors.length) {
      throw new Error("Hung RTL retry failed: requests=" + pluginRequests + "; errors=" + stalledErrors.join(" | "));
    }
    await stalledPage.close();
    console.log("PASS: A stalled RTL download recovers after Retry with a new request.");
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exit(1);
});
