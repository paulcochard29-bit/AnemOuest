import SwiftUI
import Charts

// MARK: - Compact Forecast Strip (for BottomPanel)

struct ForecastStrip: View {
    let forecasts: [HourlyForecast]
    let isLoading: Bool

    private var next12Hours: [HourlyForecast] {
        let now = Date()
        return forecasts
            .filter { $0.time >= now }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Prévisions AROME")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    // Indicator for tappable action
                    HStack(spacing: 4) {
                        Text("Voir détails")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.blue)
                }
            }

            if next12Hours.isEmpty && !isLoading {
                Text("Aucune prévision disponible")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(next12Hours) { forecast in
                            ForecastHourCell(forecast: forecast)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 14))
    }
}

// MARK: - Single Hour Cell

private struct ForecastHourCell: View {
    let forecast: HourlyForecast

    private var hourString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH'h'"
        return formatter.string(from: forecast.time)
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(hourString)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Image(systemName: forecast.weatherIcon)
                .font(.system(size: 14))
                .symbolRenderingMode(.multicolor)
                .frame(height: 16)

            Image(systemName: "arrow.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.8))
                .rotationEffect(.degrees(forecast.windDirection + 180))

            Text("\(Int(round(forecast.windSpeedKnots)))")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(windColor(forecast.windSpeedKnots))

            Text("\(Int(round(forecast.gustsKnots)))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(windColor(forecast.gustsKnots))
        }
        .frame(width: 44)
    }

    private func windColor(_ knots: Double) -> Color {
        windScale(knots)
    }
}

// MARK: - Full Forecast View (Windy-style)

struct ForecastFullView: View {
    let stationName: String
    let latitude: Double
    let longitude: Double
    let onClose: () -> Void
    var showCloseButton: Bool = true

    @State private var selectedModel: WeatherModel = .arome
    @State private var forecasts: [WeatherModel: ForecastData] = [:]
    @State private var waveData: WaveData?
    @State private var isLoading = true
    @State private var selectedTab: ForecastTab = .wind

    // Touch interaction
    @State private var selectedHour: HourlyForecast?
    @State private var selectedWave: HourlyWave?

    // Timers for auto-dismiss selection (cancellable)
    @State private var windSelectionTask: Task<Void, Never>?
    @State private var waveSelectionTask: Task<Void, Never>?

    // Hour interval (1h or 2h)
    @State private var hourInterval: Int = 2

    // Scroll tracking for day indicator
    @State private var visibleWindDay: Date = Date()
    @State private var visibleWaveDay: Date = Date()


    enum ForecastTab: String, CaseIterable {
        case wind = "Vent"
        case waves = "Vagues"
        case daily = "Jours"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Model selector
                modelSelector

                // Content tabs
                tabSelector

                // Main content
                ScrollView {
                    if isLoading {
                        loadingView
                    } else {
                        switch selectedTab {
                        case .wind:
                            windContent
                        case .waves:
                            wavesContent
                        case .daily:
                            dailyContent
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(stationName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showCloseButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task(id: "\(latitude),\(longitude)") {
            await loadAllData()
        }
    }

    // MARK: - Model Selector

    private var modelSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WeatherModel.allCases) { model in
                    ModelPill(
                        model: model,
                        isSelected: selectedModel == model,
                        isLoaded: forecasts[model] != nil
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedModel = model
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 0))
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 8) {
            ForEach(ForecastTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tabIcon(tab))
                            .font(.system(size: 14, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor : Color.clear, in: Capsule())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 0))
    }

