import Foundation

struct RoutingService {
    private let endpoint = URL(string: "https://valhalla1.openstreetmap.de/route")!

    func calculateRoute(
        from origin: RouteCoordinate,
        to destination: RouteCoordinate,
        mode: TravelMode
    ) async throws -> NavigationRoute {
        var lastError: Error = RoutingError.noRoute

        for (index, costing) in mode.costingCandidates.enumerated() {
            do {
                return try await requestRoute(
                    from: origin,
                    to: destination,
                    costing: costing,
                    usedMotorcycleFallback: index > 0
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func requestRoute(
        from origin: RouteCoordinate,
        to destination: RouteCoordinate,
        costing: String,
        usedMotorcycleFallback: Bool
    ) async throws -> NavigationRoute {
        let body: [String: Any] = [
            "locations": [
                ["lat": origin.latitude, "lon": origin.longitude],
                ["lat": destination.latitude, "lon": destination.longitude]
            ],
            "costing": costing,
            "units": "kilometers",
            "language": "en-US",
            "shape_format": "polyline6",
            "directions_type": "instructions",
            "id": "iran-navigator-ios-v0.1"
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("IranNavigator-iOS/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RoutingError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = payload?["error"] as? String
                ?? payload?["status_message"] as? String
                ?? "خطای سرویس مسیریابی (\(http.statusCode))"
            throw RoutingError.service(message)
        }

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let trip = root?["trip"] as? [String: Any],
            let legs = trip["legs"] as? [[String: Any]],
            let leg = legs.first,
            let encodedShape = leg["shape"] as? String
        else {
            throw RoutingError.noRoute
        }

        let points = Polyline6Decoder.decode(encodedShape)
        guard points.count >= 2 else { throw RoutingError.invalidGeometry }

        let summary = (trip["summary"] as? [String: Any])
            ?? (leg["summary"] as? [String: Any])
            ?? [:]
        let distance = summary["length"] as? Double ?? 0
        let duration = summary["time"] as? Double ?? 0
        let rawManeuvers = leg["maneuvers"] as? [[String: Any]] ?? []

        let maneuvers = rawManeuvers.enumerated().map { index, item in
            let type = item["type"] as? Int ?? 8
            let streetNames = item["street_names"] as? [String] ?? []
            let street = streetNames.filter { !$0.isEmpty }.joined(separator: "، ")
            return RouteManeuver(
                id: index,
                type: type,
                instruction: PersianInstructionFormatter.instruction(type: type, streetName: street),
                streetName: street,
                lengthKilometers: item["length"] as? Double ?? 0,
                timeSeconds: item["time"] as? Double ?? 0,
                endShapeIndex: item["end_shape_index"] as? Int ?? 0
            )
        }

        return NavigationRoute(
            points: points,
            maneuvers: maneuvers,
            distanceKilometers: distance,
            durationSeconds: duration,
            usedMotorcycleFallback: usedMotorcycleFallback
        )
    }

    enum RoutingError: LocalizedError {
        case invalidResponse
        case noRoute
        case invalidGeometry
        case service(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "پاسخ سرویس مسیریابی معتبر نیست."
            case .noRoute: return "مسیر قابل استفاده‌ای پیدا نشد."
            case .invalidGeometry: return "هندسه مسیر دریافت نشد."
            case .service(let message): return message
            }
        }
    }
}
