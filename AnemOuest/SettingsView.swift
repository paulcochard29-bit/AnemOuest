import SwiftUI

struct SettingsView: View {

    @Binding var refreshInterval: TimeInterval
    @ObservedObject private var notificationManager = NotificationManager.shared
    @ObservedObject private var stationManager = WindStationManager.shared
    @State private var showWidgetSettings = false
    @State private var showDebug = false
    @State private var debugTapCount = 0
    @State private var serverStatus: [ServerSourceStatus] = []
    @State private var isLoadingServerStatus = false

    // Source WindCornouaille
    @AppStorage("source_windcornouaille") var sourceWindCornouaille: Bool = true

    // Direct API sources
    @AppStorage("source_ffvl") var sourceFFVL: Bool = false
    @AppStorage("source_pioupiou") var sourcePioupiou: Bool = true

    // GoWind sources (Holfuy & Windguru)
    @AppStorage("source_holfuy") var sourceHolfuy: Bool = true
    @AppStorage("source_windguru") var sourceWindguru: Bool = true

    // WindsUp (requires paid subscription)
    @AppStorage("source_windsup") var sourceWindsUp: Bool = false
    @State private var showWindsUpLogin = false
    @State private var isWindsUpLoggedIn = false
    @State private var showWindsUpInfo = false

    // Météo France (official API)
    @AppStorage("source_meteofrance") var sourceMeteoFrance: Bool = true

    // Diabox
    @AppStorage("source_diabox") var sourceDiabox: Bool = true

    // Netatmo
    @AppStorage("source_netatmo") var sourceNetatmo: Bool = false

    // NDBC
    @AppStorage("source_ndbc") var sourceNDBC: Bool = true

    // Kite spots
    @AppStorage("showKiteSpots") var showKiteSpots: Bool = true
    @AppStorage("kiteMaxWindThreshold") var kiteMaxWindThreshold: Int = 40
    @AppStorage("kiteRiderLevel") var kiteRiderLevelRaw: String = KiteRiderLevel.intermediate.rawValue

    // Surf spots
    @AppStorage("showSurfSpots") var showSurfSpots: Bool = true

    // Paragliding spots
    @AppStorage("showParaglidingSpots") var showParaglidingSpots: Bool = true

    // Tide widget
    @AppStorage("showTideWidget") var showTideWidget: Bool = true

    // Wind unit
    @AppStorage("windUnit") var windUnitRaw: String = WindUnit.knots.rawValue

    private var windUnit: WindUnit {
        get { WindUnit(rawValue: windUnitRaw) ?? .knots }
        set { windUnitRaw = newValue.rawValue }
    }

    let intervals: [(String, TimeInterval)] = [
        ("30 secondes", 30),
        ("1 minute", 60),
        ("2 minutes", 120),
        ("5 minutes", 300)
    ]

    private var enabledSourcesCount: Int {
        [sourceWindCornouaille, sourceFFVL, sourcePioupiou, sourceHolfuy, sourceWindguru, sourceWindsUp, sourceMeteoFrance, sourceDiabox, sourceNetatmo, sourceNDBC].filter { $0 }.count
    }

