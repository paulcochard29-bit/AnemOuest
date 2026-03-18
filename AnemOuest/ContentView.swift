
import SwiftUI
import UIKit
import MapKit
import Charts
import Combine

// MARK: - Map Style Options

enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard = "standard"
    case satellite = "satellite"
    case hybrid = "hybrid"
    case muted = "muted"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .satellite: return "Satellite"
        case .hybrid: return "Hybride"
        case .muted: return "Nuit"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe.europe.africa.fill"
        case .hybrid: return "map.fill"
        case .muted: return "moon.fill"
        }
    }

    var mkMapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .satellite: return .satellite
        case .hybrid: return .hybrid
        case .muted: return .mutedStandard
        }
    }
}

// MARK: - Wind Station services are in WindStationService.swift

struct ContentView: View {

    // MARK: - State
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var remoteConfig: RemoteConfigService
    @StateObject private var stationManager = WindStationManager.shared
    @StateObject private var favoritesManager = FavoritesManager.shared
    @State private var refreshTick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    @AppStorage("refreshIntervalSeconds") private var refreshIntervalSeconds: Double = 30

    // Source filters
    @AppStorage("source_windcornouaille") private var sourceWindCornouaille: Bool = true
    @AppStorage("source_ffvl") private var sourceFFVL: Bool = false
    @AppStorage("source_pioupiou") private var sourcePioupiou: Bool = true
    @AppStorage("source_holfuy") private var sourceHolfuy: Bool = true
    @AppStorage("source_windguru") private var sourceWindguru: Bool = true
    @AppStorage("source_windsup") private var sourceWindsUp: Bool = false
    @AppStorage("source_meteofrance") private var sourceMeteoFrance: Bool = true
    @AppStorage("source_diabox") private var sourceDiabox: Bool = true
    @AppStorage("source_netatmo") private var sourceNetatmo: Bool = false
    @AppStorage("source_ndbc") private var sourceNDBC: Bool = true
    @AppStorage("windsup_email") private var windsUpEmail: String = ""
    @AppStorage("windsup_password") private var windsUpPassword: String = ""

    // Kite spots
    @AppStorage("showKiteSpots") private var showKiteSpots: Bool = false
    @AppStorage("kiteMaxWindThreshold") private var kiteMaxWindThreshold: Int = 40
    @AppStorage("kiteRiderLevel") private var kiteRiderLevelRaw: String = KiteRiderLevel.intermediate.rawValue
    @State private var selectedKiteSpot: KiteSpot? = nil
    @State private var showKitePanel: Bool = false
    @State private var kiteSpotForecast: ForecastData? = nil
    @State private var kiteSpotForecastLoading: Bool = false

    /// Find the nearest wind station to the selected kite spot (within 30km)
    private var nearestStationForKiteSpot: WindStation? {
        guard let spot = selectedKiteSpot else { return nil }
        let spotLocation = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        let maxDistance: Double = 30_000 // 30km max

        return cachedFilteredStations
            .filter { $0.isOnline }
            .min(by: { station1, station2 in
                let loc1 = CLLocation(latitude: station1.latitude, longitude: station1.longitude)
                let loc2 = CLLocation(latitude: station2.latitude, longitude: station2.longitude)
                return spotLocation.distance(from: loc1) < spotLocation.distance(from: loc2)
            })
            .flatMap { station in
                let stationLocation = CLLocation(latitude: station.latitude, longitude: station.longitude)
                return spotLocation.distance(from: stationLocation) <= maxDistance ? station : nil
            }
    }

    /// Find the nearest wave buoy to the selected kite spot (within 150km)
    /// Prioritizes buoys with seaTemp, but falls back to any active buoy with wave data
    private var nearestBuoyForKiteSpot: WaveBuoy? {
        guard let spot = selectedKiteSpot else { return nil }
        let spotLocation = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        let maxDistance: Double = 150_000 // 150km max (buoys are sparse along the coast)

        // First, try to find a buoy with seaTemp
        let buoyWithTemp = waveBuoyService.buoys
            .filter { $0.status.isOnline && $0.seaTemp != nil }
            .min(by: { buoy1, buoy2 in
                let loc1 = CLLocation(latitude: buoy1.latitude, longitude: buoy1.longitude)
                let loc2 = CLLocation(latitude: buoy2.latitude, longitude: buoy2.longitude)
                return spotLocation.distance(from: loc1) < spotLocation.distance(from: loc2)
            })
            .flatMap { buoy in
                let buoyLocation = CLLocation(latitude: buoy.latitude, longitude: buoy.longitude)
                return spotLocation.distance(from: buoyLocation) <= maxDistance ? buoy : nil
            }

        if buoyWithTemp != nil {
            return buoyWithTemp
        }

        // Fallback: any active buoy with wave data (hm0)
        return waveBuoyService.buoys
            .filter { $0.status.isOnline && $0.hm0 != nil }
            .min(by: { buoy1, buoy2 in
                let loc1 = CLLocation(latitude: buoy1.latitude, longitude: buoy1.longitude)
                let loc2 = CLLocation(latitude: buoy2.latitude, longitude: buoy2.longitude)
                return spotLocation.distance(from: loc1) < spotLocation.distance(from: loc2)
            })
            .flatMap { buoy in
                let buoyLocation = CLLocation(latitude: buoy.latitude, longitude: buoy.longitude)
                return spotLocation.distance(from: buoyLocation) <= maxDistance ? buoy : nil
            }
    }

    // Surf spots
    @AppStorage("showSurfSpots") private var showSurfSpots: Bool = false
    @State private var selectedSurfSpot: SurfSpot? = nil
    @State private var showSurfPanel: Bool = false

    // Paragliding spots
    @AppStorage("showParaglidingSpots") private var showParaglidingSpots: Bool = false
    @State private var selectedParaglidingSpot: ParaglidingSpot? = nil
    @State private var showParaglidingPanel: Bool = false
    @State private var paraglidingSpotForecast: ForecastData? = nil
    @State private var paraglidingSpotForecastLoading: Bool = false
    @State private var paraglidingSpots: [ParaglidingSpot] = []
    @State private var spotAirWebcams: [SpotAirWebcam] = []

    /// Find the nearest wind station to the selected paragliding spot (within 30km)
    private var nearestStationForParaglidingSpot: WindStation? {
        guard let spot = selectedParaglidingSpot else { return nil }
        let spotLocation = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        let maxDistance: Double = 30_000

        return cachedFilteredStations
            .filter { $0.isOnline }
            .min(by: { station1, station2 in
                let loc1 = CLLocation(latitude: station1.latitude, longitude: station1.longitude)
                let loc2 = CLLocation(latitude: station2.latitude, longitude: station2.longitude)
                return spotLocation.distance(from: loc1) < spotLocation.distance(from: loc2)
            })
            .flatMap { station in
                let stationLocation = CLLocation(latitude: station.latitude, longitude: station.longitude)
                return spotLocation.distance(from: stationLocation) <= maxDistance ? station : nil
            }
    }

    /// Find the nearest SpotAir webcam to the selected paragliding spot (within 10km)
    private var nearestWebcamForParaglidingSpot: SpotAirWebcam? {
        guard let spot = selectedParaglidingSpot else { return nil }
        let spotLocation = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        let maxDistance: Double = 10_000

        return spotAirWebcams
            .filter { $0.isOnline }
            .min(by: { cam1, cam2 in
                let loc1 = CLLocation(latitude: cam1.latitude, longitude: cam1.longitude)
                let loc2 = CLLocation(latitude: cam2.latitude, longitude: cam2.longitude)
                return spotLocation.distance(from: loc1) < spotLocation.distance(from: loc2)
            })
            .flatMap { cam in
                let camLocation = CLLocation(latitude: cam.latitude, longitude: cam.longitude)
                return spotLocation.distance(from: camLocation) <= maxDistance ? cam : nil
            }
    }

    /// Find the nearest wave buoy to the selected surf spot (within 150km)
    private var nearestBuoyForSurfSpot: WaveBuoy? {
        guard let spot = selectedSurfSpot else { return nil }
        let spotLocation = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        let maxDistance: Double = 150_000 // 150km max

        return waveBuoyService.buoys
            .filter { $0.status.isOnline && $0.hm0 != nil }
            .min(by: { buoy1, buoy2 in
                let loc1 = CLLocation(latitude: buoy1.latitude, longitude: buoy1.longitude)
                let loc2 = CLLocation(latitude: buoy2.latitude, longitude: buoy2.longitude)
                return spotLocation.distance(from: loc1) < spotLocation.distance(from: loc2)
            })
            .flatMap { buoy in
                let buoyLocation = CLLocation(latitude: buoy.latitude, longitude: buoy.longitude)
                return spotLocation.distance(from: buoyLocation) <= maxDistance ? buoy : nil
            }
    }

    // First launch detection
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    @StateObject private var locationManager = LocationManager()
    @State private var hasInitializedLocation: Bool = false

    private var enabledSources: Set<WindSource> {
        var sources = Set<WindSource>()
        if sourceWindCornouaille { sources.insert(.windCornouaille) }
        if sourceFFVL { sources.insert(.ffvl) }
        if sourcePioupiou { sources.insert(.pioupiou) }
        if sourceHolfuy { sources.insert(.holfuy) }
        if sourceWindguru { sources.insert(.windguru) }
        if sourceWindsUp { sources.insert(.windsUp) }
        if sourceMeteoFrance { sources.insert(.meteoFrance) }
        if sourceDiabox { sources.insert(.diabox) }
        if sourceNetatmo { sources.insert(.netatmo) }
        if sourceNDBC { sources.insert(.ndbc) }
        return sources
    }

    private var filteredStations: [WindStation] {
        stationManager.stations.filter { station in
            enabledSources.contains(station.source) &&
            !station.name.contains("Concorde") &&
            // Masquer les stations avec 0 nœud constant et 0 nœud en rafale
            !(station.wind == 0 && station.gust == 0)
        }
    }

