import SwiftUI
import Charts

// MARK: - Wind Station Bottom Panel

struct BottomPanel: View {
    let sensorName: String
    let sourceName: String?
    let sourceColor: Color?
    let latest: WCWindObservation?
    let samples: [WCChartSample]
    @Binding var timeFrame: Int
    let lastUpdatedAt: Date?
    let measurementDate: Date?
    let hadError: Bool

    // Chart loading
    let chartLoading: Bool

    // Station data refreshing
    var isRefreshing: Bool = false

    // Limit time picker options for sources with limited history
    var limitedHistory: Bool = false

    // Forecast
    let forecast: ForecastData?
    let forecastLoading: Bool

    // Tides
    let tideData: TideData?

    // Panel tab selection: 0 = forecast, 1 = tides
    @State private var selectedTab: Int = 0
    @State private var isExpanded: Bool = false

    // Share sheet
    @State private var showShareSheet: Bool = false

    // Forecast comparison sheet
    @State private var showForecastComparison: Bool = false

    // Favorites
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    // Alerts
    let stationId: String
    let hasWindAlert: Bool
    let onConfigureAlert: () -> Void

    // Source for fetching 24h history in comparison view
    var stationSource: WindSource? = nil

    // Location for accuracy lookup
    let latitude: Double
    let longitude: Double

    // Station metadata (optional)
    var altitude: Int? = nil
    var stationDescription: String? = nil
    var pressure: Double? = nil
    var temperature: Double? = nil
    var humidity: Double? = nil

    @Binding var touchX: Date?
    @Binding var touchWind: Double?
    @Binding var touchGust: Double?
    @Binding var touchDir: Double?

    let onClose: () -> Void
    let onForecastTap: () -> Void
    let onTideTap: () -> Void

    private var hasMetadata: Bool {
        altitude != nil || pressure != nil || temperature != nil || humidity != nil
    }

    /// True when the source doesn't provide gust data (gust == wind)
    private var noGustData: Bool {
        guard let w = latest?.ws.moy.value, let g = latest?.ws.max.value else { return false }
        return stationSource == .ndbc && w == g
    }

