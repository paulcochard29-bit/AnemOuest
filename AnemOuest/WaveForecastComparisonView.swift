import SwiftUI
import Charts

// MARK: - Comparison Data Point

struct WaveComparisonPoint: Identifiable {
    let id = UUID()
    let time: Date
    let forecastHeight: Double?    // meters (from Open-Meteo)
    let forecastPeriod: Double?    // seconds
    let actualHeight: Double?      // meters (from CANDHIS buoy hm0)
    let actualPeriod: Double?      // seconds (from buoy tp)

    var heightError: Double? {
        guard let forecast = forecastHeight, let actual = actualHeight else { return nil }
        return forecast - actual  // positive = over-predicted
    }

    var absHeightError: Double? {
        guard let error = heightError else { return nil }
        return abs(error)
    }

    var periodError: Double? {
        guard let forecast = forecastPeriod, let actual = actualPeriod else { return nil }
        return forecast - actual
    }
}

// MARK: - Comparison Statistics

struct WaveComparisonStats {
    let meanHeightError: Double     // MAE in meters
    let meanPeriodError: Double     // MAE in seconds
    let maxHeightError: Double
    let heightBias: Double          // positive = over-predicts
    let percentWithin03m: Double
    let percentWithin05m: Double
    let sampleCount: Int

    var qualityLabel: String {
        switch meanHeightError {
        case ..<0.2: return "Excellent"
        case ..<0.3: return "Tres bon"
        case ..<0.5: return "Bon"
        case ..<0.7: return "Correct"
        default: return "Variable"
        }
    }

    var qualityColor: Color {
        switch meanHeightError {
        case ..<0.2: return .green
        case ..<0.3: return .cyan
        case ..<0.5: return .orange
        case ..<0.7: return .orange
        default: return .red
        }
    }

    var biasDescription: String {
        if abs(heightBias) < 0.1 {
            return "Equilibre"
        } else if heightBias > 0 {
            return "Surestime +\(String(format: "%.1f", heightBias))m"
        } else {
            return "Sous-estime \(String(format: "%.1f", abs(heightBias)))m"
        }
    }
}

// MARK: - Wave Forecast Comparison View

struct WaveForecastComparisonView: View {
    let buoyName: String
    let buoyId: String
    let latitude: Double
    let longitude: Double
    var fallbackHistory: [WaveHistoryPoint] = []

