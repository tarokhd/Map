import Combine
import CoreLocation
import SwiftUI

struct ContentView: View {
    @StateObject private var locationService = LocationService()
    @StateObject private var speechService = PersianSpeechService()

    @State private var theme: MapTheme = .dark
    @State private var show3DBuildings = true
    @State private var travelMode: TravelMode = .car
    @State private var origin: RouteCoordinate?
    @State private var destination: RouteCoordinate?
    @State private var route: NavigationRoute?
    @State private var originText = ""
    @State private var destinationText = ""
    @State private var selectionTarget: PointSelectionTarget?
    @State private var searchTarget: PointSelectionTarget = .destination
    @State private var searchResults: [PlaceSearchResult] = []
    @State private var isShowingSearch = false
    @State private var isSearching = false
    @State private var isCalculatingRoute = false
    @State private var isNavigating = false
    @State private var pendingOriginFromGPS = false
    @State private var pendingNavigationStart = false
    @State private var statusMessage = "نقشه آماده است؛ مبدأ و مقصد را انتخاب کنید."
    @State private var recenterToken = 0
    @State private var currentManeuverIndex = 0
    @State private var lastAnnouncedManeuver: Int?
    @State private var offRouteCount = 0
    @State private var lastRerouteAt = Date.distantPast
    @State private var distanceToNextManeuver: Double?

    private let routingService = RoutingService()
    private let searchService = PlaceSearchService()

    private var primaryText: Color {
        theme == .dark ? .white : Color(red: 0.08, green: 0.16, blue: 0.23)
    }

    private var secondaryText: Color {
        theme == .dark ? Color.white.opacity(0.68) : Color(red: 0.32, green: 0.42, blue: 0.52)
    }

    var body: some View {
        ZStack {
            MapLibreView(
                theme: theme,
                show3DBuildings: show3DBuildings,
                origin: origin,
                destination: destination,
                routePoints: route?.points ?? [],
                userCoordinate: locationService.location.map(RouteCoordinate.init(location:)),
                userHeading: locationService.location.flatMap {
                    $0.course >= 0 && $0.speed > 1.5 ? $0.course : nil
                },
                isNavigating: isNavigating,
                recenterToken: recenterToken,
                onMapTap: handleMapTap
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                header
                Spacer(minLength: 8)
                routePanel
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(theme == .dark ? .dark : .light)
        .sheet(isPresented: $isShowingSearch) {
            searchResultsSheet
        }
        .onReceive(locationService.$location.compactMap { $0 }) { location in
            handleLocationUpdate(location)
        }
        .onReceive(locationService.$errorMessage.compactMap { $0 }) { message in
            statusMessage = message
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.36, green: 0.91, blue: 0.82), Color(red: 0.05, green: 0.63, blue: 0.70)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(red: 0.02, green: 0.15, blue: 0.19))
            }
            .frame(width: 43, height: 43)

            VStack(alignment: .leading, spacing: 3) {
                Text("IRAN NAVIGATOR")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(primaryText)
                Text("نقشه سه‌بعدی و مسیریاب")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(secondaryText)
            }

            Spacer(minLength: 4)

            Button {
                theme = theme == .dark ? .light : .dark
            } label: {
                Image(systemName: theme == .dark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.bordered)
            .tint(primaryText)

            Button {
                show3DBuildings.toggle()
            } label: {
                Text(show3DBuildings ? "3D" : "2D")
                    .font(.system(size: 12, weight: .black))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.04, green: 0.63, blue: 0.65))
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private var routePanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("مسیریابی هوشمند")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(primaryText)
                        Text("انتخاب مسیر و راهنمای حرکت")
                            .font(.system(size: 10))
                            .foregroundStyle(secondaryText)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(speechService.isPersianVoiceAvailable ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(speechService.isPersianVoiceAvailable ? "صدای فارسی آماده" : "صدای فارسی بررسی شود")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(secondaryText)
                    }
                }