    private var mapStyle: MapStyleOption {
        get { MapStyleOption(rawValue: mapStyleRaw) ?? .standard }
        nonmutating set { mapStyleRaw = newValue.rawValue }
    }

    @State private var selectedStation: WindStation? = nil
    @State private var stationSamples: [WCChartSample] = []

    // Cached filtered stations - avoid recomputing on every access
    @State private var cachedFilteredStations: [WindStation] = []
    // Dictionary for O(1) lookup by stationId
    @State private var stationById: [String: WindStation] = [:]
    @State private var timeFrame: Int = 60   // 2h
    @State private var showPanel: Bool = false
    @State private var showWavePanel: Bool = false
    @State private var showForecastFull: Bool = false
    @AppStorage("mapStyleRaw") private var mapStyleRaw: String = MapStyleOption.standard.rawValue
    @State private var showMapStylePicker: Bool = false
    @State private var showSeaMap: Bool = false
    @State private var lastSpotConditionCheck: Date?

    // Praticable spots overlay
    @State private var showPraticableSpots: Bool = false
    @State private var spotScores: [String: Int] = [:]  // spotId -> score
    @State private var isLoadingSpotScores: Bool = false
    @State private var showWindyFullscreen: Bool = false
    @AppStorage("openWeatherMapAPIKey") private var openWeatherMapAPIKey: String = ""
    @State private var showAlertConfig: Bool = false
    @State private var selectedWebcam: Webcam? = nil
    @State private var selectedWaveBuoy: WaveBuoy? = nil
    @AppStorage("showWebcamsOnMap") private var showWebcamsOnMap: Bool = false
    @AppStorage("showWaveBuoysOnMap") private var showWaveBuoysOnMap: Bool = true

    // Search
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var showUserLocation: Bool = false
    @State private var needsLocationZoom: Bool = false

    // Tide state
    @StateObject private var tideService = TideService.shared
    @State private var currentTideData: TideData? = nil
    @AppStorage("showTideWidget") private var showTideWidget: Bool = true
    @State private var showTideDetail: Bool = false