    @State private var forecastData: [HourlyWave] = []
    @State private var observations: [WaveHistoryPoint] = []
    @State private var comparisonPoints: [WaveComparisonPoint] = []
    @State private var stats: WaveComparisonStats?
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Touch interaction
    @State private var selectedPoint: WaveComparisonPoint?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        loadingView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if comparisonPoints.isEmpty {
                        noDataView
                    } else {
                        if let stats = stats {
                            statsCard(stats)
                        }

                        comparisonChart

                        errorChart
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Prevision vs Reel (Vagues)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadComparisonData()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Chargement des previsions Open-Meteo Marine...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Erreur")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var noDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Donnees insuffisantes")
                .font(.headline)
            Text("Pas assez de donnees pour comparer les previsions avec les mesures du houlographe.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func statsCard(_ stats: WaveComparisonStats) -> some View {
        VStack(spacing: 16) {
            // Quality badge
            HStack {
                Text("Precision Open-Meteo Marine")
                    .font(.headline)
                Spacer()
                Text(stats.qualityLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(stats.qualityColor, in: Capsule())
            }

            Divider()

            // Main stats
            HStack(spacing: 20) {
                WaveStatBox(
                    title: "Erreur moyenne",
                    value: String(format: "%.2f", stats.meanHeightError),
                    unit: "m",
                    color: stats.qualityColor
                )

                WaveStatBox(
                    title: "Erreur max",
                    value: String(format: "%.1f", stats.maxHeightError),
                    unit: "m",
                    color: .secondary
                )

                WaveStatBox(
                    title: "Dans ±0.5m",
                    value: String(format: "%.0f", stats.percentWithin05m),
                    unit: "%",
                    color: stats.percentWithin05m >= 70 ? .green : .orange
                )
            }

            // Bias indicator
            HStack {
                Image(systemName: stats.heightBias > 0.1 ? "arrow.up.circle.fill" :
                                  stats.heightBias < -0.1 ? "arrow.down.circle.fill" : "equal.circle.fill")
                    .foregroundStyle(abs(stats.heightBias) < 0.2 ? .green : .orange)
                Text(stats.biasDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(stats.sampleCount) comparaisons")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private var comparisonChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title + Legend
            HStack {
                Text("Hauteur significative (m)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.cyan)
                            .frame(width: 16, height: 3)
                        Text("Reel")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Circle().fill(Color.orange).frame(width: 4, height: 4)
                            Circle().fill(Color.orange).frame(width: 4, height: 4)
                        }
                        Text("Open-Meteo")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Selected point tooltip
            if let point = selectedPoint {
                selectedPointTooltip(point)
            }

            Chart(content: comparisonChartContent)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine()
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            VStack(spacing: 1) {
                                Text(date, format: .dateTime.hour())
                                    .font(.system(size: 10, weight: .medium))
                                if !Calendar.current.isDateInToday(date) {
                                    Text(date, format: .dateTime.weekday(.abbreviated))
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYAxisLabel("m", position: .top, alignment: .leading)
            .chartLegend(.hidden)
            .frame(height: 220)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let xPosition = value.location.x
                                    if let date: Date = proxy.value(atX: xPosition) {
                                        selectedPoint = findClosestPoint(to: date)
                                    }
                                }
                                .onEnded { _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            selectedPoint = nil
                                        }
                                    }
                                }
                        )
                }
            }

            // Time range info
            if let first = comparisonPoints.first?.time,
               let last = comparisonPoints.last?.time {
                HStack {
                    Text(formatTimeRange(from: first, to: last))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    @ViewBuilder
    private func selectedPointTooltip(_ point: WaveComparisonPoint) -> some View {
        HStack(spacing: 16) {
            // Time
            VStack(alignment: .leading, spacing: 2) {
                Text(point.time, format: .dateTime.hour().minute())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                if !Calendar.current.isDateInToday(point.time) {
                    Text(point.time, format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .frame(height: 30)

            // Real value
            VStack(alignment: .center, spacing: 2) {
                Text("Reel")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(point.actualHeight != nil ? String(format: "%.1f", point.actualHeight!) : "—")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
            }

            // Forecast value
            VStack(alignment: .center, spacing: 2) {
                Text("Prevision")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(point.forecastHeight != nil ? String(format: "%.1f", point.forecastHeight!) : "—")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            // Error
            if let error = point.heightError {
                VStack(alignment: .center, spacing: 2) {
                    Text("Ecart")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(error >= 0 ? "+\(String(format: "%.1f", error))" : String(format: "%.1f", error))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(abs(error) <= 0.3 ? .green : abs(error) <= 0.5 ? .orange : .red)
                }
            }

            Text("m")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeOut(duration: 0.15), value: point.id)
    }

    private var errorChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ecart de prevision (prevision - reel)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Chart(content: errorChartContent)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine()
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.hour())
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [-1.0, -0.5, 0.0, 0.5, 1.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            let label = v > 0 ? "+\(String(format: "%.1f", v))" : String(format: "%.1f", v)
                            Text(label)
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .frame(height: 160)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let xPosition = value.location.x
                                    if let date: Date = proxy.value(atX: xPosition) {
                                        selectedPoint = findClosestPoint(to: date)
                                    }
                                }
                                .onEnded { _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            selectedPoint = nil
                                        }
                                    }
                                }
                        )
                }
            }

            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: 12, height: 12)
                    Text("Surestime")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: 12, height: 12)
                    Text("Sous-estime")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Zone verte = ±0.5m")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    // MARK: - Chart Content Helpers