                Picker("حالت سفر", selection: $travelMode) {
                    ForEach(TravelMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: travelMode) { _ in
                    clearCalculatedRoute(message: "حالت سفر تغییر کرد؛ مسیر را دوباره محاسبه کنید.")
                }

                pointInput(
                    placeholder: "آدرس یا مکان شروع",
                    text: $originText,
                    target: .origin,
                    color: Color(red: 0.10, green: 0.72, blue: 0.48)
                )

                pointInput(
                    placeholder: "آدرس یا مکان مقصد",
                    text: $destinationText,
                    target: .destination,
                    color: Color(red: 0.91, green: 0.34, blue: 0.39)
                )

                HStack(spacing: 8) {
                    Button {
                        useCurrentLocationAsOrigin()
                    } label: {
                        Label("مبدأ = موقعیت من", systemImage: "location.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(primaryText)

                    Button {
                        selectionTarget = .origin
                        statusMessage = "برای انتخاب مبدأ، نقطه موردنظر را روی نقشه لمس کنید."
                    } label: {
                        Label("انتخاب روی نقشه", systemImage: "map")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(primaryText)
                }

                Button {
                    Task { await calculateRoute() }
                } label: {
                    HStack(spacing: 8) {
                        if isCalculatingRoute {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        }
                        Text(isCalculatingRoute ? "در حال محاسبه مسیر..." : "محاسبه مسیر جاده‌ای")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.12, green: 0.79, blue: 0.73))
                .foregroundStyle(Color.black)
                .disabled(isCalculatingRoute)

                if let route {
                    routeSummary(route)
                    guidanceCard(route)
                    HStack(spacing: 8) {
                        Button {
                            startNavigation()
                        } label: {
                            Label(isNavigating ? "مسیریابی فعال" : "شروع مسیریابی", systemImage: "location.north.fill")
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isNavigating ? .green : Color(red: 0.05, green: 0.65, blue: 0.64))
                        .disabled(isNavigating)

                        Button {
                            stopNavigation()
                        } label: {
                            Label("توقف", systemImage: "stop.fill")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 84)
                                .frame(height: 42)
                        }
                        .buttonStyle(.bordered)
                        .tint(primaryText)
                        .disabled(!isNavigating)
                    }
                }

                Text(statusMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
        .frame(maxWidth: 560)
        .frame(maxHeight: 430)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
    }

    private func pointInput(
        placeholder: String,
        text: Binding<String>,
        target: PointSelectionTarget,
        color: Color
    ) -> some View {
        HStack(spacing: 9) {
            Circle().fill(color).frame(width: 9, height: 9)
            TextField(placeholder, text: text)
                .font(.system(size: 11))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await searchPlaces(for: target) } }
            Button {
                Task { await searchPlaces(for: target) }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.12, green: 0.79, blue: 0.73))
            }
            Button {
                selectionTarget = target
                statusMessage = target == .origin
                    ? "روی نقشه محل مبدأ را انتخاب کنید."
                    : "روی نقشه محل مقصد را انتخاب کنید."
            } label: {
                Image(systemName: "map.pin")
                    .font(.system(size: 14))
                    .foregroundStyle(secondaryText)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 43)
        .background(theme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private func routeSummary(_ route: NavigationRoute) -> some View {
        HStack(spacing: 8) {
            metric(value: PersianInstructionFormatter.distance(route.distanceKilometers * 1_000), label: "مسافت")
            metric(value: PersianInstructionFormatter.duration(route.durationSeconds), label: "زمان تخمینی")
            metric(value: arrivalTime(route.durationSeconds), label: "زمان رسیدن")
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(theme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private func guidanceCard(_ route: NavigationRoute) -> some View {
        let maneuver = route.maneuvers.indices.contains(currentManeuverIndex)
            ? route.maneuvers[currentManeuverIndex]
            : nil
        let next = route.maneuvers.indices.contains(currentManeuverIndex + 1)
            ? route.maneuvers[currentManeuverIndex + 1]
            : nil

        return VStack(alignment: .leading, spacing: 5) {
            Text("راهنمای مسیر")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Color(red: 0.12, green: 0.79, blue: 0.73))
            Text(maneuver?.instruction ?? "به مقصد رسیده‌اید.")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(primaryText)
            if let next {
                Text("پس از آن: \(next.instruction)")
                    .font(.system(size: 10))
                    .foregroundStyle(secondaryText)
            }
            if let distanceToNextManeuver {
                Text("تا گردش بعدی: \(PersianInstructionFormatter.distance(distanceToNextManeuver))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.12, green: 0.79, blue: 0.73))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(red: 0.08, green: 0.42, blue: 0.47).opacity(theme == .dark ? 0.28 : 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var searchResultsSheet: some View {
        NavigationStack {
            Group {
                if isSearching {
                    ProgressView("در حال جست‌وجو...")
                } else if searchResults.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("نتیجه‌ای پیدا نشد").font(.headline)
                        Text("نام مکان یا شهر دیگری را امتحان کنید.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    List(searchResults) { result in
                        Button {
                            selectSearchResult(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .navigationTitle(searchTarget == .origin ? "انتخاب مبدأ" : "انتخاب مقصد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("بستن") { isShowingSearch = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func arrivalTime(_ seconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fa_IR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date().addingTimeInterval(seconds))
    }

    private func searchPlaces(for target: PointSelectionTarget) async {
        let query = (target == .origin ? originText : destinationText)
            .trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            statusMessage = "ابتدا نام شهر، خیابان یا مکان را وارد کنید."
            return
        }

        searchTarget = target
        isSearching = true
        searchResults = []
        isShowingSearch = true

        do {
            let bias = locationService.location.map(RouteCoordinate.init(location:))
            searchResults = try await searchService.search(query, near: bias)
            if searchResults.isEmpty { statusMessage = "مکانی با این نام پیدا نشد." }
        } catch {
            statusMessage = error.localizedDescription
            searchResults = []
        }
        isSearching = false
    }

    private func selectSearchResult(_ result: PlaceSearchResult) {
        assignPoint(result.coordinate, target: searchTarget, label: result.displayName)
        isShowingSearch = false
        recenterToken += 1
    }

    private func assignPoint(
        _ coordinate: RouteCoordinate,
        target: PointSelectionTarget,
        label: String
    ) {
        switch target {
        case .origin:
            origin = coordinate
            originText = label
            statusMessage = "مبدأ ثبت شد؛ مقصد را انتخاب کنید."
            selectionTarget = .destination
        case .destination:
            destination = coordinate
            destinationText = label
            statusMessage = "مقصد ثبت شد؛ مسیر را محاسبه کنید."
            selectionTarget = nil
        }
        clearCalculatedRoute(message: nil)
    }

    private func handleMapTap(_ coordinate: RouteCoordinate) {
        guard let target = selectionTarget else { return }
        assignPoint(coordinate, target: target, label: "نقطه انتخاب‌شده روی نقشه")
    }

    private func useCurrentLocationAsOrigin() {
        if let location = locationService.location {
            assignPoint(
                RouteCoordinate(location: location),
                target: .origin,
                label: "موقعیت فعلی من"
            )
            recenterToken += 1
        } else {
            pendingOriginFromGPS = true
            locationService.requestAndStart()
            statusMessage = "در حال دریافت موقعیت تازه از GPS..."
        }
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        if pendingOriginFromGPS && location.horizontalAccuracy <= 60 {
            pendingOriginFromGPS = false
            assignPoint(
                RouteCoordinate(location: location),
                target: .origin,
                label: "موقعیت فعلی من"
            )
            recenterToken += 1
        }

        if pendingNavigationStart && location.horizontalAccuracy <= 65 {
            pendingNavigationStart = false
            beginLiveNavigation()
        }

        if isNavigating && location.horizontalAccuracy <= 65 {
            updateNavigationProgress(location)
        }
    }

    @MainActor
    private func calculateRoute() async {
        guard let origin, let destination else {
            statusMessage = "ابتدا مبدأ و مقصد را انتخاب کنید."
            return
        }
        guard origin.location.distance(from: destination.location) >= 15 else {
            statusMessage = "مبدأ و مقصد بیش از حد به هم نزدیک هستند."
            return
        }

        isCalculatingRoute = true
        statusMessage = "در حال محاسبه مسیر واقعی خیابان‌ها..."
        do {
            let result = try await routingService.calculateRoute(
                from: origin,
                to: destination,
                mode: travelMode
            )
            route = result
            currentManeuverIndex = firstGuidanceIndex(in: result)
            distanceToNextManeuver = nil
            lastAnnouncedManeuver = nil
            offRouteCount = 0
            statusMessage = "مسیر جاده‌ای آماده است."
        } catch {
            statusMessage = error.localizedDescription
        }
        isCalculatingRoute = false
    }

    private func firstGuidanceIndex(in route: NavigationRoute) -> Int {
        route.maneuvers.firstIndex { ![1, 2, 3].contains($0.type) } ?? 0
    }

    private func startNavigation() {
        guard route != nil else {
            statusMessage = "ابتدا مسیر را محاسبه کنید."
            return
        }
        guard let location = locationService.location, location.horizontalAccuracy <= 65 else {
            pendingNavigationStart = true
            locationService.requestAndStart()
            statusMessage = "برای شروع، در حال دریافت موقعیت دقیق GPS..."
            return
        }
        beginLiveNavigation()
    }

    private func beginLiveNavigation() {
        isNavigating = true
        offRouteCount = 0
        lastAnnouncedManeuver = nil
        lastRerouteAt = .distantPast
        locationService.startUpdating()
        if speechService.isPersianVoiceAvailable {
            speechService.speak("مسیریابی شروع شد. حالت \(travelMode.title).")
        } else {
            statusMessage = "مسیریابی فعال شد؛ صدای فارسی روی این آیفون در دسترس نیست."
        }
        recenterToken += 1
    }

    private func stopNavigation() {
        isNavigating = false
        pendingNavigationStart = false
        speechService.stop()
        locationService.stopUpdating()
        statusMessage = "مسیریابی متوقف شد."
    }

    private func updateNavigationProgress(_ location: CLLocation) {
        guard let route, !route.points.isEmpty else { return }
        let current = RouteCoordinate(location: location)
        let nearest = nearestRoutePoint(to: current, in: route.points)

        if nearest.distance > 80 && location.horizontalAccuracy <= 35 {
            offRouteCount += 1
        } else {
            offRouteCount = 0
        }

        if route.maneuvers.indices.contains(currentManeuverIndex) {
            let maneuver = route.maneuvers[currentManeuverIndex]
            let targetIndex = min(max(0, maneuver.endShapeIndex), route.points.count - 1)
            let remaining = distanceAlongRoute(route.points, from: nearest.index, to: targetIndex)
            distanceToNextManeuver = remaining

            if nearest.index >= targetIndex - 2,
               currentManeuverIndex < route.maneuvers.count - 1 {
                currentManeuverIndex += 1
                lastAnnouncedManeuver = nil
                distanceToNextManeuver = nil
            } else if remaining >= 30 && remaining <= 350,
                      lastAnnouncedManeuver != currentManeuverIndex {
                speechService.speak(
                    "تا \(PersianInstructionFormatter.distance(remaining)) دیگر، \(maneuver.instruction)"
                )
                lastAnnouncedManeuver = currentManeuverIndex
            }
        }

        if let destination,
           current.location.distance(from: destination.location) < 35 {
            stopNavigation()
            statusMessage = "به مقصد رسیدید."
            speechService.speak("به مقصد رسیدید.")
            return
        }

        if offRouteCount >= 4,
           Date().timeIntervalSince(lastRerouteAt) > 25 {
            lastRerouteAt = Date()
            Task { await reroute(from: current) }
        }
    }

    private func reroute(from current: RouteCoordinate) async {
        guard let destination else { return }
        statusMessage = "از مسیر خارج شده‌اید؛ مسیر جدید محاسبه می‌شود..."
        do {
            let updated = try await routingService.calculateRoute(
                from: current,
                to: destination,
                mode: travelMode
            )
            origin = current
            originText = "موقعیت فعلی"
            route = updated
            currentManeuverIndex = firstGuidanceIndex(in: updated)
            lastAnnouncedManeuver = nil
            offRouteCount = 0
            distanceToNextManeuver = nil
            statusMessage = "مسیر جدید محاسبه شد."
            speechService.speak("مسیر جدید محاسبه شد.")
        } catch {
            statusMessage = "محاسبه مجدد مسیر ناموفق بود: \(error.localizedDescription)"
        }
    }

    private func nearestRoutePoint(
        to coordinate: RouteCoordinate,
        in points: [RouteCoordinate]
    ) -> (index: Int, distance: Double) {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, point) in points.enumerated() {
            let distance = coordinate.location.distance(from: point.location)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return (bestIndex, bestDistance)
    }

    private func distanceAlongRoute(
        _ points: [RouteCoordinate],
        from start: Int,
        to end: Int
    ) -> Double {
        guard points.count >= 2 else { return 0 }
        let lower = min(max(0, start), points.count - 1)
        let upper = min(max(lower, end), points.count - 1)
        guard upper > lower else { return 0 }
        return (lower..<upper).reduce(0.0) { total, index in
            total + points[index].location.distance(from: points[index + 1].location)
        }
    }

    private func clearCalculatedRoute(message: String?) {
        route = nil
        isNavigating = false
        currentManeuverIndex = 0
        distanceToNextManeuver = nil
        speechService.stop()
        if let message { statusMessage = message }
    }
}