    private func tabIcon(_ tab: ForecastTab) -> String {
        switch tab {
        case .wind: return "wind"
        case .waves: return "water.waves"
        case .daily: return "calendar"
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Chargement des modèles...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: - Wind Content

    private var windContent: some View {
        VStack(spacing: 16) {
            if let forecast = forecasts[selectedModel] {
                // Model info
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedModel.displayName)
                            .font(.headline)
                        Text(selectedModel.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(selectedModel.forecastDays) jours")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.2), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Wind chart
                windChart(forecast.hourly)

                // Hourly cards + grid
                HourlyForecastSection(
                    forecasts: filterByInterval(forecast.hourly.filter { $0.time >= Date() }),
                    intervalToggle: intervalToggle,
                    selectedHour: $selectedHour,
                    onTapHour: { hour in
                        selectedHour = hour
                        // Cancel previous timer and start a new one
                        windSelectionTask?.cancel()
                        windSelectionTask = Task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    selectedHour = nil
                                }
                            }
                        }
                    }
                )
            } else {
                Text("Données non disponibles pour \(selectedModel.displayName)")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 40)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Wind Chart

    private func windChart(_ hourly: [HourlyForecast]) -> some View {
        let futureData = Array(hourly.filter { $0.time >= Date() })
        let totalDays = max(1, futureData.count / 24)
        let chartWidth = max(UIScreen.main.bounds.width - 32, CGFloat(totalDays) * 400)
        let maxGust = futureData.map { $0.gustsKnots }.max() ?? 40
        let yMax = ceil(maxGust / 10) * 10 + 5

        let midnights = Set(futureData.compactMap { hour -> Date? in
            Calendar.current.component(.hour, from: hour.time) == 0 ? hour.time : nil
        })

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Évolution du vent")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
                Spacer()
                Text(frenchFullDay(visibleWindDay))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.2), in: Capsule())
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 16)

