//
//  ForecastComparisonView.swift
//  AnemOuest
//
//  Comparison view showing AROME forecast vs actual observations
//

import SwiftUI
import Charts

// MARK: - Comparison Data Point

struct ComparisonPoint: Identifiable {
    let id = UUID()
    let time: Date
    let forecastWind: Double?      // knots
    let forecastGust: Double?      // knots
    let actualWind: Double?        // knots
    let actualGust: Double?        // knots

    var windError: Double? {
        guard let forecast = forecastWind, let actual = actualWind else { return nil }
        return forecast - actual  // positive = over-predicted, negative = under-predicted
    }

    var gustError: Double? {
        guard let forecast = forecastGust, let actual = actualGust else { return nil }
        return forecast - actual
    }

    var absWindError: Double? {
        guard let error = windError else { return nil }
        return abs(error)
    }
}

// MARK: - Comparison Statistics

struct ComparisonStats {
    let meanWindError: Double      // MAE
    let meanGustError: Double
    let maxWindError: Double
    let windBias: Double           // positive = over-predicts, negative = under-predicts
    let percentWithin3Knots: Double
    let percentWithin5Knots: Double
    let sampleCount: Int

    var qualityLabel: String {
        switch meanWindError {
        case ..<3: return "Excellent"
        case ..<4: return "Tres bon"
        case ..<5: return "Bon"
        case ..<7: return "Correct"
        default: return "Variable"
        }
    }

    var qualityColor: Color {
        switch meanWindError {
        case ..<3: return .green
        case ..<4: return .cyan
        case ..<5: return .orange
        case ..<7: return .orange
        default: return .red
        }
    }

    var biasDescription: String {
        if abs(windBias) < 1 {
            return "Equilibre"
        } else if windBias > 0 {
            return "Surestime +\(WindUnit.convertValue(windBias)) \(WindUnit.current.symbol)"
        } else {
            return "Sous-estime \(WindUnit.convertValue(abs(windBias))) \(WindUnit.current.symbol)"
        }
    }
}

// MARK: - Forecast Comparison View

struct ForecastComparisonView: View {
    let stationName: String
    let stationId: String
    let stationSource: WindSource?
    let latitude: Double
    let longitude: Double
    var fallbackObservations: [WCChartSample] = []  // Used when source doesn't support 24h fetch

    @State private var forecastData: [HourlyForecast] = []
    @State private var observations: [WCChartSample] = []
    @State private var comparisonPoints: [ComparisonPoint] = []
    @State private var stats: ComparisonStats?
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Touch interaction
    @State private var selectedPoint: ComparisonPoint?
    @State private var touchLocation: CGPoint = .zero

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
                        // Stats summary
                        if let stats = stats {
                            statsCard(stats)
                        }

                        // Comparison chart
                        comparisonChart

