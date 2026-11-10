package com.irannavigator.demo

import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class RoutingEngine(
    private val endpoint: String = "https://valhalla1.openstreetmap.de/route"
) {
    fun calculateRoute(
        origin: NavPoint,
        destination: NavPoint,
        mode: TravelMode
    ): RouteResult {
        var lastError: Exception? = null

        for ((index, costing) in mode.costingCandidates().withIndex()) {
            try {
                return calculateWithCosting(
                    origin = origin,
                    destination = destination,
                    costing = costing,
                    usedMotorcycleFallback = index > 0
                )
            } catch (error: Exception) {
                lastError = error
            }
        }

        throw lastError ?: IllegalStateException("محاسبه مسیر ناموفق بود.")
    }

    private fun calculateWithCosting(
        origin: NavPoint,
        destination: NavPoint,
        costing: String,
        usedMotorcycleFallback: Boolean
    ): RouteResult {
        val request = JSONObject().apply {
            put("locations", JSONArray().apply {
                put(JSONObject().put("lat", origin.latitude).put("lon", origin.longitude))
                put(JSONObject().put("lat", destination.latitude).put("lon", destination.longitude))
            })
            put("costing", costing)
            put("units", "kilometers")
            put("language", "en-US")
            put("shape_format", "polyline6")
            put("directions_type", "instructions")
            put("id", "iran-navigator-android-v0.3")
        }

        val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15000
            readTimeout = 30000
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("User-Agent", "IranNavigatorPrototype/0.3")
        }

        try {
            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(request.toString())
                writer.flush()
            }

            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.let { input ->
                BufferedReader(InputStreamReader(input, Charsets.UTF_8)).use { it.readText() }
            }.orEmpty()

            if (status !in 200..299) {
                val detail = try {
                    JSONObject(body).optString("error", body)
                } catch (_: Exception) {
                    body
                }
                throw IllegalStateException("سرویس مسیریابی پاسخ $status داد: $detail")
            }

            val root = JSONObject(body)
            val trip = root.optJSONObject("trip")
                ?: throw IllegalStateException(root.optString("error", "پاسخ مسیریابی معتبر نیست"))
            val legs = trip.optJSONArray("legs")
                ?: throw IllegalStateException("مسیر معتبری پیدا نشد.")
            if (legs.length() == 0) throw IllegalStateException("مسیر معتبری پیدا نشد.")

            val firstLeg = legs.getJSONObject(0)
            val shape = firstLeg.optString("shape")
            val points = decodePolyline6(shape)
            if (points.size < 2) throw IllegalStateException("هندسه مسیر از سرویس دریافت نشد.")

            val summary = trip.optJSONObject("summary") ?: firstLeg.optJSONObject("summary") ?: JSONObject()
            val distanceKm = summary.optDouble("length", 0.0)
            val durationSeconds = summary.optDouble("time", 0.0)

            val maneuversJson = firstLeg.optJSONArray("maneuvers") ?: JSONArray()
            val maneuvers = ArrayList<RouteManeuver>(maneuversJson.length())
            for (index in 0 until maneuversJson.length()) {
                val item = maneuversJson.optJSONObject(index) ?: continue
                val names = item.optJSONArray("street_names")
                val streetName = names?.let { array ->
                    (0 until array.length()).mapNotNull { i ->
                        array.optString(i).takeIf { it.isNotBlank() }
                    }.joinToString("، ")
                }.orEmpty()
                val type = item.optInt("type", 8)
                maneuvers += RouteManeuver(
                    type = type,
                    instruction = PersianInstructionFormatter.instruction(type, streetName),
                    streetName = streetName,
                    lengthKm = item.optDouble("length", 0.0),
                    timeSeconds = item.optDouble("time", 0.0),
                    endShapeIndex = item.optInt("end_shape_index", 0)
                )
            }

            return RouteResult(
                points = points,
                maneuvers = maneuvers,
                distanceKm = distanceKm,
                durationSeconds = durationSeconds,
                usedMotorcycleFallback = usedMotorcycleFallback
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun decodePolyline6(encoded: String): List<NavPoint> {
        val points = ArrayList<NavPoint>()
        var index = 0
        var latitude = 0
        var longitude = 0

        fun readDelta(): Int? {
            var result = 0
            var shift = 0
            var byte: Int
            do {
                if (index >= encoded.length || shift > 30) return null
                byte = encoded[index++].code - 63
                if (byte < 0) return null
                result = result or ((byte and 0x1f) shl shift)
                shift += 5
            } while (byte >= 0x20)
            return if ((result and 1) != 0) (result shr 1).inv() else (result shr 1)
        }

        while (index < encoded.length) {
            val deltaLatitude = readDelta() ?: return points
            val deltaLongitude = readDelta() ?: return points
            latitude += deltaLatitude
            longitude += deltaLongitude

            val lat = latitude / 1_000_000.0
            val lon = longitude / 1_000_000.0
            if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return emptyList()
            points += NavPoint(lat, lon)
        }
        return points
    }
}