            if let hour = selectedHour {
                windTooltip(hour)
                    .padding(.horizontal, 16)
            }

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .leading) {
                        // Invisible anchor points for scroll synchronization
                        HStack(spacing: 0) {
                            ForEach(futureData) { hour in
                                Color.clear
                                    .frame(width: chartWidth / CGFloat(max(1, futureData.count)), height: 1)
                                    .id(hour.id)
                            }
                        }
                        .frame(height: 1)

                        Chart {
                            ForEach(Array(midnights), id: \.self) { midnight in
                                RuleMark(x: .value("Midnight", midnight))
                                    .foregroundStyle(.blue.opacity(0.3))
                                    .lineStyle(StrokeStyle(lineWidth: 1))
                            }

                            if let hour = selectedHour {
                                RuleMark(x: .value("Selected", hour.time))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                            }

                            ForEach(futureData) { hour in
                                AreaMark(
                                    x: .value("Time", hour.time),
                                    yStart: .value("Wind", hour.windSpeedKnots),
                                    yEnd: .value("Gust", hour.gustsKnots)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange.opacity(0.3), .orange.opacity(0.1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)

                                LineMark(
                                    x: .value("Time", hour.time),
                                    y: .value("Gusts", hour.gustsKnots),
                                    series: .value("Type", "Rafales")
                                )
                                .foregroundStyle(.orange)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                                .interpolationMethod(.catmullRom)

                                LineMark(
                                    x: .value("Time", hour.time),
                                    y: .value("Wind", hour.windSpeedKnots),
                                    series: .value("Type", "Moyen")
                                )
                                .foregroundStyle(.cyan)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                                .interpolationMethod(.catmullRom)
                            }

                            if let hour = selectedHour {
                                PointMark(x: .value("Time", hour.time), y: .value("Wind", hour.windSpeedKnots))
                                    .foregroundStyle(.cyan)
                                    .symbolSize(100)
                                PointMark(x: .value("Time", hour.time), y: .value("Gust", hour.gustsKnots))
                                    .foregroundStyle(.orange)
                                    .symbolSize(80)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                                if let date = value.as(Date.self) {
                                    let hour = Calendar.current.component(.hour, from: date)
                                    AxisGridLine()
                                    AxisValueLabel {
                                        VStack(spacing: 1) {
                                            Text(date, format: .dateTime.hour())
                                                .font(.system(size: 10))
                                            if hour == 0 {
                                                Text(frenchWeekday(date))
                                                    .font(.system(size: 9, weight: .medium))
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .stride(by: 10)) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(Int(v))")
                                            .font(.system(size: 9))
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: 0...yMax)
                        .chartLegend(.hidden)
                        .frame(width: chartWidth, height: 180)
                        .drawingGroup()
                        .chartOverlay { proxy in
                            GeometryReader { _ in
                                Rectangle()
                                    .fill(.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { location in
                                        if let date: Date = proxy.value(atX: location.x) {
                                            selectedHour = findClosestHour(to: date, in: futureData)
                                            windSelectionTask?.cancel()
                                            windSelectionTask = Task {
                                                try? await Task.sleep(nanoseconds: 4_000_000_000)
                                                guard !Task.isCancelled else { return }
                                                await MainActor.run {
                                                    withAnimation(.easeOut(duration: 0.3)) {
                                                        selectedHour = nil
                                                    }
                                                }
                                            }
                                        }
                                    }
                            }
                        }
                    }
                    .frame(width: chartWidth, height: 180)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    if let first = futureData.first {
                                        visibleWindDay = first.time
                                    }
                                }
                                .onChange(of: geo.frame(in: .named("windScroll")).minX) { _, newValue in
                                    let scrollOffset = -newValue
                                    let pointsPerHour = chartWidth / CGFloat(max(1, futureData.count))
                                    let hourIndex = min(max(0, Int(scrollOffset / pointsPerHour)), futureData.count - 1)
                                    if hourIndex < futureData.count {
                                        let newDay = futureData[hourIndex].time
                                        if !Calendar.current.isDate(newDay, inSameDayAs: visibleWindDay) {
                                            visibleWindDay = newDay
                                        }
                                    }
                                }
                        }
                    )
                }
                .coordinateSpace(name: "windScroll")
                .onChange(of: selectedHour?.id) { _, newId in
                    if let id = newId {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func windTooltip(_ hour: HourlyForecast) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(frenchWeekday(hour.time))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(hour.time, format: .dateTime.hour().minute())
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }

            Divider().frame(height: 36)

            VStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(hour.windDirection + 180))
                HStack(spacing: 4) {
                    Text("\(WindUnit.convertValue(hour.windSpeedKnots))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                    Text("/")
                        .foregroundStyle(.secondary)
                    Text("\(WindUnit.convertValue(hour.gustsKnots))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                }
                Text(WindUnit.current.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Divider().frame(height: 36)

            VStack(spacing: 2) {
                Image(systemName: hour.weatherIcon)
                    .font(.system(size: 20))
                    .symbolRenderingMode(.multicolor)
                Text("\(Int(round(hour.temperature)))°")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }

    private func findClosestHour(to date: Date, in data: [HourlyForecast]) -> HourlyForecast? {
        data.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
    }

    // MARK: - Interval Toggle

    private var intervalToggle: some View {
        HStack(spacing: 0) {
            ForEach([1, 2, 6], id: \.self) { interval in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hourInterval = interval
                    }
                } label: {
                    Text("\(interval)h")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hourInterval == interval ? .white : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(hourInterval == interval ? Color.accentColor : Color.clear)
                }
            }
        }
        .background(.secondary.opacity(0.2))
        .clipShape(Capsule())
    }

    private func filterByInterval(_ data: [HourlyForecast]) -> [HourlyForecast] {
        guard hourInterval > 1 else { return Array(data) }
        return data.enumerated().compactMap { index, item in
            let hour = Calendar.current.component(.hour, from: item.time)
            return hour % hourInterval == 0 ? item : nil
        }
    }

    private func filterWavesByInterval(_ data: [HourlyWave]) -> [HourlyWave] {
        guard hourInterval > 1 else { return Array(data) }
        return data.enumerated().compactMap { index, item in
            let hour = Calendar.current.component(.hour, from: item.time)
            return hour % hourInterval == 0 ? item : nil
        }
    }

    // MARK: - Waves Content

    private var wavesContent: some View {
        VStack(spacing: 16) {
            if let waves = waveData {
                // Wave chart
                waveChart(waves.hourly)

                // Wave info
                WaveCardsSection(
                    waves: filterWavesByInterval(waves.hourly.filter { $0.time >= Date() }),
                    selectedWave: $selectedWave,
                    intervalToggle: intervalToggle,
                    onTapWave: { wave in
                        selectedWave = wave
                        // Cancel previous timer and start a new one
                        waveSelectionTask?.cancel()
                        waveSelectionTask = Task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    selectedWave = nil
                                }
                            }
                        }
                    }
                )

                // Swell details
                if let currentWave = waves.hourly.first(where: { $0.time >= Date() }) {
                    swellDetailsCard(currentWave)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Données vagues non disponibles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Les prévisions marines ne sont disponibles que pour les zones côtières")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 60)
                .padding(.horizontal, 40)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Wave Chart

    private func waveChart(_ hourly: [HourlyWave]) -> some View {
        let futureData = Array(hourly.filter { $0.time >= Date() })
        let totalDays = max(1, futureData.count / 24)
        let chartWidth = max(UIScreen.main.bounds.width - 32, CGFloat(totalDays) * 400)
        let maxHeight = futureData.map { $0.waveHeight }.max() ?? 3
        let yMax = ceil(maxHeight) + 0.5

        // Get midnight dates for day separators
        let midnights = Set(futureData.compactMap { wave -> Date? in
            let cal = Calendar.current
            if cal.component(.hour, from: wave.time) == 0 {
                return wave.time
            }
            return nil
        })

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Hauteur des vagues")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
                Spacer()
                Text(frenchFullDay(visibleWaveDay))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.2), in: Capsule())
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 16)

            // Selected wave tooltip
            if let wave = selectedWave {
                waveTooltip(wave)
                    .padding(.horizontal, 16)
            }

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .leading) {
                        // Invisible anchor points for scroll synchronization
                        HStack(spacing: 0) {
                            ForEach(futureData) { wave in
                                Color.clear
                                    .frame(width: chartWidth / CGFloat(max(1, futureData.count)), height: 1)
                                    .id(wave.id)
                            }
                        }
                        .frame(height: 1)

                        Chart {
                            ForEach(Array(midnights), id: \.self) { midnight in
                                RuleMark(x: .value("Midnight", midnight))
                                    .foregroundStyle(.blue.opacity(0.3))
                                    .lineStyle(StrokeStyle(lineWidth: 1))
                            }

                            if let wave = selectedWave {
                                RuleMark(x: .value("Selected", wave.time))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                            }

                            ForEach(futureData) { wave in
                                AreaMark(
                                    x: .value("Time", wave.time),
                                    y: .value("Height", wave.waveHeight)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.4), .blue.opacity(0.1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)

                                LineMark(
                                    x: .value("Time", wave.time),
                                    y: .value("Height", wave.waveHeight)
                                )
                                .foregroundStyle(.blue)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                                .interpolationMethod(.catmullRom)
                            }

                            if let wave = selectedWave {
                                PointMark(x: .value("Time", wave.time), y: .value("Height", wave.waveHeight))
                                    .foregroundStyle(.blue)
                                    .symbolSize(100)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                                if let date = value.as(Date.self) {
                                    let hour = Calendar.current.component(.hour, from: date)
                                    AxisGridLine()
                                    AxisValueLabel {
                                        VStack(spacing: 1) {
                                            Text(date, format: .dateTime.hour())
                                                .font(.system(size: 10))
                                            if hour == 0 {
                                                Text(frenchWeekday(date))
                                                    .font(.system(size: 9, weight: .medium))
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .stride(by: 1)) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(Int(v))")
                                            .font(.system(size: 9))
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: 0...yMax)
                        .frame(width: chartWidth, height: 160)
                        .drawingGroup()
                        .chartOverlay { proxy in
                            GeometryReader { _ in
                                Rectangle()
                                    .fill(.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { location in
                                        if let date: Date = proxy.value(atX: location.x) {
                                            selectedWave = findClosestWave(to: date, in: futureData)
                                            waveSelectionTask?.cancel()
                                            waveSelectionTask = Task {
                                                try? await Task.sleep(nanoseconds: 4_000_000_000)
                                                guard !Task.isCancelled else { return }
                                                await MainActor.run {
                                                    withAnimation(.easeOut(duration: 0.3)) {
                                                        selectedWave = nil
                                                    }
                                                }
                                            }
                                        }
                                    }
                            }
                        }
                    }
                    .frame(width: chartWidth, height: 160)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    if let first = futureData.first {
                                        visibleWaveDay = first.time
                                    }
                                }
                                .onChange(of: geo.frame(in: .named("waveScroll")).minX) { _, newValue in
                                    let scrollOffset = -newValue
                                    let pointsPerHour = chartWidth / CGFloat(max(1, futureData.count))
                                    let hourIndex = min(max(0, Int(scrollOffset / pointsPerHour)), futureData.count - 1)
                                    if hourIndex < futureData.count {
                                        let newDay = futureData[hourIndex].time
                                        if !Calendar.current.isDate(newDay, inSameDayAs: visibleWaveDay) {
                                            visibleWaveDay = newDay
                                        }
                                    }
                                }
                        }
                    )
                }
                .coordinateSpace(name: "waveScroll")
                .onChange(of: selectedWave?.id) { _, newId in
                    if let id = newId {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func findClosestWave(to date: Date, in data: [HourlyWave]) -> HourlyWave? {
        data.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
    }

    @ViewBuilder
    private func waveTooltip(_ wave: HourlyWave) -> some View {
        HStack(spacing: 16) {
            // Date/Time
            VStack(alignment: .leading, spacing: 2) {
                Text(frenchWeekday(wave.time))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(wave.time, format: .dateTime.hour().minute())
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }

            Divider().frame(height: 36)

            // Total wave
            VStack(spacing: 2) {
                Image(systemName: "water.waves")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
                Text(String(format: "%.1fm", wave.waveHeight))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("\(Int(wave.wavePeriod))s")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Direction
            VStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .rotationEffect(.degrees(wave.waveDirection + 180))
                Text(directionLabel(wave.waveDirection))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Swell (if available)
            if let swellH = wave.swellHeight, swellH > 0.1 {
                Divider().frame(height: 36)
                VStack(spacing: 2) {
                    Text("Houle")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%.1fm", swellH))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                    Text("\(Int(wave.swellPeriod ?? 0))s")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Wind waves (if available)
            if let windH = wave.windWaveHeight, windH > 0.1 {
                VStack(spacing: 2) {
                    Text("Clapot")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%.1fm", windH))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Text("\(Int(wave.windWavePeriod ?? 0))s")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }

    private func directionLabel(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(round(degrees / 45.0)) % 8
        return directions[index]
    }

    private func frenchWeekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func frenchFullDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMM"
        return formatter.string(from: date).capitalized
    }

    // MARK: - Swell Details Card

    private func swellDetailsCard(_ wave: HourlyWave) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text("Détails houle")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.primary)

            HStack(spacing: 20) {
                // Total waves
                VStack(spacing: 4) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                    Text(String(format: "%.1fm", wave.waveHeight))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("\(Int(wave.wavePeriod))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Total")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)

                // Swell
                if let swellH = wave.swellHeight, swellH > 0 {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .rotationEffect(.degrees((wave.swellDirection ?? 0) + 180))
                        Text(String(format: "%.1fm", swellH))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("\(Int(wave.swellPeriod ?? 0))s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Houle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Wind waves
                if let windH = wave.windWaveHeight, windH > 0 {
                    VStack(spacing: 4) {
                        Image(systemName: "wind")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(String(format: "%.1fm", windH))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("\(Int(wave.windWavePeriod ?? 0))s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Clapot")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - Daily Content

    private var dailyContent: some View {
        VStack(spacing: 12) {
            if let forecast = forecasts[selectedModel] {
                ForEach(forecast.daily) { day in
                    DayForecastRow(forecast: day)
                }
            } else {
                Text("Données non disponibles")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 40)
            }
        }
        .padding(16)
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        // Reset state before loading new data
        await MainActor.run {
            isLoading = true
            forecasts = [:]
            waveData = nil
            selectedHour = nil
            selectedWave = nil
        }

        // Load all models in parallel
        async let allForecasts = ForecastService.shared.fetchAllModels(latitude: latitude, longitude: longitude)
        async let waves = try? ForecastService.shared.fetchWaves(latitude: latitude, longitude: longitude)

        let (fetchedForecasts, fetchedWaves) = await (allForecasts, waves)

        await MainActor.run {
            self.forecasts = fetchedForecasts
            self.waveData = fetchedWaves
            self.isLoading = false
        }
    }
}

// MARK: - Model Pill

private struct ModelPill: View {
    let model: WeatherModel
    let isSelected: Bool
    let isLoaded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isLoaded ? modelColor : .gray)
                    .frame(width: 8, height: 8)

                Text(model.displayName)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? modelColor.opacity(0.2) : Color.clear, in: Capsule())
            .overlay(
                Capsule().strokeBorder(isSelected ? modelColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var modelColor: Color {
        switch model {
        case .arome: return .blue
        case .ecmwf: return .purple
        case .gfs: return .green
        case .icon: return .orange
        }
    }
}

// MARK: - Hourly Forecast Section (simple, independent scroll)

private struct HourlyForecastSection<Toggle: View>: View {
    let forecasts: [HourlyForecast]
    let intervalToggle: Toggle
    @Binding var selectedHour: HourlyForecast?
    var onTapHour: ((HourlyForecast) -> Void)?

    private let rowHeight: CGFloat = 18
    private let cardWidth: CGFloat = 48
    private let cardSpacing: CGFloat = 8

    // Find the closest forecast to the selected hour (for when interval is 2h)
    private var selectedForecastId: UUID? {
        guard let selected = selectedHour else { return nil }
        // Find the closest forecast in our filtered list
        return forecasts.min(by: {
            abs($0.time.timeIntervalSince(selected.time)) < abs($1.time.timeIntervalSince(selected.time))
        })?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Prévisions horaires")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
                Spacer()
                intervalToggle
            }
            .padding(.horizontal, 16)

            HStack(alignment: .top, spacing: 0) {
                // Fixed labels - aligned with card rows
                VStack(alignment: .leading, spacing: 0) {
                    // Card section labels (matching WindHourCardCompact heights)
                    VStack(alignment: .leading, spacing: 2) {
                        labelRowFixed(label: "Jour", color: .blue, height: 12)
                        labelRowFixed(icon: "clock", label: "Heure", color: .primary, height: 14)
                        labelRowFixed(icon: "cloud.sun.fill", label: "Météo", color: .orange, height: 18)
                        labelRowFixed(icon: "location.north", label: "Dir.", color: .primary, height: 14)
                        labelRowFixed(icon: "wind", label: "Vent", color: .cyan, height: 16)
                        labelRowFixed(icon: "wind", label: "Raf.", color: .orange, height: 12)
                        labelRowFixed(icon: "thermometer.medium", label: "Temp.", color: .secondary, height: 14)
                    }
                    .padding(.vertical, 6)
                    .padding(.leading, 4)

                    Divider().padding(.horizontal, 4)

                    // Data rows section
                    VStack(alignment: .leading, spacing: 0) {
                        labelRow(icon: "humidity.fill", label: "Humid.", color: .cyan)
                        labelRow(icon: "cloud.fill", label: "Nuages", color: .secondary)
                        labelRow(icon: "chevron.up", label: "Hauts", color: .indigo)
                        labelRow(icon: "minus", label: "Moyens", color: .blue)
                        labelRow(icon: "chevron.down", label: "Bas", color: .gray)
                        labelRow(icon: "drop.fill", label: "Pluie", color: .blue)
                        labelRow(icon: "eye", label: "Visib.", color: .secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.leading, 4)
                }
                .frame(width: 72)
                .background(
                    .ultraThinMaterial,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 12,
                        bottomLeadingRadius: 12,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )

                // Scrollable cards + grid
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: cardSpacing) {
                                ForEach(forecasts) { hour in
                                    WindHourCardCompact(
                                        forecast: hour,
                                        isSelected: hour.id == selectedForecastId
                                    )
                                    .id(hour.id)
                                    .onTapGesture {
                                        onTapHour?(hour)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)

                            VStack(alignment: .leading, spacing: 0) {
                                dataRow { "\($0.humidity)%" }
                                dataRow { "\($0.cloudCover)%" }
                                dataRow { "\($0.cloudCoverHigh)" }
                                dataRow { "\($0.cloudCoverMid)" }
                                dataRow { "\($0.cloudCoverLow)" }
                                dataRow { $0.precipitation > 0 ? String(format: "%.1f", $0.precipitation) : "-" }
                                dataRow { formatVisibility($0.visibility) }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                        }
                        .padding(.trailing, 12)
                    }
                    .onChange(of: selectedForecastId) { _, newId in
                        if let id = newId {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.vertical, 12)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func formatVisibility(_ meters: Double) -> String {
        meters >= 10000 ? ">10" : String(format: "%.0f", meters / 1000)
    }

    private func labelRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(height: rowHeight)
    }

    private func labelRowFixed(icon: String? = nil, label: String, color: Color, height: CGFloat) -> some View {
        HStack(spacing: 3) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(icon == nil ? color : .secondary)
        }
        .frame(height: height)
    }

    private func dataRow(value: @escaping (HourlyForecast) -> String) -> some View {
        HStack(spacing: cardSpacing) {
            ForEach(forecasts) { forecast in
                Text(value(forecast))
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: cardWidth)
            }
        }
        .frame(height: rowHeight)
    }
}

// MARK: - Wind Hour Card Compact

private struct WindHourCardCompact: View {
    let forecast: HourlyForecast
    var isSelected: Bool = false

    private var hourString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH'h'"
        return formatter.string(from: forecast.time)
    }

    private var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: forecast.time)
    }

    private var isNewDay: Bool {
        Calendar.current.component(.hour, from: forecast.time) == 0
    }

    private var borderColor: Color {
        if isSelected {
            return .cyan
        } else if isNewDay {
            return .blue.opacity(0.3)
        } else {
            return .white.opacity(0.08)
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            // Day label (only at midnight)
            Text(isNewDay ? dayString.uppercased() : " ")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.blue)
                .frame(height: 12)

            // Hour
            Text(hourString)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(height: 14)

            // Weather icon
            Image(systemName: forecast.weatherIcon)
                .font(.system(size: 14))
                .symbolRenderingMode(.multicolor)
                .frame(height: 18)

            // Wind direction
            Image(systemName: "arrow.up")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(forecast.windDirection + 180))
                .frame(height: 14)

            // Wind speed
            Text("\(Int(round(forecast.windSpeedKnots)))")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(windScale(forecast.windSpeedKnots))
                .frame(height: 16)

            // Gusts
            Text("\(Int(round(forecast.gustsKnots)))")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(windScale(forecast.gustsKnots))
                .frame(height: 12)

            // Temperature
            Text("\(Int(round(forecast.temperature)))°")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(height: 14)
        }
        .frame(width: 48)
        .padding(.vertical, 6)
        .background(
            isSelected ? Color.cyan.opacity(0.2) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 0.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Wave Hour Card

// MARK: - Wave Cards Section

private struct WaveCardsSection<Toggle: View>: View {
    let waves: [HourlyWave]
    @Binding var selectedWave: HourlyWave?
    let intervalToggle: Toggle
    var onTapWave: ((HourlyWave) -> Void)?

    private var selectedWaveId: UUID? {
        guard let selected = selectedWave else { return nil }
        return waves.min(by: {
            abs($0.time.timeIntervalSince(selected.time)) < abs($1.time.timeIntervalSince(selected.time))
        })?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Prévisions vagues")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
                Spacer()
                intervalToggle
            }
            .padding(.horizontal, 16)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(waves) { wave in
                            WaveHourCard(wave: wave, isSelected: wave.id == selectedWaveId)
                                .id(wave.id)
                                .onTapGesture {
                                    onTapWave?(wave)
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .onChange(of: selectedWaveId) { _, newId in
                    if let id = newId {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
}

private struct WaveHourCard: View {
    let wave: HourlyWave
    var isSelected: Bool = false

    private var hourString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH'h'"
        return formatter.string(from: wave.time)
    }

    private var borderColor: Color {
        if isSelected {
            return .blue
        } else {
            return .white.opacity(0.08)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(hourString)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Image(systemName: "water.waves")
                .font(.system(size: 14))
                .foregroundStyle(.blue)

            // Wave direction arrow
            Image(systemName: "arrow.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .rotationEffect(.degrees(wave.waveDirection + 180))

            Text(String(format: "%.1f", wave.waveHeight))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(waveColor(wave.waveHeight))

            Text("\(Int(wave.wavePeriod))s")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 50)
        .padding(.vertical, 8)
        .background(
            isSelected ? Color.blue.opacity(0.2) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 0.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func waveColor(_ height: Double) -> Color {
        switch height {
        case ..<0.5: return .cyan
        case ..<1.0: return .green
        case ..<1.5: return .yellow
        case ..<2.5: return .orange
        default: return .red
        }
    }
}

// MARK: - Day Forecast Row

private struct DayForecastRow: View {
    let forecast: DailyForecast

    private var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: forecast.date).capitalized
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(dayString)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 120, alignment: .leading)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "wind")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(Int(round(forecast.windSpeedMaxKnots)))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(windScale(forecast.windSpeedMaxKnots))
                Text("/")
                    .foregroundStyle(.tertiary)
                Text("\(Int(round(forecast.gustsMaxKnots)))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(windScale(forecast.gustsMaxKnots))
            }

            HStack(spacing: 2) {
                Text("\(Int(round(forecast.temperatureMin)))°")
                    .font(.system(size: 13))
                    .foregroundStyle(.blue)
                Text("-")
                    .foregroundStyle(.tertiary)
                Text("\(Int(round(forecast.temperatureMax)))°")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
            }
            .frame(width: 60)

            if forecast.precipitationSum > 0.1 {
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                    Text(String(format: "%.1f", forecast.precipitationSum))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 44)
            } else {
                Color.clear.frame(width: 44)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }
}
