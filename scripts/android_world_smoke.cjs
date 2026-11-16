// Exercise the exact generated APK shell, including CSP, local renderer and GPS bridge.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const APP = process.env.APP_URL || 'http://127.0.0.1:4174/';
const points = [[51.405, 35.7006], [51.405, 35.705], [51.412, 35.705], [51.412, 35.71]];
function encode(points) {
  let lat = 0, lon = 0, result = '';
  for (const [x, y] of points) {
    for (let n of [Math.round(y * 1e6) - lat, Math.round(x * 1e6) - lon]) {
      n = n < 0 ? ~(n << 1) : n << 1;
      while (n >= 32) { result += String.fromCharCode((32 | (n & 31)) + 63); n >>>= 5; }
      result += String.fromCharCode(n + 63);
    }
    lat = Math.round(y * 1e6); lon = Math.round(x * 1e6);
  }
  return result;
}
async function configure(page, denied = false) {
  await page.addInitScript(({denied}) => {
    window.nativeRequests = []; window.nativeCancellations = []; window.nativeWatch = null;
    window.pushNativePosition = (id, longitude = 51.405, latitude = 35.7006) => {
      window.__androidLocation(id, {timestamp: Date.now(), coords: {longitude, latitude, accuracy: 8, heading: 0, speed: 4, altitude: null, altitudeAccuracy: null}}, null);
    };
    window.AndroidWorld = {
      requestLocation(id, once, timeout) {
        nativeRequests.push({id, once, timeout});
        if (!once) window.nativeWatch = Number(id);
        setTimeout(() => denied ? window.__androidLocation(Number(id), null, {code: 1, message: 'denied'}) : pushNativePosition(Number(id)), 10);
      },
      cancelLocation(id) {nativeCancellations.push(id);}
    };
    let lib;
    Object.defineProperty(window, 'maplibregl', {configurable: true, get: () => lib, set(value) {
      lib = value; const MapClass = value.Map;
      value.Map = class extends MapClass {constructor(options) {super(options); window.testMap = this;}};
    }});
    window.cspViolations = [];
    document.addEventListener('securitypolicyviolation', e => cspViolations.push(`${e.violatedDirective}: ${e.blockedURI}`));
  }, {denied});
  await page.route('https://photon.komoot.io/api/**', r => r.fulfill({contentType: 'application/json', body: JSON.stringify({features: [{type: 'Feature', geometry: {type: 'Point', coordinates: points.at(-1)}, properties: {name: 'مقصد آزمایشی', city: 'تهران', country: 'ایران'}}]})}));
  await page.route('https://valhalla1.openstreetmap.de/route', r => r.fulfill({contentType: 'application/json', body: JSON.stringify({trip: {summary: {length: 2, time: 300}, legs: [{shape: encode(points), summary: {length: 2, time: 300}, maneuvers: [{type: 1, street_names: ['ولیعصر'], end_shape_index: 1}, {type: 10, street_names: ['انقلاب'], end_shape_index: 3}]}]}})}));
}
async function search(page) {
  await page.locator('#openSearch').click();
  await page.locator('#searchInput').fill('مقصد');
  await page.locator('#searchInput').press('Enter');
  await page.locator('.search-result').first().click();
}
(async () => {
  const browser = await chromium.launch({headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage']});
  try {
    const page = await browser.newPage({viewport: {width: 393, height: 852}});
    const errors = [], cdnRequests = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('request', r => {if (new URL(r.url()).hostname === 'unpkg.com') cdnRequests.push(r.url());});
    await configure(page);
    await page.goto(APP, {waitUntil: 'domcontentloaded'});
    await page.waitForFunction(() => document.querySelector('#mapMessage').hidden && testMap.loaded(), null, {timeout: 60000});
    assert.equal(await page.evaluate(() => maplibregl.getRTLTextPluginStatus()), 'loaded');
    assert.equal(await page.locator('#travelModes').isVisible(), false);
    assert.equal(await page.evaluate(() => nativeRequests.length), 0, 'No GPS prompt before user action');
    await search(page);
    await page.waitForFunction(() => !document.querySelector('#previewRoute').disabled);
    assert.equal(await page.locator('#travelModes').isVisible(), true);
    assert.equal(await page.locator('#changeOrigin').textContent(), 'موقعیت فعلی من');
    assert.equal(await page.evaluate(() => nativeRequests[0].once), true);
    await page.locator('#previewRoute').click();
    await page.waitForFunction(() => document.body.dataset.screen === 'preview' && testMap.getPitch() > 70);
    assert.ok((await page.locator('#cockpit').getAttribute('src')).endsWith('/car.svg'));
    await page.screenshot({path: process.env.ANDROID_SCREENSHOT || 'android-world-mobile.png'});
    await page.locator('#stopNavigation').click();
    await page.locator('#startNavigation').click();
    await page.waitForFunction(() => document.body.dataset.screen === 'navigation' && nativeWatch !== null);
    await page.evaluate(() => pushNativePosition(nativeWatch, 51.405, 35.702));
    await page.waitForFunction(async () => (await import('./app.mjs')).state.distanceAlongRoute > 100);
    await page.locator('#stopNavigation').click();
    assert.ok(await page.evaluate(() => nativeCancellations.length > 0));
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    assert.deepEqual(await page.evaluate(() => cspViolations), []);
    assert.deepEqual(errors, []);
    assert.deepEqual(cdnRequests, []);
    assert.equal(await page.evaluate(async () => (await navigator.serviceWorker.getRegistrations()).length), 0);
    // Verify the local files copied into the APK. Offline maps are not promised.
    for (const asset of ['vendor/maplibre-gl.js', 'vendor/mapbox-gl-rtl-text.js', 'assets/car.svg', 'assets/motorcycle.svg', 'assets/walking.svg']) {
      assert.equal((await page.request.get(new URL(asset, APP).href)).status(), 200);
    }
    const denied = await browser.newPage({viewport: {width: 393, height: 852}});
    await configure(denied, true);
    await denied.goto(APP);
    await denied.waitForFunction(() => document.querySelector('#mapMessage').hidden, null, {timeout: 60000});
    await search(denied);
    await denied.waitForFunction(() => document.querySelector('#routeStatus').textContent.includes('اجازه موقعیت'));
    assert.equal(await denied.locator('#startNavigation').isDisabled(), true);
    assert.equal(await denied.evaluate(async () => (await import('./app.mjs')).state.origin), null);
    console.log('PASS: Bundled renderer/RTL/CSP, mobile destination flow, first-person camera, native GPS watch/cancel and denied permission. No remote application code or service worker.');
  } finally {await browser.close();}
})().catch(error => {
  console.error(error);
  if (process.env.GITHUB_ACTIONS) {
    const message = String(error.stack || error).replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
    console.error(`::error title=Bundled mobile shell failed::${message}`);
  }
  process.exit(1);
});