    @ChartContentBuilder
    private func comparisonChartContent() -> some ChartContent {
        // Selected time indicator
        if let point = selectedPoint {
            RuleMark(x: .value("Selected", point.time))
                .foregroundStyle(.white.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
        }

        // Actual observation - filled area + solid line (CYAN)
        ForEach(comparisonPoints.filter { $0.actualHeight != nil }) { point in
            AreaMark(
                x: .value("Time", point.time),
                y: .value("Meters", point.actualHeight ?? 0.0)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.cyan.opacity(0.3), Color.cyan.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
        }

        ForEach(comparisonPoints.filter { $0.actualHeight != nil }) { point in
            LineMark(
                x: .value("Time", point.time),
                y: .value("Meters", point.actualHeight ?? 0.0),
                series: .value("Type", "Reel")
            )
            .foregroundStyle(.cyan)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.catmullRom)
        }

        // Forecast line - dashed orange with dots
        ForEach(comparisonPoints.filter { $0.forecastHeight != nil }) { point in
            LineMark(
                x: .value("Time", point.time),
                y: .value("Meters", point.forecastHeight ?? 0.0),
                series: .value("Type", "Open-Meteo")
            )
            .foregroundStyle(.orange)
            .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 4]))
            .interpolationMethod(.catmullRom)
        }

        ForEach(comparisonPoints.filter { $0.forecastHeight != nil }) { point in
            PointMark(
                x: .value("Time", point.time),
                y: .value("Meters", point.forecastHeight ?? 0.0)
            )
            .foregroundStyle(.orange)
            .symbolSize(20)
        }

        // Highlight selected point
        if let point = selectedPoint {
            if let actual = point.actualHeight {
                PointMark(
                    x: .value("Time", point.time),
                    y: .value("Meters", actual)
                )
                .foregroundStyle(.cyan)
                .symbolSize(80)
            }
            if let forecast = point.forecastHeight {
                PointMark(
                    x: .value("Time", point.time),
                    y: .value("Meters", forecast)
                )
                .foregroundStyle(.orange)
                .symbolSize(80)
            }
        }
    }

    @ChartContentBuilder
    private func errorChartContent() -> some ChartContent {
        // Zero line
        RuleMark(y: .value("Zero", 0.0))
            .foregroundStyle(.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))

        // +/- 0.5m bands
        RuleMark(y: .value("Plus05", 0.5))
            .foregroundStyle(.green.opacity(0.3))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .annotation(position: .trailing, alignment: .leading) {
                Text("+0.5").font(.system(size: 8)).foregroundStyle(.green)
            }
        RuleMark(y: .value("Minus05", -0.5))
            .foregroundStyle(.green.opacity(0.3))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .annotation(position: .trailing, alignment: .leading) {
                Text("-0.5").font(.system(size: 8)).foregroundStyle(.green)
            }

        // Selected time indicator
        if let point = selectedPoint {
            RuleMark(x: .value("Selected", point.time))
                .foregroundStyle(.white.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
        }

        // Error bars
        ForEach(comparisonPoints.filter { $0.heightError != nil }) { point in
            let error = point.heightError ?? 0.0
            let isSelected = selectedPoint?.id == point.id
            let barColor: Color = error > 0 ? .orange : .blue
            BarMark(
                x: .value("Time", point.time),
                y: .value("Error", error),
                width: .fixed(8)
            )
            .foregroundStyle(barColor.opacity(isSelected ? 1.0 : 0.8))
            .cornerRadius(2)
        }
    }

    // MARK: - Helpers

    private func formatTimeRange(from: Date, to: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")

        if Calendar.current.isDate(from, inSameDayAs: to) {
            formatter.dateFormat = "EEEE d MMM, HH'h' - "
            let start = formatter.string(from: from)
            formatter.dateFormat = "HH'h'"
            return start + formatter.string(from: to)
        } else {
            formatter.dateFormat = "E HH'h'"
            return "\(formatter.string(from: from)) - \(formatter.string(from: to))"
        }
    }

    private func findClosestPoint(to date: Date) -> WaveComparisonPoint? {
        comparisonPoints.min { point1, point2 in
            abs(point1.time.timeIntervalSince(date)) < abs(point2.time.timeIntervalSince(date))
        }
    }

    // MARK: - Data Loading

    private func loadComparisonData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch wave forecast with past 1 day to get historical predictions
            let waveData = try await ForecastService.shared.fetchWaves(
                latitude: latitude,
                longitude: longitude,
                pastDays: 1
            )

            await MainActor.run {
                self.forecastData = waveData.hourly
            }

            // Fetch buoy history (48h from CANDHIS API)
            let history = await WaveBuoyService.shared.fetchHistory(buoyId: buoyId)

            await MainActor.run {
                self.observations = history.isEmpty ? fallbackHistory : history
            }

            // Store forecasts for accuracy tracking
            let futureForecasts = waveData.hourly.filter { $0.time > Date() }
            if !futureForecasts.isEmpty {
                WaveForecastAccuracyService.shared.storeForecast(
                    buoyId: buoyId,
                    buoyName: buoyName,
                    latitude: latitude,
                    longitude: longitude,
                    forecasts: futureForecasts
                )
            }

            // Build comparison points
            await buildComparisonPoints()

        } catch {
            await MainActor.run {
                self.errorMessage = "Impossible de charger les previsions: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func buildComparisonPoints() async {
        guard !observations.isEmpty, !forecastData.isEmpty else {
            await MainActor.run {
                self.comparisonPoints = []
                self.stats = nil
                self.isLoading = false
            }
            return
        }

        let obsStart = observations.map { $0.timestamp }.min() ?? Date()
        let now = Date()
        var points: [WaveComparisonPoint] = []

        // For each past forecast hour, find closest buoy observation within 30 min
        for forecast in forecastData where forecast.time <= now && forecast.time >= obsStart {
            let tolerance: TimeInterval = 30 * 60
            let matching = observations.filter {
                abs($0.timestamp.timeIntervalSince(forecast.time)) <= tolerance
            }

            if let closest = matching.min(by: {
                abs($0.timestamp.timeIntervalSince(forecast.time)) <
                abs($1.timestamp.timeIntervalSince(forecast.time))
            }) {
                let point = WaveComparisonPoint(
                    time: forecast.time,
                    forecastHeight: forecast.waveHeight,
                    forecastPeriod: forecast.wavePeriod,
                    actualHeight: closest.hm0,
                    actualPeriod: closest.tp
                )
                points.append(point)
            }
        }

        points.sort { $0.time < $1.time }

        // Calculate statistics if >= 3 valid points
        let valid = points.filter { $0.heightError != nil }
        var calculatedStats: WaveComparisonStats?

        if valid.count >= 3 {
            let absErrors = valid.compactMap { $0.absHeightError }
            let rawErrors = valid.compactMap { $0.heightError }
            let periodErrors = valid.compactMap { pt -> Double? in
                guard let f = pt.forecastPeriod, let a = pt.actualPeriod else { return nil }
                return abs(f - a)
            }

            calculatedStats = WaveComparisonStats(
                meanHeightError: absErrors.reduce(0, +) / Double(absErrors.count),
                meanPeriodError: periodErrors.isEmpty ? 0 : periodErrors.reduce(0, +) / Double(periodErrors.count),
                maxHeightError: absErrors.max() ?? 0,
                heightBias: rawErrors.reduce(0, +) / Double(rawErrors.count),
                percentWithin03m: Double(absErrors.filter { $0 <= 0.3 }.count) / Double(absErrors.count) * 100,
                percentWithin05m: Double(absErrors.filter { $0 <= 0.5 }.count) / Double(absErrors.count) * 100,
                sampleCount: valid.count
            )
        }

        await MainActor.run {
            self.comparisonPoints = points
            self.stats = calculatedStats
            self.isLoading = false
        }
    }
}

// MARK: - Wave Stat Box Component

private struct WaveStatBox: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
