import SwiftUI
import Combine

// MARK: - App Tab Enum

enum AppTab: Hashable {
    case map
    case favorites
    case forecast
    case fishing
    case settings
}

// MARK: - Main Tab View

struct MainTabView: View {
    @State private var selectedTab: AppTab = .map
    @State private var isShowingSplash = true
    @StateObject private var appState = AppState()
    @StateObject private var remoteConfig = RemoteConfigService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var stationManager = WindStationManager.shared

    // Global refresh timer — runs regardless of which tab is active
    @AppStorage("refreshIntervalSeconds") private var refreshIntervalSeconds: Double = 30
    @State private var globalRefreshTick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            tabViewContent
                .environmentObject(appState)
                .environmentObject(remoteConfig)

            // Offline banner
            if !networkMonitor.isConnected {
                offlineBanner
                    .zIndex(49)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Maintenance mode overlay
            if remoteConfig.maintenanceMode {
                maintenanceBanner
                    .zIndex(50)
            }

            // Splash screen overlay
            if isShowingSplash {
                SplashScreenView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .onAppear {
            // Hide splash after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.4)) {
                    isShowingSplash = false
                }
            }
            // Fetch remote config on launch
            Task {
                await remoteConfig.fetchConfig()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLinkReceived)) { notification in
            guard let url = notification.object as? URL,
                  url.scheme == "anemouest",
                  url.host == "station",
                  let stationId = url.pathComponents.dropFirst().first,
                  !stationId.isEmpty else { return }
            appState.showStationOnMap(stationId: stationId)
        }
        .onChange(of: selectedTab) { _, newTab in
            let tabName: String
            switch newTab {
            case .map: tabName = "map"
            case .favorites: tabName = "favorites"
            case .forecast: tabName = "forecast"
            case .fishing: tabName = "fishing"
            case .settings: tabName = "settings"
            }
            Analytics.tabChanged(tabName)
        }
        .onChange(of: appState.shouldNavigateToMap) { _, shouldNavigate in
            if shouldNavigate {
                // Save pending navigation before clearing
                let pendingStation = appState.selectedStationId
                let pendingKiteSpot = appState.selectedKiteSpotId
                let pendingSurfSpot = appState.selectedSurfSpotId
                let pendingWaveBuoy = appState.selectedWaveBuoyId

                // Clear state and switch tab
                appState.clearNavigationState()
                appState.shouldNavigateToMap = false
                selectedTab = .map

                // Re-trigger navigation after tab switch completes
                // so ContentView's .onChange handlers fire reliably
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                    if let id = pendingStation {
                        appState.selectedStationId = id
                    } else if let id = pendingKiteSpot {
                        appState.selectedKiteSpotId = id
                    } else if let id = pendingSurfSpot {
                        appState.selectedSurfSpotId = id
                    } else if let id = pendingWaveBuoy {
                        appState.selectedWaveBuoyId = id
                    }
                }
            }
        }
        .onChange(of: appState.shouldNavigateToForecast) { _, shouldNavigate in
            if shouldNavigate {
                selectedTab = .forecast
                appState.clearForecastNavigation()
            }
        }
        .onReceive(globalRefreshTick) { _ in
            globalRefreshIfNeeded()
        }
        .onChange(of: refreshIntervalSeconds) { _, _ in
            globalRefreshTick.upstream.connect().cancel()
            globalRefreshTick = Timer.publish(every: refreshIntervalSeconds, on: .main, in: .common).autoconnect()
        }
    }

    /// Refresh stations from any tab — ContentView's own timer handles map-specific updates
    private func globalRefreshIfNeeded() {
        // Only do background refresh when NOT on the map tab
        // (ContentView handles its own refresh when visible)
        guard selectedTab != .map else { return }
        guard !stationManager.isLoading else { return }

        Task {
            let sources = readEnabledSources()
            await stationManager.refresh(sources: sources)
        }
    }

    private func readEnabledSources() -> Set<WindSource> {
        let defaults = UserDefaults.standard
        var sources = Set<WindSource>()
        if defaults.bool(forKey: "source_windcornouaille") { sources.insert(.windCornouaille) }
        if defaults.bool(forKey: "source_ffvl") { sources.insert(.ffvl) }
        if defaults.bool(forKey: "source_pioupiou") { sources.insert(.pioupiou) }
        if defaults.bool(forKey: "source_holfuy") { sources.insert(.holfuy) }
        if defaults.bool(forKey: "source_windguru") { sources.insert(.windguru) }
        if defaults.bool(forKey: "source_windsup") { sources.insert(.windsUp) }
        if defaults.bool(forKey: "source_meteofrance") { sources.insert(.meteoFrance) }
        if defaults.bool(forKey: "source_diabox") { sources.insert(.diabox) }
        if defaults.bool(forKey: "source_netatmo") { sources.insert(.netatmo) }
        if defaults.bool(forKey: "source_ndbc") { sources.insert(.ndbc) }
        return sources
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.red)
                Text("Mode hors ligne")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                if let age = CacheManager.shared.cacheAge {
                    Text("· cache \(age)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .padding(.top, 60)

            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: networkMonitor.isConnected)
    }

    // MARK: - Maintenance Banner

    private var maintenanceBanner: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.orange)
                Text(remoteConfig.maintenanceMessage.isEmpty
                     ? "Application en maintenance"
                     : remoteConfig.maintenanceMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .padding(.top, 60)

            Spacer()
        }
    }

    @ViewBuilder
    private var tabViewContent: some View {
        if #available(iOS 26, *), UIDevice.current.userInterfaceIdiom == .phone {
            modernTabView
        } else {
            legacyTabView
        }
    }

    // MARK: - iOS 26+ Liquid Glass TabView

    @available(iOS 26, *)
    private var modernTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Carte", systemImage: "map.fill", value: .map) {
                ContentView()
            }

            Tab("Favoris", systemImage: "heart.fill", value: .favorites) {
                FavoritesTabView()
            }

            if remoteConfig.enableForecasts {
                Tab("Prévisions", systemImage: "cloud.sun.fill", value: .forecast) {
                    ForecastTabView()
                }
            }

            if remoteConfig.enableFishing {
                Tab("Pêche", systemImage: "fish.fill", value: .fishing) {
                    FishingView()
                }
            }

            Tab("Réglages", systemImage: "gearshape.fill", value: .settings) {
                SettingsTabView()
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    // MARK: - iOS 18-25 Legacy TabView

    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Label("Carte", systemImage: "map.fill")
                }
                .tag(AppTab.map)

            FavoritesTabView()
                .tabItem {
                    Label("Favoris", systemImage: "heart.fill")
                }
                .tag(AppTab.favorites)

            if remoteConfig.enableForecasts {
                ForecastTabView()
                    .tabItem {
                        Label("Prévisions", systemImage: "cloud.sun.fill")
                    }
                    .tag(AppTab.forecast)
            }

            if remoteConfig.enableFishing {
                FishingView()
                    .tabItem {
                        Label("Pêche", systemImage: "fish.fill")
                    }
                    .tag(AppTab.fishing)
            }

            SettingsTabView()
                .tabItem {
                    Label("Réglages", systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
        }
    }
}

// MARK: - Settings Tab Wrapper

struct SettingsTabView: View {
    @AppStorage("refreshIntervalSeconds") private var refreshIntervalSeconds: Double = 30

    var body: some View {
        SettingsView(refreshInterval: $refreshIntervalSeconds)
    }
}

#Preview {
    MainTabView()
}
