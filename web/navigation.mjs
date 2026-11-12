// Shared, renderer-independent navigation primitives. Coordinates are [longitude, latitude].
const RAD = Math.PI / 180;
export const MODES = {
  car: { label: "خودرو", costings: ["auto"], previewSpeed: 12 },
  motorcycle: {
    label: "موتور",
    costings: ["motorcycle", "motor_scooter"],
    previewSpeed: 10,
  },
  walking: { label: "پیاده", costings: ["pedestrian"], previewSpeed: 1.4 },
};
export const fa = (value) =>
  new Intl.NumberFormat("fa-IR", { maximumFractionDigits: 1 }).format(value);
export const formatDistance = (meters) =>
  meters >= 1000
    ? `${fa(meters / 1000)} کیلومتر`
    : `${fa(Math.round(meters))} متر`;
export const formatDuration = (seconds) => {
  const minutes = Math.max(1, Math.round(seconds / 60));
  return minutes >= 60
    ? `${fa(Math.floor(minutes / 60))} ساعت و ${fa(minutes % 60)} دقیقه`
    : `${fa(minutes)} دقیقه`;
};
export function distance(a, b) {
  const p = a[1] * RAD,
    q = b[1] * RAD;
  const h =
    Math.sin((q - p) / 2) ** 2 +
    Math.cos(p) * Math.cos(q) * Math.sin(((b[0] - a[0]) * RAD) / 2) ** 2;
  return 12742000 * Math.asin(Math.sqrt(Math.min(1, h)));
}
export function bearing(a, b) {
  const p = a[1] * RAD,
    q = b[1] * RAD,
    d = (b[0] - a[0]) * RAD;
  return (
    (Math.atan2(
      Math.sin(d) * Math.cos(q),
      Math.cos(p) * Math.sin(q) - Math.sin(p) * Math.cos(q) * Math.cos(d),
    ) /
      RAD +
      360) %
    360
  );
}
export const angleDelta = (a, b) => ((b - a + 540) % 360) - 180;
export function decodePolyline6(encoded) {
  if (typeof encoded !== "string" || !encoded)
    throw new Error("هندسه مسیر خالی است.");
  let index = 0,
    lat = 0,
    lon = 0;
  const points = [];
  function delta() {
    let value = 0,
      shift = 0,
      byte;
    do {
      if (index >= encoded.length || shift > 30)
        throw new Error("هندسه مسیر ناقص است.");
      byte = encoded.charCodeAt(index++) - 63;
      if (byte < 0 || byte > 63) throw new Error("هندسه مسیر معتبر نیست.");
      value |= (byte & 31) << shift;
      shift += 5;
    } while (byte >= 32);
    return value & 1 ? ~(value >> 1) : value >> 1;
  }
  while (index < encoded.length) {
    lat += delta();
    lon += delta();
    const point = [lon / 1e6, lat / 1e6];
    if (Math.abs(point[0]) > 180 || Math.abs(point[1]) > 90)
      throw new Error("مختصات مسیر معتبر نیست.");
    points.push(point);
  }
  if (points.length < 2) throw new Error("مسیر کوتاه یا ناقص است.");
  return points;
}
export function measureRoute(points) {
  const cumulative = [0];
  for (let i = 1; i < points.length; i++)
    cumulative.push(cumulative[i - 1] + distance(points[i - 1], points[i]));
  return cumulative;
}
export function pointAt(route, meters) {
  const { points, cumulative } = route;
  const target = Math.max(0, Math.min(cumulative.at(-1), meters));
  let lo = 1,
    hi = points.length - 1;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (cumulative[mid] < target) lo = mid + 1;
    else hi = mid;
  }
  const i = lo,
    length = cumulative[i] - cumulative[i - 1];
  const t = length > 0 ? (target - cumulative[i - 1]) / length : 0;
  return [
    points[i - 1][0] + (points[i][0] - points[i - 1][0]) * t,
    points[i - 1][1] + (points[i][1] - points[i - 1][1]) * t,
  ];
}
export function matchRoute(route, position, previousDistance = null) {
  const { points, cumulative } = route;
  const scaleX = 111320 * Math.cos(position[1] * RAD),
    scaleY = 111320;
  function search(local) {
    let best = null;
    for (let i = 1; i < points.length; i++) {
      if (
        local &&
        (cumulative[i] < previousDistance - 100 ||
          cumulative[i - 1] > previousDistance + 1200)
      )
        continue;
      const a = points[i - 1],
        b = points[i];
      const ax = (a[0] - position[0]) * scaleX,
        ay = (a[1] - position[1]) * scaleY;
      const dx = (b[0] - a[0]) * scaleX,
        dy = (b[1] - a[1]) * scaleY;
      const t = Math.max(
        0,
        Math.min(1, -(ax * dx + ay * dy) / (dx * dx + dy * dy || 1)),
      );
      const offRoute = Math.hypot(ax + dx * t, ay + dy * t);
      if (!best || offRoute < best.offRoute)
        best = {
          offRoute,
          distanceAlongRoute:
            cumulative[i - 1] + (cumulative[i] - cumulative[i - 1]) * t,
          point: [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t],
          index: i,
        };
    }
    return best;
  }
  const local = previousDistance !== null ? search(true) : null;
  return local && local.offRoute < 100 ? local : search(false);
}
export function usablePosition(position, now = Date.now()) {
  const c = position?.coords;
  return (
    !!c &&
    Number.isFinite(c.latitude) &&
    Number.isFinite(c.longitude) &&
    Math.abs(c.latitude) <= 90 &&
    Math.abs(c.longitude) <= 180 &&
    Number.isFinite(c.accuracy) &&
    c.accuracy >= 0 &&
    c.accuracy <= 65 &&
    now - position.timestamp <= 15000 &&
    position.timestamp <= now + 5000
  );
}
export function normalizeTrip(trip, fallback = false) {
  if (!Array.isArray(trip?.legs) || !trip.legs.length)
    throw new Error("مسیر قابل استفاده‌ای پیدا نشد.");
  const points = [],
    maneuvers = [];
  for (const leg of trip.legs) {
    const decoded = decodePolyline6(leg.shape);
    if (points.length && distance(points.at(-1), decoded[0]) > 15)
      throw new Error("بخش‌های مسیر به هم متصل نیستند.");
    const join = points.length && distance(points.at(-1), decoded[0]) < 1;
    const offset = points.length - (join ? 1 : 0);
    points.push(...(join ? decoded.slice(1) : decoded));
    for (const m of leg.maneuvers || [])
      maneuvers.push({
        type: Number(m.type),
        instruction: localInstruction(
          Number(m.type),
          (m.street_names || []).join("، "),
        ),
        endIndex:
          offset +
          Math.max(
            0,
            Math.min(
              decoded.length - 1,
              m.end_shape_index ?? decoded.length - 1,
            ),
          ),
      });
  }
  const cumulative = measureRoute(points);
  const meters =
    (trip.summary?.length ??
      trip.legs.reduce((n, l) => n + (l.summary?.length || 0), 0)) * 1000;
  const seconds =
    trip.summary?.time ??
    trip.legs.reduce((n, l) => n + (l.summary?.time || 0), 0);
  if (
    !Number.isFinite(meters) ||
    !Number.isFinite(seconds) ||
    meters <= 0 ||
    seconds <= 0 ||
    cumulative.at(-1) < 1
  )
    throw new Error("مسافت یا زمان مسیر معتبر نیست.");
  return {
    points,
    cumulative,
    maneuvers: maneuvers.map((m) => ({
      ...m,
      endDistance: cumulative[m.endIndex],
    })),
    distance: meters,
    duration: seconds,
    fallback,
  };
}
export async function calculateRoutes(origin, destination, mode, signal) {
  let lastError;
  for (const [index, costing] of MODES[mode].costings.entries()) {
    try {
      const response = await fetch("https://valhalla1.openstreetmap.de/route", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        signal: AbortSignal.any([
          signal || new AbortController().signal,
          AbortSignal.timeout(25000),
        ]),
        body: JSON.stringify({
          locations: [
            { lon: origin[0], lat: origin[1] },
            { lon: destination[0], lat: destination[1] },
          ],
          costing,
          units: "kilometers",
          language: "en-US",
          shape_format: "polyline6",
          directions_type: "instructions",
          alternates: 2,
        }),
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok)
        throw new Error(
          payload.error ||
            `سرویس مسیر پاسخ ${response.status} داد؛ دوباره تلاش کنید.`,
        );
      return [
        normalizeTrip(payload.trip, index > 0),
        ...(payload.alternates || []).map((a) =>
          normalizeTrip(a.trip || a, index > 0),
        ),
      ].slice(0, 3);
    } catch (error) {
      if (signal?.aborted) throw error;
      lastError = error;
    }
  }
  throw lastError || new Error("دریافت مسیر ممکن نشد.");
}

