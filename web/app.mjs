import {
  MODES,
  fa,
  formatDistance,
  formatDuration,
  calculateRoutes,
  distance,
  bearing,
  angleDelta,
  pointAt,
  matchRoute,
  usablePosition,
} from "./navigation.mjs";
import {
  BIOMES,
  clamp,
  solarPosition,
  classifyEnvironment,
  worldPalette,
  blendPalette,
  materialTexture,
} from "./environment.mjs";

const maplibregl = window.maplibregl;
const $ = (id) => document.getElementById(id);
const TEHRAN = [51.405, 35.7006];
const empty = () => ({ type: "FeatureCollection", features: [] });
const pointFeature = (point) => ({
  type: "Feature",
  geometry: { type: "Point", coordinates: point },
  properties: {},
});
const lineFeature = (points) => ({
  type: "Feature",
  geometry: { type: "LineString", coordinates: points },
  properties: {},
});
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
export const state = {
  screen: "home",
  mode: "car",
  origin: null,
  originName: "",
  originIsGPS: false,
  destination: null,
  routes: [],
  routeIndex: 0,
  position: null,
  accuracy: null,
  watchId: null,
  biome: "auto",
  light: "auto",
  cockpit: true,
  context: { biome: "neutral", urbanForm: "" },
  distanceAlongRoute: 0,
  demoDistance: 0,
  speed: 0,
  ready: false,
  picking: null,
  follow: true,
  bearing: null,
  lastPositionAt: 0,
};
let map,
  destinationMarker,
  originMarker,
  mapAttempt = 0,
  mapController,
  rtlPromise;
let routeController,
  routeSequence = 0,
  searchController,
  searchSequence = 0,
  searchTimer,
  searchTarget = "destination";
let originSequence = 0,
  toastTimer,
  environmentTimer,
  paletteTimer,
  demoFrame,
  lastDemoTime;
let currentPalette,
  desiredPalette,
  contextCandidate = "",
  contextCount = 0;
let offRouteCount = 0,
  lastReroute = 0,
  lastCameraAt = 0,
  contextPending = false;
const routeCache = new Map();
const mapErrors = [];
let loadingFailed = false;
let loadingTimer;

