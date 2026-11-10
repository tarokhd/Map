package com.irannavigator.demo

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
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
import org.maplibre.android.style.layers.FillLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point
import org.maplibre.geojson.Polygon
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors
import kotlin.math.*

class MainActivity : Activity() {
    private lateinit var mapView: MapView
    private lateinit var topPanel: LinearLayout
    private lateinit var bottomPanel: LinearLayout
    private lateinit var instructionCard: LinearLayout
    private lateinit var searchInput: EditText
    private lateinit var statusText: TextView
    private lateinit var summaryText: TextView
    private lateinit var instructionText: TextView
    private lateinit var nextStepText: TextView
    private lateinit var distanceText: TextView
    private lateinit var modeButtons: Map<TravelMode, TextView>
    private lateinit var originButton: TextView
    private lateinit var destinationButton: TextView
    private lateinit var voiceButton: TextView
    private lateinit var threeDButton: TextView
    private lateinit var themeButton: TextView
    private lateinit var gpsButton: TextView
    private lateinit var calculateButton: TextView
    private lateinit var startButton: TextView
    private lateinit var stopButton: TextView

    private var map: MapLibreMap? = null
    private var style: Style? = null
    private val io = Executors.newSingleThreadExecutor()
    private val routingEngine = RoutingEngine()
    private var voice: PersianVoice? = null
    private var locationManager: LocationManager? = null
    private var locationListener: LocationListener? = null

    private var origin: NavPoint? = null
    private var destination: NavPoint? = null
    private var currentLocation: Location? = null
    private var routeResult: RouteResult? = null
    private var selectedMode = TravelMode.CAR
    private var selectingOrigin = true
    private var isDarkTheme = true
    private var is3DEnabled = true
    private var voiceEnabled = true
    private var isNavigating = false
    private var trackingRequested = false
    private var centerOnNextLocation = false
    private var pendingSetOriginFromGps = false
    private var pendingStartAfterPermission = false
    private var currentManeuverIndex = 0
    private var lastMatchedRouteIndex = 0
    private var lastAnnouncedManeuver = -1
    private var offRouteCount = 0
    private var lastRerouteAt = 0L
    private var lastCameraFollowAt = 0L
    private var lastCameraLocation: NavPoint? = null
    private var smoothedCameraBearing: Double? = null
    private var routeRequestToken = 0

    private var routeSource: GeoJsonSource? = null
    private var userSource: GeoJsonSource? = null
    private var accuracySource: GeoJsonSource? = null
    private var originSource: GeoJsonSource? = null
    private var destinationSource: GeoJsonSource? = null

    private val tehran = NavPoint(35.7006, 51.4050)
    private val locationPermissionRequest = 410

    private data class SearchCandidate(val title: String, val subtitle: String, val point: NavPoint) {
        fun display(): String = if (subtitle.isBlank()) title else "$title\n$subtitle"
    }