export function localInstruction(type, street) {
  const action =
    {
      0: "به مسیر ادامه دهید",
      1: "حرکت را آغاز کنید",
      2: "از سمت راست حرکت را آغاز کنید",
      3: "از سمت چپ حرکت را آغاز کنید",
      4: "به مقصد رسیده‌اید",
      5: "از سمت راست به مقصد می‌رسید",
      6: "از سمت چپ به مقصد می‌رسید",
      7: "مسیر به خیابان دیگری تبدیل می‌شود",
      8: "به مسیر مستقیم ادامه دهید",
      9: "کمی به راست متمایل شوید",
      10: "به راست بپیچید",
      11: "با زاویه تند به راست بپیچید",
      12: "دور بزنید",
      13: "دور بزنید",
      14: "با زاویه تند به چپ بپیچید",
      15: "به چپ بپیچید",
      16: "کمی به چپ متمایل شوید",
      17: "از رمپ مستقیم وارد شوید",
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
      30: "وارد مسیر حمل‌ونقل عمومی شوید",
      31: "وسیله یا خط حمل‌ونقل را عوض کنید",
      32: "در همین وسیله بمانید",
      33: "به مسیر اتصال حمل‌ونقل عمومی بروید",
      34: "در مسیر اتصال، وسیله را عوض کنید",
      35: "به مقصد حمل‌ونقل عمومی رسیده‌اید",
      36: "به مقصد حمل‌ونقل عمومی رسیده‌اید",
      37: "از سمت راست به مسیر اصلی ادغام شوید",
      38: "از سمت چپ به مسیر اصلی ادغام شوید",
      39: "وارد آسانسور شوید",
      40: "از پله‌ها استفاده کنید",
      41: "از پله‌برقی استفاده کنید",
      42: "وارد ساختمان شوید",
      43: "از ساختمان خارج شوید",
      44: "به طبقه یا تراز دیگری بروید",
      45: "وسیله نقلیه را پارک کنید",
    }[type] || "به مسیر ادامه دهید";
  const streetlessTypes = [
    4, 5, 6, 28, 29, 30, 31, 32, 33, 34, 35, 36, 39, 40, 41, 42, 43, 44, 45,
  ];
  return street &&
    street.toLowerCase() !== "unnamed road" &&
    !streetlessTypes.includes(type)
    ? action + " و وارد " + street + " شوید"
    : action;
}
