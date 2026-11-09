package com.irannavigator.demo

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.location.LocationManager
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.SeekBar
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
import java.util.concurrent.Executors

class MainActivity : Activity() {
    private lateinit var mapView: MapView
    private lateinit var statusText: TextView
    private lateinit var searchInput: EditText
    private lateinit var tiltSeek: SeekBar
    private var map: MapLibreMap? = null
    private var style: Style? = null
    private var origin: LatLng? = null
    private var destination: LatLng? = null
    private var routeSource: GeoJsonSource? = null
    private val io = Executors.newSingleThreadExecutor()

    private val tehran = LatLng(35.7006, 51.4050)
    private val azadi = LatLng(35.6997, 51.3380)
    private val milad = LatLng(35.7448, 51.3753)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(16, 27, 44)
        window.navigationBarColor = Color.rgb(16, 27, 44)
        MapLibre.getInstance(applicationContext)

        val root = FrameLayout(this)
        mapView = MapView(this)
        mapView.onCreate(savedInstanceState)
        root.addView(mapView, FrameLayout.LayoutParams(-1, -1))
        root.addView(buildTopPanel(), FrameLayout.LayoutParams(-1, -2, Gravity.TOP).apply {
            setMargins(dp(12), dp(12), dp(12), 0)
        })
        root.addView(buildBottomPanel(), FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM).apply {
            setMargins(dp(12), 0, dp(12), dp(28))
        })
        setContentView(root)

        mapView.getMapAsync { mapObject ->
            map = mapObject
            mapObject.uiSettings.isCompassEnabled = true
            mapObject.uiSettings.isAttributionEnabled = true
            mapObject.setStyle(Style.Builder().fromUri("https://tiles.openfreemap.org/styles/bright")) { loadedStyle ->
                style = loadedStyle
                add3DBuildings(loadedStyle)
                mapObject.animateCamera(
                    CameraUpdateFactory.newCameraPosition(
                        CameraPosition.Builder().target(tehran).zoom(15.2).tilt(55.0).bearing(0.0).build()
                    ),
                    700
                )
            }
            mapObject.addOnMapClickListener { point ->
                if (origin == null || destination != null) {
                    origin = point
                    destination = null
                    statusText.text = "مبدأ انتخاب شد؛ نقطه مقصد را لمس کنید."
                } else {
                    destination = point
                    statusText.text = "مقصد انتخاب شد؛ نمایش خط مسیر نمونه را بزنید."
                }
                true
            }
        }
    }

    private fun buildTopPanel(): View {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(15), dp(12), dp(15), dp(12))
            background = rounded(Color.rgb(17, 30, 49), 20)
            elevation = dp(8).toFloat()
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        val title = TextView(this).apply {
            text = "IRAN NAVIGATOR  •  نسخه آزمایشی"
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER_VERTICAL or Gravity.RIGHT
        }
        panel.addView(title)
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        searchInput = EditText(this).apply {
            hint = "جست‌وجوی شهر یا مکان..."
            textSize = 13f
            singleLine = true
            setTextColor(Color.WHITE)
            setHintTextColor(Color.LTGRAY)
            setPadding(dp(12), 0, dp(12), 0)
            background = rounded(Color.rgb(35, 51, 72), 12)
        }
        row.addView(searchInput, LinearLayout.LayoutParams(0, dp(46), 1f))
        row.addView(button("جست‌وجو") { searchPlace() }, LinearLayout.LayoutParams(dp(86), dp(46)).apply {
            marginStart = dp(7)
        })
        val rowParams = LinearLayout.LayoutParams(-1, -2)
        rowParams.topMargin = dp(9)
        panel.addView(row, rowParams)
        return panel
    }

    private fun buildBottomPanel(): View {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = rounded(Color.rgb(16, 28, 46), 22)
            elevation = dp(10).toFloat()
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        val heading = TextView(this).apply {
            text = "نقشه سه‌بعدی و مسیریابی آزمایشی"
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
        }
        panel.addView(heading)
        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        buttons.addView(button("موقعیت من") { locateUser() }, LinearLayout.LayoutParams(0, dp(44), 1.2f))
        buttons.addView(button("2D") { setTilt(0) }, LinearLayout.LayoutParams(0, dp(44), 0.7f).apply { marginStart = dp(6) })
        buttons.addView(button("3D") { setTilt(55) }, LinearLayout.LayoutParams(0, dp(44), 0.7f).apply { marginStart = dp(6) })
        buttons.addView(button("مسیر نمونه") { showSampleRoute() }, LinearLayout.LayoutParams(0, dp(44), 1.1f).apply { marginStart = dp(6) })
        val buttonParams = LinearLayout.LayoutParams(-1, -2)
        buttonParams.topMargin = dp(10)
        panel.addView(buttons, buttonParams)

        val tiltRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        val tiltTitle = TextView(this).apply {
            text = "زاویه دید"
            setTextColor(Color.LTGRAY)
            textSize = 12f
        }
        tiltRow.addView(tiltTitle, LinearLayout.LayoutParams(dp(62), -2))
        tiltSeek = SeekBar(this).apply {
            max = 60
            progress = 55
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) = Unit
                override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit
                override fun onStopTrackingTouch(seekBar: SeekBar?) { setTilt(seekBar?.progress ?: 55) }
            })
        }
        tiltRow.addView(tiltSeek, LinearLayout.LayoutParams(0, dp(38), 1f))
        val tiltParams = LinearLayout.LayoutParams(-1, -2)
        tiltParams.topMargin = dp(4)
        panel.addView(tiltRow, tiltParams)

        statusText = TextView(this).apply {
            text = "برای انتخاب مبدأ و مقصد، دو نقطه روی نقشه لمس کنید."
            setTextColor(Color.rgb(170, 190, 210))
            textSize = 11f
            setPadding(0, dp(5), 0, 0)
        }
        panel.addView(statusText)
        return panel
    }

    private fun button(textValue: String, action: () -> Unit): TextView =
        TextView(this).apply {
            text = textValue
            gravity = Gravity.CENTER
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            background = rounded(Color.rgb(31, 83, 104), 12)
            isClickable = true
            isFocusable = true
            setOnClickListener { action() }
        }

    private fun add3DBuildings(loadedStyle: Style) {
        try {
            val buildings = FillExtrusionLayer("iran-buildings-3d", "openmaptiles")
            buildings.sourceLayer = "building"
            buildings.minZoom = 15f
            buildings.setFilter(Expression.has("render_height"))
            buildings.setProperties(
                PropertyFactory.fillExtrusionColor(Color.rgb(191, 204, 216)),
                PropertyFactory.fillExtrusionHeight(Expression.get("render_height")),
                PropertyFactory.fillExtrusionBase(Expression.get("render_min_height")),
                PropertyFactory.fillExtrusionOpacity(0.9f)
            )
            loadedStyle.addLayer(buildings)
        } catch (_: Exception) {
            statusText.text = "ساختمان سه‌بعدی در این محدوده داده کافی ندارد."
        }
    }

    private fun setTilt(value: Int) {
        val safe = value.coerceIn(0, 60)
        tiltSeek.progress = safe
        val current = map?.cameraPosition ?: return
        val target = current.target ?: tehran
        val camera = CameraPosition.Builder()
            .target(target)
            .zoom(maxOf(current.zoom, if (safe == 0) 12.5 else 15.0))
            .tilt(safe.toDouble())
            .bearing(current.bearing)
            .build()
        map?.animateCamera(CameraUpdateFactory.newCameraPosition(camera), 450)
    }

    private fun showSampleRoute() {
        val from = origin ?: azadi
        val to = destination ?: milad
        val loadedStyle = style ?: return
        val points = listOf(
            Point.fromLngLat(from.longitude, from.latitude),
            Point.fromLngLat(to.longitude, to.latitude)
        )
        val feature = Feature.fromGeometry(LineString.fromLngLats(points))
        if (routeSource == null) {
            routeSource = GeoJsonSource("sample-route-source", feature)
            loadedStyle.addSource(routeSource!!)
            val line = LineLayer("sample-route-line", "sample-route-source").withProperties(
                PropertyFactory.lineColor("#087FCE"),
                PropertyFactory.lineWidth(5f),
                PropertyFactory.lineOpacity(0.95f),
                PropertyFactory.lineCap("round"),
                PropertyFactory.lineJoin("round")
            )
            loadedStyle.addLayer(line)
        } else {
            routeSource?.setGeoJson(feature)
        }
        origin = from
        destination = to
        statusText.text = "خط مستقیم نمونه نمایش داده شد؛ این نسخه موتور مسیریابی واقعی ندارد."
        map?.animateCamera(
            CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder().target(from).zoom(13.5).tilt(48.0).bearing(0.0).build()
            ),
            600
        )
        tiltSeek.progress = 48
    }

    private fun searchPlace() {
        val query = searchInput.text.toString().trim()
        if (query.isEmpty()) {
            Toast.makeText(this, "نام مکان را وارد کنید.", Toast.LENGTH_SHORT).show()
            return
        }
        statusText.text = "در حال جست‌وجو..."
        io.execute {
            var connection: HttpURLConnection? = null
            try {
                val q = URLEncoder.encode(query, "UTF-8")
                val endpoint = "https://photon.komoot.io/api/?q=$q&limit=1&lat=35.70&lon=51.40&lang=fa"
                connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 10000
                    readTimeout = 12000
                    setRequestProperty("User-Agent", "IranNavigatorDemo/0.1")
                }
                val json = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
                val features = json.getJSONArray("features")
                if (features.length() == 0) throw IllegalStateException("مکانی پیدا نشد")
                val first = features.getJSONObject(0)
                val coords = first.getJSONObject("geometry").getJSONArray("coordinates")
                val point = LatLng(coords.getDouble(1), coords.getDouble(0))
                val name = first.optJSONObject("properties")?.optString("name").orEmpty()
                runOnUiThread {
                    map?.animateCamera(
                        CameraUpdateFactory.newCameraPosition(
                            CameraPosition.Builder().target(point).zoom(16.0).tilt(55.0).build()
                        ),
                        650
                    )
                    statusText.text = if (name.isBlank()) "مکان پیدا شد." else "مکان پیدا شد: $name"
                    tiltSeek.progress = 55
                }
            } catch (error: Exception) {
                runOnUiThread {
                    statusText.text = "جست‌وجو انجام نشد؛ اتصال اینترنت را بررسی کنید."
                    Toast.makeText(this, error.message ?: "خطای جست‌وجو", Toast.LENGTH_LONG).show()
                }
            } finally {
                connection?.disconnect()
            }
        }
    }

    private fun locateUser() {
        val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) {
            requestPermissions(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                410
            )
            return
        }
        try {
            val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val location = manager.getProviders(true)
                .mapNotNull { provider -> manager.getLastKnownLocation(provider) }
                .minByOrNull { it.accuracy }
            if (location == null) {
                Toast.makeText(this, "موقعیت فعلاً در دسترس نیست؛ GPS را فعال کنید.", Toast.LENGTH_LONG).show()
                return
            }
            val point = LatLng(location.latitude, location.longitude)
            map?.animateCamera(
                CameraUpdateFactory.newCameraPosition(
                    CameraPosition.Builder().target(point).zoom(16.0).tilt(55.0).build()
                ),
                650
            )
            statusText.text = "موقعیت تقریبی شما: دقت ${location.accuracy.toInt()} متر"
        } catch (_: SecurityException) {
            Toast.makeText(this, "اجازه دسترسی به موقعیت صادر نشده است.", Toast.LENGTH_SHORT).show()
        }
    }

    private fun rounded(color: Int, radius: Int): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius).toFloat()
        }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 410 && grantResults.any { it == PackageManager.PERMISSION_GRANTED }) locateUser()
    }

    override fun onStart() { super.onStart(); mapView.onStart() }
    override fun onResume() { super.onResume(); mapView.onResume() }
    override fun onPause() { mapView.onPause(); super.onPause() }
    override fun onStop() { mapView.onStop(); super.onStop() }
    override fun onLowMemory() { super.onLowMemory(); mapView.onLowMemory() }

    override fun onSaveInstanceState(outState: Bundle) {
        mapView.onSaveInstanceState(outState)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        io.shutdownNow()
        mapView.onDestroy()
        super.onDestroy()
    }
}