    private val locationCallback = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            handleLocation(location)
        }

        override fun onProviderEnabled(provider: String) {
            statusText.text = "دریافت موقعیت فعال شد."
        }

        override fun onProviderDisabled(provider: String) {
            if (provider == LocationManager.GPS_PROVIDER) {
                statusText.text = "GPS خاموش است؛ در صورت امکان از موقعیت شبکه استفاده می‌شود."
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(10, 19, 32)
        window.navigationBarColor = Color.rgb(10, 19, 32)
        MapLibre.getInstance(applicationContext)
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager

        val root = FrameLayout(this)
        mapView = MapView(this)
        mapView.onCreate(savedInstanceState)
        root.addView(mapView, FrameLayout.LayoutParams(-1, -1))

        topPanel = buildTopPanel()
        bottomPanel = buildBottomPanel()
        root.addView(topPanel, FrameLayout.LayoutParams(-1, -2, Gravity.TOP).apply {
            setMargins(dp(12), dp(12), dp(12), 0)
        })
        root.addView(bottomPanel, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM).apply {
            setMargins(dp(12), 0, dp(12), dp(18))
        })
        setContentView(root)

        voice = PersianVoice(this) { _, message ->
            runOnUiThread {
                if (::statusText.isInitialized) {
                    statusText.text = message
                    refreshControlButtons()
                }
            }
        }
        refreshThemeUi()
        updateSelectionButtons()
        updateModeButtons()
        refreshControlButtons()

        mapView.getMapAsync { mapObject ->
            map = mapObject
            mapObject.uiSettings.isCompassEnabled = true
            mapObject.uiSettings.isAttributionEnabled = true
            loadMapStyle()
            mapObject.addOnMapClickListener { point ->
                val selected = NavPoint(point.latitude, point.longitude)
                applyPointSelection(selected, if (selectingOrigin) "مبدأ انتخاب شد" else "مقصد انتخاب شد")
                true
            }
        }
    }

    private fun buildTopPanel(): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = rounded(Color.rgb(16, 29, 47), 22)
            elevation = dp(10).toFloat()
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        val brand = TextView(this).apply {
            text = "IRAN NAVIGATOR"
            setTextColor(Color.WHITE)
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.08f
        }
        header.addView(brand, LinearLayout.LayoutParams(0, -2, 1f))
        themeButton = button("تاریک") { toggleTheme() }
        header.addView(themeButton, LinearLayout.LayoutParams(dp(66), dp(38)))
        threeDButton = button("۳D روشن") { toggle3D() }
        header.addView(threeDButton, LinearLayout.LayoutParams(dp(78), dp(38)).apply {
            marginEnd = dp(6)
        })
        panel.addView(header)

        val searchRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        searchInput = EditText(this).apply {
            hint = "جست‌وجوی شهر، خیابان یا مکان"
            textSize = 13f
            maxLines = 1
            setTextColor(Color.WHITE)
            setHintTextColor(Color.rgb(165, 181, 199))
            setPadding(dp(12), 0, dp(12), 0)
            background = rounded(Color.rgb(35, 51, 72), 14)
        }
        searchRow.addView(searchInput, LinearLayout.LayoutParams(0, dp(46), 1f))
        searchRow.addView(button("جست‌وجو") { searchPlace() }, LinearLayout.LayoutParams(dp(86), dp(46)).apply {
            marginStart = dp(7)
        })
        panel.addView(searchRow, LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = dp(10)
        })
        return panel
    }

    private fun buildBottomPanel(): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = rounded(Color.rgb(13, 25, 41), 24)
            elevation = dp(14).toFloat()
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }

        val titleRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        val title = TextView(this).apply {
            text = "مسیریابی هوشمند"
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
        }
        titleRow.addView(title, LinearLayout.LayoutParams(0, -2, 1f))
        voiceButton = button("صدای فارسی") { toggleVoice() }
        titleRow.addView(voiceButton, LinearLayout.LayoutParams(dp(104), dp(36)))
        panel.addView(titleRow)

        statusText = TextView(this).apply {
            text = "برای انتخاب مبدأ یا مقصد، حالت انتخاب را مشخص و روی نقشه لمس کنید."
            setTextColor(Color.rgb(172, 191, 210))
            textSize = 11f
            maxLines = 2
            setPadding(0, dp(6), 0, dp(4))
        }
        panel.addView(statusText)

        instructionCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(9), dp(12), dp(9))
            background = rounded(Color.rgb(25, 47, 68), 16)
        }
        instructionText = TextView(this).apply {
            text = "راهنمای مسیر پس از محاسبه نمایش داده می‌شود."
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 2
        }
        nextStepText = TextView(this).apply {
            text = "گام بعدی: —"
            setTextColor(Color.rgb(178, 198, 216))
            textSize = 11f
            maxLines = 1
            setPadding(0, dp(4), 0, 0)
        }
        distanceText = TextView(this).apply {
            text = "فاصله تا گردش بعدی: —"
            setTextColor(Color.rgb(84, 220, 203))
            textSize = 11f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(4), 0, 0)
        }
        instructionCard.addView(instructionText)
        instructionCard.addView(nextStepText)
        instructionCard.addView(distanceText)
        panel.addView(instructionCard, LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = dp(4)
        })

        summaryText = TextView(this).apply {
            text = "مسافت —  •  زمان —"
            setTextColor(Color.rgb(200, 216, 230))
            textSize = 11f
            setPadding(0, dp(7), 0, dp(3))
        }
        panel.addView(summaryText)

        val modeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        val buttons = linkedMapOf<TravelMode, TextView>()
        TravelMode.values().forEach { mode ->
            val label = when (mode) {
                TravelMode.CAR -> "خودرو"
                TravelMode.MOTORCYCLE -> "موتور"
                TravelMode.WALKING -> "پیاده"
            }
            val item = button(label) {
                selectedMode = mode
                clearRoute("حالت سفر تغییر کرد؛ مسیر را دوباره محاسبه کنید.")
                updateModeButtons()
            }
            buttons[mode] = item
            modeRow.addView(item, LinearLayout.LayoutParams(0, dp(40), 1f).apply {
                if (mode != TravelMode.CAR) marginStart = dp(7)
            })
        }
        modeButtons = buttons
        panel.addView(modeRow, LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = dp(7)
        })

        val selectionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        originButton = button("انتخاب مبدأ") {
            selectingOrigin = true
            updateSelectionButtons()
            statusText.text = "مبدأ فعال است؛ روی نقشه لمس کنید یا دکمه GPS را بزنید."
        }
        destinationButton = button("انتخاب مقصد") {
            selectingOrigin = false
            updateSelectionButtons()
            statusText.text = "مقصد فعال است؛ روی نقشه لمس کنید یا از جست‌وجو استفاده کنید."
        }
        selectionRow.addView(originButton, LinearLayout.LayoutParams(0, dp(40), 1f))
        selectionRow.addView(destinationButton, LinearLayout.LayoutParams(0, dp(40), 1f).apply {
            marginStart = dp(7)
        })
        panel.addView(selectionRow, LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = dp(7)
        })

        val actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }
        gpsButton = button("موقعیت من") { locateUser() }
        calculateButton = button("محاسبه مسیر") { calculateRoute() }
        startButton = button("شروع") { startNavigation() }
        stopButton = button("توقف") { stopNavigation() }
        actionRow.addView(gpsButton, LinearLayout.LayoutParams(0, dp(44), 1f))
        actionRow.addView(calculateButton, LinearLayout.LayoutParams(0, dp(44), 1.25f).apply {
            marginStart = dp(6)
        })
        actionRow.addView(startButton, LinearLayout.LayoutParams(0, dp(44), 0.85f).apply {
            marginStart = dp(6)
        })
        actionRow.addView(stopButton, LinearLayout.LayoutParams(0, dp(44), 0.75f).apply {
            marginStart = dp(6)
        })
        panel.addView(actionRow, LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = dp(8)
        })
        return panel
    }

    private fun button(label: String, action: () -> Unit): TextView =
        TextView(this).apply {
            text = label
            gravity = Gravity.CENTER
            textSize = 11.5f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            background = rounded(Color.rgb(34, 78, 101), 13)
            isClickable = true
            isFocusable = true
            setPadding(dp(5), 0, dp(5), 0)
            setOnClickListener { action() }
        }

    private fun refreshThemeUi() {
        if (!::topPanel.isInitialized || !::bottomPanel.isInitialized) return
        val panelColor = if (isDarkTheme) Color.rgb(13, 25, 41) else Color.rgb(250, 252, 255)
        val cardColor = if (isDarkTheme) Color.rgb(25, 47, 68) else Color.rgb(229, 239, 249)
        topPanel.background = rounded(if (isDarkTheme) Color.rgb(16, 29, 47) else Color.rgb(248, 251, 255), 22)
        bottomPanel.background = rounded(panelColor, 24)
        instructionCard.background = rounded(cardColor, 16)
        val mainText = if (isDarkTheme) Color.WHITE else Color.rgb(20, 39, 57)
        val secondary = if (isDarkTheme) Color.rgb(172, 191, 210) else Color.rgb(73, 94, 116)
        instructionText.setTextColor(mainText)
        nextStepText.setTextColor(secondary)
        statusText.setTextColor(secondary)
        summaryText.setTextColor(secondary)
        distanceText.setTextColor(if (isDarkTheme) Color.rgb(84, 220, 203) else Color.rgb(0, 126, 132))
        themeButton.text = if (isDarkTheme) "تاریک" else "روشن"
        updateModeButtons()
        updateSelectionButtons()
        refreshControlButtons()
    }

    private fun refreshControlButtons() {
        if (!::voiceButton.isInitialized) return
        voiceButton.text = if (voiceEnabled) "صدا: روشن" else "صدا: خاموش"
        threeDButton.text = if (is3DEnabled) "۳D روشن" else "۳D خاموش"
        startButton.text = if (isNavigating) "در حال حرکت" else "شروع"
        startButton.isEnabled = !isNavigating
        stopButton.isEnabled = isNavigating
        calculateButton.isEnabled = !isNavigating
        val active = if (isDarkTheme) Color.rgb(0, 139, 145) else Color.rgb(0, 130, 145)
        voiceButton.background = rounded(if (voiceEnabled) active else Color.rgb(65, 83, 99), 13)
        threeDButton.background = rounded(if (is3DEnabled) active else Color.rgb(65, 83, 99), 13)
    }

    private fun updateModeButtons() {
        if (!::modeButtons.isInitialized) return
        modeButtons.forEach { (mode, view) ->
            val selected = mode == selectedMode
            view.background = rounded(
                if (selected) Color.rgb(0, 139, 145)
                else if (isDarkTheme) Color.rgb(34, 55, 76) else Color.rgb(219, 231, 242),
                13
            )
            view.setTextColor(if (selected || isDarkTheme) Color.WHITE else Color.rgb(24, 50, 73))
        }
    }

    private fun updateSelectionButtons() {
        if (!::originButton.isInitialized) return
        originButton.background = rounded(
            if (selectingOrigin) Color.rgb(0, 145, 106) else Color.rgb(49, 72, 91), 13
        )
        destinationButton.background = rounded(
            if (!selectingOrigin) Color.rgb(199, 74, 75) else Color.rgb(49, 72, 91), 13
        )
    }

    private fun toggleTheme() {
        isDarkTheme = !isDarkTheme
        refreshThemeUi()
        loadMapStyle()
    }

    private fun toggle3D() {
        is3DEnabled = !is3DEnabled
        val currentStyle = style
        if (currentStyle != null) {
            try {
                if (is3DEnabled) add3DBuildings(currentStyle) else currentStyle.removeLayer("iran-buildings-3d")
            } catch (_: Exception) {
                if (is3DEnabled) add3DBuildings(currentStyle)
            }
        }
        refreshControlButtons()
    }

    private fun toggleVoice() {
        voiceEnabled = !voiceEnabled
        if (!voiceEnabled) voice?.stop()
        refreshControlButtons()
        statusText.text = if (voiceEnabled) {
            if (voice?.isReady == true) "راهنمای صوتی فارسی فعال است."
            else "صدای فارسی روی این گوشی هنوز آماده نیست."
        } else "راهنمای صوتی خاموش شد."
    }

    private fun loadMapStyle() {
        val mapObject = map ?: return
        val styleUrl = if (isDarkTheme) {
            "https://tiles.openfreemap.org/styles/dark"
        } else {
            "https://tiles.openfreemap.org/styles/positron"
        }
        mapObject.setStyle(Style.Builder().fromUri(styleUrl)) { loadedStyle ->
            style = loadedStyle
            routeSource = null
            userSource = null
            accuracySource = null
            originSource = null
            destinationSource = null
            if (is3DEnabled) add3DBuildings(loadedStyle)
            renderRoute()
            renderPointMarkers()
            currentLocation?.let { updateLocationLayers(it) }
            statusText.text = if (isDarkTheme) "نقشه سه‌بعدی با پوسته تاریک آماده است." else "نقشه با پوسته روشن آماده است."
            refreshThemeUi()
            if (routeResult == null && origin == null && destination == null) {
                mapObject.animateCamera(
                    CameraUpdateFactory.newCameraPosition(
                        CameraPosition.Builder()
                            .target(LatLng(tehran.latitude, tehran.longitude))
                            .zoom(14.8)
                            .tilt(52.0)
                            .bearing(0.0)
                            .build()
                    ),
                    650
                )
            }
        }
    }

    private fun add3DBuildings(loadedStyle: Style) {
        if (!is3DEnabled) return
        try {
            val buildings = FillExtrusionLayer("iran-buildings-3d", "openmaptiles")
            buildings.sourceLayer = "building"
            buildings.minZoom = 14f
            buildings.setFilter(Expression.has("render_height"))
            buildings.setProperties(
                PropertyFactory.fillExtrusionColor(if (isDarkTheme) "#73869B" else "#B8C6D4"),
                PropertyFactory.fillExtrusionHeight(Expression.get("render_height")),
                PropertyFactory.fillExtrusionBase(Expression.get("render_min_height")),
                PropertyFactory.fillExtrusionOpacity(0.88f)
            )
            loadedStyle.addLayer(buildings)
        } catch (_: Exception) {
            statusText.text = "داده ساختمان سه‌بعدی در این محدوده کامل نیست."
        }
    }

    private fun applyPointSelection(point: NavPoint, message: String) {
        if (selectingOrigin) {
            origin = point
            selectingOrigin = false
            updateSelectionButtons()
            statusText.text = "$message؛ اکنون مقصد را انتخاب کنید."
        } else {
            destination = point
            statusText.text = "$message؛ حالا مسیر را محاسبه کنید."
        }
        clearRoute(null)
        renderPointMarkers()
        updatePointSummary()
    }

    private fun updatePointSummary() {
        val start = if (origin == null) "مبدأ انتخاب نشده" else "مبدأ ثبت شد"
        val end = if (destination == null) "مقصد انتخاب نشده" else "مقصد ثبت شد"
        summaryText.text = "$start  •  $end"
    }

    private fun clearRoute(message: String?) {
        routeRequestToken += 1
        routeResult = null
        isNavigating = false
        centerOnNextLocation = false
        currentManeuverIndex = 0
        lastMatchedRouteIndex = 0
        lastAnnouncedManeuver = -1
        offRouteCount = 0
        voice?.stop()
        resetCameraPadding()
        try {
            style?.removeLayer("active-route-line")
            style?.removeLayer("active-route-casing")
            style?.removeSource("active-route-source")
        } catch (_: Exception) {
        }
        routeSource = null
        if (message != null) statusText.text = message
        instructionText.text = "راهنمای مسیر پس از محاسبه نمایش داده می‌شود."
        nextStepText.text = "گام بعدی: —"
        distanceText.text = "فاصله تا گردش بعدی: —"
        summaryText.text = "مسافت —  •  زمان —"
        refreshControlButtons()
        renderPointMarkers()
    }

    private fun locateUser() {
        trackingRequested = true
        centerOnNextLocation = true
        if (!hasLocationPermission()) {
            requestPermissions(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                locationPermissionRequest
            )
            return
        }
        if (selectingOrigin && currentLocation == null) pendingSetOriginFromGps = true
        startLocationUpdates()
        val location = currentLocation
        if (location != null && selectingOrigin && isFreshLocation(location) && location.accuracy <= 60f) {
            origin = NavPoint(location.latitude, location.longitude)
            selectingOrigin = false
            updateSelectionButtons()
            clearRoute("موقعیت فعلی به‌عنوان مبدأ ثبت شد.")
            renderPointMarkers()
            updatePointSummary()
        } else {
            if (selectingOrigin) pendingSetOriginFromGps = true
            statusText.text = "در حال دریافت موقعیت تازه از GPS و شبکه..."
        }
    }

    private fun hasLocationPermission(): Boolean {
        val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun startLocationUpdates() {
        if (!hasLocationPermission()) return
        val manager = locationManager ?: return
        val listener = locationCallback
        locationListener = listener
        try {
            val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val providers = if (fine) {
                listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            } else {
                listOf(LocationManager.NETWORK_PROVIDER)
            }
            var registered = false
            providers.forEach { provider ->
                try {
                    if (manager.isProviderEnabled(provider)) {
                        manager.requestLocationUpdates(provider, 1500L, 2f, listener, Looper.getMainLooper())
                        registered = true
                    }
                } catch (_: IllegalArgumentException) {
                } catch (_: SecurityException) {
                }
            }

            val recent = providers.mapNotNull { provider ->
                try {
                    manager.getLastKnownLocation(provider)
                } catch (_: SecurityException) {
                    null
                }
            }.filter { location ->
                val age = System.currentTimeMillis() - location.time
                age in 0..20000 && location.accuracy <= 100f
            }.minByOrNull { it.accuracy }

            if (recent != null && currentLocation == null) {
                handleLocation(recent, fromCache = true)
            }
            if (!registered) statusText.text = "هیچ ارائه‌دهنده موقعیت فعالی پیدا نشد؛ GPS دستگاه را بررسی کنید."
        } catch (_: SecurityException) {
            statusText.text = "اجازه دسترسی به موقعیت صادر نشده است."
        }
    }

    private fun stopLocationUpdates() {
        try {
            locationListener?.let { locationManager?.removeUpdates(it) }
        } catch (_: SecurityException) {
        }
        locationListener = null
    }

    private fun handleLocation(location: Location, fromCache: Boolean = false) {
        val previous = currentLocation
        if (previous != null && location.time < previous.time) return
        currentLocation = location
        updateLocationLayers(location)

        if (isNavigating && !fromCache && location.accuracy <= 65f) {
            val forceCenter = centerOnNextLocation
            centerOnNextLocation = false
            followNavigationCamera(location, forceCenter)
            updateNavigationProgress(location)
        } else if (centerOnNextLocation && !fromCache && location.accuracy <= 60f) {
            centerOnNextLocation = false
            centerMapOnLocation(location)
        }

        if (pendingSetOriginFromGps && !fromCache && location.accuracy <= 60f) {
            pendingSetOriginFromGps = false
            origin = NavPoint(location.latitude, location.longitude)
            selectingOrigin = false
            updateSelectionButtons()
            clearRoute("موقعیت تازه GPS به‌عنوان مبدأ ثبت شد.")
            renderPointMarkers()
            updatePointSummary()
        }

        val accuracyText = PersianInstructionFormatter.toPersianDigits(location.accuracy.toInt().toString())
        statusText.text = if (fromCache) {
            "آخرین موقعیت ذخیره‌شده؛ دقت تقریبی $accuracyText متر. منتظر GPS تازه..."
        } else {
            "موقعیت به‌روز شد؛ دقت گزارش‌شده $accuracyText متر."
        }


    }

    private fun updateLocationLayers(location: Location) {
        val loadedStyle = style ?: return
        val point = Point.fromLngLat(location.longitude, location.latitude)
        val userFeature = Feature.fromGeometry(point)

        if (userSource == null) {
            userSource = GeoJsonSource("user-location-source", userFeature)
            loadedStyle.addSource(userSource!!)
            val userLayer = CircleLayer("user-location-layer", "user-location-source").withProperties(
                PropertyFactory.circleRadius(8f),
                PropertyFactory.circleColor("#168BFF"),
                PropertyFactory.circleStrokeColor("#FFFFFF"),
                PropertyFactory.circleStrokeWidth(2.5f)
            )
            loadedStyle.addLayer(userLayer)
        } else {
            userSource?.setGeoJson(userFeature)
        }

        val radius = location.accuracy.toDouble().coerceIn(8.0, 1200.0)
        val ring = accuracyRing(location.latitude, location.longitude, radius)
        val accuracyFeature = Feature.fromGeometry(Polygon.fromLngLats(listOf(ring)))
        if (accuracySource == null) {
            accuracySource = GeoJsonSource("user-accuracy-source", accuracyFeature)
            loadedStyle.addSource(accuracySource!!)
            val accuracyLayer = FillLayer("user-accuracy-layer", "user-accuracy-source").withProperties(
                PropertyFactory.fillColor("#168BFF"),
                PropertyFactory.fillOpacity(0.13f)
            )
            loadedStyle.addLayer(accuracyLayer)
        } else {
            accuracySource?.setGeoJson(accuracyFeature)
        }
    }

    private fun accuracyRing(latitude: Double, longitude: Double, radiusMeters: Double): List<Point> {
        val earth = 6378137.0
        val lat1 = Math.toRadians(latitude)
        val lon1 = Math.toRadians(longitude)
        val angular = radiusMeters / earth
        val ring = ArrayList<Point>()
        for (i in 0..36) {
            val bearing = 2.0 * Math.PI * i / 36.0
            val lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
            val lon2 = lon1 + atan2(
                sin(bearing) * sin(angular) * cos(lat1),
                cos(angular) - sin(lat1) * sin(lat2)
            )
            ring += Point.fromLngLat(Math.toDegrees(lon2), Math.toDegrees(lat2))
        }
        return ring
    }

    private fun renderPointMarkers() {
        val loadedStyle = style ?: return
        origin?.let { point ->
            val feature = Feature.fromGeometry(Point.fromLngLat(point.longitude, point.latitude))
            if (originSource == null) {
                originSource = GeoJsonSource("route-origin-source", feature)
                loadedStyle.addSource(originSource!!)
                loadedStyle.addLayer(
                    CircleLayer("route-origin-layer", "route-origin-source").withProperties(
                        PropertyFactory.circleRadius(8f),
                        PropertyFactory.circleColor("#12B886"),
                        PropertyFactory.circleStrokeColor("#FFFFFF"),
                        PropertyFactory.circleStrokeWidth(2f)
                    )
                )
            } else originSource?.setGeoJson(feature)
        }
        destination?.let { point ->
            val feature = Feature.fromGeometry(Point.fromLngLat(point.longitude, point.latitude))
            if (destinationSource == null) {
                destinationSource = GeoJsonSource("route-destination-source", feature)
                loadedStyle.addSource(destinationSource!!)
                loadedStyle.addLayer(
                    CircleLayer("route-destination-layer", "route-destination-source").withProperties(
                        PropertyFactory.circleRadius(8f),
                        PropertyFactory.circleColor("#EF5350"),
                        PropertyFactory.circleStrokeColor("#FFFFFF"),
                        PropertyFactory.circleStrokeWidth(2f)
                    )
                )
            } else destinationSource?.setGeoJson(feature)
        }
    }

    private fun searchPlace() {
        val query = searchInput.text.toString().trim()
        if (query.isBlank()) {
            Toast.makeText(this, "نام شهر، خیابان یا مکان را وارد کنید.", Toast.LENGTH_SHORT).show()
            return
        }
        val center = map?.cameraPosition?.target
        val bias = center ?: LatLng(tehran.latitude, tehran.longitude)
        statusText.text = "در حال جست‌وجوی مکان..."
        io.execute {
            var connection: HttpURLConnection? = null
            try {
                val q = URLEncoder.encode(query, "UTF-8")
                val endpoint = "https://photon.komoot.io/api/?q=$q&limit=5&lat=${bias.latitude}&lon=${bias.longitude}&lang=fa"
                connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 10000
                    readTimeout = 15000
                    setRequestProperty("User-Agent", "IranNavigatorPrototype/0.2")
                }
                val root = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
                val features = root.optJSONArray("features") ?: throw IllegalStateException("نتیجه‌ای پیدا نشد.")
                val results = ArrayList<SearchCandidate>()
                for (i in 0 until features.length()) {
                    val feature = features.optJSONObject(i) ?: continue
                    val coordinates = feature.optJSONObject("geometry")?.optJSONArray("coordinates") ?: continue
                    if (coordinates.length() < 2) continue
                    val properties = feature.optJSONObject("properties") ?: JSONObject()
                    val name = properties.optString("name").ifBlank {
                        properties.optString("street").ifBlank { properties.optString("city") }
                    }
                    if (name.isBlank()) continue
                    val subtitle = listOf(
                        properties.optString("street"),
                        properties.optString("district"),
                        properties.optString("city"),
                        properties.optString("state")
                    ).filter { it.isNotBlank() && it != name }.distinct().joinToString("، ")
                    results += SearchCandidate(
                        name,
                        subtitle,
                        NavPoint(coordinates.getDouble(1), coordinates.getDouble(0))
                    )
                }
                runOnUiThread {
                    if (results.isEmpty()) {
                        statusText.text = "مکانی با این نام پیدا نشد."
                    } else {
                        val labels = results.map { it.display() }.toTypedArray()
                        AlertDialog.Builder(this)
                            .setTitle("نتایج جست‌وجو")
                            .setItems(labels) { _, which ->
                                val result = results[which]
                                applyPointSelection(result.point, "مکان «${result.title}» انتخاب شد")
                                map?.animateCamera(
                                    CameraUpdateFactory.newCameraPosition(
                                        CameraPosition.Builder()
                                            .target(LatLng(result.point.latitude, result.point.longitude))
                                            .zoom(16.5)
                                            .tilt(48.0)
                                            .build()
                                    ),
                                    600
                                )
                            }
                            .setNegativeButton("بستن", null)
                            .show()
                        statusText.text = "${PersianInstructionFormatter.toPersianDigits(results.size.toString())} نتیجه پیدا شد؛ یکی را انتخاب کنید."
                    }
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

    private fun calculateRoute() {
        val start = origin
        val end = destination
        if (start == null || end == null) {
            pendingStartAfterPermission = false
            statusText.text = "ابتدا مبدأ و مقصد را انتخاب کنید."
            return
        }
        if (distanceMeters(start, end) < 15.0) {
            pendingStartAfterPermission = false
            statusText.text = "مبدأ و مقصد بیش از حد به هم نزدیک هستند."
            return
        }

        routeRequestToken += 1
        val token = routeRequestToken
        val mode = selectedMode
        calculateButton.isEnabled = false
        statusText.text = "در حال محاسبه مسیر واقعی خیابان‌ها..."
        instructionText.text = "در حال دریافت مسیر..."
        io.execute {
            try {
                val result = routingEngine.calculateRoute(start, end, mode)
                runOnUiThread {
                    if (token != routeRequestToken) return@runOnUiThread
                    routeResult = result
                    currentManeuverIndex = firstGuidanceIndex(result)
                    lastMatchedRouteIndex = 0
                    lastAnnouncedManeuver = -1
                    offRouteCount = 0
                    renderRoute()
                    renderPointMarkers()
                    fitRoute(result)
                    summaryText.text = "مسافت ${PersianInstructionFormatter.distance(result.distanceKm * 1000.0)}  •  زمان تقریبی ${PersianInstructionFormatter.duration(result.durationSeconds)}"
                    updateGuidanceCard(null)
                    statusText.text = if (result.usedMotorcycleFallback) {
                        "پروفایل اختصاصی موتورسیکلت موجود نبود؛ مسیر با پروفایل اسکوتر محاسبه شد."
                    } else {
                        "مسیر جاده‌ای محاسبه شد؛ برای دنبال‌کردن زنده، شروع را بزنید."
                    }
                    calculateButton.isEnabled = true
                    if (pendingStartAfterPermission) {
                        pendingStartAfterPermission = false
                        startNavigation()
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (token != routeRequestToken) return@runOnUiThread
                    calculateButton.isEnabled = true
                    statusText.text = "محاسبه مسیر ناموفق بود."
                    instructionText.text = error.message ?: "سرویس مسیریابی در دسترس نیست."
                }
            }
        }
    }

    private fun renderRoute() {
        val loadedStyle = style ?: return
        val result = routeResult ?: return
        val coordinates = result.points.map { Point.fromLngLat(it.longitude, it.latitude) }
        if (coordinates.size < 2) return
        val feature = Feature.fromGeometry(LineString.fromLngLats(coordinates))
        if (routeSource == null) {
            routeSource = GeoJsonSource("active-route-source", feature)
            loadedStyle.addSource(routeSource!!)
            loadedStyle.addLayer(
                LineLayer("active-route-casing", "active-route-source").withProperties(
                    PropertyFactory.lineColor(if (isDarkTheme) "#061A2B" else "#FFFFFF"),
                    PropertyFactory.lineWidth(9f),
                    PropertyFactory.lineOpacity(0.9f),
                    PropertyFactory.lineCap("round"),
                    PropertyFactory.lineJoin("round")
                )
            )
            loadedStyle.addLayer(
                LineLayer("active-route-line", "active-route-source").withProperties(
                    PropertyFactory.lineColor("#16C7C1"),
                    PropertyFactory.lineWidth(5f),
                    PropertyFactory.lineOpacity(1f),
                    PropertyFactory.lineCap("round"),
                    PropertyFactory.lineJoin("round")
                )
            )
        } else {
            routeSource?.setGeoJson(feature)
        }
    }

    private fun fitRoute(result: RouteResult) {
        if (result.points.isEmpty()) return
        val minLat = result.points.minOf { it.latitude }
        val maxLat = result.points.maxOf { it.latitude }
        val minLon = result.points.minOf { it.longitude }
        val maxLon = result.points.maxOf { it.longitude }
        val center = LatLng((minLat + maxLat) / 2.0, (minLon + maxLon) / 2.0)
        val span = max(maxLat - minLat, maxLon - minLon)
        val zoom = when {
            span < 0.025 -> 14.0
            span < 0.07 -> 12.5
            span < 0.18 -> 11.0
            span < 0.5 -> 9.5
            else -> 7.5
        }
        map?.animateCamera(
            CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder()
                    .target(center)
                    .zoom(zoom)
                    .tilt(46.0)
                    .bearing(0.0)
                    .padding(0.0, dp(110).toDouble(), 0.0, dp(240).toDouble())
                    .build()
            ),
            650
        )
    }

    private fun firstGuidanceIndex(result: RouteResult): Int {
        val index = result.maneuvers.indexOfFirst { it.type !in 1..3 }
        return if (index >= 0) index else 0
    }

    private fun updateGuidanceCard(distanceToManeuver: Double?) {
        val result = routeResult ?: return
        val maneuver = result.maneuvers.getOrNull(currentManeuverIndex)
        if (maneuver == null) {
            instructionText.text = "به مقصد رسیده‌اید."
            nextStepText.text = "مسیریابی پایان یافت."
            distanceText.text = "فاصله تا گردش بعدی: —"
            return
        }
        instructionText.text = maneuver.instruction
        val next = result.maneuvers.getOrNull(currentManeuverIndex + 1)
        nextStepText.text = if (next == null) "گام بعدی: رسیدن به مقصد" else "پس از آن: ${next.instruction}"
        distanceText.text = if (distanceToManeuver == null) {
            "راهنمای مسیر آماده است."
        } else {
            "تا گردش بعدی: ${PersianInstructionFormatter.distance(distanceToManeuver)}"
        }
    }

    private fun startNavigation() {
        if (routeResult == null) {
            pendingStartAfterPermission = true
            calculateRoute()
            return
        }
        if (!hasLocationPermission()) {
            pendingStartAfterPermission = true
            requestPermissions(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                locationPermissionRequest
            )
            return
        }
        isNavigating = true
        trackingRequested = true
        centerOnNextLocation = true
        offRouteCount = 0
        lastMatchedRouteIndex = 0
        lastAnnouncedManeuver = -1
        lastCameraFollowAt = 0L
        lastCameraLocation = null
        smoothedCameraBearing = null
        startLocationUpdates()
        refreshControlButtons()
        statusText.text = "مسیریابی زنده فعال شد؛ منتظر موقعیت دقیق GPS..."
        if (voiceEnabled) voice?.speak("مسیریابی شروع شد. ${selectedMode.label}.")
        currentLocation?.takeIf { isFreshLocation(it) && it.accuracy <= 65f }?.let {
            centerOnNextLocation = false
            followNavigationCamera(it, force = true)
            updateNavigationProgress(it)
        }
    }

    private fun stopNavigation() {
        isNavigating = false
        centerOnNextLocation = false
        smoothedCameraBearing = null
        voice?.stop()
        resetCameraPadding()
        refreshControlButtons()
        statusText.text = "مسیریابی متوقف شد."
    }

    private fun centerMapOnLocation(location: Location) {
        val currentBearing = map?.cameraPosition?.bearing ?: 0.0
        val bearing = if (location.hasBearing() && location.speed > 2f) {
            location.bearing.toDouble()
        } else {
            currentBearing
        }
        map?.animateCamera(
            CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder()
                    .target(LatLng(location.latitude, location.longitude))
                    .zoom(17.0)
                    .tilt(48.0)
                    .bearing(bearing)
                    .padding(0.0, 0.0, 0.0, 0.0)
                    .build()
            ),
            650
        )
    }

    private fun followNavigationCamera(location: Location, force: Boolean = false) {
        val now = System.currentTimeMillis()
        val point = NavPoint(location.latitude, location.longitude)
        val previous = lastCameraLocation
        val movedMeters = previous?.let { distanceMeters(it, point) } ?: Double.MAX_VALUE
        val movementThreshold = if (location.accuracy <= 25f) 3.0 else 7.0
        if (!force && (movedMeters < movementThreshold || now - lastCameraFollowAt < 1400L)) return

        val currentBearing = smoothedCameraBearing ?: (map?.cameraPosition?.bearing ?: 0.0)
        val targetBearing = if (location.hasBearing() && location.speed > 2f) {
            location.bearing.toDouble()
        } else {
            currentBearing
        }
        val delta = ((targetBearing - currentBearing + 540.0) % 360.0) - 180.0
        val bearing = (currentBearing + delta * 0.28 + 360.0) % 360.0
        smoothedCameraBearing = bearing

        map?.animateCamera(
            CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder()
                    .target(LatLng(point.latitude, point.longitude))
                    .zoom(17.2)
                    .tilt(58.0)
                    .bearing(bearing)
                    .padding(0.0, dp(160).toDouble(), 0.0, dp(170).toDouble())
                    .build()
            ),
            850
        )
        lastCameraFollowAt = now
        lastCameraLocation = point
    }

    private fun resetCameraPadding() {
        val current = map?.cameraPosition ?: return
        val target = current.target ?: LatLng(tehran.latitude, tehran.longitude)
        map?.animateCamera(
            CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder()
                    .target(target)
                    .zoom(current.zoom)
                    .tilt(current.tilt)
                    .bearing(current.bearing)
                    .padding(0.0, 0.0, 0.0, 0.0)
                    .build()
            ),
            350
        )
    }

    private fun updateNavigationProgress(location: Location) {
        val result = routeResult ?: return
        if (result.points.isEmpty()) return

        val current = NavPoint(location.latitude, location.longitude)
        val nearest = nearestRoutePoint(current, result.points, lastMatchedRouteIndex)
        lastMatchedRouteIndex = max(lastMatchedRouteIndex, nearest.index)

        if (nearest.distanceMeters > 75.0 && location.accuracy <= 40f) {
            offRouteCount += 1
        } else {
            offRouteCount = 0
        }

        val maneuver = result.maneuvers.getOrNull(currentManeuverIndex)
        if (maneuver != null) {
            val targetIndex = maneuver.endShapeIndex.coerceIn(0, result.points.lastIndex)
            val distance = distanceAlongRoute(result.points, lastMatchedRouteIndex, targetIndex)

            if (targetIndex > 0 && lastMatchedRouteIndex >= targetIndex - 2 &&
                currentManeuverIndex < result.maneuvers.lastIndex) {
                currentManeuverIndex += 1
                lastAnnouncedManeuver = -1
                updateGuidanceCard(null)
            } else {
                updateGuidanceCard(distance)
                if (voiceEnabled && distance in 35.0..350.0 && lastAnnouncedManeuver != currentManeuverIndex) {
                    val spoken = "تا ${PersianInstructionFormatter.distance(distance)} دیگر، ${maneuver.instruction}"
                    voice?.speak(spoken)
                    lastAnnouncedManeuver = currentManeuverIndex
                }
            }
        }

        val end = destination
        if (end != null && distanceMeters(current, end) < 35.0) {
            isNavigating = false
            centerOnNextLocation = false
            voice?.speak("به مقصد رسیدید.")
            statusText.text = "به مقصد رسیدید."
            resetCameraPadding()
            refreshControlButtons()
            return
        }

        if (offRouteCount >= 4 && System.currentTimeMillis() - lastRerouteAt > 25000L) {
            rerouteFrom(location)
        }
    }

    private data class RouteMatch(val index: Int, val distanceMeters: Double)

    private fun nearestRoutePoint(
        point: NavPoint,
        points: List<NavPoint>,
        previousIndex: Int
    ): RouteMatch {
        var bestIndex = previousIndex.coerceIn(0, points.lastIndex)
        var bestDistance = Double.MAX_VALUE
        val startIndex = (previousIndex - 3).coerceAtLeast(0)

        for (index in startIndex..points.lastIndex) {
            val distance = distanceMeters(point, points[index])
            if (distance < bestDistance) {
                bestDistance = distance
                bestIndex = index
            }
        }
        return RouteMatch(bestIndex, bestDistance)
    }

    private fun distanceAlongRoute(points: List<NavPoint>, startIndex: Int, endIndex: Int): Double {
        if (points.size < 2) return 0.0
        val start = startIndex.coerceIn(0, points.lastIndex)
        val end = endIndex.coerceIn(start, points.lastIndex)
        var distance = 0.0
        for (index in start until end) {
            distance += distanceMeters(points[index], points[index + 1])
        }
        return distance
    }

    private fun rerouteFrom(location: Location) {
        val end = destination ?: return
        lastRerouteAt = System.currentTimeMillis()
        offRouteCount = 0
        val start = NavPoint(location.latitude, location.longitude)
        val mode = selectedMode
        val token = ++routeRequestToken
        statusText.text = "از مسیر خارج شده‌اید؛ در حال محاسبه مسیر جدید..."
        io.execute {
            try {
                val result = routingEngine.calculateRoute(start, end, mode)
                runOnUiThread {
                    if (token != routeRequestToken || !isNavigating) return@runOnUiThread
                    routeResult = result
                    origin = start
                    currentManeuverIndex = firstGuidanceIndex(result)
                    lastAnnouncedManeuver = -1
                    renderRoute()
                    renderPointMarkers()
                    currentLocation?.let { followNavigationCamera(it, force = true) }
                    summaryText.text = "مسافت باقی‌مانده ${PersianInstructionFormatter.distance(result.distanceKm * 1000.0)}  •  ${PersianInstructionFormatter.duration(result.durationSeconds)}"
                    updateGuidanceCard(null)
                    statusText.text = "مسیر جدید محاسبه شد."
                    if (voiceEnabled) voice?.speak("مسیر جدید محاسبه شد.")
                }
            } catch (_: Exception) {
                runOnUiThread {
                    statusText.text = "محاسبه مجدد مسیر ناموفق بود؛ به مسیر اصلی برگردید."
                }
            }
        }
    }

    private fun isFreshLocation(location: Location): Boolean {
        val age = System.currentTimeMillis() - location.time
        return age in 0..20000
    }

    private fun distanceMeters(a: NavPoint, b: NavPoint): Double {
        val earth = 6371000.0
        val dLat = Math.toRadians(b.latitude - a.latitude)
        val dLon = Math.toRadians(b.longitude - a.longitude)
        val lat1 = Math.toRadians(a.latitude)
        val lat2 = Math.toRadians(b.latitude)
        val h = sin(dLat / 2).pow(2.0) + cos(lat1) * cos(lat2) * sin(dLon / 2).pow(2.0)
        return 2.0 * earth * asin(sqrt(h.coerceIn(0.0, 1.0)))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == locationPermissionRequest) {
            if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
                trackingRequested = true
                startLocationUpdates()
                if (pendingStartAfterPermission) {
                    pendingStartAfterPermission = false
                    startNavigation()
                }
            } else {
                pendingStartAfterPermission = false
                statusText.text = "برای GPS و مسیریابی زنده باید اجازه موقعیت مکانی بدهید."
            }
        }
    }

    override fun onStart() {
        super.onStart()
        mapView.onStart()
    }

    override fun onResume() {
        super.onResume()
        mapView.onResume()
        if (trackingRequested && hasLocationPermission()) startLocationUpdates()
    }

    override fun onPause() {
        stopLocationUpdates()
        mapView.onPause()
        super.onPause()
    }

    override fun onStop() {
        mapView.onStop()
        super.onStop()
    }

    override fun onLowMemory() {
        super.onLowMemory()
        mapView.onLowMemory()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        mapView.onSaveInstanceState(outState)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        stopLocationUpdates()
        voice?.shutdown()
        io.shutdownNow()
        mapView.onDestroy()
        super.onDestroy()
    }

    private fun rounded(color: Int, radius: Int): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius).toFloat()
        }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