function toast(message) {
  $("toast").textContent = message;
  $("toast").hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    $("toast").hidden = true;
  }, 4500);
}
function setScreen(screen) {
  state.screen = screen;
  document.body.dataset.screen = screen;
  const immersive = ["navigation", "preview"].includes(screen);
  $("homeDock").hidden = screen !== "home";
  $("journeySheet").hidden = screen !== "planning";
  $("navigationHUD").hidden = !immersive;
  $("navigationBar").hidden = !immersive;
  $("navigationStatus").hidden = !immersive;
  $("cockpit").hidden = !immersive || !state.cockpit;
  $("cockpit").dataset.mode = state.mode;
  $("cockpit").src = `./assets/${state.mode}.svg`;
  $("navigationBadge").textContent =
    screen === "preview" ? "پیش‌نمایش · حرکت شبیه‌سازی‌شده" : "ناوبری زنده";
}
function showMapMessage(message, failed = false) {
  $("mapMessage").hidden = false;
  $("mapMessageText").textContent = message;
  $("mapMessage").classList.toggle("failed", failed);
  $("retryMap").hidden = !failed;
  $("map").setAttribute("aria-busy", String(!failed));
}
function bilingualName() {
  const local = [
    "coalesce",
    ["get", "name:fa"],
    ["get", "name:nonlatin"],
    ["get", "name"],
    ["get", "name:latin"],
    "",
  ];
  const english = [
    "coalesce",
    ["get", "name:en"],
    ["get", "name_en"],
    ["get", "name:latin"],
    "",
  ];
  // A single text section avoids the upstream styled-bidi incompatibility.
  return [
    "concat",
    local,
    [
      "case",
      ["all", ["!=", english, ""], ["!=", english, local]],
      ["concat", "\n", english],
      "",
    ],
  ];
}
async function ensureRTL() {
  const status = maplibregl.getRTLTextPluginStatus();
  if (status === "loaded") return;
  if (!rtlPromise) {
    if (["loading", "error"].includes(status))
      throw new Error(
        "برای دریافت دوباره نوشته‌های فارسی، نقشه را بازآوری کنید.",
      );
    let timer;
    rtlPromise = Promise.race([
      maplibregl.setRTLTextPlugin(
        "https://unpkg.com/@mapbox/mapbox-gl-rtl-text@0.3.0/dist/mapbox-gl-rtl-text.js",
        false,
      ),
      new Promise((_, reject) => {
        timer = setTimeout(
          () => reject(new Error("دریافت نوشته‌های فارسی طول کشید.")),
          20000,
        );
      }),
    ])
      .catch((error) => {
        rtlPromise = null;
        throw error;
      })
      .finally(() => clearTimeout(timer));
  }
  await rtlPromise;
}
function prepareBase(raw) {
  const style = structuredClone(raw);
  style.sources.openfreemap = style.sources.openmaptiles;
  delete style.sources.openmaptiles;
  style.transition = { duration: 800, delay: 0 };
  style.layers = style.layers.filter(
    (layer) =>
      !JSON.stringify(layer.layout?.["text-field"] || "").includes('"ref"'),
  );
  for (const layer of style.layers) {
    if (layer.source === "openmaptiles") layer.source = "openfreemap";
    if (layer.type === "raster")
      layer.layout = { ...layer.layout, visibility: "none" };
    if (layer.paint?.["fill-pattern"]) delete layer.paint["fill-pattern"];
    if (layer.type === "symbol" && layer.layout?.["text-field"]) {
      if (!JSON.stringify(layer.layout["text-field"]).includes('"ref"'))
        layer.layout["text-field"] = bilingualName();
      layer.layout["text-letter-spacing"] = 0;
      layer.layout["text-line-height"] = 1.4;
      layer.layout["text-padding"] = 4;
      layer.layout["text-font"] = ["Noto Sans Regular"];
      layer.metadata = {
        ...layer.metadata,
        "navigator:visibility": layer.layout.visibility || "visible",
      };
    }
  }
  return style;
}
async function loadMap() {
  const attempt = ++mapAttempt;
  clearTimeout(loadingTimer);
  loadingTimer = setTimeout(() => {
    if (attempt === mapAttempt && !state.ready)
      showMapMessage(
        "دریافت نقشه طول کشیده؛ می‌توانید دوباره تلاش کنید.",
        true,
      );
  }, 30000);
  mapController?.abort();
  mapController = new AbortController();
  loadingFailed = false;
  state.ready = false;
  mapErrors.length = 0;
  showMapMessage("آماده‌سازی نقشه و نوشته‌های فارسی…");
  try {
    const response = await fetch(
      "https://tiles.openfreemap.org/styles/positron",
      {
        signal: AbortSignal.any([
          mapController.signal,
          AbortSignal.timeout(20000),
        ]),
      },
    );
    if (!response.ok) throw new Error("دریافت نقشه ممکن نشد.");
    const raw = await response.json();
    await ensureRTL();
    if (attempt !== mapAttempt) return;
    map.setStyle(prepareBase(raw), { diff: false });
    showMapMessage("دریافت خیابان‌ها و ساختمان‌ها…");
  } catch (error) {
    if (attempt !== mapAttempt) return;
    clearTimeout(loadingTimer);
    loadingFailed = true;
    showMapMessage(error.message || "اتصال نقشه برقرار نشد.", true);
  }
}
function addWorldLayers() {
  const base = map.getStyle().layers;
  const buildingIndex = base.findIndex((l) => l["source-layer"] === "building");
  const before = base
    .slice(buildingIndex + 1)
    .find((l) => l.type === "symbol")?.id;
  map.addImage("surface-asphalt", materialTexture("#738894"));
  map.addImage("surface-asphalt-major", materialTexture("#8d9da3"));
  map.addImage("surface-ground", materialTexture("#b2c0c4", "urban"));
  for (const layer of ["landcover", "landuse"])
    map.addLayer(
      {
        id: `world-grain-${layer}`,
        type: "fill",
        source: "openfreemap",
        "source-layer": layer,
        paint: { "fill-pattern": "surface-ground", "fill-opacity": 0.1 },
      },
      base[buildingIndex]?.id,
    );
  const height = [
    "max",
    0,
    ["to-number", ["coalesce", ["get", "render_height"], ["get", "height"]], 0],
  ];
  const floor = [
    "max",
    0,
    [
      "to-number",
      ["coalesce", ["get", "render_min_height"], ["get", "min_height"]],
      0,
    ],
  ];
  const buildingFilter = [
    "all",
    ["!", ["in", ["get", "hide_3d"], ["literal", [true, 1, "true", "1"]]]],
    [">", height, 0],
  ];
  map.addLayer(
    {
      id: "world-buildings",
      source: "openfreemap",
      "source-layer": "building",
      type: "fill-extrusion",
      minzoom: 14,
      filter: buildingFilter,
      paint: {
        "fill-extrusion-color": "#6e8390",
        "fill-extrusion-opacity": 0.96,
        "fill-extrusion-height": [
          "interpolate",
          ["linear"],
          ["zoom"],
          14,
          0,
          15,
          height,
        ],
        "fill-extrusion-base": [
          "interpolate",
          ["linear"],
          ["zoom"],
          14,
          0,
          15,
          ["min", floor, height],
        ],
        "fill-extrusion-vertical-gradient": true,
      },
    },
    before,
  );
  map.addLayer(
    {
      id: "world-building-edges",
      source: "openfreemap",
      "source-layer": "building",
      type: "line",
      minzoom: 14,
      filter: buildingFilter,
      paint: {
        "line-color": "#a5d8dc",
        "line-width": 0.6,
        "line-opacity": 0.2,
      },
    },
    before,
  );
  for (const id of [
    "journey-route",
    "journey-progress",
    "user-position",
    "accuracy-source",
  ])
    map.addSource(id, { type: "geojson", data: empty() });
  map.addLayer({
    id: "route-aura",
    type: "line",
    source: "journey-route",
    layout: { "line-cap": "round", "line-join": "round" },
    paint: {
      "line-color": "#a5e2df",
      "line-width": 15,
      "line-blur": 8,
      "line-opacity": 0.36,
    },
  });
  map.addLayer({
    id: "route-bed",
    type: "line",
    source: "journey-route",
    layout: { "line-cap": "round", "line-join": "round" },
    paint: { "line-color": "#112d3b", "line-width": 8, "line-opacity": 0.9 },
  });
  map.addLayer({
    id: "route-light",
    type: "line",
    source: "journey-route",
    layout: { "line-cap": "round", "line-join": "round" },
    paint: { "line-color": "#c6f4ed", "line-width": 3.5, "line-opacity": 0.95 },
  });
  map.addLayer({
    id: "route-progress",
    type: "line",
    source: "journey-progress",
    layout: { "line-cap": "round", "line-join": "round" },
    paint: { "line-color": "#566f7c", "line-width": 4, "line-opacity": 0.85 },
  });
  map.addLayer({
    id: "accuracy-radius",
    type: "fill",
    source: "accuracy-source",
    paint: { "fill-color": "#a5d8dc", "fill-opacity": 0.07 },
  });
  map.addLayer({
    id: "position-halo",
    type: "circle",
    source: "user-position",
    paint: {
      "circle-radius": 13,
      "circle-color": "#b0dce2",
      "circle-opacity": 0.1,
    },
  });
  map.addLayer({
    id: "position-dot",
    type: "circle",
    source: "user-position",
    paint: {
      "circle-radius": 4,
      "circle-color": "#effcf9",
      "circle-stroke-color": "#447384",
      "circle-stroke-width": 2,
    },
  });
  addPlaces();
  updateRouteSource();
  updatePositionSources();
  currentPalette = null;
  desiredPalette = null;
  updateEnvironment(true);
}
function addPlaces() {
  map.addLayer({
    id: "world-places",
    type: "symbol",
    source: "openfreemap",
    "source-layer": "poi",
    minzoom: 16,
    filter: [
      "in",
      ["get", "class"],
      [
        "literal",
        ["shop", "grocery", "cafe", "restaurant", "pharmacy", "bank"],
      ],
    ],
    layout: {
      "text-field": bilingualName(),
      "text-font": ["Noto Sans Regular"],
      "text-size": 10,
      "text-max-width": 10,
      "symbol-sort-key": ["to-number", ["coalesce", ["get", "rank"], 1000]],
      "text-padding": 7,
      "icon-image": ["get", "class"],
      "icon-size": 0.65,
      "text-offset": [0, 1.2],
      "text-anchor": "top",
      "text-optional": true,
    },
    paint: {
      "text-color": "#a9c3cf",
      "text-halo-color": "#243b49",
      "text-halo-width": 1.3,
    },
  });
}
function queryContext() {
  if (!map?.isStyleLoaded()) return;
  const c = map.project(environmentPoint());
  const features = map.queryRenderedFeatures([
    [c.x - 80, c.y - 80],
    [c.x + 80, c.y + 80],
  ]);
  const context = classifyEnvironment(features);
  if (context.biome === contextCandidate) contextCount++;
  else {
    contextCandidate = context.biome;
    contextCount = 1;
  }
  if (contextCount >= 2 || !state.context.evidence) state.context = context;
}
function environmentPoint() {
  const route = state.routes[state.routeIndex];
  if (state.screen === "preview" && route)
    return pointAt(route, state.demoDistance);
  if (state.screen === "navigation" && state.position) return state.position;
  return map.getCenter().toArray();
}
function applyPalette(palette, sun) {
  if (!map?.isStyleLoaded()) return;
  const p = palette;
  for (const layer of map.getStyle().layers) {
    const source = layer["source-layer"],
      id = layer.id;
    const paint = (property, value) =>
      map.setPaintProperty(id, property, value);
    if (layer.type === "background") paint("background-color", p.ground);
    if (layer.type === "fill") {
      if (source === "water") paint("fill-color", p.water);
      else if (source === "landcover" || id === "park")
        paint("fill-color", p.green);
      else if (source === "landuse") paint("fill-color", p.ground);
      else if (source === "building") {
        paint("fill-color", p.building);
        paint("fill-outline-color", p.edge);
      } else if (source === "aeroway" || source === "transportation")
        paint("fill-color", p.road);
    }
    if (layer.type === "line" && source) {
      if (source === "transportation")
        paint(
          "line-color",
          /casing/.test(id)
            ? p.ground
            : /major|motorway/.test(id)
              ? p.roadMajor
              : p.road,
        );
      if (
        source === "transportation" &&
        !layer.paint?.["line-dasharray"] &&
        /minor|major_inner|motorway_inner/.test(id)
      )
        paint(
          "line-pattern",
          /major|motorway/.test(id)
            ? "surface-asphalt-major"
            : "surface-asphalt",
        );
      if (source === "waterway") paint("line-color", p.water);
      if (source === "boundary") paint("line-color", p.edge);
    }
    if (layer.type === "symbol" && layer.layout?.["text-field"]) {
      paint("text-color", p.text);
      paint("text-halo-color", p.ground);
      paint("text-halo-width", 1.4);
    }
  }
  map.setPaintProperty("world-buildings", "fill-extrusion-color", p.building);
  map.setPaintProperty("world-building-edges", "line-color", p.edge);
  map.setPaintProperty(
    "world-building-edges",
    "line-opacity",
    0.12 + (1 - p.daylight) * 0.16,
  );
  map.setPaintProperty("route-aura", "line-color", p.accent);
  map.setPaintProperty("route-light", "line-color", p.accent);
  map.updateImage("surface-asphalt", materialTexture(p.road));
  map.updateImage("surface-asphalt-major", materialTexture(p.roadMajor));
  map.updateImage("surface-ground", materialTexture(p.edge, p.biome));
  map.setLight({
    anchor: "map",
    color: p.daylight > 0.2 ? "#f4e4cf" : "#b5d5e9",
    intensity: p.intensity,
    position: [1.15, sun.azimuth, clamp(90 - sun.elevation, 15, 85)],
  });
  map.setSky({
    "sky-color": p.sky,
    "horizon-color": p.horizon,
    "fog-color": p.ground,
    "sky-horizon-blend": 0.7,
    "horizon-fog-blend": 0.5,
    "fog-ground-blend": 0.6,
  });
  document.documentElement.style.setProperty("--accent", p.accent);
  document.documentElement.style.setProperty("--sky", p.sky);
}
function updateEnvironment(immediate = false) {
  if (!map?.isStyleLoaded() || !map.getLayer("world-buildings")) return;
  queryContext();
  const center = environmentPoint();
  const sun = solarPosition(new Date(), center[1], center[0]);
  if (state.light !== "auto")
    sun.elevation = { noon: 55, sunset: 0, night: -18 }[state.light];
  const biome = state.biome === "auto" ? state.context.biome : state.biome;
  const target = worldPalette(biome, sun.elevation);
  const previous = currentPalette;
  const signature = `${biome}:${Math.round(sun.elevation * 5)}`;
  const changed = signature !== desiredPalette;
  desiredPalette = signature;
  $("environmentLabel").textContent =
    `${BIOMES[biome].label}${state.context.urbanForm && biome === "urban" ? " " + state.context.urbanForm : ""} · ${target.phase}`;
  $("appearanceBadge").hidden =
    state.biome === "auto" && state.light === "auto";
  $("localClock").textContent = new Intl.DateTimeFormat("fa-IR", {
    timeZone: "Asia/Tehran",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date());
  $("localClock").title = "ساعت ایران";
  if (!changed && !immediate) return;
  clearInterval(paletteTimer);
  if (immediate || !previous || reducedMotion) {
    currentPalette = target;
    applyPalette(target, sun);
    return;
  }
  const start = performance.now();
  paletteTimer = setInterval(() => {
    const t = clamp((performance.now() - start) / 2200);
    currentPalette = blendPalette(previous, target, t * t * (3 - 2 * t));
    applyPalette(currentPalette, sun);
    if (t === 1) clearInterval(paletteTimer);
  }, 100);
}
function updateMarkers() {
  destinationMarker?.remove();
  originMarker?.remove();
  if (state.destination) {
    const el = document.createElement("div");
    el.className = "destination-marker";
    destinationMarker = new maplibregl.Marker({ element: el })
      .setLngLat(state.destination.point)
      .addTo(map);
  }
  if (state.origin && !state.originIsGPS) {
    const el = document.createElement("div");
    el.className = "origin-marker";
    originMarker = new maplibregl.Marker({ element: el })
      .setLngLat(state.origin)
      .addTo(map);
  }
}
function updateRouteSource() {
  const route = state.routes[state.routeIndex];
  map
    ?.getSource("journey-route")
    ?.setData(route ? lineFeature(route.points) : empty());
  map?.getSource("journey-progress")?.setData(empty());
}
function updatePositionSources() {
  const immersive = ["navigation", "preview"].includes(state.screen);
  map
    ?.getSource("user-position")
    ?.setData(
      state.position && !immersive ? pointFeature(state.position) : empty(),
    );
  if (state.position && state.accuracy !== null && !immersive) {
    const [lon, lat] = state.position;
    const radius = Math.min(500, state.accuracy);
    const ring = Array.from({ length: 49 }, (_, index) => {
      const angle = (index * Math.PI) / 24;
      return [
        lon +
          (Math.cos(angle) * radius) /
            (111320 * Math.cos((lat * Math.PI) / 180)),
        lat + (Math.sin(angle) * radius) / 111320,
      ];
    });
    map.getSource("accuracy-source")?.setData({
      type: "Feature",
      geometry: { type: "Polygon", coordinates: [ring] },
      properties: {},
    });
  } else map?.getSource("accuracy-source")?.setData(empty());
}
function setRouteStatus(message, error = false) {
  $("routeStatus").textContent = message;
  $("routeStatus").classList.toggle("error", error);
}
function invalidateRoute() {
  routeController?.abort();
  routeSequence++;
  state.routes = [];
  state.routeIndex = 0;
  $("startNavigation").disabled = true;
  $("previewRoute").disabled = true;
  $("routeSummary").hidden = true;
  $("routeAlternatives").replaceChildren();
  $("retryRoute").hidden = true;
  updateRouteSource();
}
function fitRoute() {
  const route = state.routes[state.routeIndex];
  if (!route) return;
  const bounds = route.points.reduce(
    (b, p) => b.extend(p),
    new maplibregl.LngLatBounds(route.points[0], route.points[0]),
  );
  const mobile = innerWidth < 900;
  map.fitBounds(bounds, {
    padding: mobile
      ? {
          top: 100,
          bottom: Math.min(innerHeight * 0.55, 460),
          left: 45,
          right: 45,
        }
      : { top: 130, bottom: 90, left: 440, right: 90 },
    maxZoom: 17,
    pitch: 45,
    bearing: 0,
    duration: reducedMotion ? 0 : 1100,
  });
}
function selectRoute(index, fit = true) {
  state.routeIndex = index;
  const route = state.routes[index];
  if (!route) return;
  $("routeSummary").hidden = false;
  $("routeDuration").textContent = formatDuration(route.duration);
  $("routeDistance").textContent = formatDistance(route.distance);
  $("startNavigation").disabled = false;
  $("previewRoute").disabled = false;
  document
    .querySelectorAll("[data-route]")
    .forEach((b) =>
      b.setAttribute("aria-pressed", String(Number(b.dataset.route) === index)),
    );
  setRouteStatus(
    route.fallback
      ? "پروفایل جایگزین موتور استفاده شده؛ مسیر بدون ترافیک زنده است."
      : "مسیر آماده است. حرکت را شروع کن یا پیش‌نمایش را ببین.",
  );
  updateRouteSource();
  if (fit) fitRoute();
}
async function planRoute({ reroute = false } = {}) {
  if (!state.origin || !state.destination) {
    setRouteStatus("مبدأ را با موقعیت فعلی یا انتخاب روی نقشه مشخص کنید.");
    return;
  }
  const sequence = ++routeSequence;
  routeController?.abort();
  routeController = new AbortController();
  const mode = state.mode,
    origin = [...state.origin],
    destination = [...state.destination.point];
  $("retryRoute").hidden = true;
  $("startNavigation").disabled = true;
  $("previewRoute").disabled = true;
  setRouteStatus("در حال پیدا کردن مسیر…");
  if (reroute) $("navigationStatus").textContent = "دریافت مسیر تازه…";
  const key = `${origin.join(",")}:${destination.join(",")}:${mode}`;
  try {
    const routes =
      !reroute && routeCache.has(key)
        ? routeCache.get(key)
        : await calculateRoutes(
            origin,
            destination,
            mode,
            routeController.signal,
          );
    if (sequence !== routeSequence) return;
    if (routeCache.size > 12) routeCache.delete(routeCache.keys().next().value);
    routeCache.set(key, routes);
    state.routes = routes;
    state.routeIndex = 0;
    $("routeAlternatives").replaceChildren();
    if (routes.length > 1)
      routes.forEach((route, index) => {
        const button = document.createElement("button");
        button.dataset.route = String(index);
        button.setAttribute("aria-pressed", String(index === 0));
        const title = document.createElement("span");
        title.textContent =
          index === 0 ? "مسیر پیشنهادی" : `مسیر ${fa(index + 1)}`;
        const metrics = document.createElement("span");
        metrics.textContent = `${formatDuration(route.duration)} · ${formatDistance(route.distance)}`;
        button.append(title, metrics);
        button.onclick = () => selectRoute(index);
        $("routeAlternatives").append(button);
      });
    if (reroute) {
      state.distanceAlongRoute = 0;
      offRouteCount = 0;
      selectRoute(0, false);
      $("navigationStatus").textContent = "مسیر به‌روز شد.";
    } else selectRoute(0);
  } catch (error) {
    if (sequence !== routeSequence || routeController.signal.aborted) return;
    if (!reroute) {
      state.routes = [];
      $("routeSummary").hidden = true;
      updateRouteSource();
    }
    setRouteStatus(
      error.name === "TimeoutError"
        ? "سرویس مسیر دیر پاسخ داد؛ دوباره تلاش کنید."
        : error.message,
      true,
    );
    $("retryRoute").hidden = false;
    if (reroute)
      $("navigationStatus").textContent =
        "مسیر تازه دریافت نشد؛ مسیر قبلی نمایش داده می‌شود.";
  }
}
function coordinateName(point) {
  return `${fa(point[1])}، ${fa(point[0])}`;
}
async function choosePlace(place, target) {
  $("searchDialog").close();
  cancelPicking();
  if (target === "origin") {
    originSequence++;
    state.origin = place.point;
    state.originName = place.name;
    state.originIsGPS = false;
    $("locate").disabled = false;
    $("useLocation").disabled = false;
    $("changeOrigin").textContent = place.name;
    invalidateRoute();
    updateMarkers();
    await planRoute();
    return;
  }
  stopMovement(false);
  state.destination = place;
  invalidateRoute();
  $("destinationTitle").textContent = place.name;
  setScreen("planning");
  updateMarkers();
  map.easeTo({
    center: place.point,
    zoom: 15.2,
    pitch: 48,
    duration: reducedMotion ? 0 : 900,
  });
  if (state.origin) {
    await planRoute();
  } else {
    await locate(true, false);
  }
}
function openSearch(target = "destination") {
  searchTarget = target;
  searchController?.abort();
  searchSequence++;
  $("searchTitle").textContent =
    target === "origin" ? "از کجا می‌رویم؟" : "مقصدت کجاست؟";
  $("searchInput").value = "";
  $("searchResults").replaceChildren();
  $("searchStatus").textContent = "نام شهر، خیابان یا مکان را وارد کنید.";
  $("searchDialog").showModal();
  $("searchInput").focus();
}
async function search() {
  const query = $("searchInput").value.trim();
  searchController?.abort();
  const sequence = ++searchSequence;
  if (query.length < 2) {
    $("searchResults").replaceChildren();
    $("searchStatus").textContent = "حداقل دو حرف وارد کنید.";
    return;
  }
  searchController = new AbortController();
  $("searchStatus").textContent = "در حال جست‌وجو…";
  $("searchResults").replaceChildren();
  const center = map?.getCenter().toArray() || TEHRAN;
  // Public Photon accepts default/de/en/fr; default retains local OSM names in Iran.
  const params = new URLSearchParams({
    q: query,
    limit: "6",
    lat: center[1],
    lon: center[0],
    lang: "default",
  });
  try {
    const response = await fetch(`https://photon.komoot.io/api/?${params}`, {
      signal: AbortSignal.any([
        searchController.signal,
        AbortSignal.timeout(15000),
      ]),
    });
    if (!response.ok)
      throw new Error(
        "جست‌وجو فعلاً در دسترس نیست؛ دوباره تلاش کنید یا روی نقشه انتخاب کنید.",
      );
    const payload = await response.json();
    if (sequence !== searchSequence || !$("searchDialog").open) return;
    const places = (payload.features || []).filter(
      (f) =>
        f.geometry?.type === "Point" && f.geometry.coordinates?.length === 2,
    );
    $("searchStatus").textContent = places.length
      ? "یک مکان را انتخاب کنید."
      : "نتیجه‌ای پیدا نشد؛ نام دقیق‌تر یا انتخاب روی نقشه را امتحان کنید.";
    for (const place of places) {
      const p = place.properties,
        name = p.name || p.street || p.city || "مکان روی نقشه";
      const button = document.createElement("button");
      button.className = "search-result";
      const title = document.createElement("strong");
      title.textContent = name;
      const detail = document.createElement("small");
      detail.textContent = [
        ...new Set([p.street, p.district, p.city, p.country].filter(Boolean)),
      ].join(" · ");
      button.append(title, detail);
      button.onclick = () =>
        choosePlace({ point: place.geometry.coordinates, name }, searchTarget);
      $("searchResults").append(button);
    }
  } catch (error) {
    if (sequence !== searchSequence || searchController.signal.aborted) return;
    $("searchStatus").textContent =
      error.name === "TimeoutError"
        ? "جست‌وجو دیر پاسخ داد؛ دوباره تلاش کنید."
        : error.message;
  }
}
function startPicking() {
  state.picking = searchTarget;
  $("searchDialog").close();
  document.body.classList.add("picking");
  $("pickHint").hidden = false;
  $("pickHintText").textContent =
    searchTarget === "origin"
      ? "مبدأ را روی نقشه انتخاب کنید"
      : "مقصد را روی نقشه انتخاب کنید";
  if (map) map.getCanvas().style.cursor = "crosshair";
}
function cancelPicking() {
  state.picking = null;
  document.body.classList.remove("picking");
  $("pickHint").hidden = true;
  if (map) map.getCanvas().style.cursor = "";
}
function positionError(error) {
  return error?.code === 1
    ? "اجازه موقعیت داده نشد؛ مبدأ را از جست‌وجو یا روی نقشه انتخاب کنید."
    : error?.code === 3
      ? "موقعیت به‌موقع دریافت نشد؛ دوباره تلاش کنید یا مبدأ را انتخاب کنید."
      : "موقعیت فعلاً در دسترس نیست؛ مبدأ را روی نقشه انتخاب کنید.";
}
async function locate(asOrigin = false, recenter = true) {
  const sequence = ++originSequence;
  if (!navigator.geolocation) {
    setRouteStatus(positionError());
    toast(positionError());
    return;
  }
  if (asOrigin) setRouteStatus("در حال دریافت موقعیت فعلی…");
  $("locate").disabled = true;
  $("useLocation").disabled = true;
  try {
    const position = await new Promise((resolve, reject) =>
      navigator.geolocation.getCurrentPosition(resolve, reject, {
        enableHighAccuracy: true,
        timeout: 15000,
        maximumAge: 5000,
      }),
    );
    if (sequence !== originSequence) return;
    if (!usablePosition(position))
      throw new Error(
        "موقعیت دقیق یا تازه نیست؛ دوباره تلاش کنید یا مبدأ را دستی انتخاب کنید.",
      );
    const point = [position.coords.longitude, position.coords.latitude];
    state.position = point;
    state.accuracy = position.coords.accuracy;
    updatePositionSources();
    if (asOrigin) {
      state.origin = point;
      state.originName = "موقعیت فعلی من";
      state.originIsGPS = true;
      $("changeOrigin").textContent = state.originName;
      invalidateRoute();
      updateMarkers();
      await planRoute();
    }
    if (recenter)
      map.easeTo({
        center: point,
        zoom: 16.5,
        pitch: 48,
        duration: reducedMotion ? 0 : 900,
      });
    updateEnvironment();
  } catch (error) {
    if (sequence !== originSequence) return;
    const message = error.code ? positionError(error) : error.message;
    setRouteStatus(message, true);
    toast(message);
  } finally {
    if (sequence === originSequence) {
      $("locate").disabled = false;
      $("useLocation").disabled = false;
    }
  }
}
function clearDestination() {
  stopMovement(false);
  originSequence++;
  searchSequence++;
  searchController?.abort();
  $("locate").disabled = false;
  $("useLocation").disabled = false;
  invalidateRoute();
  state.destination = null;
  cancelPicking();
  setScreen("home");
  updateMarkers();
  map.easeTo({
    padding: { top: 0, bottom: 0, left: 0, right: 0 },
    pitch: 48,
    bearing: 0,
    duration: reducedMotion ? 0 : 800,
  });
}
function beginMovement(preview) {
  const route = state.routes[state.routeIndex];
  if (!route) return;
  stopMovement(false);
  state.follow = true;
  state.distanceAlongRoute = 0;
  state.demoDistance = 0;
  state.bearing = null;
  offRouteCount = 0;
  lastCameraAt = 0;
  setScreen(preview ? "preview" : "navigation");
  updatePositionSources();
  immersiveLabels(true);
  if (preview) {
    $("navigationStatus").textContent =
      "پیش‌نمایش مسیر؛ موقعیت GPS شما نمایش داده نمی‌شود.";
    lastDemoTime = null;
    function frame(now) {
      if (state.screen !== "preview") return;
      if (lastDemoTime !== null && document.visibilityState === "visible")
        state.demoDistance +=
          Math.min((now - lastDemoTime) / 1000, 0.25) *
          MODES[state.mode].previewSpeed *
          3;
      lastDemoTime = now;
      const limit = route.cumulative.at(-1);
      state.demoDistance = Math.min(state.demoDistance, limit);
      updateMovement(
        pointAt(route, state.demoDistance),
        state.demoDistance,
        MODES[state.mode].previewSpeed,
        now,
      );
      if (state.demoDistance >= limit) {
        $("navigationStatus").textContent = "پیش‌نمایش به مقصد رسید.";
        return;
      }
      demoFrame = requestAnimationFrame(frame);
    }
    demoFrame = requestAnimationFrame(frame);
  } else {
    $("navigationStatus").textContent = "منتظر موقعیت دقیق…";
    if (!navigator.geolocation) {
      toast(positionError());
      stopMovement();
      return;
    }
    state.watchId = navigator.geolocation.watchPosition(
      handlePosition,
      (error) => {
        if (state.screen !== "navigation") return;
        if (error.code === 1) {
          toast(positionError(error));
          stopMovement();
        } else
          $("navigationStatus").textContent =
            "دریافت GPS قطع شده؛ منتظر موقعیت تازه…";
      },
      { enableHighAccuracy: true, timeout: 20000, maximumAge: 1000 },
    );
  }
}
function handlePosition(position) {
  if (state.screen !== "navigation") return;
  if (!usablePosition(position)) {
    $("navigationStatus").textContent = "دقت موقعیت کافی نیست؛ منتظر GPS بهتر…";
    return;
  }
  const route = state.routes[state.routeIndex];
  if (!route) return;
  const point = [position.coords.longitude, position.coords.latitude];
  state.position = point;
  state.accuracy = position.coords.accuracy;
  state.lastPositionAt = Date.now();
  const matched = matchRoute(route, point, state.distanceAlongRoute);
  if (matched.offRoute > 65) {
    offRouteCount++;
    $("navigationStatus").textContent = "خارج از مسیر؛ در حال بررسی موقعیت…";
    if (offRouteCount >= 3 && Date.now() - lastReroute > 20000) {
      lastReroute = Date.now();
      state.origin = point;
      planRoute({ reroute: true });
    }
    return;
  }
  offRouteCount = 0;
  $("navigationStatus").textContent =
    `GPS · دقت ${fa(Math.round(position.coords.accuracy))} متر`;
  const speed =
    Number.isFinite(position.coords.speed) && position.coords.speed >= 0
      ? position.coords.speed
      : 0;
  updateMovement(
    matched.point,
    matched.distanceAlongRoute,
    speed,
    performance.now(),
  );
  if (
    route.cumulative.at(-1) - matched.distanceAlongRoute < 25 &&
    distance(point, state.destination.point) < 45
  ) {
    toast("به مقصد رسیده‌اید.");
    stopMovement();
  }
}
function updateMovement(point, progress, speed, now) {
  const route = state.routes[state.routeIndex];
  if (!route) return;
  state.distanceAlongRoute = progress;
  state.speed = speed;
  const length = route.cumulative.at(-1),
    remaining = Math.max(0, length - progress);
  const maneuver =
    route.maneuvers.find((m) => m.endDistance > progress + 6) ||
    route.maneuvers.at(-1);
  $("nextInstruction").textContent =
    maneuver?.instruction || "به مسیر ادامه دهید";
  $("nextDistance").textContent = maneuver
    ? `${formatDistance(Math.max(0, maneuver.endDistance - progress))} دیگر`
    : formatDistance(remaining);
  const glyphs = {
    9: "↗",
    10: "↱",
    11: "↱",
    12: "↶",
    13: "↶",
    14: "↰",
    15: "↰",
    16: "↖",
    26: "⟳",
    27: "↗",
    4: "◎",
    5: "◎",
    6: "◎",
  };
  $("maneuverGlyph").textContent = glyphs[maneuver?.type] || "↑";
  $("remainingTime").textContent =
    remaining < 10
      ? "رسیدید"
      : formatDuration((route.duration * remaining) / Math.max(1, length));
  $("remainingDistance").textContent = formatDistance(remaining);
  $("speed").textContent = fa(Math.round(speed * 3.6));
  if (now - lastCameraAt < 130 || !state.follow) return;
  lastCameraAt = now;
  const look = pointAt(
    route,
    Math.min(
      length,
      progress + Math.max(state.mode === "walking" ? 20 : 45, speed * 3),
    ),
  );
  const targetBearing = bearing(point, look);
  state.bearing =
    state.bearing === null
      ? targetBearing
      : state.bearing + angleDelta(state.bearing, targetBearing) * 0.28;
  const height =
    state.mode === "walking" ? 3 : state.mode === "motorcycle" ? 8 : 12;
  const pitch = clamp(
    (Math.atan2(distance(point, look), height) * 180) / Math.PI,
    0,
    84,
  );
  const camera = map.calculateCameraOptionsFromCameraLngLatAltRotation(
    point,
    height,
    state.bearing,
    pitch,
    0, // Explicit roll avoids an undefined matrix input in MapLibre 5.24.
  );
  map.easeTo({
    ...camera,
    bearing: state.bearing,
    padding: { top: 0, bottom: 0, left: 0, right: 0 },
    duration: reducedMotion ? 0 : 450,
    essential: false,
  });
  const visited = route.points.filter((_, i) => route.cumulative[i] < progress);
  visited.push(point);
  if (visited.length >= 2)
    map.getSource("journey-progress")?.setData(lineFeature(visited));
  // Preview follows the route's coordinates without replacing the real GPS position.
  if (state.screen === "preview" && !contextPending) {
    contextPending = true;
    setTimeout(() => {
      contextPending = false;
      updateEnvironment();
    }, 1500);
  }
}
function stopMovement(restore = true) {
  cancelAnimationFrame(demoFrame);
  demoFrame = null;
  if (state.watchId !== null) navigator.geolocation?.clearWatch(state.watchId);
  state.watchId = null;
  state.follow = true;
  state.lastPositionAt = 0;
  immersiveLabels(false);
  if (restore && state.destination) {
    setScreen("planning");
    if (state.ready) {
      map.setLayoutProperty("world-places", "visibility", "visible");
      fitRoute();
    }
  }
  map?.getSource("journey-progress")?.setData(empty());
  updatePositionSources();
}
function immersiveLabels(hide) {
  if (!map?.getStyle()?.layers) return;
  for (const layer of map.getStyle().layers)
    if (layer.type === "symbol" && layer.source === "openfreemap") {
      map.setLayoutProperty(
        layer.id,
        "visibility",
        hide ? "none" : layer.metadata?.["navigator:visibility"] || "visible",
      );
    }
}
function bindEvents() {
  $("openSearch").onclick = () => openSearch();
  $("closeSearch").onclick = () => $("searchDialog").close();
  $("searchForm").onsubmit = (event) => {
    event.preventDefault();
    clearTimeout(searchTimer);
    search();
  };
  $("searchInput").oninput = () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(search, 400);
  };
  $("searchInput").onkeydown = (event) => {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      $("searchResults").querySelector("button")?.focus();
    }
  };
  $("searchDialog").addEventListener("close", () => {
    searchController?.abort();
    searchSequence++;
    clearTimeout(searchTimer);
  });
  $("pickOnMap").onclick = startPicking;
  $("cancelPick").onclick = cancelPicking;
  $("clearDestination").onclick = clearDestination;
  $("changeOrigin").onclick = () => openSearch("origin");
  $("locate").onclick = () => locate(false);
  $("useLocation").onclick = () => locate(true);
  document.querySelectorAll("[data-mode]").forEach((button) => {
    button.onclick = () => {
      state.mode = button.dataset.mode;
      document
        .querySelectorAll("[data-mode]")
        .forEach((b) => b.setAttribute("aria-pressed", String(b === button)));
      invalidateRoute();
      planRoute();
    };
  });
  $("retryRoute").onclick = () => planRoute();
  $("startNavigation").onclick = () => beginMovement(false);
  $("previewRoute").onclick = () => beginMovement(true);
  $("stopNavigation").onclick = () => stopMovement();
  $("openAppearance").onclick = $("navigationAppearance").onclick = () =>
    $("appearanceDialog").showModal();
  $("closeAppearance").onclick = () => $("appearanceDialog").close();
  document.querySelectorAll("[data-biome]").forEach((button) => {
    button.onclick = () => {
      state.biome = button.dataset.biome;
      document
        .querySelectorAll("[data-biome]")
        .forEach((b) => b.setAttribute("aria-pressed", String(b === button)));
      updateEnvironment();
    };
  });
  document.querySelectorAll("[data-light]").forEach((button) => {
    button.onclick = () => {
      state.light = button.dataset.light;
      document
        .querySelectorAll("[data-light]")
        .forEach((b) => b.setAttribute("aria-pressed", String(b === button)));
      updateEnvironment();
    };
  });
  $("cockpitToggle").onchange = (event) => {
    state.cockpit = event.target.checked;
    $("cockpit").hidden =
      !state.cockpit || !["navigation", "preview"].includes(state.screen);
  };
  $("retryMap").onclick = () => {
    if (
      !map ||
      ["loading", "error"].includes(maplibregl.getRTLTextPluginStatus())
    )
      location.reload();
    else loadMap();
  };
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && state.picking) cancelPicking();
  });
  document.addEventListener("visibilitychange", () => {
    lastDemoTime = null;
    if (!document.hidden) updateEnvironment();
  });
  window.addEventListener("resize", () => map?.resize());
}
async function boot() {
  bindEvents();
  setScreen("home");
  if (!maplibregl?.Map) {
    showMapMessage("ابزار نقشه دریافت نشد؛ اتصال را بررسی کنید.", true);
    return;
  }
  try {
    map = new maplibregl.Map({
      container: "map",
      style: null,
      center: TEHRAN,
      zoom: 15.2,
      pitch: 48,
      bearing: -12,
      antialias: true,
      maxPitch: 85,
      maxZoom: 24,
      attributionControl: { compact: true },
    });
    map.on("style.load", () => {
      addWorldLayers();
    });
    map.on("idle", () => {
      if (loadingFailed || !map.getLayer("world-buildings")) return;
      state.ready = true;
      clearTimeout(loadingTimer);
      $("mapMessage").hidden = true;
      $("map").setAttribute("aria-busy", "false");
      updateEnvironment();
    });
    map.on("error", (event) => {
      console.warn("Map:", event.error?.message);
      mapErrors.push(event.error?.message || "Map error");
      if (!state.ready) {
        loadingFailed = true;
        showMapMessage(
          "دریافت بخشی از نقشه ناموفق بود؛ دوباره تلاش کنید.",
          true,
        );
      } else toast("بخشی از نقشه دریافت نشد؛ اتصال را بررسی کنید.");
    });
    map.on("click", (event) => {
      if (!state.ready || ["navigation", "preview"].includes(state.screen))
        return;
      const target = state.picking;
      const feature = map.queryRenderedFeatures(event.point, {
        layers: ["world-places"],
      })[0];
      if (!target && !feature) return;
      const point =
        feature?.geometry?.type === "Point"
          ? feature.geometry.coordinates
          : [event.lngLat.lng, event.lngLat.lat];
      const p = feature?.properties || {};
      choosePlace(
        {
          point,
          name: p["name:fa"] || p["name:nonlatin"] || p.name || "نقطه روی نقشه",
        },
        target || "destination",
      );
    });
    map.on("moveend", () => updateEnvironment());
    map.on("dragstart", (event) => {
      if (
        event.originalEvent &&
        ["navigation", "preview"].includes(state.screen)
      ) {
        state.follow = false;
        $("navigationStatus").textContent =
          "برای دنبال کردن مسیر، روی راهنمای بالا بزنید.";
      }
    });
    $("navigationHUD").onclick = () => {
      state.follow = true;
    };
    await loadMap();
    environmentTimer = setInterval(() => {
      if (document.hidden) return;
      updateEnvironment();
      if (
        state.screen === "navigation" &&
        state.lastPositionAt &&
        Date.now() - state.lastPositionAt > 15000
      )
        $("navigationStatus").textContent =
          "موقعیت تازه دریافت نشده؛ منتظر GPS…";
    }, 2000);
  } catch (error) {
    console.error(error);
    showMapMessage(
      "نمایش گرافیکی نقشه راه‌اندازی نشد؛ مرورگر را بررسی کنید.",
      true,
    );
  }
  if ("serviceWorker" in navigator)
    navigator.serviceWorker.register("./sw.js").catch(() => {});
}
boot();
