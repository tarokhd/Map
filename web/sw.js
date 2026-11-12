/* Only the small, first-party visual shell is retained. Map tiles are not bulk-downloaded. */
const CACHE = "navigator-world-v1";
const ASSETS = [
  "./",
  "./index.html",
  "./app.css",
  "./app.mjs",
  "./navigation.mjs",
  "./environment.mjs",
  "./manifest.webmanifest",
  "./assets/mark.svg",
  "./assets/car.svg",
  "./assets/motorcycle.svg",
  "./assets/walking.svg",
];
const allowed = new Set(
  ASSETS.map((path) => new URL(path, self.registration.scope).pathname),
);
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(ASSETS))
      .then(() => self.skipWaiting()),
  );
});
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter(
              (key) => key.startsWith("navigator-world-") && key !== CACHE,
            )
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (
    event.request.method !== "GET" ||
    url.origin !== self.location.origin ||
    !allowed.has(url.pathname)
  )
    return;
  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      try {
        const response = await fetch(event.request);
        if (response.ok)
          await cache.put(url.origin + url.pathname, response.clone());
        return response;
      } catch (error) {
        const cached = await cache.match(url.origin + url.pathname);
        if (cached) return cached;
        throw error;
      }
    })(),
  );
});