    var body: some View {
        NavigationStack {
            List {
                widgetsSection
                notificationsSection
                sourcesSection
                mapSection
                unitsSection
                refreshSection
                cacheSection
                if showDebug {
                    debugSection
                }
            }
            .navigationTitle("Reglages")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showWindsUpLogin) {
                WindsUpLoginView()
            }
            .alert("WindsUp", isPresented: $showWindsUpInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Un abonnement payant WindsUp est nécessaire pour accéder aux données de leurs stations.")
            }
            .sheet(isPresented: $showWidgetSettings) {
                WidgetSettingsView()
            }
            .onAppear {
                isWindsUpLoggedIn = WindsUpService.shared.checkAuthCookies()
            }
            .onChange(of: showWindsUpLogin) { _, isShowing in
                if !isShowing {
                    isWindsUpLoggedIn = WindsUpService.shared.checkAuthCookies()
                }
            }
        }
    }

    // MARK: - Sections

    private var widgetsSection: some View {
        Section {
            Button {
                showWidgetSettings = true
            } label: {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)

                        Image(systemName: "square.text.square")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Configurer les widgets")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)

                        Text("Personnaliser l'affichage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Widgets")
        } footer: {
            Text("Choisissez les spots et personnalisez l'apparence des widgets")
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $notificationManager.quietHoursEnabled) {
                HStack(spacing: 10) {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(.purple)
                        .frame(width: 20)
                    Text("Mode silencieux")
                }
            }
            .hapticOnChange(of: notificationManager.quietHoursEnabled)

            if notificationManager.quietHoursEnabled {
                HStack {
                    Text("De")
                    Spacer()
                    Picker("", selection: $notificationManager.quietHoursStart) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text("\(hour)h").tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }

                HStack {
                    Text("A")
                    Spacer()
                    Picker("", selection: $notificationManager.quietHoursEnd) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text("\(hour)h").tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            if notificationManager.quietHoursEnabled {
                Text("Pas de notifications de \(notificationManager.quietHoursStart)h a \(notificationManager.quietHoursEnd)h")
            } else {
                Text("Configurez une alerte sur vos favoris pour etre notifie")
            }
        }
    }

    private var sourcesSection: some View {
        Section {
            SourceToggle(name: "Wind France", count: "19", isOn: $sourceWindCornouaille, color: .blue)
            SourceToggle(name: "Pioupiou", count: "~800", isOn: $sourcePioupiou, color: .orange)
            SourceToggle(name: "Holfuy", count: "~1100", isOn: $sourceHolfuy, color: .green)
            SourceToggle(name: "Windguru", count: "~1800", isOn: $sourceWindguru, color: .purple)
            SourceToggle(name: "Météo France", count: "~74", isOn: $sourceMeteoFrance, color: .blue)
            SourceToggle(name: "Diabox", count: "~9", isOn: $sourceDiabox, color: .teal)
            SourceToggle(name: "Netatmo", count: "~500+", isOn: $sourceNetatmo, color: .pink)
            SourceToggle(name: "NDBC", count: "1", isOn: $sourceNDBC, color: .indigo)
            SourceToggle(name: "WindsUp", count: "~150", isOn: $sourceWindsUp, color: .cyan)

            if sourceWindsUp {
                Button {
                    showWindsUpLogin = true
                } label: {
                    HStack {
                        Image(systemName: isWindsUpLoggedIn ? "checkmark.circle.fill" : "person.circle")
                            .foregroundStyle(isWindsUpLoggedIn ? .green : .blue)
                        Text(isWindsUpLoggedIn ? "Connecté" : "Se connecter à WindsUp")

                        if !isWindsUpLoggedIn {
                            Button {
                                showWindsUpInfo = true
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()
                        if !isWindsUpLoggedIn {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundColor(isWindsUpLoggedIn ? .primary : .blue)
            }
        } header: {
            Text("Sources")
        } footer: {
            if sourceWindsUp && !isWindsUpLoggedIn {
                Text("Compte WindsUp payant requis")
            }
            Text("\(enabledSourcesCount) source(s) activée(s)")
        }
    }

    private var mapSection: some View {
        Section {
            Toggle(isOn: $showKiteSpots) {
                Label("Spots de Kite", systemImage: "wind")
            }
            .hapticOnChange(of: showKiteSpots)

            if showKiteSpots {
                HStack {
                    Text("Niveau rider")
                    Spacer()
                    Picker("", selection: $kiteRiderLevelRaw) {
                        ForEach(KiteRiderLevel.allCases, id: \.rawValue) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Seuil vent fort")
                    Spacer()
                    Picker("", selection: $kiteMaxWindThreshold) {
                        ForEach([25, 30, 35, 40, 45, 50, 55, 60], id: \.self) { val in
                            Text("\(val) \(windUnit.symbol)").tag(val)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Toggle(isOn: $showSurfSpots) {
                Label("Spots de Surf", systemImage: "figure.surfing")
            }
            .hapticOnChange(of: showSurfSpots)

            Toggle(isOn: $showParaglidingSpots) {
                Label("Spots de Parapente", systemImage: "arrow.up.circle.fill")
            }
            .hapticOnChange(of: showParaglidingSpots)

            Toggle(isOn: $showTideWidget) {
                Label("Marees", systemImage: "water.waves.and.arrow.up")
            }
            .hapticOnChange(of: showTideWidget)
        } header: {
            Text("Carte")
        }
    }

    private var unitsSection: some View {
        Section {
            HStack {
                Label("Unité de vent", systemImage: "wind")
                Spacer()
                Picker("", selection: $windUnitRaw) {
                    ForEach(WindUnit.allCases, id: \.rawValue) { unit in
                        Text(unit.rawValue).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: windUnitRaw) { _, newValue in
                    HapticManager.shared.selection()
                    WindUnit.syncToAppGroup()
                    Analytics.settingChanged(key: "windUnit", value: newValue)
                }
            }
        } header: {
            Text("Unités")
        } footer: {
            Text("Affecte l'affichage dans l'app et les widgets")
        }
    }

    private var refreshSection: some View {
        Section("Actualisation") {
            ForEach(intervals, id: \.1) { label, value in
                HStack {
                    Text(label)
                    Spacer()
                    if refreshInterval == value {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticManager.shared.selection()
                    refreshInterval = value
                    UserDefaults.standard.set(true, forKey: "user_customized_refresh")
                    Analytics.settingChanged(key: "refreshInterval", value: "\(Int(value))s")
                }
            }
        }
        .onAppear {
            // Clamp old values (5s, 10s, 20s) to minimum 30s
            if refreshInterval < 30 {
                refreshInterval = 30
            }
        }
    }

    private var cacheSection: some View {
        Section {
            CacheStatusRow(icon: "sensor.fill", label: "Stations", age: CacheManager.shared.cacheAge)
            CacheStatusRow(icon: "cloud.sun.fill", label: "Prévisions", age: forecastCacheAge())
            CacheStatusRow(icon: "water.waves", label: "Bouées", age: waveBuoyCacheAge())
            CacheStatusRow(icon: "video.fill", label: "Webcams", age: webcamCacheAge())

            HStack {
                Label("Taille totale", systemImage: "internaldrive")
                Spacer()
                Text(cacheSizeFormatted())
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                clearAllCaches()
                HapticManager.shared.warning()
            } label: {
                Label("Vider le cache", systemImage: "trash")
            }
        } header: {
            Text("Cache")
                .onTapGesture {
                    debugTapCount += 1
                    if debugTapCount >= 5 {
                        withAnimation {
                            showDebug.toggle()
                        }
                        debugTapCount = 0
                        HapticManager.shared.selection()
                    }
                }
        } footer: {
            if !NetworkMonitor.shared.isConnected {
                Text("Vous êtes hors ligne. Les données affichées proviennent du cache.")
            } else {
                Text("Les données sont mises en cache pour un accès hors ligne")
            }
        }
    }

    // MARK: - Cache Helpers

    private func forecastCacheAge() -> String? {
        let entries = OfflineCache.shared.allEntries()
        guard let forecastEntry = entries.first(where: { $0.key.hasPrefix("forecast_") }) else { return nil }
        return formatAge(forecastEntry.age)
    }

    private func waveBuoyCacheAge() -> String? {
        OfflineCache.shared.cacheAge(forKey: OfflineCache.waveBuoyKey())
    }

    private func webcamCacheAge() -> String? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let webcamDir = cacheDir.appendingPathComponent("WebcamImages_v2")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: webcamDir.path),
              let modDate = attrs[.modificationDate] as? Date else { return nil }
        return formatAge(Date().timeIntervalSince(modDate))
    }

    private func formatAge(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "< 1 min" }
        if seconds < 3600 { return "il y a \(Int(seconds / 60)) min" }
        if seconds < 86400 { return "il y a \(Int(seconds / 3600))h" }
        return "il y a \(Int(seconds / 86400))j"
    }

    private func cacheSizeFormatted() -> String {
        let fm = FileManager.default
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        var totalSize: Int64 = 0

        // OfflineData
        totalSize += OfflineCache.shared.totalSize()

        // Direct cache files
        for name in ["stations.json", "observations.json"] {
            let url = cacheDir.appendingPathComponent(name)
            totalSize += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }

        // Webcam cache
        let webcamDir = cacheDir.appendingPathComponent("WebcamImages_v2")
        if let files = try? fm.contentsOfDirectory(at: webcamDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files {
                totalSize += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }

        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    private func clearAllCaches() {
        CacheManager.shared.clearCache()
        OfflineCache.shared.clearAll()
    }

    // MARK: - Debug Section

    @ViewBuilder
    private var debugSection: some View {
        Section {
            // Last refresh info
            if let lastRefresh = stationManager.lastRefreshDate {
                HStack {
                    Label("Dernier refresh", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(lastRefresh, style: .relative)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(stationManager.lastRefreshDurationMs)ms")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Statut global
            HStack {
                Label("Statut", systemImage: stationManager.isUsingCache ? "arrow.triangle.2.circlepath" : "antenna.radiowaves.left.and.right")
                Spacer()
                Text(stationManager.isUsingCache ? "Cache (fallback)" : "Temps réel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(stationManager.isUsingCache ? .orange : .green)
            }

            // Per-source details
            ForEach(stationManager.sourceDebugInfos.filter { $0.source != .ffvl }.sorted(by: { $0.source.rawValue < $1.source.rawValue }), id: \.source.rawValue) { info in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(debugStatusColor(info.status))
                            .frame(width: 8, height: 8)

                        Text(info.source.rawValue)
                            .font(.system(size: 13, weight: .medium))

                        Spacer()

                        if info.status == .disabled {
                            Text("désactivé")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        } else {
                            HStack(spacing: 6) {
                                Text("\(info.stationCount)")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.primary)

                                Text(debugStatusLabel(info.status))
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(debugStatusColor(info.status).opacity(0.15))
                                    .foregroundStyle(debugStatusColor(info.status))
                                    .cornerRadius(4)

                                Text("\(info.durationMs)ms")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    if let endpoint = info.apiEndpoint {
                        Text(endpoint)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 16)
                    }
                }
            }

            // Network status
            HStack {
                Label("Réseau", systemImage: NetworkMonitor.shared.isConnected ? "wifi" : "wifi.slash")
                Spacer()
                Text(NetworkMonitor.shared.isConnected ? "Connecté" : "Hors ligne")
                    .font(.system(size: 13))
                    .foregroundStyle(NetworkMonitor.shared.isConnected ? .green : .red)
            }
        } header: {
            Text("Debug — Client")
        }

        // Server-side API status (separate section)
        Section {
            if isLoadingServerStatus {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Chargement statut serveur...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } else if serverStatus.isEmpty {
                Button {
                    fetchServerStatus()
                } label: {
                    Label("Charger statut serveur", systemImage: "server.rack")
                }
                if let error = serverStatusError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            } else {
                ForEach(serverStatus, id: \.key) { source in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(serverStatusColor(source.status))
                                .frame(width: 8, height: 8)
                            Text(source.label)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            if let count = source.count {
                                Text("\(count)")
                                    .font(.system(size: 13, design: .monospaced))
                            }
                            Text(source.cached ? "cache" : "fresh")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(source.cached ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
                                .foregroundStyle(source.cached ? .orange : .green)
                                .cornerRadius(4)
                            Text("\(source.durationMs)ms")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        HStack(spacing: 4) {
                            Text(source.endpoint)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            if let error = source.serverError ?? source.error {
                                Text("· \(error)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.leading, 16)
                    }
                }

                Button {
                    fetchServerStatus()
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                        .font(.system(size: 13))
                }
            }
        } header: {
            Text("Debug — Serveur Vercel")
        } footer: {
            Text("Ping les API Vercel en temps réel pour vérifier leur état.")
        }
    }

    private func debugStatusColor(_ status: WindStationManager.SourceDebugInfo.SourceStatus) -> Color {
        switch status {
        case .fresh: .green
        case .fallback: .orange
        case .failed: .red
        case .disabled: .gray
        }
    }

    private func debugStatusLabel(_ status: WindStationManager.SourceDebugInfo.SourceStatus) -> String {
        switch status {
        case .fresh: "fresh"
        case .fallback: "cache"
        case .failed: "erreur"
        case .disabled: "off"
        }
    }

    private func serverStatusColor(_ status: String) -> Color {
        switch status {
        case "ok": .green
        case "degraded": .orange
        case "error": .red
        default: .gray
        }
    }

    // MARK: - Server Status Fetch

    @State private var serverStatusError: String?

    private func fetchServerStatus() {
        isLoadingServerStatus = true
        serverStatusError = nil
        Task {
            do {
                guard let url = URL(string: "\(AppConstants.API.anemOuestAPI)/admin/status") else {
                    await MainActor.run { isLoadingServerStatus = false; serverStatusError = "URL invalide" }
                    return
                }
                let request = AppConstants.apiRequest(url: url)
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    await MainActor.run {
                        serverStatusError = "HTTP \(httpResponse.statusCode)"
                        isLoadingServerStatus = false
                    }
                    return
                }
                let decoded = try JSONDecoder().decode(ServerStatusResponse.self, from: data)
                await MainActor.run {
                    serverStatus = decoded.sources
                    isLoadingServerStatus = false
                }
            } catch {
                await MainActor.run {
                    serverStatusError = error.localizedDescription
                    isLoadingServerStatus = false
                }
            }
        }
    }
}

// MARK: - Server Status Models

struct ServerSourceStatus: Decodable {
    let key: String
    let label: String
    let endpoint: String
    let status: String
    let count: Int?
    let cached: Bool
    let stale: Bool?
    let durationMs: Int
    let serverTimestamp: String?
    let serverError: String?
    let error: String?
    let httpStatus: Int?

    enum CodingKeys: String, CodingKey {
        case key, label, endpoint, status, count, cached, stale, durationMs, serverTimestamp, serverError, error, httpStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decode(String.self, forKey: .label)
        endpoint = try c.decode(String.self, forKey: .endpoint)
        status = try c.decode(String.self, forKey: .status)
        count = try c.decodeIfPresent(Int.self, forKey: .count)
        cached = (try? c.decode(Bool.self, forKey: .cached)) ?? false
        stale = try c.decodeIfPresent(Bool.self, forKey: .stale)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        serverTimestamp = try c.decodeIfPresent(String.self, forKey: .serverTimestamp)
        serverError = try c.decodeIfPresent(String.self, forKey: .serverError)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        httpStatus = try c.decodeIfPresent(Int.self, forKey: .httpStatus)
    }
}

private struct ServerStatusResponse: Decodable {
    let sources: [ServerSourceStatus]
    let timestamp: String
}

// MARK: - Cache Status Row

private struct CacheStatusRow: View {
    let icon: String
    let label: String
    let age: String?

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            if let age {
                Text(age)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.orange)
            } else {
                Text("Pas de cache")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SourceToggle: View {
    let name: String
    let count: String
    @Binding var isOn: Bool
    let color: Color

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)

                Text(name)

                Text(count)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: isOn) { _, newValue in
            HapticManager.shared.toggle()
            Analytics.sourceToggled(source: name, enabled: newValue)
            UserDefaults.standard.set(true, forKey: "user_customized_sources")
        }
    }
}

// MARK: - Haptic Toggle Modifier

private struct HapticToggleModifier<V: Equatable>: ViewModifier {
    let value: V

    func body(content: Content) -> some View {
        content
            .onChange(of: value) { _, _ in
                HapticManager.shared.toggle()
            }
    }
}

extension View {
    func hapticOnChange<V: Equatable>(of value: V) -> some View {
        modifier(HapticToggleModifier(value: value))
    }
}