                        // Error distribution chart
                        errorChart
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Prevision vs Reel")
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
            Text("Chargement des previsions AROME...")
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
            Text("Pas assez de donnees pour comparer les previsions avec les observations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func statsCard(_ stats: ComparisonStats) -> some View {
        VStack(spacing: 16) {
            // Quality badge
            HStack {
                Text("Precision AROME")
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
                StatBox(
                    title: "Erreur moyenne",
                    value: String(format: "%.1f", WindUnit.current.convert(fromKnots: stats.meanWindError)),
                    unit: WindUnit.current.symbol,
                    color: stats.qualityColor
                )

                StatBox(
                    title: "Erreur max",
                    value: String(format: "%.0f", WindUnit.current.convert(fromKnots: stats.maxWindError)),
                    unit: WindUnit.current.symbol,
                    color: .secondary
                )

                StatBox(
                    title: "Dans ±\(WindUnit.convertValue(5)) \(WindUnit.current.symbol)",
                    value: String(format: "%.0f", stats.percentWithin5Knots),
                    unit: "%",
                    color: stats.percentWithin5Knots >= 70 ? .green : .orange
                )
            }

            // Bias indicator
            HStack {
                Image(systemName: stats.windBias > 1 ? "arrow.up.circle.fill" :
                                  stats.windBias < -1 ? "arrow.down.circle.fill" : "equal.circle.fill")
                    .foregroundStyle(abs(stats.windBias) < 2 ? .green : .orange)
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
                Text("Vent moyen (nds)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                // Clear legend
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
                        Text("AROME")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Selected point tooltip
            if let point = selectedPoint {
                selectedPointTooltip(point)
            }

            Chart {
                // Selected time indicator (vertical line)
                if let point = selectedPoint {
                    RuleMark(x: .value("Selected", point.time))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                }

                // Actual observation - filled area + solid line (CYAN - more visible)
                ForEach(comparisonPoints.filter { $0.actualWind != nil }) { point in
                    AreaMark(
                        x: .value("Time", point.time),
                        y: .value("Knots", point.actualWind ?? 0)
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

                ForEach(comparisonPoints.filter { $0.actualWind != nil }) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Knots", point.actualWind ?? 0),
                        series: .value("Type", "Reel")
                    )
                    .foregroundStyle(.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }

                // Forecast line - dashed orange with dots
                ForEach(comparisonPoints.filter { $0.forecastWind != nil }) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Knots", point.forecastWind ?? 0),
                        series: .value("Type", "AROME")
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .interpolationMethod(.catmullRom)
                }

                // Add points on forecast line for clarity
                ForEach(comparisonPoints.filter { $0.forecastWind != nil }) { point in
                    PointMark(
                        x: .value("Time", point.time),
                        y: .value("Knots", point.forecastWind ?? 0)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(20)
                }

                // Highlight selected point
                if let point = selectedPoint {
                    if let actual = point.actualWind {
                        PointMark(
                            x: .value("Time", point.time),
                            y: .value("Knots", actual)
                        )
                        .foregroundStyle(.cyan)
                        .symbolSize(80)
                    }
                    if let forecast = point.forecastWind {
                        PointMark(
                            x: .value("Time", point.time),
                            y: .value("Knots", forecast)
                        )
                        .foregroundStyle(.orange)
                        .symbolSize(80)
                    }
                }
            }
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
            .chartYAxisLabel(WindUnit.current.symbol, position: .top, alignment: .leading)
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
                                        // Find closest comparison point
                                        selectedPoint = findClosestPoint(to: date)
                                    }
                                }
                                .onEnded { _ in
                                    // Keep selection visible for a moment then clear
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

    private func findClosestPoint(to date: Date) -> ComparisonPoint? {
        comparisonPoints.min { point1, point2 in
            abs(point1.time.timeIntervalSince(date)) < abs(point2.time.timeIntervalSince(date))
        }
    }

    @ViewBuilder
    private func selectedPointTooltip(_ point: ComparisonPoint) -> some View {
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
                Text(point.actualWind != nil ? "\(Int(round(point.actualWind!)))" : "—")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
            }

            // Forecast value
            VStack(alignment: .center, spacing: 2) {
                Text("AROME")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(point.forecastWind != nil ? "\(Int(round(point.forecastWind!)))" : "—")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            // Error
            if let error = point.windError {
                VStack(alignment: .center, spacing: 2) {
                    Text("Ecart")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(error >= 0 ? "+\(Int(round(error)))" : "\(Int(round(error)))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(abs(error) <= 3 ? .green : abs(error) <= 5 ? .orange : .red)
                }
            }

            Text(WindUnit.current.symbol)
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

            Chart {
                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))

                // +/- 5 knots bands
                RuleMark(y: .value("Plus5", 5))
                    .foregroundStyle(.green.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("+5").font(.system(size: 8)).foregroundStyle(.green)
                    }
                RuleMark(y: .value("Minus5", -5))
                    .foregroundStyle(.green.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("-5").font(.system(size: 8)).foregroundStyle(.green)
                    }

                // Selected time indicator
                if let point = selectedPoint {
                    RuleMark(x: .value("Selected", point.time))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                }

                // Error bars
                ForEach(comparisonPoints.filter { $0.windError != nil }) { point in
                    BarMark(
                        x: .value("Time", point.time),
                        y: .value("Error", point.windError ?? 0),
                        width: .fixed(8)
                    )
                    .foregroundStyle(
                        (point.windError ?? 0) > 0 ?
                            Color.orange.opacity(selectedPoint?.id == point.id ? 1.0 : 0.8) :
                            Color.blue.opacity(selectedPoint?.id == point.id ? 1.0 : 0.8)
                    )
                    .cornerRadius(2)
                }
            }
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
                AxisMarks(position: .leading, values: [-10, -5, 0, 5, 10]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(v > 0 ? "+\(v)" : "\(v)")
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
                Text("Zone verte = ±\(WindUnit.convertValue(5)) \(WindUnit.current.symbol)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    // MARK: - Data Loading

    private func loadComparisonData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch forecast with past 1 day to get historical predictions
            let forecast = try await ForecastService.shared.fetchForecast(
                latitude: latitude,
                longitude: longitude,
                pastDays: 1
            )

            await MainActor.run {
                self.forecastData = forecast.hourly
            }

            // Fetch 24h observations based on source
            let fetchedObs = await fetch24hObservations()
            await MainActor.run {
                self.observations = fetchedObs
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

    private func fetch24hObservations() async -> [WCChartSample] {
        var samples: [WCChartSample] = []

        switch stationSource {
        case .pioupiou:
            do {
                let history = try await PioupiouVercelService.shared.fetchHistoryDirect(stationId: stationId, hours: 24)
                for obs in history {
                    samples.append(WCChartSample(id: "\(obs.timestamp.timeIntervalSince1970)_wind", t: obs.timestamp, value: obs.windSpeed, kind: .wind))
                    if obs.gustSpeed > 0 {
                        samples.append(WCChartSample(id: "\(obs.timestamp.timeIntervalSince1970)_gust", t: obs.timestamp, value: obs.gustSpeed, kind: .gust))
                    }
                }
                Log.data("ForecastComparison: Pioupiou fetched \(samples.count) samples")
            } catch {
                Log.error("ForecastComparison: Pioupiou fetch error: \(error)")
            }

        case .windsUp:
            let allObs = WindsUpService.shared.getObservations(windStationId: stationId)
            let cutoff = Date().addingTimeInterval(-24 * 3600)
            for obs in allObs where obs.timestamp >= cutoff {
                samples.append(WCChartSample(id: "\(obs.timestamp.timeIntervalSince1970)_wind", t: obs.timestamp, value: obs.windSpeed, kind: .wind))
                if let gust = obs.gustSpeed {
                    samples.append(WCChartSample(id: "\(obs.timestamp.timeIntervalSince1970)_gust", t: obs.timestamp, value: gust, kind: .gust))
                }
            }
            Log.data("ForecastComparison: WindsUp fetched \(samples.count) samples from cache")

        case .holfuy:
            do {
                let history = try await HolfuyHistoryService.shared.fetchHistory(stationId: stationId, hours: 24)
                for obs in history {
                    samples.append(WCChartSample(id: "\(obs.timestamp.timeIntervalSince1970)_wind", t: obs.timestamp, value: obs.windSpeed, kind: .wind))
                    if obs.gustSpeed > 0 {
                        samples.append(WCChartSample(id: "\(obs.timestamp.timeIntervalSince1970)_gust", t: obs.timestamp, value: obs.gustSpeed, kind: .gust))
                    }
                }
                Log.data("ForecastComparison: Holfuy fetched \(samples.count) samples")
            } catch {
                Log.error("ForecastComparison: Holfuy fetch error: \(error)")
            }

        case .meteoFrance:
            do {
                // stationId might be "meteofrance_29076001" (stableId) - extract raw ID
                let rawId = stationId.replacingOccurrences(of: "meteofrance_", with: "")
                let history = try await MeteoFranceService.shared.fetchHistoryFromVercel(stationId: rawId, hours: 24)
                for obs in history {
                    samples.append(WCChartSample(id: "\(obs.timestamp.timeIntervalSince1970)_wind", t: obs.timestamp, value: obs.windSpeed, kind: .wind))
                    if obs.windGust > 0 {
                        samples.append(WCChartSample(id: "\(obs.timestamp.timeIntervalSince1970)_gust", t: obs.timestamp, value: obs.windGust, kind: .gust))
                    }
                }
                Log.data("ForecastComparison: MeteoFrance fetched \(samples.count) samples for \(rawId)")
            } catch {
                Log.error("ForecastComparison: MeteoFrance fetch error: \(error)")
            }

        case .windCornouaille:
            // WindCornouaille uses time_frame=144 for 24h data
            do {
                let result = try await WindService.fetchChartWC(sensorId: stationId, timeFrame: 144)
                samples = result.samples
                Log.data("ForecastComparison: WindCornouaille fetched \(samples.count) samples")
            } catch {
                Log.error("ForecastComparison: WindCornouaille fetch error: \(error)")
            }

        case .windguru:
            do {
                let history = try await GoWindVercelService.shared.fetchHistory(stationId: stationId, hours: 24)
                for obs in history {
                    samples.append(WCChartSample(id: "\(obs.timestamp.timeIntervalSince1970)_wind", t: obs.timestamp, value: obs.windSpeed, kind: .wind))
                    if obs.gustSpeed > 0 {
                        samples.append(WCChartSample(id: "\(obs.timestamp.timeIntervalSince1970)_gust", t: obs.timestamp, value: obs.gustSpeed, kind: .gust))
                    }
                }
                Log.data("ForecastComparison: Windguru fetched \(samples.count) samples")
            } catch {
                Log.error("ForecastComparison: Windguru fetch error: \(error)")
            }

        default:
            // For unknown sources, use fallback observations
            Log.data("ForecastComparison: Unknown source, using fallback observations (\(fallbackObservations.count) samples)")
            samples = fallbackObservations
        }

        // If we couldn't fetch anything, use fallback
        if samples.isEmpty && !fallbackObservations.isEmpty {
            Log.data("ForecastComparison: Fetch returned empty, using fallback (\(fallbackObservations.count) samples)")
            samples = fallbackObservations
        }

        return samples.sorted { $0.t < $1.t }
    }

    private func buildComparisonPoints() async {
        // Get wind observations from samples
        let windObs = observations.filter { $0.kind == .wind }

        guard !windObs.isEmpty, !forecastData.isEmpty else {
            await MainActor.run {
                self.comparisonPoints = []
                self.stats = nil
                self.isLoading = false
            }
            return
        }

        // Find time range overlap
        let obsStart = windObs.map(\.t).min() ?? Date()
        let obsEnd = windObs.map(\.t).max() ?? Date()

        var points: [ComparisonPoint] = []

        // For each forecast hour that has passed (is in the past)
        let now = Date()
        for forecast in forecastData where forecast.time <= now && forecast.time >= obsStart {
            // Find closest observation within 30 minutes
            let tolerance: TimeInterval = 30 * 60
            let matchingObs = windObs.filter {
                abs($0.t.timeIntervalSince(forecast.time)) <= tolerance
            }

            if let closestObs = matchingObs.min(by: {
                abs($0.t.timeIntervalSince(forecast.time)) < abs($1.t.timeIntervalSince(forecast.time))
            }) {
                // Also find gust observation
                let gustObs = observations.filter { $0.kind == .gust }
                let matchingGust = gustObs.first {
                    abs($0.t.timeIntervalSince(forecast.time)) <= tolerance
                }

                let point = ComparisonPoint(
                    time: forecast.time,
                    forecastWind: forecast.windSpeedKnots,
                    forecastGust: forecast.gustsKnots,
                    actualWind: closestObs.value,
                    actualGust: matchingGust?.value
                )
                points.append(point)
            }
        }

        // Sort by time
        points.sort { $0.time < $1.time }

        // Calculate statistics
        let validPoints = points.filter { $0.windError != nil }
        var calculatedStats: ComparisonStats?

        if validPoints.count >= 3 {
            let windErrors = validPoints.compactMap { $0.absWindError }
            let gustErrors = validPoints.compactMap { pt -> Double? in
                guard let fe = pt.forecastGust, let ae = pt.actualGust else { return nil }
                return abs(fe - ae)
            }
            let rawWindErrors = validPoints.compactMap { $0.windError }

            let meanWindError = windErrors.reduce(0, +) / Double(windErrors.count)
            let meanGustError = gustErrors.isEmpty ? 0 : gustErrors.reduce(0, +) / Double(gustErrors.count)
            let maxWindError = windErrors.max() ?? 0
            let windBias = rawWindErrors.reduce(0, +) / Double(rawWindErrors.count)

            let within3 = windErrors.filter { $0 <= 3 }.count
            let within5 = windErrors.filter { $0 <= 5 }.count

            calculatedStats = ComparisonStats(
                meanWindError: meanWindError,
                meanGustError: meanGustError,
                maxWindError: maxWindError,
                windBias: windBias,
                percentWithin3Knots: Double(within3) / Double(windErrors.count) * 100,
                percentWithin5Knots: Double(within5) / Double(windErrors.count) * 100,
                sampleCount: validPoints.count
            )
        }

        await MainActor.run {
            self.comparisonPoints = points
            self.stats = calculatedStats
            self.isLoading = false
        }
    }
}

// MARK: - Stat Box Component

private struct StatBox: View {
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

// MARK: - Preview

#Preview {
    ForecastComparisonView(
        stationName: "La Torche",
        stationId: "pioupiou_123",
        stationSource: .pioupiou,
        latitude: 47.8525,
        longitude: -4.34792,
        fallbackObservations: []
    )
}
