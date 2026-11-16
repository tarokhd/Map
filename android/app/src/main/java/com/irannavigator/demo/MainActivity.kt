package com.irannavigator.demo

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Color
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.webkit.WebViewAssetLoader
import org.json.JSONObject
import java.io.ByteArrayInputStream

/** Android host for the bundled 3D World renderer, with permission-gated native GPS. */
class MainActivity : Activity() {
    lateinit var worldView: WebView
        private set
    private lateinit var root: FrameLayout
    private lateinit var locations: LocationManager
    private val handler = Handler(Looper.getMainLooper())
    private data class Pending(val once: Boolean, val timeout: Long, var timer: Runnable? = null)
    private val pending = mutableMapOf<Int, Pending>()
    private var requestingPermission = false
    private var receivingLocations = false
    private var resumed = false
    private var destroyed = false
    private var rendererAlive = false
    private var backCallback: android.window.OnBackInvokedCallback? = null
    private val permissionRequest = 410

    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) { publishLocation(location) }
        override fun onProviderEnabled(provider: String) = Unit
        override fun onProviderDisabled(provider: String) {
            pending.filterValues { !it.once }.keys.toList().forEach { sendError(it, 2, "موقعیت فعلاً در دسترس نیست.", false) }
        }
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(9, 19, 29)
        window.navigationBarColor = Color.rgb(9, 19, 29)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        root = FrameLayout(this)
        root.setBackgroundColor(Color.rgb(9, 19, 29))
        setContentView(root)
        locations = getSystemService(LOCATION_SERVICE) as LocationManager
        createWorldView()
        if (Build.VERSION.SDK_INT >= 33) {
            backCallback = android.window.OnBackInvokedCallback { handleBack() }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, backCallback!!)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWorldView() {
        root.removeAllViews()
        worldView = WebView(this)
        rendererAlive = true
        worldView.setBackgroundColor(Color.rgb(9, 19, 29))
        val debug = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        WebView.setWebContentsDebuggingEnabled(debug)
        worldView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
            setGeolocationEnabled(false) // Location is provided by the scoped native bridge.
            setSupportMultipleWindows(false)
            javaScriptCanOpenWindowsAutomatically = false
            mediaPlaybackRequiresUserGesture = true
            if (Build.VERSION.SDK_INT >= 26) safeBrowsingEnabled = true
        }
        val loader = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.PathHandler { path ->
                if (!path.startsWith("world/") || path.split('/').any { it == ".." }) {
                    WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden", emptyMap(), ByteArrayInputStream(ByteArray(0)))
                } else try {
                    val mime = when (path.substringAfterLast('.')) {
                        "html" -> "text/html"
                        "js", "mjs" -> "application/javascript"
                        "css" -> "text/css"
                        "svg" -> "image/svg+xml"
                        "json", "webmanifest" -> "application/json"
                        else -> "application/octet-stream"
                    }
                    WebResourceResponse(mime, "UTF-8", 200, "OK", mapOf("Cache-Control" to "no-store", "X-Content-Type-Options" to "nosniff"), assets.open(path))
                } catch (_: Exception) {
                    WebResourceResponse("text/plain", "UTF-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0)))
                }
            }).build()
        worldView.addJavascriptInterface(LocationBridge(), "AndroidWorld")
        worldView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? = loader.shouldInterceptRequest(request.url)
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (WorldHostPolicy.isTrustedUrl(request.url.toString())) return false
                if (request.isForMainFrame && request.hasGesture() && request.url.scheme == "https") {
                    try { startActivity(Intent(Intent.ACTION_VIEW, request.url)) } catch (_: Exception) { }
                }
                return true
            }
            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                if (!WorldHostPolicy.isTrustedUrl(url)) { view.stopLoading(); cancelAllLocations() }
            }
            override fun onRenderProcessGone(view: WebView, detail: android.webkit.RenderProcessGoneDetail): Boolean {
                rendererAlive = false
                cancelAllLocations()
                root.removeView(view)
                view.destroy()
                val panel = LinearLayout(this@MainActivity).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER
                    setPadding(40, 40, 40, 40)
                    addView(TextView(context).apply { text = "موتور نمایش متوقف شد. Android System WebView را به‌روز کنید یا دوباره تلاش کنید."; setTextColor(Color.WHITE) })
                    addView(Button(context).apply { text = "تلاش دوباره"; setOnClickListener { createWorldView() } })
                }
                root.addView(panel, FrameLayout.LayoutParams(-1, -1))
                return true
            }
        }
        worldView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
        }
        root.addView(worldView, FrameLayout.LayoutParams(-1, -1))
        worldView.loadUrl(WorldHostPolicy.ENTRY)
    }

    inner class LocationBridge {
        @JavascriptInterface
        fun requestLocation(value: String, once: Boolean, timeout: Long) {
            val id = WorldHostPolicy.callbackId(value) ?: return
            runOnUiThread {
                if (destroyed || !rendererAlive || !WorldHostPolicy.isTrustedUrl(worldView.url)) return@runOnUiThread
                pending.remove(id)?.timer?.let { handler.removeCallbacks(it) }
                pending[id] = Pending(once, timeout.coerceIn(1000L, 60000L))
                if (hasLocationPermission()) startLocations() else if (!requestingPermission) {
                    requestingPermission = true
                    requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), permissionRequest)
                }
            }
        }
        @JavascriptInterface
        fun cancelLocation(value: String) {
            val id = WorldHostPolicy.callbackId(value) ?: return
            runOnUiThread {
                pending.remove(id)?.timer?.let { handler.removeCallbacks(it) }
                if (pending.isEmpty()) stopLocations()
            }
        }
    }

    private fun hasLocationPermission() = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    private fun startLocations() {
        if (!resumed || pending.isEmpty() || !hasLocationPermission()) return
        for ((id, request) in pending.toMap()) if (request.timer == null) armTimeout(id, request)
        if (!receivingLocations) {
            val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER).filter {
                try { locations.isProviderEnabled(it) } catch (_: Exception) { false }
            }
            if (providers.isEmpty()) {
                pending.keys.toList().forEach { sendError(it, 2, "GPS خاموش یا موقعیت در دسترس نیست.", pending[it]?.once == true) }
                return
            }
            try {
                for (provider in providers) locations.requestLocationUpdates(provider, 500L, 1f, listener, Looper.getMainLooper())
                receivingLocations = true
                providers.mapNotNull { locations.getLastKnownLocation(it) }.filter { fresh(it) }.minByOrNull { it.accuracy }?.let { publishLocation(it) }
            } catch (_: SecurityException) {
                pending.keys.toList().forEach { sendError(it, 1, "اجازه موقعیت داده نشد.", true) }
            }
        }
    }
    private fun fresh(location: Location) = WorldHostPolicy.isFreshAccurateLocation(location.latitude, location.longitude, location.accuracy, location.time, System.currentTimeMillis())

    private fun armTimeout(id: Int, request: Pending) {
        request.timer?.let { handler.removeCallbacks(it) }
        val timer = Runnable {
            if (pending[id] !== request) return@Runnable
            request.timer = null
            sendError(id, 3, "دریافت موقعیت بیش از حد طول کشید.", request.once)
        }
        request.timer = timer
        handler.postDelayed(timer, request.timeout)
    }

    private fun publishLocation(location: Location) {
        if (!location.latitude.isFinite() || !location.longitude.isFinite() || !location.accuracy.isFinite()) return
        for ((id, request) in pending.toMap()) {
            if (request.once && !fresh(location)) continue
            val coordinates = JSONObject().put("latitude", location.latitude).put("longitude", location.longitude)
                .put("accuracy", location.accuracy.toDouble())
                .put("altitude", if (location.hasAltitude()) location.altitude else JSONObject.NULL)
                .put("altitudeAccuracy", JSONObject.NULL)
                .put("heading", if (location.hasBearing()) location.bearing.toDouble() else JSONObject.NULL)
                .put("speed", if (location.hasSpeed()) location.speed.toDouble() else JSONObject.NULL)
            val position = JSONObject().put("coords", coordinates).put("timestamp", location.time)
            if (request.once) { request.timer?.let { handler.removeCallbacks(it) }; pending.remove(id) }
            else if (fresh(location)) armTimeout(id, request)
            dispatch(id, position.toString(), "null")
        }
        if (pending.isEmpty()) stopLocations()
    }
    private fun sendError(id: Int, code: Int, message: String, remove: Boolean) {
        if (remove) pending.remove(id)?.timer?.let { handler.removeCallbacks(it) }
        dispatch(id, "null", JSONObject().put("code", code).put("message", message).toString())
        if (pending.isEmpty()) stopLocations()
    }
    private fun dispatch(id: Int, position: String, error: String) {
        if (!destroyed && rendererAlive && WorldHostPolicy.isTrustedUrl(worldView.url)) worldView.evaluateJavascript("window.__androidLocation?.($id,$position,$error);", null)
    }
    private fun stopLocations() {
        if (receivingLocations) try { locations.removeUpdates(listener) } catch (_: Exception) { }
        receivingLocations = false
    }
    private fun cancelAllLocations() {
        for (request in pending.values) request.timer?.let { handler.removeCallbacks(it) }
        pending.clear()
        stopLocations()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequest) return
        requestingPermission = false
        if (hasLocationPermission()) startLocations()
        else pending.keys.toList().forEach { sendError(it, 1, "اجازه موقعیت داده نشد.", true) }
    }
    private fun handleBack() {
        if (!rendererAlive) { finish(); return }
        worldView.evaluateJavascript("""
            (() => {
              const dialog = document.querySelector('dialog[open]');
              if (dialog) { dialog.close(); return true; }
              const screen = document.body.dataset.screen;
              if (screen === 'navigation' || screen === 'preview') { document.getElementById('stopNavigation').click(); return true; }
              if (document.body.classList.contains('picking')) { document.getElementById('cancelPick').click(); return true; }
              if (screen === 'planning') { document.getElementById('clearDestination').click(); return true; }
              return false;
            })()
        """.trimIndent()) { handled -> if (handled != "true") finish() }
    }
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() { handleBack() }
    override fun onResume() {
        super.onResume(); resumed = true; if (rendererAlive) worldView.onResume(); startLocations()
    }
    override fun onPause() {
        resumed = false
        stopLocations()
        for (request in pending.values) {
            request.timer?.let { handler.removeCallbacks(it) }
            request.timer = null
        }
        if (rendererAlive) worldView.onPause()
        super.onPause()
    }
    override fun onDestroy() {
        destroyed = true
        cancelAllLocations()
        handler.removeCallbacksAndMessages(null)
        if (Build.VERSION.SDK_INT >= 33) backCallback?.let { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
        if (rendererAlive) {
            worldView.removeJavascriptInterface("AndroidWorld")
            worldView.destroy()
        }
        rendererAlive = false
        root.removeAllViews()
        super.onDestroy()
    }
}
