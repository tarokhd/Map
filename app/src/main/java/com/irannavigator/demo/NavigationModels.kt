package com.irannavigator.demo

data class NavPoint(
    val latitude: Double,
    val longitude: Double
)

enum class TravelMode(val costing: String, val label: String) {
    CAR("auto", "خودرو"),
    MOTORCYCLE("motorcycle", "موتورسیکلت"),
    WALKING("pedestrian", "پیاده‌روی")
}

data class RouteManeuver(
    val type: Int,
    val instruction: String,
    val streetName: String,
    val lengthKm: Double,
    val timeSeconds: Double,
    val endShapeIndex: Int
)

data class RouteResult(
    val points: List<NavPoint>,
    val maneuvers: List<RouteManeuver>,
    val distanceKm: Double,
    val durationSeconds: Double
)

object PersianInstructionFormatter {
    fun instruction(type: Int, streetName: String): String {
        val action = when (type) {
            1, 2, 3 -> "حرکت را آغاز کنید"
            4, 5, 6 -> "به مقصد رسیده‌اید"
            7, 8 -> "به مسیر مستقیم ادامه دهید"
            9 -> "کمی به سمت راست متمایل شوید"
            10 -> "به راست بپیچید"
            11 -> "با زاویه تند به راست بپیچید"
            12, 13 -> "دور بزنید و در جهت مخالف حرکت کنید"
            14 -> "با زاویه تند به چپ بپیچید"
            15 -> "به چپ بپیچید"
            16 -> "کمی به سمت چپ متمایل شوید"
            17 -> "از مسیر مستقیم وارد رمپ شوید"
            18 -> "از رمپ سمت راست وارد شوید"
            19 -> "از رمپ سمت چپ وارد شوید"
            20 -> "خروجی سمت راست را انتخاب کنید"
            21 -> "خروجی سمت چپ را انتخاب کنید"
            22 -> "در مسیر مستقیم بمانید"
            23 -> "در سمت راست مسیر بمانید"
            24 -> "در سمت چپ مسیر بمانید"
            25 -> "به مسیر ادغام شوید"
            26 -> "وارد میدان شوید"
            27 -> "از میدان خارج شوید"
            28 -> "وارد مسیر کشتی شوید"
            29 -> "از مسیر کشتی خارج شوید"
            else -> "به مسیر ادامه دهید"
        }
        val street = streetName.trim()
        return if (street.isBlank() || street.equals("unnamed road", ignoreCase = true)) {
            action
        } else {
            "$action و وارد $street شوید"
        }
    }

    fun distance(meters: Double): String {
        val safe = meters.coerceAtLeast(0.0)
        return if (safe >= 1000.0) {
            val km = safe / 1000.0
            val rounded = if (km < 10.0) String.format(java.util.Locale.US, "%.1f", km) else km.toInt().toString()
            "${toPersianDigits(rounded)} کیلومتر"
        } else {
            "${toPersianDigits(safe.toInt().toString())} متر"
        }
    }

    fun duration(seconds: Double): String {
        val minutes = (seconds / 60.0).toInt().coerceAtLeast(1)
        val hours = minutes / 60
        val remainder = minutes % 60
        return if (hours > 0) {
            "${toPersianDigits(hours.toString())} ساعت و ${toPersianDigits(remainder.toString())} دقیقه"
        } else {
            "${toPersianDigits(minutes.toString())} دقیقه"
        }
    }

    fun toPersianDigits(value: String): String {
        val digits = charArrayOf('۰','۱','۲','۳','۴','۵','۶','۷','۸','۹')
        return value.map { ch ->
            if (ch in '0'..'9') digits[ch - '0'] else if (ch == '.') '٫' else ch
        }.joinToString("")
    }
}
