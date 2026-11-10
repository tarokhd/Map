import CoreLocation
import MapLibre
import SwiftUI
import UIKit

struct MapLibreView: UIViewRepresentable {
    let theme: MapTheme
    let show3DBuildings: Bool
    let origin: RouteCoordinate?
    let destination: RouteCoordinate?
    let routePoints: [RouteCoordinate]
    let userCoordinate: RouteCoordinate?
    let userAccuracy: CLLocationAccuracy?
    let userHeading: CLLocationDirection?
    let isNavigating: Bool
    let recenterToken: Int
    let onMapTap: (RouteCoordinate) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: theme.styleURL)
        mapView.delegate = context.coordinator
        mapView.allowsRotating = true
        mapView.allowsTilting = true
        mapView.allowsZooming = true
        mapView.allowsScrolling = true
        mapView.attributionButtonPosition = .topLeft
        mapView.attributionButtonMargins = CGPoint(x: 12, y: 128)
        mapView.compassViewPosition = .topLeft
        mapView.compassViewMargins = CGPoint(x: 12, y: 178)
        let initialCenter = CLLocationCoordinate2D(latitude: 35.7006, longitude: 51.4050)
        mapView.setCenter(initialCenter, zoomLevel: 13.8, animated: false)
        let initialCamera = MLNMapCamera(
            lookingAtCenter: initialCenter,
            altitude: mapView.camera.altitude,
            pitch: show3DBuildings ? 50 : 0,
            heading: 0
        )
        mapView.setCamera(initialCamera, animated: false)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        for recognizer in mapView.gestureRecognizers ?? [] {
            if recognizer is UITapGestureRecognizer {
                tap.require(toFail: recognizer)
            }
        }
        mapView.addGestureRecognizer(tap)
        context.coordinator.mapView = mapView
        context.coordinator.activeStyleURL = theme.styleURL
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if coordinator.activeStyleURL != theme.styleURL {
            coordinator.activeStyleURL = theme.styleURL
            mapView.styleURL = theme.styleURL
            return
        }

        coordinator.updateMapContent(mapView)
        coordinator.recenterIfNeeded(mapView)
        coordinator.updateCamera(mapView)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreView
        weak var mapView: MLNMapView?
        var activeStyleURL: URL?
        private var originAnnotation: MLNPointAnnotation?
        private var destinationAnnotation: MLNPointAnnotation?
        private var userAnnotation: MLNPointAnnotation?
        private var lastAccuracyCenter: RouteCoordinate?
        private var lastAccuracyMeters: CLLocationAccuracy?
        private var lastOrigin: RouteCoordinate?
        private var lastDestination: RouteCoordinate?
        private var lastUserCoordinate: RouteCoordinate?
        private var lastRoutePoints: [RouteCoordinate] = []
        private var lastFollowCoordinate: RouteCoordinate?
        private var lastFollowTime = Date.distantPast
        private var lastSmoothedHeading: CLLocationDirection?
        private var wasFollowingNavigation = false
        private var lastRecenterToken = 0
        private var last3DBuildingsEnabled: Bool?

        init(parent: MapLibreView) {
            self.parent = parent
        }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView, gesture.state == .ended else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onMapTap(
                RouteCoordinate(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            )
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            addBuildingLayer(to: style)
            last3DBuildingsEnabled = parent.show3DBuildings
            renderAccuracy(on: mapView, force: true)
            renderRoute(on: mapView, force: true)
            renderAnnotations(on: mapView, force: true)
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let point = annotation as? MLNPointAnnotation else { return nil }

            let isUser = point.title == "موقعیت شما"
            let isOrigin = point.title == "مبدأ"
            let reuseIdentifier = isUser ? "iran-user-marker" : (isOrigin ? "iran-origin-marker" : "iran-destination-marker")
            let marker = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier)
                ?? MLNAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)

            let size: CGFloat = isUser ? 22 : 25
            marker.annotation = annotation
            marker.frame = CGRect(x: 0, y: 0, width: size, height: size)
            marker.backgroundColor = isUser
                ? UIColor(red: 0.08, green: 0.53, blue: 0.98, alpha: 1)
                : (isOrigin
                    ? UIColor(red: 0.10, green: 0.72, blue: 0.48, alpha: 1)
                    : UIColor(red: 0.91, green: 0.34, blue: 0.39, alpha: 1))
            marker.layer.cornerRadius = size / 2
            marker.layer.borderWidth = 3
            marker.layer.borderColor = UIColor.white.cgColor
            marker.layer.shadowColor = UIColor.black.cgColor
            marker.layer.shadowOpacity = 0.24
            marker.layer.shadowRadius = 5
            marker.layer.shadowOffset = CGSize(width: 0, height: 2)
            marker.centerOffset = .zero
            marker.canShowCallout = !isUser
            return marker
        }

        func updateMapContent(_ mapView: MLNMapView) {
            guard let style = mapView.style else { return }
            if last3DBuildingsEnabled != parent.show3DBuildings {
                if parent.show3DBuildings {
                    addBuildingLayer(to: style)
                } else if let layer = style.layer(withIdentifier: "iran-buildings-3d") {
                    style.removeLayer(layer)
                }

                let camera = MLNMapCamera(
                    lookingAtCenter: mapView.centerCoordinate,
                    altitude: mapView.camera.altitude,
                    pitch: parent.show3DBuildings ? 50 : 0,
                    heading: mapView.direction
                )
                mapView.setCamera(camera, animated: true)
                last3DBuildingsEnabled = parent.show3DBuildings
            } else if parent.show3DBuildings {
                addBuildingLayer(to: style)
            }
            renderAccuracy(on: mapView, force: false)
            renderRoute(on: mapView, force: false)
            renderAnnotations(on: mapView, force: false)
        }

        private func addBuildingLayer(to style: MLNStyle) {
            guard parent.show3DBuildings,
                  style.layer(withIdentifier: "iran-buildings-3d") == nil,
                  let source = style.source(withIdentifier: "openmaptiles") else {
                return
            }

            let buildings = MLNFillExtrusionStyleLayer(
                identifier: "iran-buildings-3d",
                source: source
            )
            buildings.sourceLayerIdentifier = "building"
            buildings.minimumZoomLevel = 14.5
            buildings.predicate = NSPredicate(format: "render_height != NIL AND hide_3d != YES")
            buildings.fillExtrusionColor = NSExpression(
                forConstantValue: parent.theme == .dark
                    ? UIColor(red: 0.39, green: 0.49, blue: 0.60, alpha: 1)
                    : UIColor(red: 0.69, green: 0.77, blue: 0.84, alpha: 1)
            )
            buildings.fillExtrusionHeight = NSExpression(forKeyPath: "render_height")
            buildings.fillExtrusionBase = NSExpression(forKeyPath: "render_min_height")
            buildings.fillExtrusionOpacity = NSExpression(forConstantValue: 0.9)

            if let firstSymbolLayer = style.layers.first(where: { $0 is MLNSymbolStyleLayer }) {
                style.insertLayer(buildings, below: firstSymbolLayer)
            } else {
                style.addLayer(buildings)
            }
        }

        private func renderAccuracy(on mapView: MLNMapView, force: Bool) {
            guard let style = mapView.style else { return }

            guard let center = parent.userCoordinate,
                  let accuracy = parent.userAccuracy,
                  accuracy >= 0 else {
                if let layer = style.layer(withIdentifier: "iran-user-accuracy-fill") {
                    style.removeLayer(layer)
                }
                if let source = style.source(withIdentifier: "iran-user-accuracy-source") {
                    style.removeSource(source)
                }
                lastAccuracyCenter = nil
                lastAccuracyMeters = nil
                return
            }

            let clampedAccuracy = min(max(accuracy, 5), 1_500)
            if !force,
               lastAccuracyCenter == center,
               let lastAccuracyMeters,
               abs(lastAccuracyMeters - clampedAccuracy) < 2 {
                return
            }

            var coordinates = accuracyRing(
                latitude: center.latitude,
                longitude: center.longitude,
                radiusMeters: clampedAccuracy
            )
            let polygon = MLNPolygonFeature(
                coordinates: &coordinates,
                count: UInt(coordinates.count)
            )

            if let source = style.source(withIdentifier: "iran-user-accuracy-source") as? MLNShapeSource {
                source.shape = polygon
            } else {
                let source = MLNShapeSource(
                    identifier: "iran-user-accuracy-source",
                    shape: polygon,
                    options: nil
                )
                style.addSource(source)

                let fill = MLNFillStyleLayer(
                    identifier: "iran-user-accuracy-fill",
                    source: source
                )
                fill.fillColor = NSExpression(
                    forConstantValue: UIColor(red: 0.08, green: 0.53, blue: 0.98, alpha: 1)
                )
                fill.fillOpacity = NSExpression(forConstantValue: 0.13)
                fill.fillOutlineColor = NSExpression(
                    forConstantValue: UIColor(red: 0.25, green: 0.67, blue: 1, alpha: 0.65)
                )

                if let routeLayer = style.layer(withIdentifier: "iran-route-casing") {
                    style.insertLayer(fill, below: routeLayer)
                } else {
                    style.addLayer(fill)
                }
            }

            lastAccuracyCenter = center
            lastAccuracyMeters = clampedAccuracy
        }

        private func accuracyRing(
            latitude: Double,
            longitude: Double,
            radiusMeters: CLLocationAccuracy
        ) -> [CLLocationCoordinate2D] {
            let earthRadius = 6_378_137.0
            let angularDistance = radiusMeters / earthRadius
            let latitudeRadians = latitude * .pi / 180
            let longitudeRadians = longitude * .pi / 180
            var coordinates: [CLLocationCoordinate2D] = []

            for index in 0...48 {
                let bearing = 2 * .pi * Double(index) / 48
                let targetLatitude = asin(
                    sin(latitudeRadians) * cos(angularDistance)
                    + cos(latitudeRadians) * sin(angularDistance) * cos(bearing)
                )
                let targetLongitude = longitudeRadians + atan2(
                    sin(bearing) * sin(angularDistance) * cos(latitudeRadians),
                    cos(angularDistance) - sin(latitudeRadians) * sin(targetLatitude)
                )
                coordinates.append(
                    CLLocationCoordinate2D(
                        latitude: targetLatitude * 180 / .pi,
                        longitude: targetLongitude * 180 / .pi
                    )
                )
            }
            return coordinates
        }

        private func renderRoute(on mapView: MLNMapView, force: Bool) {
            guard force || parent.routePoints != lastRoutePoints else { return }
            guard let style = mapView.style else { return }

            if let line = style.layer(withIdentifier: "iran-route-line") {
                style.removeLayer(line)
            }
            if let casing = style.layer(withIdentifier: "iran-route-casing") {
                style.removeLayer(casing)
            }
            if let source = style.source(withIdentifier: "iran-route-source") {
                style.removeSource(source)
            }

            lastRoutePoints = parent.routePoints
            guard parent.routePoints.count >= 2 else { return }

            var coordinates = parent.routePoints.map(\.clCoordinate)
            let polyline = MLNPolylineFeature(
                coordinates: &coordinates,
                count: UInt(coordinates.count)
            )
            let source = MLNShapeSource(
                identifier: "iran-route-source",
                features: [polyline],
                options: nil
            )
            style.addSource(source)

            let casing = MLNLineStyleLayer(identifier: "iran-route-casing", source: source)
            casing.lineJoin = NSExpression(forConstantValue: "round")
            casing.lineCap = NSExpression(forConstantValue: "round")
            casing.lineColor = NSExpression(
                forConstantValue: parent.theme == .dark ? UIColor.black : UIColor.white
            )
            casing.lineWidth = NSExpression(forConstantValue: 9)

            let route = MLNLineStyleLayer(identifier: "iran-route-line", source: source)
            route.lineJoin = NSExpression(forConstantValue: "round")
            route.lineCap = NSExpression(forConstantValue: "round")
            route.lineColor = NSExpression(
                forConstantValue: UIColor(red: 0.08, green: 0.78, blue: 0.74, alpha: 1)
            )
            route.lineWidth = NSExpression(forConstantValue: 5)

            style.addLayer(casing)
            style.addLayer(route)

            if !parent.isNavigating {
                fitRoute(on: mapView)
            }
        }

        private func fitRoute(on mapView: MLNMapView) {
            guard parent.routePoints.count >= 2 else { return }
            var coordinates = parent.routePoints.map(\.clCoordinate)
            mapView.setVisibleCoordinates(
                &coordinates,
                count: UInt(coordinates.count),
                edgePadding: UIEdgeInsets(top: 105, left: 35, bottom: 300, right: 35),
                animated: true
            )
        }

        private func renderAnnotations(on mapView: MLNMapView, force: Bool) {
            if force || parent.origin != lastOrigin {
                if let originAnnotation { mapView.removeAnnotation(originAnnotation) }
                originAnnotation = nil
                lastOrigin = parent.origin
                if let origin = parent.origin {
                    let annotation = MLNPointAnnotation()
                    annotation.coordinate = origin.clCoordinate
                    annotation.title = "مبدأ"
                    originAnnotation = annotation
                    mapView.addAnnotation(annotation)
                }
            }

            if force || parent.destination != lastDestination {
                if let destinationAnnotation { mapView.removeAnnotation(destinationAnnotation) }
                destinationAnnotation = nil
                lastDestination = parent.destination
                if let destination = parent.destination {
                    let annotation = MLNPointAnnotation()
                    annotation.coordinate = destination.clCoordinate
                    annotation.title = "مقصد"
                    destinationAnnotation = annotation
                    mapView.addAnnotation(annotation)
                }
            }

            if force || parent.userCoordinate != lastUserCoordinate {
                if let userAnnotation { mapView.removeAnnotation(userAnnotation) }
                userAnnotation = nil
                lastUserCoordinate = parent.userCoordinate
                if let user = parent.userCoordinate {
                    let annotation = MLNPointAnnotation()
                    annotation.coordinate = user.clCoordinate
                    annotation.title = "موقعیت شما"
                    userAnnotation = annotation
                    mapView.addAnnotation(annotation)
                }
            }
        }

        func recenterIfNeeded(_ mapView: MLNMapView) {
            guard parent.recenterToken != lastRecenterToken,
                  let coordinate = parent.userCoordinate else { return }
            lastRecenterToken = parent.recenterToken
            let camera = MLNMapCamera(
                lookingAtCenter: coordinate.clCoordinate,
                altitude: max(mapView.camera.altitude, 700),
                pitch: parent.show3DBuildings ? 50 : 0,
                heading: mapView.direction
            )
            mapView.setCamera(
                camera,
                withDuration: 0.45,
                animationTimingFunction: nil,
                edgePadding: UIEdgeInsets(top: 85, left: 12, bottom: 320, right: 12),
                completionHandler: nil
            )
        }

        func updateCamera(_ mapView: MLNMapView) {
            guard parent.isNavigating, let coordinate = parent.userCoordinate else {
                if wasFollowingNavigation {
                    let camera = MLNMapCamera(
                        lookingAtCenter: mapView.centerCoordinate,
                        altitude: mapView.camera.altitude,
                        pitch: parent.show3DBuildings ? 50 : 0,
                        heading: mapView.direction
                    )
                    mapView.setCamera(
                        camera,
                        withDuration: 0.4,
                        animationTimingFunction: nil,
                        edgePadding: .zero,
                        completionHandler: nil
                    )
                }
                wasFollowingNavigation = false
                lastFollowCoordinate = nil
                lastSmoothedHeading = nil
                return
            }
            wasFollowingNavigation = true

            let now = Date()
            let moved = lastFollowCoordinate.map {
                coordinate.location.distance(from: $0.location)
            } ?? .greatestFiniteMagnitude
            guard moved >= 4, now.timeIntervalSince(lastFollowTime) >= 1.0 else { return }

            let currentHeading = lastSmoothedHeading ?? mapView.direction
            let targetHeading = parent.userHeading ?? inferredBearing(
                from: lastFollowCoordinate,
                to: coordinate
            ) ?? currentHeading
            let delta = ((targetHeading - currentHeading + 540).truncatingRemainder(dividingBy: 360)) - 180
            let heading = (currentHeading + delta * 0.28 + 360)
                .truncatingRemainder(dividingBy: 360)
            lastSmoothedHeading = heading

            let camera = MLNMapCamera(
                lookingAtCenter: coordinate.clCoordinate,
                altitude: 850,
                pitch: 58,
                heading: heading
            )
            mapView.setCamera(
                camera,
                withDuration: 0.85,
                animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut),
                edgePadding: UIEdgeInsets(top: 85, left: 12, bottom: 320, right: 12),
                completionHandler: nil
            )
            lastFollowCoordinate = coordinate
            lastFollowTime = now
        }

        private func inferredBearing(
            from previous: RouteCoordinate?,
            to current: RouteCoordinate
        ) -> CLLocationDirection? {
            guard let previous,
                  previous.location.distance(from: current.location) >= 6 else {
                return nil
            }
            let startLatitude = previous.latitude * .pi / 180
            let endLatitude = current.latitude * .pi / 180
            let deltaLongitude = (current.longitude - previous.longitude) * .pi / 180
            let y = sin(deltaLongitude) * cos(endLatitude)
            let x = cos(startLatitude) * sin(endLatitude)
                - sin(startLatitude) * cos(endLatitude) * cos(deltaLongitude)
            return (atan2(y, x) * 180 / .pi + 360)
                .truncatingRemainder(dividingBy: 360)
        }
    }
}