    @State private var tideUpdateTask: Task<Void, Never>?
    @State private var scoresUpdateTask: Task<Void, Never>?
    @State private var lastTidePortCode: String = "BREST"
    @State private var lastKnownSpan: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 1.6, longitudeDelta: 2.0)
    @State private var isCenteringCamera: Bool = false
    @State private var centeringTaskId: UUID = UUID()

    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var phoneSessionManager = PhoneSessionManager.shared
    @StateObject private var waveBuoyService = WaveBuoyService.shared
    @StateObject private var webcamService = WebcamService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    // Forecast state
    @State private var forecast: ForecastData? = nil
    @State private var forecastLoading: Bool = false

    // Chart loading state
    @State private var isChartLoading: Bool = false
    @State private var chartLoadGeneration: Int = 0

    // Initial camera: uses remote config defaults or falls back to France
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: UserDefaults.standard.object(forKey: "defaultMapLat") as? Double ?? 46.5,
                longitude: UserDefaults.standard.object(forKey: "defaultMapLon") as? Double ?? 2.5
            ),
            span: MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 10.0)
        )
    )

    // Chart interaction
    @State private var touchX: Date? = nil
    @State private var touchSampleWind: Double? = nil
    @State private var touchSampleGust: Double? = nil
    @State private var touchSampleDir: Double? = nil

    // MARK: - Animations
    private let panelAnim = Animation.smooth(duration: 0.38)
    private let cameraAnim = Animation.smooth(duration: 0.55)

    /// Check if any detail panel is visible (to hide tab bar)
    private var isAnyPanelShowing: Bool {
        showPanel || showKitePanel || showSurfPanel || showParaglidingPanel || showWavePanel
    }

    /// iPad uses trailing slide, iPhone uses bottom slide
    private var panelTransition: AnyTransition {
        if horizontalSizeClass == .regular {
            return .move(edge: .trailing).combined(with: .opacity)
        }
        return .move(edge: .bottom).combined(with: .opacity)
    }

    /// iPad panel padding (vertical + trailing), iPhone padding (bottom + horizontal)
    private func panelPadding() -> some ViewModifier {
        PanelPaddingModifier(isRegular: horizontalSizeClass == .regular)
    }

    var body: some View {
        homeView
            .toolbar(isAnyPanelShowing ? .hidden : .visible, for: .tabBar)
            .animation(.easeInOut(duration: 0.25), value: isAnyPanelShowing)
            .sheet(isPresented: $showMapStylePicker) {
                MapStylePicker(selectedStyle: Binding(
                    get: { mapStyle },
                    set: { mapStyleRaw = $0.rawValue }
                ))
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showWindyFullscreen) {
                WindyOverlayView(
                    isPresented: $showWindyFullscreen,
                    latitude: camera.region?.center.latitude ?? 47.6,
                    longitude: camera.region?.center.longitude ?? -3.6,
                    zoom: lastKnownSpan.windyZoom
                )
            }
    }

    private var homeView: some View {
        homeViewBase
            .modifier(HomeViewModifiers(
                showForecastFull: $showForecastFull,
                showAlertConfig: $showAlertConfig,
                selectedKiteSpot: $selectedKiteSpot,
                selectedStation: selectedStation,
                haptic: haptic
            ))
            .fullScreenCover(item: $selectedWebcam) { webcam in
                WebcamFullScreenView(webcam: webcam)
            }
    }

    // Computed hash for all source settings - changes when any source toggle changes
    private var sourceSettingsHash: Int {
        var hasher = Hasher()
        hasher.combine(sourceWindCornouaille)
        hasher.combine(sourceFFVL)
        hasher.combine(sourcePioupiou)
        hasher.combine(sourceHolfuy)
        hasher.combine(sourceWindguru)
        hasher.combine(sourceWindsUp)
        hasher.combine(sourceMeteoFrance)
        hasher.combine(sourceDiabox)
        return hasher.finalize()
    }

    private var homeViewBase: some View {
        homeViewLayers
            .sheet(isPresented: $showTideDetail) {
                TideDetailView(initialTideData: currentTideData, tideService: tideService)
            }

            .onAppear { handleOnAppear() }
            .onDisappear { }
            .onReceive(refreshTick) { _ in handleRefreshTick() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                handleReturnToForeground()
            }
            .onChange(of: sourceSettingsHash) { _, _ in refreshSources() }
            .onChange(of: favoritesManager.favorites) { _, _ in updateWidgetData() }
            .onChange(of: favoritesManager.favoriteWaveBuoys) { _, _ in updateWidgetData() }
            .onChange(of: timeFrame) { _, _ in handleTimeFrameChange() }
            .onChange(of: refreshIntervalSeconds) { _, _ in handleRefreshIntervalChange() }
            .onChange(of: camera) { _, newCamera in handleCameraChange(newCamera) }
            .onChange(of: locationManager.userLocation) { _, newLocation in
                handleLocationUpdate(newLocation)
                if needsLocationZoom, let loc = newLocation {
                    needsLocationZoom = false
                    zoomToLocation(loc)
                }
            }
            .onChange(of: isSearchFocused) { _, _ in }
            .onChange(of: stationManager.stations) { _, newStations in
                // Update selected station with fresh data after refresh
                if let selected = selectedStation,
                   let updated = newStations.first(where: { $0.stableId == selected.stableId }) {
                    selectedStation = updated
                }
            }
            .onChange(of: appState.selectedStationId) { _, stationId in handleAppStateStationChange(stationId) }
            .onChange(of: appState.selectedKiteSpotId) { _, spotId in handleAppStateKiteSpotChange(spotId) }
            .onChange(of: appState.selectedSurfSpotId) { _, spotId in handleAppStateSurfSpotChange(spotId) }
            .onChange(of: appState.selectedWaveBuoyId) { _, buoyId in handleAppStateWaveBuoyChange(buoyId) }
    }

    @ViewBuilder
    private var homeViewLayers: some View {
        ZStack {
            // Layer 0: Map (full screen, bottommost)
            mapWithSettings

            // Layer 1: Top controls (search + filter pills + results)
            VStack(spacing: 4) {
                searchPillContent
                    .padding(.horizontal, 16)

                ZStack {
                    filterPillsContent
                        .opacity(isSearchFocused && searchText.count >= 2 ? 0 : 1)
                        .allowsHitTesting(!(isSearchFocused && searchText.count >= 2))

                    if isSearchFocused && searchText.count >= 2 {
                        searchResultsOverlay
                    }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Layer 2: Bottom-left buttons
            bottomLeadingContent
                .padding(.leading, 12)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // Layer 3: Bottom-right buttons
            bottomTrailingContent
                .padding(.trailing, 12)
                .padding(.bottom, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            // Layer 4: Error banner
            ErrorBannerView()
                .padding(.top, 90)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(ErrorManager.shared.isShowingError)

            // Layer 6: Detail panels (topmost)
            if isAnyPanelShowing {
                if horizontalSizeClass == .regular {
                    panelContent
                        .frame(width: 560)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else {
                    panelContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }

    private func handleOnAppear() {
        // 0. Request notification authorization if user has alerts configured
        if !favoritesManager.favorites.filter({ $0.windAlertThreshold != nil }).isEmpty ||
           !favoritesManager.spotsWithActiveAlerts.isEmpty {
            Task { _ = await notificationManager.requestAuthorization() }
        }

        // 1. Show cached data immediately (non-blocking)
        updateCachedStations()

        // 2. Handle pending cross-tab navigation (from Favorites tab)
        if let stationId = appState.selectedStationId {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms - let Map settle
                handleAppStateStationChange(stationId)
            }
        } else if let spotId = appState.selectedKiteSpotId {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                handleAppStateKiteSpotChange(spotId)
            }
        } else if let spotId = appState.selectedSurfSpotId {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                handleAppStateSurfSpotChange(spotId)
            }
        } else if let buoyId = appState.selectedWaveBuoyId {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                handleAppStateWaveBuoyChange(buoyId)
            }
        }

        // 3. Handle location — only center on first launch (not when returning from another tab)
        showUserLocation = true
        locationManager.requestLocation()
        if let loc = locationManager.userLocation, !hasInitializedLocation {
            let taskId = UUID()
            centeringTaskId = taskId
            isCenteringCamera = true
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            ))
            hasInitializedLocation = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                if centeringTaskId == taskId {
                    isCenteringCamera = false
                }
            }
        }
        if !hasLaunchedBefore {
            hasLaunchedBefore = true
        }

        // 3. Launch independent data fetches in parallel
        // Tide data has no dependency on wind stations — fetch immediately
        Task(priority: .medium) {
            _ = await tideService.fetchPorts()
            let tideResult = await tideService.fetchTideData(portCode: "BREST", duration: 11)
            if let data = tideResult {
                await MainActor.run {
                    currentTideData = data
                    favoritesManager.updateTideWidgetData(
                        tides: data.tides,
                        locationName: data.port.name
                    )
                }
            } else {
                await MainActor.run {
                    ErrorManager.shared.show(.tideFailed)
                }
            }
        }

        // Launch all data fetches in parallel for fastest startup
        let loc = locationManager.userLocation?.clCoordinate

        // Wind stations (highest priority)
        Task(priority: .userInitiated) {
            await stationManager.refresh(sources: enabledSources, userLocation: loc)
            await MainActor.run {
                updateCachedStations()
                updateWidgetData()
                reportStationErrors()
                checkWindAlerts()
            }
            // Holfuy direct update after main stations
            await stationManager.refreshHolfuyDirect(userLocation: loc)
        }

        // Wave buoys (parallel, no dependency on stations)
        Task(priority: .userInitiated) {
            await waveBuoyService.fetchBuoys()
            await MainActor.run {
                favoritesManager.updateWaveBuoyWidgetData(buoys: waveBuoyService.buoys)
                if waveBuoyService.lastError != nil {
                    ErrorManager.shared.show(.waveBuoysFailed)
                }
            }
        }

        // Paragliding spots (parallel, if enabled)
        if showParaglidingSpots, let region = camera.region {
            Task(priority: .medium) {
                let south = region.center.latitude - region.span.latitudeDelta / 2
                let north = region.center.latitude + region.span.latitudeDelta / 2
                let west = region.center.longitude - region.span.longitudeDelta / 2
                let east = region.center.longitude + region.span.longitudeDelta / 2
                do {
                    async let spotsResult = SpotAirService.shared.fetchSpots(
                        south: south, north: north, west: west, east: east
                    )
                    async let webcamsResult = SpotAirService.shared.fetchWebcams(
                        south: south, north: north, west: west, east: east
                    )
                    let (spots, webcams) = try await (spotsResult, webcamsResult)
                    await MainActor.run {
                        paraglidingSpots = spots
                        spotAirWebcams = webcams
                    }
                } catch {
                    Log.error("Initial SpotAir load: \(error)")
                }
            }
        }

    }

    private func handleReturnToForeground() {
        // Refresh data and check alerts immediately when returning from background
        Task {
            let loc = locationManager.userLocation?.clCoordinate
            await stationManager.refresh(sources: enabledSources, userLocation: loc)
            updateCachedStations()
            updateWidgetData()
            reportStationErrors()
            checkWindAlerts()
            await stationManager.refreshHolfuyDirect(userLocation: loc)

        }
    }

    private func handleRefreshTick() {
        // Skip if already refreshing (prevents overlapping refreshes)
        guard !stationManager.isLoading else {
            Log.network("⏭ Refresh tick skipped — already loading")
            return
        }
        Task {
            let loc = locationManager.userLocation?.clCoordinate
            await stationManager.refresh(sources: enabledSources, userLocation: loc)
            updateCachedStations()
            updateWidgetData()
            reportStationErrors()
            checkWindAlerts()
            await stationManager.refreshHolfuyDirect(userLocation: loc)
        }
    }

    private func handleRefreshIntervalChange() {
        // Cancel old timer by replacing with new one at the correct interval
        refreshTick.upstream.connect().cancel()
        refreshTick = Timer.publish(every: refreshIntervalSeconds, on: .main, in: .common).autoconnect()
    }

    private func handleTimeFrameChange() {
        guard let station = selectedStation else { return }
        switch station.source {
        case .windsUp: loadWindsUpChart(stationId: station.id)
        case .meteoFrance: loadMeteoFranceChart(stationId: station.id)
        case .holfuy: loadHolfuyChart(stationId: station.stableId)
        case .windguru: loadWindguruChart(stationId: station.stableId)
        case .pioupiou: loadPioupiouChart(stationId: station.stableId)
        case .diabox: loadDiaboxChart(stationId: station.stableId)
        case .windCornouaille: loadWindCornouailleChart(stationId: station.id)
        case .netatmo: loadNetatmoChart(stationId: station.stableId)
        case .ndbc: loadNDBCChart(stationId: station.id)
        default: break
        }
    }

    private func handleCameraChange(_ newCamera: MapCameraPosition) {
        guard !isCenteringCamera else { return }
        if let region = newCamera.region,
           region.span.latitudeDelta > 0.01,
           region.span.longitudeDelta > 0.01 {
            lastKnownSpan = region.span

            // Update tide port based on map center (debounced)
            updateTidePortForLocation(region.center)

            // Load paragliding spots for visible region (debounced)
            if showParaglidingSpots {
                loadParaglidingSpotsDebounced(region: region)
            }

            // Reload praticable spots scores if enabled (debounced)
            if showPraticableSpots {
                reloadPraticableSpotsDebounced()
            }
        }
    }

    @State private var paraglidingLoadTask: Task<Void, Never>?

    private func loadParaglidingSpotsDebounced(region: MKCoordinateRegion) {
        paraglidingLoadTask?.cancel()
        paraglidingLoadTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }

            let south = region.center.latitude - region.span.latitudeDelta / 2
            let north = region.center.latitude + region.span.latitudeDelta / 2
            let west = region.center.longitude - region.span.longitudeDelta / 2
            let east = region.center.longitude + region.span.longitudeDelta / 2

            do {
                async let spotsResult = SpotAirService.shared.fetchSpots(
                    south: south, north: north, west: west, east: east
                )
                async let webcamsResult = SpotAirService.shared.fetchWebcams(
                    south: south, north: north, west: west, east: east
                )

                let (spots, webcams) = try await (spotsResult, webcamsResult)

                await MainActor.run {
                    paraglidingSpots = spots
                    spotAirWebcams = webcams
                }
            } catch {
                Log.error("SpotAir load error: \(error)")
            }
        }
    }

    private func reloadPraticableSpotsDebounced() {
        scoresUpdateTask?.cancel()
        scoresUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // 800ms debounce
            guard !Task.isCancelled else { return }
            await MainActor.run {
                loadPraticableSpots()
            }
        }
    }

    private func updateTidePortForLocation(_ center: CLLocationCoordinate2D) {
        // Cancel previous task (debounce)
        tideUpdateTask?.cancel()

        tideUpdateTask = Task {
            // Wait a bit before updating (debounce 500ms)
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            // Find nearest port
            if let nearestPort = tideService.findNearestPort(to: center) {
                // Only update if different port
                if nearestPort.cst != lastTidePortCode {
                    lastTidePortCode = nearestPort.cst
                    if let data = await tideService.fetchTideData(for: nearestPort, duration: 11) {
                        await MainActor.run {
                            currentTideData = data
                            // Update widget with tide data
                            favoritesManager.updateTideWidgetData(
                                tides: data.tides,
                                locationName: data.port.name
                            )
                        }
                    }
                }
            }
        }
    }

    // mapWithControls removed - controls now in ZStack within homeViewBase

    private var mapWithSettings: some View {
        MapLayerView(
            camera: $camera,
            selectedStationId: selectedStation?.stableId,
            windStations: cachedFilteredStations,
            kiteSpots: kiteSpots,  // Always pass for combined clustering
            surfSpots: allSurfSpots,  // Always pass for combined clustering
            showKiteSpots: showKiteSpots,
            showSurfSpots: showSurfSpots,
            paraglidingSpots: paraglidingSpots,
            showParaglidingSpots: showParaglidingSpots,
            webcams: (remoteConfig.enableWebcams && showWebcamsOnMap) ? webcamService.webcams : [],
            waveBuoys: (remoteConfig.enableWaveBuoys && showWaveBuoysOnMap) ? waveBuoyService.buoys : [],
            mapStyle: mapStyle,
            showSeaMap: showSeaMap,
            isCenteringCamera: isCenteringCamera,
            showUserLocation: showUserLocation,
            onTapStationById: { stationId in
                selectStationFast(stationId: stationId)
            },
            onTapKiteSpot: { spot in
                haptic(.medium)
                selectedKiteSpot = spot
                showKitePanel = true
                showPanel = false
                showWavePanel = false
                showSurfPanel = false
                showParaglidingPanel = false

                // Center camera on kite spot
                centerOnAnnotation(coordinate: spot.coordinate)

                // Load forecast for kite spot
                kiteSpotForecastLoading = true
                kiteSpotForecast = nil
                Task {
                    do {
                        let data = try await ForecastService.shared.fetchForecast(
                            latitude: spot.latitude,
                            longitude: spot.longitude,
                            model: .arome
                        )
                        await MainActor.run {
                            kiteSpotForecast = data
                            kiteSpotForecastLoading = false
                        }
                    } catch {
                        await MainActor.run {
                            kiteSpotForecastLoading = false
                        }
                    }
                }
            },
            onTapSurfSpot: { spot in
                haptic(.medium)
                selectedSurfSpot = spot
                showSurfPanel = true
                showPanel = false
                showWavePanel = false
                showKitePanel = false
                showParaglidingPanel = false

                // Center camera on surf spot
                centerOnAnnotation(coordinate: spot.coordinate)
            },
            onTapParaglidingSpot: { spot in
                haptic(.medium)
                selectedParaglidingSpot = spot
                showParaglidingPanel = true
                showPanel = false
                showWavePanel = false
                showKitePanel = false
                showSurfPanel = false

                // Center camera on paragliding spot
                centerOnAnnotation(coordinate: spot.coordinate)

                // Load forecast for paragliding spot
                paraglidingSpotForecastLoading = true
                paraglidingSpotForecast = nil
                Task {
                    do {
                        let data = try await ForecastService.shared.fetchForecast(
                            latitude: spot.latitude,
                            longitude: spot.longitude,
                            model: .arome
                        )
                        await MainActor.run {
                            paraglidingSpotForecast = data
                            paraglidingSpotForecastLoading = false
                        }
                    } catch {
                        await MainActor.run {
                            paraglidingSpotForecastLoading = false
                        }
                    }
                }
            },
            onTapWebcam: { webcam in
                haptic(.light)
                selectedWebcam = webcam
                Analytics.webcamViewed(id: webcam.id)
            },
            onTapWaveBuoy: { buoy in
                haptic(.medium)
                // Close any open wind panel
                showPanel = false
                selectedStation = nil
                // Open wave panel
                selectedWaveBuoy = buoy
                withAnimation(panelAnim) {
                    showWavePanel = true
                }
                // Center camera on buoy
                centerOnAnnotation(coordinate: buoy.coordinate)
            },
            showPraticableSpots: showPraticableSpots,
            spotScores: spotScores
        )
    }

    private func updateCachedStations() {
        let filtered = filteredStations
        cachedFilteredStations = filtered
        // Build dictionary for O(1) lookup by stationId
        stationById = Dictionary(uniqueKeysWithValues: filtered.map { ($0.stableId, $0) })
    }

    private func updateWidgetData() {
        favoritesManager.updateWidgetData(
            stations: stationManager.stations
        )

        // Update wave buoy widget data
        favoritesManager.updateWaveBuoyWidgetData(buoys: waveBuoyService.buoys)

        // Also update Watch
        phoneSessionManager.sendFavoritesToWatch(
            favoritesManager.favorites,
            stations: stationManager.stations
        )
    }

    private func reportStationErrors() {
        // Cache icon + offline banner handle all feedback now
    }

    private func refreshSources() {
        // Update cached stations immediately (for filtering)
        updateCachedStations()

        // Trigger a full refresh with new enabled sources
        Task {
            let loc = locationManager.userLocation?.clCoordinate
            await stationManager.refresh(sources: enabledSources, userLocation: loc)
            updateCachedStations()
            updateWidgetData()
            reportStationErrors()
            checkWindAlerts()
            await stationManager.refreshHolfuyDirect(userLocation: loc)

        }
    }

    private func handleLocationUpdate(_ newLocation: LocationCoordinate?) {
        // Center on user location only once per session
        guard let location = newLocation, !hasInitializedLocation else { return }
        hasInitializedLocation = true

        // Center on user with a local span (~100km view)
        let taskId = UUID()
        centeringTaskId = taskId
        isCenteringCamera = true

        let userRegion = MKCoordinateRegion(
            center: location.clCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        camera = .region(userRegion)
        Log.debug("Centered on user location: \(location.latitude), \(location.longitude)")

        // Reset centering flag after animation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if centeringTaskId == taskId {
                isCenteringCamera = false
            }
        }
    }

    // MARK: - AppState Navigation Handlers (from Favorites tab)

    private let favoritesZoomSpan = MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)

    private func handleAppStateStationChange(_ stationId: String?) {
        guard let stationId = stationId else { return }
        defer { appState.clearNavigationState() }

        // Check in cached filtered stations (O(1) lookup)
        if let station = stationById[stationId] {
            selectStationFast(stationId: stationId)
            centerOnAnnotation(coordinate: station.coordinate, zoomSpan: favoritesZoomSpan)
            return
        }

        // Try ALL stations including disabled sources / offline
        if let station = stationManager.stations.first(where: { $0.stableId == stationId }) {
            selectStationFast(stationId: station.stableId)
            centerOnAnnotation(coordinate: station.coordinate, zoomSpan: favoritesZoomSpan)
            return
        }

        // Fallback: use saved coordinates from favorites
        if let favorite = favoritesManager.favorites.first(where: { $0.id == stationId }) {
            haptic(.medium)
            centerOnAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: favorite.latitude, longitude: favorite.longitude),
                zoomSpan: favoritesZoomSpan
            )
        }
    }

    private func handleAppStateKiteSpotChange(_ spotId: String?) {
        guard let spotId = spotId else { return }
        defer { appState.clearNavigationState() }

        if let spot = kiteSpots.first(where: { $0.id == spotId }) {
            haptic(.medium)
            selectedKiteSpot = spot
            showKitePanel = true
            showPanel = false
            showWavePanel = false
            showSurfPanel = false
            centerOnAnnotation(coordinate: spot.coordinate, zoomSpan: favoritesZoomSpan)
            return
        }

        // Fallback: use saved coordinates from favorites
        if let favorite = favoritesManager.favoriteSpots.first(where: { $0.id == spotId }) {
            haptic(.medium)
            centerOnAnnotation(coordinate: favorite.coordinate, zoomSpan: favoritesZoomSpan)
        }
    }

    private func handleAppStateSurfSpotChange(_ spotId: String?) {
        guard let spotId = spotId else { return }
        defer { appState.clearNavigationState() }

        if let spot = allSurfSpots.first(where: { $0.id == spotId }) {
            haptic(.medium)
            selectedSurfSpot = spot
            showSurfPanel = true
            showPanel = false
            showWavePanel = false
            showKitePanel = false
            centerOnAnnotation(coordinate: spot.coordinate, zoomSpan: favoritesZoomSpan)
            return
        }

        // Fallback: use saved coordinates from favorites
        if let favorite = favoritesManager.favoriteSpots.first(where: { $0.id == spotId }) {
            haptic(.medium)
            centerOnAnnotation(coordinate: favorite.coordinate, zoomSpan: favoritesZoomSpan)
        }
    }

    private func handleAppStateWaveBuoyChange(_ buoyId: String?) {
        guard let buoyId = buoyId else { return }
        defer { appState.clearNavigationState() }

        if let buoy = waveBuoyService.buoys.first(where: { $0.id == buoyId }) {
            haptic(.medium)
            selectedWaveBuoy = buoy
            showWavePanel = true
            showPanel = false
            showKitePanel = false
            showSurfPanel = false
            centerOnAnnotation(coordinate: CLLocationCoordinate2D(latitude: buoy.latitude, longitude: buoy.longitude), zoomSpan: favoritesZoomSpan)
            return
        }

        // Fallback: buoys might not be loaded yet, use saved coordinates
        if let favorite = favoritesManager.favoriteWaveBuoys.first(where: { $0.id == buoyId }) {
            haptic(.medium)
            centerOnAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: favorite.latitude, longitude: favorite.longitude),
                zoomSpan: favoritesZoomSpan
            )
        }
    }

    private func checkWindAlerts() {
        // WC stations are already in stationManager.stations
        notificationManager.checkAndNotify(
            stations: stationManager.stations,
            favorites: favoritesManager.favorites
        )

        // Check spot conditions (throttled to every 15 minutes)
        Task {
            await checkSpotConditionsForeground()
        }
    }

    /// Check spot conditions in foreground (throttled)
    private func checkSpotConditionsForeground() async {
        // Throttle: only check every 15 minutes
        if let lastCheck = lastSpotConditionCheck,
           Date().timeIntervalSince(lastCheck) < 15 * 60 {
            return
        }

        let spotsWithAlerts = favoritesManager.spotsWithActiveAlerts
        guard !spotsWithAlerts.isEmpty else { return }

        // Fetch forecasts for each spot
        var forecasts: [String: ForecastData] = [:]
        var surfForecasts: [String: SurfWaveForecast] = [:]

        for spot in spotsWithAlerts {
            do {
                let forecast = try await ForecastService.shared.fetchForecast(
                    latitude: spot.latitude,
                    longitude: spot.longitude
                )
                forecasts[spot.id] = forecast
            } catch {
                Log.network("Foreground spot check: Failed to fetch forecast for \(spot.name)")
            }

            if spot.type == .surf {
                do {
                    let surfForecast = try await SurfForecastService.shared.fetchForecastDirect(
                        latitude: spot.latitude,
                        longitude: spot.longitude
                    )
                    if let current = surfForecast.first {
                        surfForecasts[spot.id] = current
                    }
                } catch {
                    Log.network("Foreground spot check: Failed to fetch surf forecast for \(spot.name)")
                }
            }
        }

        // Fetch tide data
        var tideData: TideData?
        if let firstSpot = spotsWithAlerts.first {
            let coordinate = CLLocationCoordinate2D(latitude: firstSpot.latitude, longitude: firstSpot.longitude)
            tideData = await TideService.shared.fetchTideForLocation(coordinate)
        }

        // Check conditions and send notifications
        await MainActor.run {
            notificationManager.checkSpotConditions(
                spots: spotsWithAlerts,
                forecasts: forecasts,
                surfForecasts: surfForecasts,
                tideData: tideData,
                nearbyStations: stationManager.stations
            )
            lastSpotConditionCheck = Date()
        }

        Log.debug("Foreground: Checked spot conditions for \(spotsWithAlerts.count) spots")
    }

    // MARK: - Ultra-fast selection (optimized for responsiveness)

    private func selectStationFast(stationId: String) {
        // O(1) lookup using dictionary
        guard let station = stationById[stationId] else { return }

        Analytics.stationSelected(name: station.name, source: station.source.displayName)

        // 1. Haptic FIRST - user feels immediate response
        haptic(.medium)

        // 2. Update state
        stationSamples = []
        forecast = nil
        selectedStation = station
        selectedWaveBuoy = nil
        showWavePanel = false
        showPanel = true

        // 3. Center camera on station
        centerOnAnnotation(coordinate: station.coordinate)

        // 4. Load forecast async
        loadForecast(stationId: station.stableId, stationName: station.name, latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)

        // 5. Load chart data for stations with history
        if station.source == .windsUp {
            if timeFrame == 288 { timeFrame = 144 }
            loadWindsUpChart(stationId: station.id)
        } else if station.source == .meteoFrance {
            loadMeteoFranceChart(stationId: station.id)
        } else if station.source == .holfuy {
            loadHolfuyChart(stationId: station.stableId)
        } else if station.source == .windguru {
            loadWindguruChart(stationId: station.stableId)
        } else if station.source == .pioupiou {
            loadPioupiouChart(stationId: station.stableId)
        } else if station.source == .diabox {
            if timeFrame == 288 { timeFrame = 144 }
            loadDiaboxChart(stationId: station.stableId)
        } else if station.source == .windCornouaille {
            loadWindCornouailleChart(stationId: station.id)
        } else if station.source == .netatmo {
            loadNetatmoChart(stationId: station.stableId)
        } else if station.source == .ndbc {
            loadNDBCChart(stationId: station.id)
        }
    }

    private func centerAbovePanel(coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan? = nil, animated: Bool = true) {
        // Use provided span or fall back to lastKnownSpan
        let useSpan = span ?? lastKnownSpan

        // Validate span to prevent glitches
        guard useSpan.latitudeDelta > 0.005 && useSpan.longitudeDelta > 0.005 else { return }

        // Offset to position station above panel (30% offset)
        let yOffset = useSpan.latitudeDelta * 0.30

        let centered = CLLocationCoordinate2D(
            latitude: coordinate.latitude - yOffset,
            longitude: coordinate.longitude
        )

        let newRegion = MKCoordinateRegion(center: centered, span: useSpan)

        // Set camera - animation handled by caller or simple flag
        if animated {
            withAnimation(.easeOut(duration: 0.3)) {
                camera = .region(newRegion)
            }
        } else {
            camera = .region(newRegion)
        }
    }

    /// Simplified centering that's more reliable during refreshes
    private func centerOnAnnotation(coordinate: CLLocationCoordinate2D, zoomSpan: MKCoordinateSpan? = nil) {
        let taskId = UUID()
        centeringTaskId = taskId
        isCenteringCamera = true

        // Use provided zoom span or current span
        let span = zoomSpan ?? lastKnownSpan

        // Small delay to let state settle, then center
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            guard centeringTaskId == taskId else { return }
            centerAbovePanel(coordinate: coordinate, span: span)

            // Reset flag after animation completes
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms
            if centeringTaskId == taskId {
                isCenteringCamera = false
            }
        }
    }

    /// Zoom to user location with proper isCenteringCamera flag
    private func zoomToLocation(_ loc: LocationCoordinate) {
        let taskId = UUID()
        centeringTaskId = taskId
        isCenteringCamera = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            guard centeringTaskId == taskId else { return }
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            ))

            // Reset flag after animation completes
            try? await Task.sleep(nanoseconds: 600_000_000) // 600ms
            if centeringTaskId == taskId {
                isCenteringCamera = false
            }
        }
    }

    /// Load forecast for a kite spot
    private func loadKiteSpotForecast(spot: KiteSpot) {
        kiteSpotForecastLoading = true
        kiteSpotForecast = nil
        Task {
            do {
                let data = try await ForecastService.shared.fetchForecast(
                    latitude: spot.latitude,
                    longitude: spot.longitude,
                    model: .arome
                )
                await MainActor.run {
                    kiteSpotForecast = data
                    kiteSpotForecastLoading = false
                }
            } catch {
                Log.error("Kite spot forecast error: \(error)")
                await MainActor.run {
                    kiteSpotForecastLoading = false
                    ErrorManager.shared.show(.forecastFailed(spot.name))
                }
            }
        }
    }

    private func loadWindsUpChart(stationId: String) {
        let allObservations = WindsUpService.shared.getObservations(windStationId: stationId)

        // Map timeFrame picker tags to actual hours (same as other sources)
        let hours: Int
        switch timeFrame {
        case 60: hours = 2
        case 36: hours = 6
        case 144: hours = 24
        case 288: hours = 48
        default: hours = 2
        }

        let cutoffDate = Date().addingTimeInterval(-Double(hours) * 3600)
        let observations = allObservations.filter { $0.timestamp >= cutoffDate }

        Log.data("WindsUp Chart: Loading \(observations.count)/\(allObservations.count) observations for \(stationId) (last \(hours)h)")

        // Convert WindsUp observations to WCChartSample format
        var samples: [WCChartSample] = []
        var gustCount = 0
        for obs in observations {
            // Wind speed
            samples.append(WCChartSample(
                id: "\(obs.timestamp.timeIntervalSince1970)_wind",
                t: obs.timestamp,
                value: obs.windSpeed,
                kind: .wind
            ))
            // Gust speed (if available)
            if let gust = obs.gustSpeed {
                samples.append(WCChartSample(
                    id: "\(obs.timestamp.timeIntervalSince1970)_gust",
                    t: obs.timestamp,
                    value: gust,
                    kind: .gust
                ))
                gustCount += 1
            }
            // Direction (if available)
            if let dir = obs.windDirectionDegrees {
                samples.append(WCChartSample(
                    id: "\(obs.timestamp.timeIntervalSince1970)_dir",
                    t: obs.timestamp,
                    value: dir,
                    kind: .dir
                ))
            }
        }

        // Sort by time ascending
        samples.sort { $0.t < $1.t }
        stationSamples = samples
        Log.data("WindsUp Chart: Created \(samples.count) samples (\(gustCount) gusts)")
    }

    private func loadMeteoFranceChart(stationId: String) {
        chartLoadGeneration += 1
        let generation = chartLoadGeneration
        isChartLoading = true
        Task {
            defer { if chartLoadGeneration == generation { isChartLoading = false } }
            do {
                // Map timeFrame picker values to actual hours
                let hours: Int
                switch timeFrame {
                case 60: hours = 2
                case 36: hours = 6
                case 144: hours = 24
                case 288: hours = 48
                default: hours = 2
                }

                // Use Vercel API (cached, supports unlimited users)
                let history = try await MeteoFranceService.shared.fetchHistoryFromVercel(stationId: stationId, hours: hours)

                guard chartLoadGeneration == generation else { return }

                // Filter by actual duration
                let cutoffDate = Date().addingTimeInterval(-Double(hours) * 3600)
                let filtered = history.filter { $0.timestamp >= cutoffDate }

                Log.data("MF Chart: Loading \(filtered.count)/\(history.count) observations for \(stationId) (last \(hours)h)")

                // Convert to WCChartSample format
                var samples: [WCChartSample] = []
                for obs in filtered {
                    // Wind speed
                    samples.append(WCChartSample(
                        id: "\(obs.timestamp.timeIntervalSince1970)_wind",
                        t: obs.timestamp,
                        value: obs.windSpeed,
                        kind: .wind
                    ))
                    // Gust speed
                    if obs.windGust > 0 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_gust",
                            t: obs.timestamp,
                            value: obs.windGust,
                            kind: .gust
                        ))
                    }
                    // Direction
                    if obs.windDirection >= 0 && obs.windDirection <= 360 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_dir",
                            t: obs.timestamp,
                            value: obs.windDirection,
                            kind: .dir
                        ))
                    }
                }

                // Sort by time ascending
                samples.sort { $0.t < $1.t }
                stationSamples = samples
                Log.data("MF Chart: Created \(samples.count) samples")
            } catch {
                if chartLoadGeneration == generation {
                    Log.error("MF Chart error: \(error)")
                }
            }
        }
    }

    private func loadHolfuyChart(stationId: String) {
        chartLoadGeneration += 1
        let generation = chartLoadGeneration
        isChartLoading = true
        Task {
            defer { if chartLoadGeneration == generation { isChartLoading = false } }
            do {
                // Map timeFrame picker values to actual hours
                let hours: Int
                switch timeFrame {
                case 60: hours = 2
                case 36: hours = 6
                case 144: hours = 24
                case 288: hours = 48
                default: hours = 2
                }

                // Use direct Holfuy API for history (~5 days available)
                let history = try await HolfuyHistoryService.shared.fetchHistory(stationId: stationId, hours: hours)

                guard chartLoadGeneration == generation else { return }

                Log.data("Holfuy Chart: Loading \(history.count) observations for \(stationId) (last \(hours)h)")

                // Convert to WCChartSample format
                var samples: [WCChartSample] = []
                for obs in history {
                    samples.append(WCChartSample(
                        id: "\(obs.timestamp.timeIntervalSince1970)_wind",
                        t: obs.timestamp,
                        value: obs.windSpeed,
                        kind: .wind
                    ))
                    if obs.gustSpeed > 0 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_gust",
                            t: obs.timestamp,
                            value: obs.gustSpeed,
                            kind: .gust
                        ))
                    }
                    if obs.direction >= 0 && obs.direction <= 360 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_dir",
                            t: obs.timestamp,
                            value: obs.direction,
                            kind: .dir
                        ))
                    }
                }

                samples.sort { $0.t < $1.t }
                stationSamples = samples
                Log.data("Holfuy Chart: Created \(samples.count) samples")
            } catch {
                if chartLoadGeneration == generation {
                    Log.error("Holfuy Chart error: \(error)")
                    stationSamples = []
                }
            }
        }
    }

    private func loadWindguruChart(stationId: String) {
        chartLoadGeneration += 1
        let generation = chartLoadGeneration
        isChartLoading = true
        Task {
            defer { if chartLoadGeneration == generation { isChartLoading = false } }
            do {
                // Map timeFrame picker values to actual hours
                let hours: Int
                switch timeFrame {
                case 60: hours = 2
                case 36: hours = 6
                case 144: hours = 24
                case 288: hours = 48
                default: hours = 2
                }

                // Use Vercel API for Windguru history (accumulates over time)
                let history = try await GoWindVercelService.shared.fetchHistory(stationId: stationId, hours: hours)

                guard chartLoadGeneration == generation else { return }

                let cutoffDate = Date().addingTimeInterval(-Double(hours) * 3600)
                let filtered = history.filter { $0.timestamp >= cutoffDate }

                Log.data("Windguru Chart: Loading \(filtered.count)/\(history.count) observations for \(stationId) (last \(hours)h)")

                var samples: [WCChartSample] = []
                for obs in filtered {
                    samples.append(WCChartSample(
                        id: "\(obs.timestamp.timeIntervalSince1970)_wind",
                        t: obs.timestamp,
                        value: obs.windSpeed,
                        kind: .wind
                    ))
                    if obs.gustSpeed > 0 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_gust",
                            t: obs.timestamp,
                            value: obs.gustSpeed,
                            kind: .gust
                        ))
                    }
                    if obs.direction >= 0 && obs.direction <= 360 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_dir",
                            t: obs.timestamp,
                            value: obs.direction,
                            kind: .dir
                        ))
                    }
                }

                samples.sort { $0.t < $1.t }
                stationSamples = samples
                Log.data("Windguru Chart: Created \(samples.count) samples")
            } catch {
                if chartLoadGeneration == generation {
                    Log.error("Windguru Chart error: \(error)")
                    stationSamples = []
                }
            }
        }
    }

    private func loadPioupiouChart(stationId: String) {
        chartLoadGeneration += 1
        let generation = chartLoadGeneration
        isChartLoading = true
        Task {
            defer { if chartLoadGeneration == generation { isChartLoading = false } }
            do {
                // Map timeFrame picker values to actual hours
                let hours: Int
                switch timeFrame {
                case 60: hours = 2
                case 36: hours = 6
                case 144: hours = 24
                case 288: hours = 48
                default: hours = 2
                }

                // Use official Pioupiou Archive API (faster, direct)
                let history = try await PioupiouVercelService.shared.fetchHistoryDirect(stationId: stationId, hours: hours)

                guard chartLoadGeneration == generation else { return }

                // Filter by actual duration
                let cutoffDate = Date().addingTimeInterval(-Double(hours) * 3600)
                let filtered = history.filter { $0.timestamp >= cutoffDate }

                Log.data("Pioupiou Chart: Loading \(filtered.count)/\(history.count) observations for \(stationId) (last \(hours)h)")

                // Convert to WCChartSample format
                var samples: [WCChartSample] = []
                for obs in filtered {
                    // Wind speed
                    samples.append(WCChartSample(
                        id: "\(obs.timestamp.timeIntervalSince1970)_wind",
                        t: obs.timestamp,
                        value: obs.windSpeed,
                        kind: .wind
                    ))
                    // Gust speed
                    if obs.gustSpeed > 0 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_gust",
                            t: obs.timestamp,
                            value: obs.gustSpeed,
                            kind: .gust
                        ))
                    }
                    // Direction
                    if obs.direction >= 0 && obs.direction <= 360 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_dir",
                            t: obs.timestamp,
                            value: obs.direction,
                            kind: .dir
                        ))
                    }
                }

                // Sort by time ascending
                samples.sort { $0.t < $1.t }
                stationSamples = samples
                Log.data("Pioupiou Chart: Created \(samples.count) samples")
            } catch {
                if chartLoadGeneration == generation {
                    Log.error("Pioupiou Chart error: \(error)")
                    stationSamples = []
                }
            }
        }
    }

    private func loadDiaboxChart(stationId: String) {
        chartLoadGeneration += 1
        let generation = chartLoadGeneration
        isChartLoading = true
        Task {
            defer { if chartLoadGeneration == generation { isChartLoading = false } }
            do {
                let hours: Int
                switch timeFrame {
                case 60: hours = 2
                case 36: hours = 6
                case 144: hours = 24
                case 288: hours = 48
                default: hours = 2
                }

                let rawId = stationId.replacingOccurrences(of: "diabox_", with: "")
                let history = try await DiaboxService.shared.fetchHistory(stationId: rawId, hours: hours)

                guard chartLoadGeneration == generation else { return }

                let cutoffDate = Date().addingTimeInterval(-Double(hours) * 3600)
                let filtered = history.filter { $0.timestamp >= cutoffDate }

                Log.data("Diabox Chart: Loading \(filtered.count)/\(history.count) observations for \(stationId) (last \(hours)h)")

                var samples: [WCChartSample] = []
                for obs in filtered {
                    samples.append(WCChartSample(
                        id: "\(obs.timestamp.timeIntervalSince1970)_wind",
                        t: obs.timestamp,
                        value: obs.windSpeed,
                        kind: .wind
                    ))
                    if obs.gustSpeed > 0 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_gust",
                            t: obs.timestamp,
                            value: obs.gustSpeed,
                            kind: .gust
                        ))
                    }
                    if obs.direction >= 0 && obs.direction <= 360 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_dir",
                            t: obs.timestamp,
                            value: obs.direction,
                            kind: .dir
                        ))
                    }
                }

                samples.sort { $0.t < $1.t }
                stationSamples = samples
                Log.data("Diabox Chart: Created \(samples.count) samples")
            } catch {
                if chartLoadGeneration == generation {
                    Log.error("Diabox Chart error: \(error)")
                    stationSamples = []
                }
            }
        }
    }

    private func loadNetatmoChart(stationId: String) {
        chartLoadGeneration += 1
        let generation = chartLoadGeneration
        isChartLoading = true
        Task {
            defer { if chartLoadGeneration == generation { isChartLoading = false } }
            do {
                let hours: Int
                switch timeFrame {
                case 60: hours = 2
                case 36: hours = 6
                case 144: hours = 24
                case 288: hours = 48
                default: hours = 2
                }

                let history = try await NetatmoService.shared.fetchHistory(stationId: stationId, hours: hours)

                guard chartLoadGeneration == generation else { return }

                let cutoffDate = Date().addingTimeInterval(-Double(hours) * 3600)
                let filtered = history.filter { $0.timestamp >= cutoffDate }

                Log.data("Netatmo Chart: Loading \(filtered.count)/\(history.count) observations for \(stationId) (last \(hours)h)")

                var samples: [WCChartSample] = []
                for obs in filtered {
                    samples.append(WCChartSample(
                        id: "\(obs.timestamp.timeIntervalSince1970)_wind",
                        t: obs.timestamp,
                        value: obs.windSpeed,
                        kind: .wind
                    ))
                    if obs.gustSpeed > 0 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_gust",
                            t: obs.timestamp,
                            value: obs.gustSpeed,
                            kind: .gust
                        ))
                    }
                    if obs.direction >= 0 && obs.direction <= 360 {
                        samples.append(WCChartSample(
                            id: "\(obs.timestamp.timeIntervalSince1970)_dir",
                            t: obs.timestamp,
                            value: obs.direction,
                            kind: .dir
                        ))
                    }
                }

                samples.sort { $0.t < $1.t }
                stationSamples = samples
                Log.data("Netatmo Chart: Created \(samples.count) samples")
            } catch {
                if chartLoadGeneration == generation {
                    Log.error("Netatmo Chart error: \(error)")
                    stationSamples = []
                }
            }
        }
    }

    private func loadNDBCChart(stationId: String) {
        chartLoadGeneration += 1
        let generation = chartLoadGeneration
        isChartLoading = true
        Task {
            defer { if chartLoadGeneration == generation { isChartLoading = false } }

            let hours: Int
            switch timeFrame {
            case 60: hours = 2
            case 36: hours = 6
            case 144: hours = 24
            case 288: hours = 48
            default: hours = 2
            }

            let history = await NDBCService.shared.fetchHistory(stationId: stationId, hours: hours)

            guard chartLoadGeneration == generation else { return }

            let cutoffDate = Date().addingTimeInterval(-Double(hours) * 3600)
            let filtered = history.filter { Date(timeIntervalSince1970: $0.ts) >= cutoffDate }

            var samples: [WCChartSample] = []
            for obs in filtered {
                let date = Date(timeIntervalSince1970: obs.ts)
                samples.append(WCChartSample(
                    id: "\(obs.ts)_wind",
                    t: date,
                    value: obs.ws.moy.value ?? 0,
                    kind: .wind
                ))
                if let gustVal = obs.ws.max.value, gustVal > 0 {
                    samples.append(WCChartSample(
                        id: "\(obs.ts)_gust",
                        t: date,
                        value: gustVal,
                        kind: .gust
                    ))
                }
                if let dirVal = obs.wd.moy.value, dirVal >= 0 && dirVal <= 360 {
                    samples.append(WCChartSample(
                        id: "\(obs.ts)_dir",
                        t: date,
                        value: dirVal,
                        kind: .dir
                    ))
                }
            }

            samples.sort { $0.t < $1.t }
            stationSamples = samples
        }
    }

    private func loadWindCornouailleChart(stationId: String) {
        chartLoadGeneration += 1
        let generation = chartLoadGeneration
        isChartLoading = true
        Task {
            defer { if chartLoadGeneration == generation { isChartLoading = false } }
            do {
                let result = try await WindService.fetchChartWC(sensorId: stationId, timeFrame: timeFrame)
                guard chartLoadGeneration == generation else { return }
                stationSamples = result.samples
            } catch {
                if chartLoadGeneration == generation {
                    stationSamples = []
                }
            }
        }
    }

    private func loadForecast(stationId: String, stationName: String, latitude: Double, longitude: Double) {
        Analytics.forecastLoaded(stationId: stationId, source: "forecast")
        forecastLoading = true
        Task {
            do {
                let data = try await ForecastService.shared.fetchForecast(latitude: latitude, longitude: longitude)
                self.forecast = data

                // Store forecasts for accuracy tracking
                ForecastAccuracyService.shared.storeForecast(
                    stationId: stationId,
                    stationName: stationName,
                    latitude: latitude,
                    longitude: longitude,
                    forecasts: data.hourly
                )

                // Update widget with forecast data
                favoritesManager.updateForecastWidgetData(
                    forecast: data,
                    stationId: stationId,
                    stationName: stationName
                )
            } catch {
                Log.error("Forecast error: \(error)")
                self.forecast = nil
                ErrorManager.shared.show(.forecastFailed(stationName))
            }
            self.forecastLoading = false
        }
    }

    @ViewBuilder
    private var panelContent: some View {
            if showPanel, let station = selectedStation {
                BottomPanel(
                    sensorName: station.name,
                    sourceName: station.source.displayName,
                    sourceColor: station.source.color,
                    latest: stationLatest(for: station),
                    samples: stationSamples,
                    timeFrame: $timeFrame,
                    lastUpdatedAt: Date(),
                    measurementDate: station.lastUpdate,
                    hadError: false,
                    chartLoading: isChartLoading,
                    isRefreshing: stationManager.isLoading,
                    limitedHistory: false,  // WindsUp has 22+ hours of data
                    forecast: forecast,
                    forecastLoading: forecastLoading,
                    tideData: currentTideData,
                    isFavorite: favoritesManager.isFavorite(stationId: station.stableId),
                    onToggleFavorite: {
                        haptic(.medium)
                        favoritesManager.toggleFavorite(station: station)
                    },
                    stationId: station.stableId,
                    hasWindAlert: notificationManager.hasAlert(for: station.stableId),
                    onConfigureAlert: {
                        haptic(.light)
                        showAlertConfig = true
                    },
                    stationSource: station.source,
                    latitude: station.latitude,
                    longitude: station.longitude,
                    altitude: station.altitude,
                    stationDescription: station.stationDescription,
                    pressure: station.pressure,
                    temperature: station.temperature,
                    humidity: station.humidity,
                    touchX: $touchX,
                    touchWind: $touchSampleWind,
                    touchGust: $touchSampleGust,
                    touchDir: $touchSampleDir,
                    onClose: {
                        haptic(.light)
                        isCenteringCamera = false
                        withAnimation(panelAnim) {
                            showPanel = false
                            selectedStation = nil
                        }
                    },
                    onForecastTap: {
                        haptic(.light)
                        showForecastFull = true
                    },
                    onTideTap: {
                        haptic(.light)
                        showTideDetail = true
                    }
                )
                .modifier(PanelPaddingModifier(isRegular: horizontalSizeClass == .regular))
                .transition(panelTransition)
            } else if showWavePanel, let waveBuoy = selectedWaveBuoy {
                WaveBuoyBottomPanel(
                    buoy: waveBuoy,
                    isFavorite: favoritesManager.isFavorite(buoyId: waveBuoy.id),
                    onToggleFavorite: {
                        haptic(.medium)
                        favoritesManager.toggleFavorite(buoy: waveBuoy)
                    },
                    onClose: {
                        haptic(.light)
                        isCenteringCamera = false
                        withAnimation(panelAnim) {
                            showWavePanel = false
                            selectedWaveBuoy = nil
                        }
                    }
                )
                .modifier(PanelPaddingModifier(isRegular: horizontalSizeClass == .regular))
                .transition(panelTransition)
            } else if showKitePanel, let spot = selectedKiteSpot {
                KiteSpotBottomPanel(
                    spot: spot,
                    forecast: kiteSpotForecast,
                    forecastLoading: kiteSpotForecastLoading,
                    nearbyStation: nearestStationForKiteSpot,
                    nearbyBuoy: nearestBuoyForKiteSpot,
                    tideData: currentTideData,
                    onClose: {
                        haptic(.light)
                        isCenteringCamera = false
                        withAnimation(panelAnim) {
                            showKitePanel = false
                            selectedKiteSpot = nil
                        }
                    },
                    onForecastTap: {
                        haptic(.light)
                        showForecastFull = true
                    },
                    onTideTap: {
                        haptic(.light)
                        showTideDetail = true
                    }
                )
                .modifier(PanelPaddingModifier(isRegular: horizontalSizeClass == .regular))
                .transition(panelTransition)
            } else if showSurfPanel, let spot = selectedSurfSpot {
                SurfSpotBottomPanel(
                    spot: spot,
                    nearbyBuoy: nearestBuoyForSurfSpot,
                    tideData: currentTideData,
                    onClose: {
                        haptic(.light)
                        isCenteringCamera = false
                        withAnimation(panelAnim) {
                            showSurfPanel = false
                            selectedSurfSpot = nil
                        }
                    },
                    onTideTap: {
                        haptic(.light)
                        showTideDetail = true
                    }
                )
                .modifier(PanelPaddingModifier(isRegular: horizontalSizeClass == .regular))
                .transition(panelTransition)
            } else if showParaglidingPanel, let spot = selectedParaglidingSpot {
                ParaglidingSpotBottomPanel(
                    spot: spot,
                    forecast: paraglidingSpotForecast,
                    forecastLoading: paraglidingSpotForecastLoading,
                    nearbyStation: nearestStationForParaglidingSpot,
                    nearbyWebcam: nearestWebcamForParaglidingSpot,
                    onClose: {
                        haptic(.light)
                        isCenteringCamera = false
                        withAnimation(panelAnim) {
                            showParaglidingPanel = false
                            selectedParaglidingSpot = nil
                        }
                    },
                    onForecastTap: {
                        haptic(.light)
                        showForecastFull = true
                    }
                )
                .modifier(PanelPaddingModifier(isRegular: horizontalSizeClass == .regular))
                .transition(panelTransition)
            }
    }

    // MARK: - Top: Search Pill

    private var searchPillContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Rechercher un spot ou une station", text: $searchText)
                .focused($isSearchFocused)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if isSearchFocused && !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isSearchFocused {
                Button("Annuler") {
                    searchText = ""
                    isSearchFocused = false
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Capsule())
        .modifier(LiquidGlassCapsuleModifier())
        .animation(.easeOut(duration: 0.15), value: isSearchFocused)
    }

    // MARK: - Search Results

    private func matchesSearch(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private var searchResults: [SearchResult] {
        guard searchText.count >= 2 else { return [] }
        let query = searchText
        var all: [SearchResult] = []

        for station in cachedFilteredStations where matchesSearch(station.name, query) {
            all.append(SearchResult(
                id: "station_\(station.stableId)", name: station.name,
                subtitle: "Station \(station.source.displayName)",
                type: .windStation(station), iconName: "sensor.fill", iconColor: station.source.color
            ))
            if all.count >= 20 { return all }
        }

        for spot in kiteSpots where matchesSearch(spot.name, query) {
            all.append(SearchResult(
                id: "kite_\(spot.id)", name: spot.name,
                subtitle: "Kite · \(spot.level.rawValue) · \(spot.orientation)",
                type: .kiteSpot(spot), iconName: "wind", iconColor: .orange
            ))
            if all.count >= 20 { return all }
        }

        for spot in allSurfSpots where matchesSearch(spot.name, query) {
            all.append(SearchResult(
                id: "surf_\(spot.id)", name: spot.name,
                subtitle: "Surf · \(spot.level.rawValue) · \(spot.waveType.rawValue)",
                type: .surfSpot(spot), iconName: "water.waves", iconColor: .cyan
            ))
            if all.count >= 20 { return all }
        }

        for spot in paraglidingSpots where matchesSearch(spot.name, query) {
            all.append(SearchResult(
                id: "paragliding_\(spot.id)", name: spot.name,
                subtitle: "Parapente · \(spot.type.rawValue)",
                type: .paraglidingSpot(spot), iconName: "arrow.up.right.circle.fill", iconColor: .red
            ))
            if all.count >= 20 { return all }
        }

        return all
    }

    private var searchResultsOverlay: some View {
        VStack(spacing: 0) {
            if searchResults.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("Aucun resultat")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 15, weight: .medium))
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(searchResults) { result in
                            Button {
                                selectSearchResult(result)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: result.iconName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(result.iconColor)
                                        .frame(width: 32, height: 32)
                                        .background(result.iconColor.opacity(0.15))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(result.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 350)
            }
        }
        .padding(12)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private let searchZoomSpan = MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)

    private func selectSearchResult(_ result: SearchResult) {
        searchText = ""
        isSearchFocused = false

        switch result.type {
        case .windStation(let station):
            haptic(.medium)
            stationSamples = []
            forecast = nil
            selectedStation = station
            selectedWaveBuoy = nil
            showWavePanel = false
            showPanel = true
            centerOnAnnotation(coordinate: CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude), zoomSpan: searchZoomSpan)
            loadForecast(stationId: station.stableId, stationName: station.name, latitude: station.latitude, longitude: station.longitude)
            // Load chart data
            if station.source == .windsUp {
                if timeFrame == 288 { timeFrame = 144 }
                loadWindsUpChart(stationId: station.id)
            } else if station.source == .meteoFrance {
                loadMeteoFranceChart(stationId: station.id)
            } else if station.source == .holfuy {
                loadHolfuyChart(stationId: station.stableId)
            } else if station.source == .windguru {
                loadWindguruChart(stationId: station.stableId)
            } else if station.source == .pioupiou {
                loadPioupiouChart(stationId: station.stableId)
            } else if station.source == .diabox {
                if timeFrame == 288 { timeFrame = 144 }
                loadDiaboxChart(stationId: station.stableId)
            } else if station.source == .windCornouaille {
                loadWindCornouailleChart(stationId: station.id)
            }
        case .kiteSpot(let spot):
            haptic(.medium)
            selectedKiteSpot = spot
            showKitePanel = true
            showPanel = false
            showWavePanel = false
            showSurfPanel = false
            showParaglidingPanel = false
            centerOnAnnotation(coordinate: spot.coordinate, zoomSpan: searchZoomSpan)
            loadKiteSpotForecast(spot: spot)
        case .surfSpot(let spot):
            haptic(.medium)
            selectedSurfSpot = spot
            showSurfPanel = true
            showPanel = false
            showWavePanel = false
            showKitePanel = false
            showParaglidingPanel = false
            centerOnAnnotation(coordinate: spot.coordinate, zoomSpan: searchZoomSpan)
        case .paraglidingSpot(let spot):
            haptic(.medium)
            selectedParaglidingSpot = spot
            showParaglidingPanel = true
            showPanel = false
            showWavePanel = false
            showKitePanel = false
            showSurfPanel = false
            centerOnAnnotation(coordinate: spot.coordinate, zoomSpan: searchZoomSpan)
            paraglidingSpotForecastLoading = true
            paraglidingSpotForecast = nil
            Task {
                do {
                    let data = try await ForecastService.shared.fetchForecast(
                        latitude: spot.latitude,
                        longitude: spot.longitude,
                        model: .arome
                    )
                    await MainActor.run {
                        paraglidingSpotForecast = data
                        paraglidingSpotForecastLoading = false
                    }
                } catch {
                    await MainActor.run {
                        paraglidingSpotForecastLoading = false
                    }
                }
            }
        }
    }

    // MARK: - Filter Pills Content

    private var filterPillsContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Tide widget inline
                if showTideWidget, let tideData = currentTideData {
                    TideWidget(tideData: tideData, onTap: {
                        haptic(.light)
                        showTideDetail = true
                    })
                }

                filterPill(
                    icon: "figure.sailing",
                    label: "Kite",
                    isActive: showKiteSpots,
                    activeColor: .orange,
                    action: { haptic(.light); showKiteSpots.toggle() }
                )

                filterPill(
                    icon: "surfboard.fill",
                    label: "Surf",
                    isActive: showSurfSpots,
                    activeColor: .cyan,
                    action: { haptic(.light); showSurfSpots.toggle() }
                )

                filterPill(
                    icon: "arrow.up.right.circle.fill",
                    label: "Parapente",
                    isActive: showParaglidingSpots,
                    activeColor: .red,
                    action: { haptic(.light); showParaglidingSpots.toggle() }
                )

                filterPill(
                    icon: "checkmark.seal.fill",
                    label: "Praticable",
                    isActive: showPraticableSpots,
                    activeColor: .green,
                    action: { togglePraticableSpots() },
                    isLoading: isLoadingSpotScores
                )

            }
            .padding(.horizontal, 16)
        }
    }

    private func filterPill(
        icon: String,
        label: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void,
        isLoading: Bool = false
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isActive ? activeColor : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .modifier(LiquidGlassCapsuleModifier())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Left Content

    private var bottomLeadingContent: some View {
        VStack(spacing: 10) {
            Button {
                haptic(.light)
                showMapStylePicker = true
            } label: {
                Image(systemName: mapStyle.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .modifier(LiquidGlassCircleModifier())
            }
            .buttonStyle(.plain)

            Button {
                haptic(.light)
                showUserLocation.toggle()
                if showUserLocation {
                    locationManager.requestLocation()
                    if let loc = locationManager.userLocation {
                        zoomToLocation(loc)
                    } else {
                        needsLocationZoom = true
                    }
                } else {
                    needsLocationZoom = false
                }
            } label: {
                Image(systemName: showUserLocation ? "location.fill" : "location")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(showUserLocation ? .blue : .primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .modifier(LiquidGlassCircleModifier())
            }
            .buttonStyle(.plain)

            Button {
                guard !stationManager.isLoading else { return }
                haptic(.light)
                Task {
                    let loc = locationManager.userLocation?.clCoordinate
                    await stationManager.refresh(sources: enabledSources, userLocation: loc)
                    if enabledSources.contains(.holfuy) {
                        await stationManager.refreshHolfuyDirect(userLocation: loc)
                    }
                }
            } label: {
                ZStack {
                    if stationManager.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: !networkMonitor.isConnected ? "wifi.slash" : stationManager.isUsingCache ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(!networkMonitor.isConnected ? .red : stationManager.isUsingCache ? .orange : .primary)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .modifier(LiquidGlassCircleModifier())
            }
            .buttonStyle(.plain)
            .disabled(stationManager.isLoading)
        }
    }

    // MARK: - Bottom Right Content

    private var bottomTrailingContent: some View {
        VStack(spacing: 10) {
            // Windy button
            Button {
                haptic(.light)
                toggleWindOverlay()
            } label: {
                Image(systemName: "wind")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .modifier(LiquidGlassCircleModifier())
            }
            .buttonStyle(.plain)

            // Webcams button
            if remoteConfig.enableWebcams {
                Button {
                    haptic(.light)
                    showWebcamsOnMap.toggle()
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(showWebcamsOnMap ? .cyan : .primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .modifier(LiquidGlassCircleModifier())
                }
                .buttonStyle(.plain)
            }
        }
    }



    private func stationLatest(for station: WindStation) -> WCWindObservation {
        let timestamp = station.lastUpdate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        return WCWindObservation(
            ts: timestamp,
            ws: WCWindSpeed(moy: WCScalar(station.wind), max: WCScalar(station.gust)),
            wd: WCWindDir(moy: WCScalar(station.direction))
        )
    }


    // Pre-initialized haptic generators for instant feedback
    private static let lightHaptic: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()
    private static let mediumHaptic: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        return g
    }()

    private func toggleWindOverlay() {
        // Show Windy fullscreen overlay
        showWindyFullscreen = true
        Analytics.overlayToggled(type: "wind", enabled: true)
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light:
            Self.lightHaptic.impactOccurred()
            Self.lightHaptic.prepare()
        case .medium:
            Self.mediumHaptic.impactOccurred()
            Self.mediumHaptic.prepare()
        default:
            let g = UIImpactFeedbackGenerator(style: style)
            g.impactOccurred()
        }
    }

    // MARK: - Praticable Spots

    private func togglePraticableSpots() {
        print("🔘 Toggle praticable spots: \(showPraticableSpots) -> \(!showPraticableSpots)")
        showPraticableSpots.toggle()
        if showPraticableSpots {
            haptic(.medium)
            loadPraticableSpots()
        } else {
            spotScores = [:]
        }
    }

    private func loadPraticableSpots() {
        guard !isLoadingSpotScores else { return }
        isLoadingSpotScores = true

        Task {
            // Get visible region from camera
            guard let region = camera.region else {
                await MainActor.run { isLoadingSpotScores = false }
                return
            }

            let minLat = region.center.latitude - region.span.latitudeDelta / 2
            let maxLat = region.center.latitude + region.span.latitudeDelta / 2
            let minLon = region.center.longitude - region.span.longitudeDelta / 2
            let maxLon = region.center.longitude + region.span.longitudeDelta / 2

            // Filter to visible spots only
            let visibleKiteSpots = kiteSpots.filter { spot in
                spot.latitude >= minLat && spot.latitude <= maxLat &&
                spot.longitude >= minLon && spot.longitude <= maxLon
            }
            let visibleSurfSpots = allSurfSpots.filter { spot in
                spot.latitude >= minLat && spot.latitude <= maxLat &&
                spot.longitude >= minLon && spot.longitude <= maxLon
            }

            // Filter paragliding spots to visible area
            let visibleParaglidingSpots = paraglidingSpots.filter { spot in
                spot.latitude >= minLat && spot.latitude <= maxLat &&
                spot.longitude >= minLon && spot.longitude <= maxLon
            }

            print("🎯 Loading praticable spots: \(visibleKiteSpots.count) kite, \(visibleSurfSpots.count) surf, \(visibleParaglidingSpots.count) paragliding")

            var newScores: [String: Int] = [:]

            // Use real station observations for scoring (same data as detail panels)
            let onlineStations = cachedFilteredStations.filter { $0.isOnline }

            // Evaluate kite spots using nearest wind station data
            for spot in visibleKiteSpots {
                guard let station = findNearestStation(
                    latitude: spot.latitude, longitude: spot.longitude,
                    stations: onlineStations, maxDistance: 30_000
                ) else { continue }
                let rating = KiteConditionRating.evaluate(
                    wind: station.wind,
                    gust: station.gust,
                    direction: station.direction,
                    spot: spot,
                    dangerThreshold: Double(kiteMaxWindThreshold),
                    riderLevel: KiteRiderLevel(rawValue: kiteRiderLevelRaw) ?? .intermediate
                )
                newScores[spot.id] = rating.score
            }
            print("✅ Calculated \(visibleKiteSpots.count) kite scores")

            // Evaluate paragliding spots using nearest wind station data
            for spot in visibleParaglidingSpots {
                guard let station = findNearestStation(
                    latitude: spot.latitude, longitude: spot.longitude,
                    stations: onlineStations, maxDistance: 30_000
                ) else { continue }
                let rating = ParaglidingConditionRating.evaluate(
                    wind: station.wind,
                    gust: station.gust,
                    direction: station.direction,
                    spot: spot
                )
                newScores[spot.id] = rating.score
            }
            print("✅ Calculated \(visibleParaglidingSpots.count) paragliding scores")

            // Fetch wave forecasts for surf spots (uses swell data, not wind)
            if !visibleSurfSpots.isEmpty {
                await SurfForecastService.shared.fetchForecasts(for: visibleSurfSpots)

                for spot in visibleSurfSpots {
                    if let waveForecast = SurfForecastService.shared.currentForecast(for: spot.id) {
                        let rating = evaluateSurfConditionsFromForecast(spot: spot, forecast: waveForecast, tide: nil)
                        newScores[spot.id] = rating.score
                    } else {
                        newScores[spot.id] = 0
                    }
                }
                print("✅ Calculated \(visibleSurfSpots.count) surf scores")
            }

            await MainActor.run {
                spotScores = newScores
                isLoadingSpotScores = false
                print("📍 SpotScores updated: \(spotScores.count) entries")
            }
        }
    }

    private func findNearestStation(latitude: Double, longitude: Double, stations: [WindStation], maxDistance: Double) -> WindStation? {
        let spotLocation = CLLocation(latitude: latitude, longitude: longitude)
        return stations
            .min(by: { s1, s2 in
                let loc1 = CLLocation(latitude: s1.latitude, longitude: s1.longitude)
                let loc2 = CLLocation(latitude: s2.latitude, longitude: s2.longitude)
                return spotLocation.distance(from: loc1) < spotLocation.distance(from: loc2)
            })
            .flatMap { station in
                let stationLocation = CLLocation(latitude: station.latitude, longitude: station.longitude)
                return spotLocation.distance(from: stationLocation) <= maxDistance ? station : nil
            }
    }

}


