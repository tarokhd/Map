package com.irannavigator.demo

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.FillExtrusionLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : Activity(), LocationListener {
    private lateinit var mapView: MapView
    private lateinit var status: TextView
    private lateinit var search: EditText
    private lateinit var instruction: TextView
    private lateinit var summary: TextView
    private var map: MapLibreMap? = null
    private var style: Style? = null
    private var routeSource: GeoJsonSource? = null
    private var userSource: GeoJsonSource? = null
    private var origin: LatLng? = null
    private var destination: LatLng? = null
    private var routePoints: List<LatLng> = emptyList()
    private var maneuvers = org.json.JSONArray()
    private var maneuverIndex = 0
    private var mode = "auto"
    private var dark = true
    private var navigating = false
    private var lastLocation: Location? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val io = Executors.newSingleThreadExecutor()
    private val lm by lazy { getSystemService(Context.LOCATION_SERVICE) as LocationManager }
    private val tehran = LatLng(35.7006, 51.4050)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(12, 22, 36)
        window.navigationBarColor = Color.rgb(12, 22, 36)
        MapLibre.getInstance(applicationContext)
        tts = TextToSpeech(this) { result ->
            ttsReady = result == TextToSpeech.SUCCESS && (tts?.setLanguage(Locale("fa", "IR")) ?: TextToSpeech.LANG_MISSING_DATA) >= TextToSpeech.LANG_AVAILABLE
        }
        val root = FrameLayout(this)
        mapView = MapView(this).also { it.onCreate(savedInstanceState) }
        root.addView(mapView, FrameLayout.LayoutParams(-1, -1))
        root.addView(topPanel(), FrameLayout.LayoutParams(-1, -2, Gravity.TOP).apply { setMargins(dp(12), dp(12), dp(12), 0) })
        root.addView(bottomPanel(), FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM).apply { setMargins(dp(12), 0, dp(12), dp(16)) })
        setContentView(root)
        mapView.getMapAsync { m ->
            map = m
            m.uiSettings.isCompassEnabled = true
            m.uiSettings.isAttributionEnabled = true
            m.addOnMapClickListener { p ->
                if (origin == null || destination != null) {
                    origin = p; destination = null
                    status.text = "مبدأ انتخاب شد؛ حالا مقصد را انتخاب کنید."
                } else {
                    destination = p
                    status.text = "مقصد انتخاب شد؛ محاسبه مسیر را بزنید."
                }
                true
            }
            loadStyle()
        }
    }

    private fun loadStyle() {
        val uri = if (dark) "https://tiles.openfreemap.org/styles/dark" else "https://tiles.openfreemap.org/styles/bright"
        map?.setStyle(Style.Builder().fromUri(uri)) { s ->
            style = s; routeSource = null; userSource = null
            try {
                val b = FillExtrusionLayer("buildings-3d", "openmaptiles")
                b.sourceLayer = "building"; b.minZoom = 15f
                b.setFilter(Expression.has("render_height"))
                b.setProperties(PropertyFactory.fillExtrusionColor(if (dark) "#8FAABD" else "#AAB8C4"),
                    PropertyFactory.fillExtrusionHeight(Expression.get("render_height")),
                    PropertyFactory.fillExtrusionBase(Expression.get("render_min_height")),
                    PropertyFactory.fillExtrusionOpacity(0.88f))
                s.addLayer(b)
            } catch (_: Exception) { }
            userSource = GeoJsonSource("user-source", Feature.fromGeometry(Point.fromLngLat(tehran.longitude, tehran.latitude)))
            s.addSource(userSource!!)
            s.addLayer(CircleLayer("user-dot", "user-source").withProperties(
                PropertyFactory.circleRadius(8f), PropertyFactory.circleColor("#087CFF"),
                PropertyFactory.circleStrokeColor("#FFFFFF"), PropertyFactory.circleStrokeWidth(3f)))
            if (routePoints.isNotEmpty()) drawRoute()
            val target = lastLocation?.let { LatLng(it.latitude, it.longitude) } ?: tehran
            map?.animateCamera(CameraUpdateFactory.newCameraPosition(CameraPosition.Builder().target(target).zoom(15.5).tilt(50.0).build()), 450)
        }
    }

    private fun topPanel(): View {
        val p = panel()
        val title = TextView(this).apply {
            text = "IRAN NAVIGATOR 2.0"; textSize = 16f; typeface = Typeface.DEFAULT_BOLD
            setTextColor(if (dark) Color.WHITE else Color.rgb(20, 38, 58)); gravity = Gravity.RIGHT
        }
        p.addView(title)
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; layoutDirection = View.LAYOUT_DIRECTION_RTL }
        search = EditText(this).apply {
            hint = "جست‌وجوی شهر، خیابان یا مکان"; maxLines = 1; textSize = 13f
            setTextColor(if (dark) Color.WHITE else Color.BLACK); setHintTextColor(Color.GRAY)
            setPadding(dp(12), 0, dp(12), 0); background = rounded(if (dark) 0xFF24364C.toInt() else 0xFFF0F4F7.toInt(), 12)
        }
        row.addView(search, LinearLayout.LayoutParams(0, dp(46), 1f))
        row.addView(btn("جست‌وجو") { searchPlace() }, LinearLayout.LayoutParams(dp(84), dp(46)).apply { marginStart = dp(6) })
        p.addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(9) })
        return p
    }

    private fun bottomPanel(): View {
        val p = panel()
        val modes = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; layoutDirection = View.LAYOUT_DIRECTION_RTL }
        modes.addView(btn("خودرو") { setMode("auto") }, LinearLayout.LayoutParams(0, dp(40), 1f))
        modes.addView(btn("موتورسیکلت") { setMode("motorcycle") }, LinearLayout.LayoutParams(0, dp(40), 1f).apply { marginStart = dp(5) })
        modes.addView(btn("پیاده") { setMode("pedestrian") }, LinearLayout.LayoutParams(0, dp(40), 1f).apply { marginStart = dp(5) })
        p.addView(modes)
        val tools = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; layoutDirection = View.LAYOUT_DIRECTION_RTL }
        tools.addView(btn("موقعیت من") { requestGps() }, LinearLayout.LayoutParams(0, dp(42), 1.2f))
        tools.addView(btn(if (dark) "حالت روشن" else "حالت تاریک") { dark = !dark; loadStyle(); rebuildPanels() }, LinearLayout.LayoutParams(0, dp(42), 1f).apply { marginStart = dp(5) })
        tools.addView(btn("۲بعدی") { tilt(0) }, LinearLayout.LayoutParams(0, dp(42), .7f).apply { marginStart = dp(5) })
        tools.addView(btn("۳بعدی") { tilt(52) }, LinearLayout.LayoutParams(0, dp(42), .7f).apply { marginStart = dp(5) })
        p.addView(tools, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(7) })
        p.addView(btn("محاسبه مسیر و شروع راهنمایی") { route() }, LinearLayout.LayoutParams(-1, dp(46)).apply { topMargin = dp(8) })
        instruction = TextView(this).apply {
            text = "مبدأ و مقصد را با لمس نقشه یا جست‌وجو انتخاب کنید."
            textSize = 14f; typeface = Typeface.DEFAULT_BOLD
            setTextColor(if (dark) Color.WHITE else Color.rgb(20, 38, 58)); setPadding(0, dp(9), 0, dp(3))
        }
        p.addView(instruction)
        summary = TextView(this).apply { text = "موقعیت‌یابی تازه و راهنمای صوتی فارسی"; textSize = 11f; setTextColor(if (dark) Color.LTGRAY else Color.DKGRAY) }
        p.addView(summary)
        status = TextView(this).apply { text = "حالت خودرو"; textSize = 11f; setTextColor(0xFF16BFA9.toInt()); setPadding(0, dp(4), 0, 0) }
        p.addView(status)
        return p
    }

    private fun rebuildPanels() {
        val root = mapView.parent as? FrameLayout ?: return
        if (root.childCount >= 3) { root.removeViewAt(2); root.removeViewAt(1) }
        root.addView(topPanel(), FrameLayout.LayoutParams(-1, -2, Gravity.TOP).apply { setMargins(dp(12), dp(12), dp(12), 0) })
        root.addView(bottomPanel(), FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM).apply { setMargins(dp(12), 0, dp(12), dp(16)) })
    }

    private fun panel() = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL; layoutDirection = View.LAYOUT_DIRECTION_RTL
        setPadding(dp(15), dp(13), dp(15), dp(13))
        background = rounded(if (dark) 0xF20D1B2D.toInt() else Color.WHITE, 22); elevation = dp(10).toFloat()
    }
    private fun btn(label: String, action: () -> Unit) = TextView(this).apply {
        text = label; gravity = Gravity.CENTER; textSize = 12f; typeface = Typeface.DEFAULT_BOLD
        setTextColor(Color.WHITE); background = rounded(0xFF147F8B.toInt(), 12)
        isClickable = true; isFocusable = true; setOnClickListener { action() }
    }
    private fun rounded(color: Int, radius: Int) = GradientDrawable().apply { setColor(color); cornerRadius = dp(radius).toFloat() }
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun setMode(value: String) {
        mode = value
        status.text = "حالت: " + when (mode) { "auto" -> "خودرو"; "motorcycle" -> "موتورسیکلت"; else -> "پیاده‌روی" }
        if (origin != null && destination != null) route()
    }
    private fun tilt(value: Int) {
        val c = map?.cameraPosition ?: return
        map?.animateCamera(CameraUpdateFactory.newCameraPosition(CameraPosition.Builder().target(c.target ?: tehran).zoom(maxOf(c.zoom, 15.0)).tilt(value.toDouble()).bearing(c.bearing).build()), 350)
    }

    private fun route() {
        val from = origin ?: lastLocation?.let { LatLng(it.latitude, it.longitude) }
        val to = destination
        if (from == null || to == null) { Toast.makeText(this, "مبدأ و مقصد را مشخص کنید.", Toast.LENGTH_LONG).show(); return }
        status.text = "در حال محاسبه مسیر خیابانی..."
        io.execute {
            var c: HttpURLConnection? = null
            try {
                val request = JSONObject().apply {
                    put("locations", org.json.JSONArray()
                        .put(JSONObject().put("lat", from.latitude).put("lon", from.longitude).put("type", "break"))
                        .put(JSONObject().put("lat", to.latitude).put("lon", to.longitude).put("type", "break")))
                    put("costing", mode); put("units", "kilometers"); put("language", "en-US")
                }
                c = URL("https://valhalla1.openstreetmap.de/route").openConnection() as HttpURLConnection
                c.requestMethod = "POST"; c.connectTimeout = 15000; c.readTimeout = 25000; c.doOutput = true
                c.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                c.setRequestProperty("User-Agent", "IranNavigator/2.0")
                c.outputStream.use { it.write(request.toString().toByteArray(Charsets.UTF_8)) }
                val stream = if (c.responseCode in 200..299) c.inputStream else c.errorStream
                val response = JSONObject(stream.bufferedReader().use { it.readText() })
                if (c.responseCode !in 200..299 || response.has("error")) throw Exception(response.optString("error", "Route unavailable"))
                val trip = response.getJSONObject("trip")
                val leg = trip.getJSONArray("legs").getJSONObject(0)
                val points = decodePolyline6(leg.getString("shape"))
                val steps = leg.getJSONArray("maneuvers")
                runOnUiThread {
                    routePoints = points; maneuvers = steps; maneuverIndex = 0
                    drawRoute()
                    val s = trip.getJSONObject("summary")
                    summary.text = String.format(Locale.US, "%.1f km  •  حدود %.0f دقیقه", s.optDouble("length"), s.optDouble("time") / 60.0)
                    navigating = true; showStep(0, true); fitRoute(points)
                    status.text = "مسیر جاده‌ای محاسبه شد؛ موقعیت‌یابی را فعال کنید."
                }
            } catch (e: Exception) {
                runOnUiThread { status.text = "مسیریابی ناموفق: " + (e.message ?: "خطای اتصال") }
            } finally { c?.disconnect() }
        }
    }

    private fun decodePolyline6(encoded: String): List<LatLng> {
        val result = mutableListOf<LatLng>(); var i = 0; var lat = 0; var lon = 0
        while (i < encoded.length) {
            var b: Int; var shift = 0; var value = 0
            do { b = encoded[i++].code - 63; value = value or ((b and 31) shl shift); shift += 5 } while (b >= 32 && i < encoded.length)
            lat += if ((value and 1) != 0) (value shr 1).inv() else value shr 1
            shift = 0; value = 0
            do { b = encoded[i++].code - 63; value = value or ((b and 31) shl shift); shift += 5 } while (b >= 32 && i < encoded.length)
            lon += if ((value and 1) != 0) (value shr 1).inv() else value shr 1
            result.add(LatLng(lat / 1e6, lon / 1e6))
        }
        return result
    }

    private fun drawRoute() {
        val s = style ?: return
        if (routePoints.size < 2) return
        val feature = Feature.fromGeometry(LineString.fromLngLats(routePoints.map { Point.fromLngLat(it.longitude, it.latitude) }))
        if (routeSource == null) {
            routeSource = GeoJsonSource("route-source-v2", feature); s.addSource(routeSource!!)
            s.addLayer(LineLayer("route-shadow-v2", "route-source-v2").withProperties(PropertyFactory.lineColor(if (dark) "#06354A" else "#D2F3EF"), PropertyFactory.lineWidth(10f), PropertyFactory.lineCap("round"), PropertyFactory.lineJoin("round")))
            s.addLayer(LineLayer("route-line-v2", "route-source-v2").withProperties(PropertyFactory.lineColor("#00BFA6"), PropertyFactory.lineWidth(5f), PropertyFactory.lineCap("round"), PropertyFactory.lineJoin("round")))
        } else routeSource?.setGeoJson(feature)
    }

    private fun fitRoute(points: List<LatLng>) {
        if (points.isEmpty()) return
        val b = org.maplibre.android.geometry.LatLngBounds.Builder()
        points.forEach { b.include(it) }
        map?.animateCamera(CameraUpdateFactory.newLatLngBounds(b.build(), dp(45), dp(180), dp(230)), 600)
    }

    private fun showStep(index: Int, speak: Boolean) {
        if (maneuvers.length() == 0) return
        maneuverIndex = index.coerceIn(0, maneuvers.length() - 1)
        val m = maneuvers.getJSONObject(maneuverIndex)
        val type = m.optInt("type", 8)
        val streetArray = m.optJSONArray("street_names")
        val street = if (streetArray != null && streetArray.length() > 0) streetArray.optString(0) else ""
        val text = persianStep(type, street)
        instruction.text = text
        if (speak && ttsReady) tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "step-" + maneuverIndex)
    }

    private fun persianStep(type: Int, street: String): String {
        val turn = when (type) {
            1, 2, 3 -> "حرکت را آغاز کنید"
            4, 5, 6 -> "به مقصد رسیدید"
            9 -> "کمی به راست متمایل شوید"
            16 -> "کمی به چپ متمایل شوید"
            10, 11, 18, 20, 23 -> "به راست بپیچید"
            15, 14, 19, 21, 24 -> "به چپ بپیچید"
            12, 13 -> "دور بزنید"
            17, 22 -> "مستقیم ادامه دهید"
            25 -> "به مسیر ادغام شوید"
            26 -> "وارد میدان شوید"
            27 -> "از میدان خارج شوید"
            else -> "مسیر را ادامه دهید"
        }
        return if (street.isBlank()) turn else turn + " به مسیر " + street
    }

    private fun requestGps() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 410); return
        }
        try {
            var active = false
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1200L, 2f, this); active = true
            }
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 2500L, 5f, this); active = true
            }
            status.text = if (active) "در حال دریافت موقعیت تازه؛ منتظر دقت بهتر..." else "GPS و مکان‌یابی شبکه را روشن کنید."
        } catch (_: SecurityException) { status.text = "اجازه مکان‌یابی صادر نشده است." }
    }

    override fun onLocationChanged(location: Location) {
        if (location.hasAccuracy() && location.accuracy > 65f) {
            status.text = "دقت فعلی ضعیف است: " + location.accuracy.toInt() + " متر؛ منتظر GPS بهتر..."
            return
        }
        if (lastLocation != null && location.time < lastLocation!!.time) return
        lastLocation = location
        val point = LatLng(location.latitude, location.longitude)
        userSource?.setGeoJson(Feature.fromGeometry(Point.fromLngLat(location.longitude, location.latitude)))
        summary.text = "دقت موقعیت حدود " + location.accuracy.toInt() + " متر"
        if (origin == null) origin = point
        if (navigating) {
            map?.animateCamera(CameraUpdateFactory.newCameraPosition(CameraPosition.Builder().target(point).zoom(17.0).tilt(50.0).bearing(if (location.hasBearing()) location.bearing.toDouble() else 0.0).build()), 650)
            advanceManeuver(location)
        } else map?.animateCamera(CameraUpdateFactory.newLatLng(point), 300)
    }

    private fun advanceManeuver(location: Location) {
        if (maneuvers.length() == 0 || routePoints.isEmpty()) return
        val next = (maneuverIndex + 1).coerceAtMost(maneuvers.length() - 1)
        val m = maneuvers.optJSONObject(next) ?: return
        val shapeIndex = m.optInt("begin_shape_index", 0).coerceIn(0, routePoints.lastIndex)
        val target = routePoints[shapeIndex]
        val distance = FloatArray(1)
        Location.distanceBetween(location.latitude, location.longitude, target.latitude, target.longitude, distance)
        if (distance[0] < 40f && next > maneuverIndex) showStep(next, true)
    }

    private fun searchPlace() {
        val q0 = search.text.toString().trim()
        if (q0.isEmpty()) return
        status.text = "در حال جست‌وجو..."
        io.execute {
            var c: HttpURLConnection? = null
            try {
                val q = URLEncoder.encode(q0, "UTF-8")
                val center = lastLocation
                val lat = center?.latitude ?: map?.cameraPosition?.target?.latitude ?: 35.70
                val lon = center?.longitude ?: map?.cameraPosition?.target?.longitude ?: 51.40
                c = URL("https://photon.komoot.io/api/?q=" + q + "&limit=5&lat=" + lat + "&lon=" + lon + "&lang=fa").openConnection() as HttpURLConnection
                c.connectTimeout = 12000; c.readTimeout = 15000; c.setRequestProperty("User-Agent", "IranNavigator/2.0")
                val features = JSONObject(c.inputStream.bufferedReader().use { it.readText() }).getJSONArray("features")
                if (features.length() == 0) throw Exception("مکانی پیدا نشد")
                val item = features.getJSONObject(0)
                val xy = item.getJSONObject("geometry").getJSONArray("coordinates")
                val point = LatLng(xy.getDouble(1), xy.getDouble(0))
                val name = item.optJSONObject("properties")?.optString("name") ?: "مکان انتخاب‌شده"
                runOnUiThread {
                    if (origin == null) { origin = point; status.text = "مبدأ انتخاب شد: " + name }
                    else { destination = point; status.text = "مقصد انتخاب شد: " + name }
                    map?.animateCamera(CameraUpdateFactory.newLatLngZoom(point, 16.5), 550)
                }
            } catch (e: Exception) { runOnUiThread { status.text = "جست‌وجو ناموفق بود؛ اتصال یا نام مکان را بررسی کنید." } }
            finally { c?.disconnect() }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 410 && grantResults.any { it == PackageManager.PERMISSION_GRANTED }) requestGps()
    }
    override fun onStart() { super.onStart(); mapView.onStart() }
    override fun onResume() { super.onResume(); mapView.onResume() }
    override fun onPause() { mapView.onPause(); super.onPause() }
    override fun onStop() { try { lm.removeUpdates(this) } catch (_: Exception) {}; mapView.onStop(); super.onStop() }
    override fun onLowMemory() { super.onLowMemory(); mapView.onLowMemory() }
    override fun onSaveInstanceState(outState: Bundle) { mapView.onSaveInstanceState(outState); super.onSaveInstanceState(outState) }
    override fun onDestroy() {
        try { lm.removeUpdates(this) } catch (_: Exception) {}
        tts?.stop(); tts?.shutdown(); io.shutdownNow(); mapView.onDestroy(); super.onDestroy()
    }
}
