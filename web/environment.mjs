// Solar position is computed locally from UTC + coordinates, independent of device timezone.
const RAD = Math.PI / 180;
export const clamp = (n, min = 0, max = 1) => Math.max(min, Math.min(max, n));
export function solarPosition(date, latitude, longitude) {
  const days = date.getTime() / 86400000 - 10957.5; // J2000
  const mean = (357.5291 + 0.98560028 * days) * RAD;
  const center =
    (1.9148 * Math.sin(mean) +
      0.02 * Math.sin(2 * mean) +
      0.0003 * Math.sin(3 * mean)) *
    RAD;
  const longitudeSun = mean + center + 102.9372 * RAD + Math.PI;
  const obliquity = 23.4397 * RAD;
  const declination = Math.asin(Math.sin(longitudeSun) * Math.sin(obliquity));
  const ascension = Math.atan2(
    Math.sin(longitudeSun) * Math.cos(obliquity),
    Math.cos(longitudeSun),
  );
  const sidereal = (280.16 + 360.9856235 * days + longitude) * RAD;
  const hourAngle = sidereal - ascension,
    lat = latitude * RAD;
  return {
    elevation:
      Math.asin(
        Math.sin(lat) * Math.sin(declination) +
          Math.cos(lat) * Math.cos(declination) * Math.cos(hourAngle),
      ) / RAD,
    azimuth:
      (Math.atan2(
        Math.sin(hourAngle),
        Math.cos(hourAngle) * Math.sin(lat) -
          Math.tan(declination) * Math.cos(lat),
      ) /
        RAD +
        180 +
        360) %
      360,
  };
}
export const BIOMES = {
  neutral: {
    label: "محیط",
    ground: "#36414a",
    building: "#6e8390",
    green: "#37483f",
    water: "#234551",
    accent: "#9adfe1",
  },
  urban: {
    label: "شهری",
    ground: "#343d46",
    building: "#7f94a2",
    green: "#384d42",
    water: "#284752",
    accent: "#a5e2df",
  },
  forest: {
    label: "جنگلی",
    ground: "#263e36",
    building: "#7a9385",
    green: "#30513f",
    water: "#264a50",
    accent: "#b4dca3",
  },
  desert: {
    label: "خشک و ماسه‌ای",
    ground: "#50483e",
    building: "#a29680",
    green: "#50583b",
    water: "#33535a",
    accent: "#edcf9b",
  },
  coast: {
    label: "ساحلی",
    ground: "#3b474a",
    building: "#8ea3a6",
    green: "#3b5548",
    water: "#244f5c",
    accent: "#96dadd",
  },
  mountain: {
    label: "سنگی و کوهستانی",
    ground: "#3d414b",
    building: "#9193a4",
    green: "#414c44",
    water: "#314c5b",
    accent: "#c9cbe7",
  },
  farmland: {
    label: "دشت و کشاورزی",
    ground: "#414a3c",
    building: "#8d9983",
    green: "#4b603f",
    water: "#344f55",
    accent: "#d2daa1",
  },
};
export function classifyEnvironment(features) {
  const scores = { forest: 0, desert: 0, coast: 0, mountain: 0, farmland: 0 };
  let buildings = 0,
    high = 0,
    urban = false;
  for (const feature of features) {
    const p = feature.properties || {},
      layer = feature.sourceLayer || feature.layer?.["source-layer"];
    const type = `${p.class || ""} ${p.subclass || ""}`.toLowerCase();
    if (layer === "building") {
      buildings++;
      if (Number(p.render_height || p.height) >= 35) high++;
    }
    if (
      layer === "landuse" &&
      /residential|commercial|industrial|retail/.test(type)
    )
      urban = true;
    if (!["landcover", "landuse", "water"].includes(layer)) continue;
    if (/wood|forest/.test(type)) scores.forest += 3;
    if (/sand|desert/.test(type)) scores.desert += 3;
    if (/ocean|sea/.test(type)) scores.coast += 4;
    if (/rock|bare_rock|scree|ice|glacier/.test(type)) scores.mountain += 3;
    if (/farmland|orchard|vineyard/.test(type)) scores.farmland += 3;
  }
  const ranked = Object.entries(scores).sort((a, b) => b[1] - a[1]);
  const nature = ranked[0][1] > 0 ? ranked[0][0] : "neutral";
  // A small wooded city park should not recolor an otherwise dense urban scene.
  const cityDominates = buildings >= 16 && ranked[0][1] < buildings / 3;
  return {
    biome: cityDominates
      ? "urban"
      : nature !== "neutral"
        ? nature
        : urban || buildings >= 8
          ? "urban"
          : "neutral",
    urbanForm:
      high >= 3
        ? "مرتفع"
        : buildings >= 30
          ? "متراکم"
          : buildings > 0 || urban
            ? "شهری"
            : "",
    evidence: ranked[0][1] > 0 || urban || buildings > 0,
  };
}
function rgb(hex) {
  return [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
}
export function mixColor(a, b, amount) {
  const x = rgb(a),
    y = rgb(b),
    t = clamp(amount);
  return (
    "#" +
    x
      .map((v, i) =>
        Math.round(v + (y[i] - v) * t)
          .toString(16)
          .padStart(2, "0"),
      )
      .join("")
  );
}
export function worldPalette(biome, elevation) {
  const material = BIOMES[biome] || BIOMES.neutral;
  const daylight = clamp((elevation + 6) / 30);
  const twilight = clamp(1 - Math.abs(elevation - 1) / 12) * 0.45;
  const ground = mixColor("#151e29", material.ground, 0.35 + daylight * 0.65);
  return {
    ground,
    building: mixColor("#334b5a", material.building, 0.35 + daylight * 0.65),
    edge: mixColor(material.accent, "#a1adb5", daylight * 0.75),
    road: mixColor("#435b68", "#8a999f", daylight),
    roadMajor: mixColor("#657f88", "#b0b4b1", daylight),
    green: mixColor("#1c3029", material.green, 0.35 + daylight * 0.65),
    water: mixColor("#172d3a", material.water, 0.3 + daylight * 0.7),
    text: mixColor("#b5ced8", "#e0e7e7", daylight),
    sky: mixColor(
      mixColor("#080f1e", "#567784", daylight),
      "#7b605f",
      twilight,
    ),
    horizon: mixColor(
      mixColor("#1e3546", "#a5b4b5", daylight),
      "#ba8e70",
      twilight,
    ),
    biome,
    accent: material.accent,
    daylight,
    intensity: 0.2 + daylight * 0.35,
    phase: elevation >= 12 ? "روز" : elevation >= -6 ? "گرگ‌ومیش" : "شب",
  };
}
export function blendPalette(from, to, amount) {
  const result = { ...to };
  for (const key of Object.keys(to)) {
    if (typeof to[key] === "string" && to[key].startsWith("#"))
      result[key] = mixColor(from[key] || to[key], to[key], amount);
    if (typeof to[key] === "number")
      result[key] =
        (from[key] ?? to[key]) +
        (to[key] - (from[key] ?? to[key])) * clamp(amount);
  }
  return result;
}

// Tiny deterministic materials, generated locally instead of downloading texture packs.
export function materialTexture(color, kind = "road", size = 32) {
  const base = rgb(color),
    data = new Uint8Array(size * size * 4);
  let seed = 17491;
  for (let y = 0; y < size; y++)
    for (let x = 0; x < size; x++) {
      seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
      const random = seed / 4294967296;
      const variation =
        kind === "desert"
          ? Math.sin(y / 4 + Math.sin(x / 9)) * 10
          : kind === "forest"
            ? Math.sin(x * 0.8) * Math.cos(y * 0.6) * 8
            : (random - 0.5) * (kind === "mountain" ? 20 : 9);
      const i = (y * size + x) * 4;
      for (let c = 0; c < 3; c++)
        data[i + c] = clamp(Math.round(base[c] + variation), 0, 255);
      data[i + 3] = kind === "road" ? 255 : Math.round(35 + random * 55);
    }
  return { width: size, height: size, data };
}
