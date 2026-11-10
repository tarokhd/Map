import Foundation

struct PlaceSearchService {
    func search(_ query: String, near coordinate: RouteCoordinate?) async throws -> [PlaceSearchResult] {
        var components = URLComponents(string: "https://photon.komoot.io/api/")!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "6"),
            URLQueryItem(name: "lang", value: "fa")
        ]
        if let coordinate {
            items.append(URLQueryItem(name: "lat", value: String(coordinate.latitude)))
            items.append(URLQueryItem(name: "lon", value: String(coordinate.longitude)))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("IranNavigator-iOS/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SearchError.serviceUnavailable
        }

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let features = root?["features"] as? [[String: Any]] ?? []
        return features.compactMap { feature in
            guard
                let geometry = feature["geometry"] as? [String: Any],
                let coordinates = geometry["coordinates"] as? [Double],
                coordinates.count >= 2
            else { return nil }

            let properties = feature["properties"] as? [String: Any] ?? [:]
            let name = (properties["name"] as? String)
                ?? (properties["street"] as? String)
                ?? (properties["city"] as? String)
                ?? ""
            guard !name.isEmpty else { return nil }

            let subtitle = [
                properties["street"] as? String,
                properties["district"] as? String,
                properties["city"] as? String,
                properties["state"] as? String
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != name }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
            .joined(separator: "، ")

            return PlaceSearchResult(
                title: name,
                subtitle: subtitle,
                coordinate: RouteCoordinate(latitude: coordinates[1], longitude: coordinates[0])
            )
        }
    }

    enum SearchError: LocalizedError {
        case serviceUnavailable

        var errorDescription: String? {
            "سرویس جست‌وجوی مکان در دسترس نیست."
        }
    }
}
