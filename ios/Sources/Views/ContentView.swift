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
    @State private var pendingRecenterAfterGPS = false
    @State private var showRouteSteps = false
    @State private var statusMessage = "نقشه آماده است؛ مبدأ و مقصد را انتخاب کنید."
    @State private var recenterToken = 0
    @State private var currentManeuverIndex = 0
    @State private var lastMatchedRouteIndex = 0
    @State private var lastAnnouncedManeuver: Int?
    @State private var offRouteCount = 0
    @State private var lastRerouteAt = Date.distantPast
    @State private var distanceToNextManeuver: Double?

    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
                userAccuracy: locationService.location?.horizontalAccuracy,
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.36, green: 0.91, blue: 0.82),
                            Color(red: 0.05, green: 0.63, blue: 0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Color(red: 0.02, green: 0.15, blue: 0.19))
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("IRAN NAVIGATOR")
                    .font(.headline.weight(.heavy))
                    .tracking(0.4)
                    .foregroundStyle(primaryText)
                Text("نقشه سه‌بعدی و مسیریاب")
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 2)

            Button(action: centerOnUser) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .tint(primaryText)
            .accessibilityLabel("رفتن به موقعیت فعلی")
            .accessibilityHint("نقشه را روی موقعیت مکانی شما متمرکز می‌کند.")

            Button {
                theme = theme == .dark ? .light : .dark
            } label: {
                Image(systemName: theme == .dark ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .tint(primaryText)
            .accessibilityLabel(theme == .dark ? "پوسته روشن" : "پوسته تاریک")

            Button {
                show3DBuildings.toggle()
            } label: {
                Text(show3DBuildings ? "3D" : "2D")
                    .font(.subheadline.weight(.heavy))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.04, green: 0.63, blue: 0.65))
            .accessibilityLabel(show3DBuildings ? "تغییر به نقشه دوبعدی" : "تغییر به نقشه سه‌بعدی")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(primaryText.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }

    private var routePanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("مسیریابی")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(primaryText)
                        Text("مبدأ و مقصد را مشخص کنید")
                            .font(.subheadline)
                            .foregroundStyle(secondaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(speechService.isPersianVoiceAvailable ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(speechService.isPersianVoiceAvailable ? "صدای فارسی" : "بدون صدای فارسی")
                                .font(.caption)
                                .foregroundStyle(secondaryText)
                        }
                        if let location = locationService.location {
                            Text("دقت GPS ±\(PersianInstructionFormatter.distance(location.horizontalAccuracy))")
                                .font(.caption2)
                                .foregroundStyle(secondaryText)
                        }
                    }
                    .accessibilityElement(children: .combine)
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
                .accessibilityLabel("حالت سفر")

                VStack(spacing: 9) {
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
                }

                HStack(spacing: 8) {
                    Button(action: useCurrentLocationAsOrigin) {
                        Label("مبدأ = موقعیت من", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(primaryText)
                    .accessibilityHint("موقعیت فعلی را به‌عنوان مبدأ ثبت می‌کند.")

                    Button(action: swapRoutePoints) {
                        Label("جابه‌جایی", systemImage: "arrow.up.arrow.down")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(primaryText)
                    .disabled(origin == nil || destination == nil)
                    .accessibilityLabel("جابه‌جایی مبدأ و مقصد")
                }

                Button {
                    Task { await calculateRoute() }
                } label: {
                    HStack(spacing: 9) {
                        if isCalculatingRoute {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        }
                        Text(isCalculatingRoute ? "در حال محاسبه مسیر…" : "محاسبه مسیر جاده‌ای")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.12, green: 0.79, blue: 0.73))
                .foregroundStyle(Color.black)
                .disabled(isCalculatingRoute || origin == nil || destination == nil)

                if let route {
                    routeSummary(route)
                    guidanceCard(route)

                    DisclosureGroup(isExpanded: $showRouteSteps) {
                        VStack(spacing: 8) {
                            ForEach(route.maneuvers) { maneuver in
                                maneuverRow(maneuver, isCurrent: maneuver.id == currentManeuverIndex)
                            }
                        }
                        .padding(.top, 10)
                    } label: {
                        Label("جزئیات مسیر و گردش‌ها", systemImage: "list.number")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(primaryText)
                    }
                    .tint(Color(red: 0.12, green: 0.79, blue: 0.73))

                    HStack(spacing: 9) {
                        Button(action: startNavigation) {
                            Label("شروع مسیریابی", systemImage: "location.north.fill")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.05, green: 0.65, blue: 0.64))
                        .disabled(isNavigating)

                        Button(action: stopNavigation) {
                            Image(systemName: "stop.fill")
                                .font(.headline)
                                .frame(width: 52, height: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(primaryText)
                        .disabled(!isNavigating)
                        .accessibilityLabel("توقف مسیریابی")
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isNavigating ? "location.north.circle.fill" : "info.circle")
                        .foregroundStyle(isNavigating ? Color.green : secondaryText)
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
            .padding(16)
        }
        .frame(maxWidth: 560)
        .frame(maxHeight: verticalSizeClass == .compact ? 250 : 450)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(primaryText.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
    }

    private func pointInput(
        placeholder: String,
        text: Binding<String>,
        target: PointSelectionTarget,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            TextField(placeholder, text: text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await searchPlaces(for: target) } }
                .accessibilityLabel(placeholder)

            Button {
                Task { await searchPlaces(for: target) }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.12, green: 0.67, blue: 0.68))
            .accessibilityLabel("جست‌وجوی \(placeholder)")

            Button {
                selectionTarget = target
                statusMessage = target == .origin
                    ? "روی نقشه محل مبدأ را انتخاب کنید."
                    : "روی نقشه محل مقصد را انتخاب کنید."
            } label: {
                Image(systemName: "map.pin")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(secondaryText)
            .accessibilityLabel("انتخاب \(placeholder) روی نقشه")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 52)
        .background(theme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(primaryText.opacity(0.08), lineWidth: 1)
        )
    }

    private func maneuverRow(_ maneuver: RouteManeuver, isCurrent: Bool) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: maneuverSymbol(for: maneuver.type))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isCurrent ? Color.black : Color(red: 0.10, green: 0.68, blue: 0.67))
                .frame(width: 34, height: 34)
                .background(
                    isCurrent ? Color(red: 0.42, green: 0.88, blue: 0.80) : primaryText.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(maneuver.instruction)
                    .font(.subheadline.weight(isCurrent ? .bold : .medium))
                    .foregroundStyle(primaryText)
                if !maneuver.streetName.isEmpty {
                    Text(maneuver.streetName)
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                }
            }
            Spacer(minLength: 4)
            Text(PersianInstructionFormatter.distance(maneuver.lengthKilometers * 1_000))
                .font(.caption)
                .foregroundStyle(secondaryText)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isCurrent ? Color(red: 0.12, green: 0.79, blue: 0.73).opacity(0.14) : primaryText.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func maneuverSymbol(for type: Int) -> String {
        switch type {
        case 2, 9, 10, 11, 18, 20, 23, 37: return "arrow.turn.up.right"
        case 3, 14, 15, 16, 19, 21, 24, 38: return "arrow.turn.up.left"
        case 12, 13: return "arrow.uturn.down"
        case 26, 27: return "arrow.trianglehead.2.clockwise.rotate.90"
        case 39: return "arrow.up.to.line"
        case 40, 41: return "figure.stairs"
        case 42: return "door.left.hand.open"
        case 43: return "door.left.hand.closed"
        case 45: return "parkingsign.circle"
        case 4, 5, 6: return "flag.checkered"
        default: return "arrow.up"
        }
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
                .font(.subheadline.weight(.bold))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
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
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color(red: 0.12, green: 0.79, blue: 0.73))
            Text(maneuver?.instruction ?? "به مقصد رسیده‌اید.")
                .font(.headline)
                .foregroundStyle(primaryText)
            if let next {
                Text("پس از آن: \(next.instruction)")
                    .font(.footnote)
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

    private func centerOnUser() {
        if let location = locationService.location,
           NavigationLocationQuality.isUsable(
                horizontalAccuracy: location.horizontalAccuracy,
                timestamp: location.timestamp,
                maximumAccuracy: 100
           ) {
            recenterToken += 1
            statusMessage = "نقشه روی موقعیت فعلی متمرکز شد."
            return
        }

        pendingRecenterAfterGPS = true
        locationService.requestAndStart()
        statusMessage = "در حال دریافت موقعیت تازه برای تمرکز نقشه..."
    }

    private func useCurrentLocationAsOrigin() {
        if let location = locationService.location,
           NavigationLocationQuality.isUsable(
                horizontalAccuracy: location.horizontalAccuracy,
                timestamp: location.timestamp,
                maximumAccuracy: 60
           ) {
            assignPoint(
                RouteCoordinate(location: location),
                target: .origin,
                label: "موقعیت فعلی من"
            )
            recenterToken += 1
        } else {
            pendingOriginFromGPS = true
            locationService.requestAndStart()
            statusMessage = "در حال دریافت موقعیت دقیق و تازه از GPS..."
        }
    }

    private func swapRoutePoints() {
        guard origin != nil, destination != nil else { return }
        let previousOrigin = origin
        origin = destination
        destination = previousOrigin

        let previousOriginText = originText
        originText = destinationText
        destinationText = previousOriginText

        clearCalculatedRoute(message: "مبدأ و مقصد جابه‌جا شدند؛ مسیر را دوباره محاسبه کنید.")
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        guard NavigationLocationQuality.isFresh(timestamp: location.timestamp) else { return }

        if pendingRecenterAfterGPS && location.horizontalAccuracy <= 100 {
            pendingRecenterAfterGPS = false
            recenterToken += 1
            statusMessage = "موقعیت تازه دریافت شد؛ نقشه روی شما متمرکز شد."
        }

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

        if isNavigating {
            stopNavigation()
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
            lastMatchedRouteIndex = 0
            distanceToNextManeuver = nil
            lastAnnouncedManeuver = nil
            offRouteCount = 0
            showRouteSteps = false
            statusMessage = result.usedMotorcycleFallback
                ? "پروفایل موتورسیکلت در سرویس موجود نبود؛ مسیر با پروفایل اسکوتر محاسبه شد."
                : "مسیر جاده‌ای آماده است."
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
        guard let location = locationService.location,
              NavigationLocationQuality.isUsable(
                horizontalAccuracy: location.horizontalAccuracy,
                timestamp: location.timestamp,
                maximumAccuracy: 65
              ) else {
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
        lastMatchedRouteIndex = 0
        locationService.startNavigationUpdates(for: travelMode)
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
        lastMatchedRouteIndex = 0
        speechService.stop()
        locationService.stopUpdating()
        statusMessage = "مسیریابی متوقف شد."
    }

    private func updateNavigationProgress(_ location: CLLocation) {
        guard let route, !route.points.isEmpty else { return }
        let current = RouteCoordinate(location: location)
        let nearest = nearestRoutePoint(
            to: current,
            in: route.points,
            startingAt: lastMatchedRouteIndex
        )
        lastMatchedRouteIndex = max(lastMatchedRouteIndex, nearest.index)

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
            lastMatchedRouteIndex = 0
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
        in points: [RouteCoordinate],
        startingAt previousIndex: Int
    ) -> (index: Int, distance: Double) {
        var bestIndex = min(max(0, previousIndex), max(0, points.count - 1))
        var bestDistance = Double.greatestFiniteMagnitude
        let startIndex = max(0, previousIndex - 3)

        for index in startIndex..<points.count {
            let distance = coordinate.location.distance(from: points[index].location)
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
        if isNavigating || pendingNavigationStart {
            stopNavigation()
        }
        route = nil
        pendingNavigationStart = false
        currentManeuverIndex = 0
        lastMatchedRouteIndex = 0
        lastAnnouncedManeuver = nil
        distanceToNextManeuver = nil
        showRouteSteps = false
        speechService.stop()
        if let message { statusMessage = message }
    }
}