    private var measurementAgo: String? {
        guard let date = measurementDate else { return nil }
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "il y a \(seconds)s"
        } else if seconds < 3600 {
            let mins = seconds / 60
            return "il y a \(mins) min"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            let mins = (seconds % 3600) / 60
            return mins > 0 ? "il y a \(hours)h\(mins)" : "il y a \(hours)h"
        } else {
            let days = seconds / 86400
            return "il y a \(days)j"
        }
    }

    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 12) {

            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 4)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(sensorName)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.secondary)
                        }
                    }

                    HStack(spacing: 4) {
                        if let source = sourceName {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(sourceColor ?? .secondary)
                                    .frame(width: 8, height: 8)
                                Text(source)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let ago = measurementAgo {
                            Text("• \(ago)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }

                        // Forecast accuracy badge (show mean error in knots) - tap to compare
                        if let meanError = ForecastAccuracyService.shared.getMeanError(latitude: latitude, longitude: longitude) {
                            Button {
                                showForecastComparison = true
                            } label: {
                                AccuracyBadge(meanError: meanError)
                            }
                            .buttonStyle(.plain)
                        } else if !samples.isEmpty {
                            // Show comparison button even without accuracy data
                            Button {
                                showForecastComparison = true
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("Comparer")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                // Share button
                Button(action: { showShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)

                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isFavorite ? .yellow : .primary)
                }
                .buttonStyle(.plain)

                if isFavorite {
                    Button(action: onConfigureAlert) {
                        Image(systemName: hasWindAlert ? "bell.fill" : "bell")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(hasWindAlert ? .orange : .primary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                StatCard(title: "Vent", value: statWind, icon: "wind", accentColor: statWindColor)
                if !noGustData {
                    StatCard(title: "Rafales", value: statGust, icon: "wind", accentColor: statGustColor)
                }
                WindDirectionCard(title: "Direction", value: statDir, direction: latest?.wd.moy.value)
            }

            // Station metadata row (if available)
            if hasMetadata {
                HStack(spacing: 12) {
                    if let alt = altitude {
                        MetadataChip(icon: "mountain.2.fill", value: "\(alt)m", label: "Alt")
                    }
                    if let press = pressure {
                        MetadataChip(icon: "gauge.with.dots.needle.33percent", value: "\(Int(press))", label: "hPa")
                    }
                    if let temp = temperature {
                        MetadataChip(icon: "thermometer.medium", value: String(format: "%.1f°", temp), label: "Temp")
                    }
                    if let hum = humidity {
                        MetadataChip(icon: "humidity.fill", value: "\(Int(hum))%", label: "Hum")
                    }
                }
            }

            // Time picker always visible (limited options for WindsUp)
            if limitedHistory {
                Text("2 h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if stationSource == .ndbc {
                // NDBC data is hourly — ~25h available, skip 2h (too few points)
                Picker("Période", selection: $timeFrame) {
                    Text("6 h").tag(36)
                    Text("24 h").tag(144)
                }
                .pickerStyle(.segmented)
                .onAppear {
                    if timeFrame == 60 || timeFrame == 288 { timeFrame = 144 }
                }
            } else {
                Picker("Période", selection: $timeFrame) {
                    Text("2 h").tag(60)
                    Text("6 h").tag(36)
                    Text("24 h").tag(144)
                    if stationSource != .diabox && stationSource != .windsUp {
                        Text("48 h").tag(288)
                    }
                }
                .pickerStyle(.segmented)
            }

            if chartLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Chargement du graphique...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
            } else if !samples.isEmpty {
                WindChartWithTooltip(
                    samples: samples,
                    touchX: $touchX,
                    touchWind: $touchWind,
                    touchGust: $touchGust,
                    touchDir: $touchDir
                )
                .frame(height: 220)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("Historique non disponible")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Cette source ne fournit pas de donnees historiques")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
            }

            // Forecast & Tides segmented section
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(0..<2) { index in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selectedTab == index && isExpanded {
                                    isExpanded = false
                                } else {
                                    selectedTab = index
                                    isExpanded = true
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: index == 0 ? "cloud.sun.fill" : "water.waves")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(index == 0 ? "Prévisions" : "Marées")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(selectedTab == index && isExpanded ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                selectedTab == index && isExpanded
                                    ? (index == 0 ? Color.orange : Color.cyan)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 10))

                if isExpanded {
                    if selectedTab == 0 {
                        ForecastStrip(
                            forecasts: forecast?.hourly ?? [],
                            isLoading: forecastLoading
                        )
                        .onTapGesture {
                            onForecastTap()
                        }
                    } else if let tide = tideData {
                        TideChartStrip(tideData: tide)
                            .onTapGesture {
                                onTideTap()
                            }
                    }
                }
            }

            HStack(spacing: 10) {
                Text(hadError ? "Certaines balises ne répondent pas" : measureText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                StatusPill(isOnline: isOnline)
            }
        }
        .padding(16)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 22))
        .shadow(radius: 14)
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if value.translation.height < -threshold {
                            isExpanded = true
                        } else if value.translation.height > threshold {
                            if isExpanded {
                                isExpanded = false
                            } else {
                                onClose()
                            }
                        }
                    }
                }
        )
        .sheet(isPresented: $showShareSheet) {
            ShareWindSheet(
                stationName: sensorName,
                wind: latest?.ws.moy.value,
                gust: latest?.ws.max.value,
                direction: latest?.wd.moy.value,
                samples: samples,
                sensorId: stationId,
                stationSource: stationSource
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showForecastComparison) {
            ForecastComparisonView(
                stationName: sensorName,
                stationId: stationId,
                stationSource: stationSource,
                latitude: latitude,
                longitude: longitude,
                fallbackObservations: samples
            )
        }
    }

    private var stationDate: Date? {
        guard let ts = latest?.ts else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(Int(ts)))
    }

    private var isOnline: Bool {
        guard let d = stationDate else { return false }
        // NDBC data is hourly — use 3h threshold instead of 20min
        let threshold: TimeInterval = stationSource == .ndbc ? 3 * 3600 : 20 * 60
        return Date().timeIntervalSince(d) <= threshold
    }

    private var measureText: String {
        guard let d = stationDate else { return "Mesure —" }
        let s = Int(Date().timeIntervalSince(d))
        if s < 0 { return "Mesure —" }
        if s < 60 { return "Mesure il y a \(s)s" }
        if s < 3600 { return "Mesure il y a \(s/60)m" }
        return "Mesure il y a \(s/3600)h"
    }

    private var statWind: String {
        guard let w = latest?.ws.moy.value else { return "—" }
        return WindUnit.format(w)
    }

    private var statWindColor: Color {
        guard let w = latest?.ws.moy.value else { return .secondary }
        return windScale(w)
    }

    private var statGust: String {
        guard let g = latest?.ws.max.value else { return "—" }
        return WindUnit.format(g)
    }

    private var statGustColor: Color {
        guard let g = latest?.ws.max.value else { return .secondary }
        return windScale(g)
    }

    private var statDir: String {
        guard let d = latest?.wd.moy.value else { return "—" }
        return "\(Int(round(d)))° \(cardinal(from: d))"
    }

    private func cardinal(from deg: Double) -> String {
        let dirs = ["N","NE","E","SE","S","SW","W","NW"]
        let idx = Int((deg + 22.5) / 45.0) & 7
        return dirs[idx]
    }

    private func updateTouchValues(for date: Date) {
        let wind = samples.filter { $0.kind == .wind }
        let gust = samples.filter { $0.kind == .gust }

        touchWind = nearestValue(in: wind, to: date)
        touchGust = nearestValue(in: gust, to: date)

        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.35)
    }

    private func nearestValue(in arr: [WCChartSample], to date: Date) -> Double? {
        guard !arr.isEmpty else { return nil }
        var best: WCChartSample = arr[0]
        var bestDist = abs(arr[0].t.timeIntervalSince(date))
        for s in arr {
            let d = abs(s.t.timeIntervalSince(date))
            if d < bestDist {
                bestDist = d
                best = s
            }
        }
        return best.value
    }
}

// MARK: - Wind Direction Card

struct WindDirectionCard: View {
    let title: String
    let value: String
    let direction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "location.north")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .rotationEffect(.degrees((direction ?? 0) + 180))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }
}
