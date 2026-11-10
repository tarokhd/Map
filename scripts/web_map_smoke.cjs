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

    await page.goto(process.env.APP_URL || "http://127.0.0.1:4173/", {
      waitUntil: "domcontentloaded",
      timeout: 30000
    });

    await page.waitForFunction(() => {
      const status = document.querySelector("#connectionStatus");
      return status && status.textContent.trim() === "نقشه آماده است";
    }, { timeout: 60000 });

    const canvas = page.locator("#map canvas").first();
    await canvas.waitFor({ state: "visible", timeout: 15000 });
    const bounds = await canvas.boundingBox();
    if (!bounds || bounds.width < 300 || bounds.height < 300) {
      throw new Error("Map canvas is not visible at a usable size.");
    }

    const toggle = page.locator("#threeDButton");
    await toggle.waitFor({ state: "visible" });
    await toggle.click();
    await page.waitForFunction(() => {
      const button = document.querySelector("#threeDButton");
      return button && button.textContent.trim() === "2D";
    }, { timeout: 5000 });

    await toggle.click();
    await page.waitForFunction(() => {
      const button = document.querySelector("#threeDButton");
      return button && button.textContent.trim() === "3D";
    }, { timeout: 5000 });

    if (pageErrors.length) {
      throw new Error("Browser JavaScript errors: " + pageErrors.join(" | "));
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
        mapReadyMs: Math.round(performance.now()),
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
    console.log(
      "Map canvas: " + Math.round(bounds.width) + "x" + Math.round(bounds.height)
    );
    console.log("Map ready after navigation start: " + diagnostics.mapReadyMs + " ms");
    console.log("WebGL2 available: " + diagnostics.webgl2);
    console.log("Slowest map resources: " + JSON.stringify(diagnostics.resources));
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exit(1);
});
