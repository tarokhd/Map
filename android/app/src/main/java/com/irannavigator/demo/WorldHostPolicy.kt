package com.irannavigator.demo

import java.net.URI

/** Security and location preconditions independent of Android framework classes. */
object WorldHostPolicy {
    const val ORIGIN = "https://appassets.androidplatform.net"
    const val ENTRY = "$ORIGIN/assets/world/index.html"

    fun isTrustedUrl(value: String?): Boolean = try {
        val uri = URI(value ?: "")
        uri.scheme == "https" && uri.host == "appassets.androidplatform.net" &&
            uri.userInfo == null && uri.port in listOf(-1, 443) &&
            uri.path.startsWith("/assets/world/") && uri.path.split('/').none { it == ".." }
    } catch (_: Exception) { false }

    fun callbackId(value: String): Int? = value.toIntOrNull()?.takeIf { it in 1..1_000_000_000 }

    fun isFreshAccurateLocation(latitude: Double, longitude: Double, accuracy: Float, timestamp: Long, now: Long): Boolean =
        latitude.isFinite() && longitude.isFinite() && latitude in -90.0..90.0 && longitude in -180.0..180.0 &&
            accuracy.isFinite() && accuracy in 0f..65f && now - timestamp in 0L..15000L
}
