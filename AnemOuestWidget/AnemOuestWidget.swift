//
//  AnemOuestWidget.swift
//  AnemOuestWidget
//
//  Created by Paul Cochard on 05/01/2026.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WindEntry {
        WindEntry(
            date: Date(),
            favorites: Self.sampleData,
            config: AnemWidgetConfig(),
            forecast: Self.sampleForecast,
            tide: Self.sampleTide,
            waveBuoy: Self.sampleWaveBuoy
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WindEntry) -> ()) {
        let config = AppGroupManager.shared.loadConfiguration()
        let favorites = getFavoritesForFamily(context.family)
        let forecast = AppGroupManager.shared.loadForecastForWidget()
        let tide = AppGroupManager.shared.loadTideForWidget()
        let waveBuoys = AppGroupManager.shared.loadWaveBuoysForWidget()

        let entry = WindEntry(
            date: Date(),
            favorites: favorites.isEmpty ? Self.sampleData : favorites,
            config: config,
            forecast: forecast ?? Self.sampleForecast,
            tide: tide ?? Self.sampleTide,
            waveBuoy: waveBuoys.first ?? Self.sampleWaveBuoy
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        // Get current data BEFORE refresh to use as fallback
        let currentFavorites = getFavoritesForFamily(context.family)
        let currentConfig = AppGroupManager.shared.loadConfiguration()

        // Fetch fresh data from network
        Task {
            await WidgetDataFetcher.shared.refreshAllData()

            // Get updated data (may be same as current if refresh failed)
            let config = AppGroupManager.shared.loadConfiguration()
            var favorites = getFavoritesForFamily(context.family)
            let forecast = AppGroupManager.shared.loadForecastForWidget()
            let tide = AppGroupManager.shared.loadTideForWidget()
            let waveBuoys = AppGroupManager.shared.loadWaveBuoysForWidget()

            // Use current data as fallback if refresh returned empty
            // This prevents flickering when network fails temporarily
            if favorites.isEmpty && !currentFavorites.isEmpty {
                favorites = currentFavorites
            }

            // If still empty, try the "last known good" cache
            if favorites.isEmpty {
                favorites = AppGroupManager.shared.loadLastKnownGood()
            }

            let now = Date()
            let displayFavorites = favorites.isEmpty ? Self.sampleData : favorites

            // Generate entries spanning 2 hours (every 15 min)
            // This ensures the widget always shows something even if iOS delays the refresh
            var entries: [WindEntry] = []
            for minuteOffset in stride(from: 0, through: 120, by: 15) {
                let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: now)!
                entries.append(WindEntry(
                    date: entryDate,
                    favorites: displayFavorites,
                    config: config,
                    forecast: forecast ?? Self.sampleForecast,
                    tide: tide ?? Self.sampleTide,
                    waveBuoy: waveBuoys.first ?? Self.sampleWaveBuoy
                ))
            }

            // Request next refresh after 15 minutes (iOS may delay, but entries cover 2h as fallback)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now)!
            let timeline = Timeline(entries: entries, policy: .after(nextRefresh))
            completion(timeline)
        }
    }

    private func getFavoritesForFamily(_ family: WidgetFamily) -> [WidgetStationData] {
        switch family {
        case .systemSmall:
            return AppGroupManager.shared.getStationsForSmallWidget()
        case .systemMedium:
            return AppGroupManager.shared.getStationsForMediumWidget()
        case .systemLarge:
            return AppGroupManager.shared.getStationsForLargeWidget()
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            // Lock screen widgets show first favorite
            return AppGroupManager.shared.getStationsForSmallWidget()
        default:
            return AppGroupManager.shared.getStationsForSmallWidget()
        }
    }

    private static let sampleData: [WidgetStationData] = [
        WidgetStationData(id: "1", name: "Glénan", source: "WindCornouaille", wind: 18, gust: 25, direction: 275, isOnline: true, lastUpdate: Date()),
        WidgetStationData(id: "2", name: "Penmarch", source: "WindCornouaille", wind: 22, gust: 32, direction: 290, isOnline: true, lastUpdate: Date()),
        WidgetStationData(id: "3", name: "Belle-Île", source: "WindCornouaille", wind: 14, gust: 19, direction: 260, isOnline: true, lastUpdate: Date())
    ]

    private static let sampleForecast: WidgetForecastData = {
        let now = Date()
        let hours = (0..<6).map { i -> WidgetForecastHour in
            let time = Calendar.current.date(byAdding: .hour, value: i, to: now)!
            return WidgetForecastHour(
                time: time,
                windSpeed: Double([14, 16, 18, 20, 19, 17][i]),
                gustSpeed: Double([20, 24, 26, 28, 27, 24][i]),
                windDirection: Double([270, 275, 280, 285, 280, 275][i]),
                weatherCode: [0, 1, 2, 2, 1, 0][i]
            )
        }
        return WidgetForecastData(
            stationId: "1",
            stationName: "Glénan",
            hourly: hours,
            lastUpdate: now
        )
    }()

    private static let sampleTide: WidgetTideData = {
        let now = Date()
        return WidgetTideData(
            locationName: "Concarneau",
            events: [
                WidgetTideEvent(time: Calendar.current.date(byAdding: .hour, value: 2, to: now)!, height: 4.8, type: .high),
                WidgetTideEvent(time: Calendar.current.date(byAdding: .hour, value: 8, to: now)!, height: 1.2, type: .low)
            ],
            coefficient: 78,
            lastUpdate: now
        )
    }()

    private static let sampleWaveBuoy: WidgetWaveBuoyData = WidgetWaveBuoyData(
        id: "02911",
        name: "Les Pierres Noires",
        region: "bretagne",
        hm0: 1.8,
        tp: 9,
        direction: 280,
        seaTemp: 14,
        isOnline: true,
        lastUpdate: Date()
    )
}

// MARK: - Entry

struct WindEntry: TimelineEntry {
    let date: Date
    let favorites: [WidgetStationData]
    let config: AnemWidgetConfig
    let forecast: WidgetForecastData?
    let tide: WidgetTideData?
    let waveBuoy: WidgetWaveBuoyData?
}

// MARK: - Main Widget View

struct AnemOuestWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidget(station: entry.favorites.first, config: entry.config, favoriteCount: entry.favorites.count)
            case .systemMedium:
                MediumWidget(stations: Array(entry.favorites.prefix(3)), config: entry.config)
            case .systemLarge:
                LargeWidget(
                    stations: Array(entry.favorites.prefix(6)),
                    config: entry.config,
                    forecast: entry.forecast,
                    tide: entry.tide,
                    waveBuoy: entry.waveBuoy
                )
            case .accessoryCircular:
                LockScreenCircularWidget(station: entry.favorites.first, config: entry.config)
            case .accessoryRectangular:
                LockScreenRectangularWidget(station: entry.favorites.first, config: entry.config)
            case .accessoryInline:
                LockScreenInlineWidget(station: entry.favorites.first, config: entry.config)
            default:
                SmallWidget(station: entry.favorites.first, config: entry.config, favoriteCount: entry.favorites.count)
            }
        }
    }
}

// MARK: - Small Widget

struct SmallWidget: View {
    let station: WidgetStationData?
    let config: AnemWidgetConfig
    let favoriteCount: Int

    private func convertedWind(_ knots: Double) -> Int {
        Int(config.windUnit.convert(fromKnots: knots))
    }

    var body: some View {
        if let station = station {
            GeometryReader { geo in
                ZStack {
                    // Background
                    WidgetBackground(wind: station.wind, gust: station.gust, theme: config.colorTheme)

                    VStack(alignment: .leading, spacing: 0) {
                        // Top: Name + Status + Actions
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(shortenStationName(station.name, maxLength: 14))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                if config.showOnlineStatus || config.showLastUpdate {
                                    StatusBadge(
                                        isOnline: station.isOnline,
                                        lastUpdate: config.showLastUpdate ? station.lastUpdate : nil,
                                        showStatus: config.showOnlineStatus
                                    )
                                }
                            }

                            Spacer()

                            // Interactive buttons (iOS 17+)
                            VStack(spacing: 6) {
                                if config.showDirection {
                                    WindDirectionIndicator(direction: station.direction, size: 32, color: .white.opacity(0.95))
                                }

                                // Cycle station button
                                if favoriteCount > 1 {
                                    Button(intent: CycleStationIntent()) {
                                        Image(systemName: "chevron.right.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Spacer()

                        // Bottom: Wind Values + Unit toggle
                        HStack(alignment: .bottom, spacing: 0) {
                            // Main wind value
                            Text("\(convertedWind(station.wind))")
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)

                            VStack(alignment: .leading, spacing: 2) {
                                // Gust
                                if config.showGustSpeed {
                                    HStack(spacing: 3) {
                                        Image(systemName: "wind")
                                            .font(.system(size: 11, weight: .semibold))
                                        Text("\(convertedWind(station.gust))")
                                            .font(.system(size: 17, weight: .bold, design: .rounded))
                                    }
                                    .foregroundStyle(.white.opacity(0.85))
                                }

                                // Unit (tappable to toggle)
                                Button(intent: ToggleWindUnitIntent()) {
                                    Text(config.windUnit.symbol)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .underline(true, color: .white.opacity(0.3))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.leading, 8)
                            .padding(.bottom, 6)

                            Spacer()
                        }
                    }
                    .padding(16)
                }
            }
            .widgetURL(URL(string: "anemouest://station/\(station.id)"))
        } else {
            EmptyWidget()
        }
    }
}

// MARK: - Medium Widget

struct MediumWidget: View {
    let stations: [WidgetStationData]
    let config: AnemWidgetConfig

    var body: some View {
        if stations.isEmpty {
            EmptyWidget()
        } else {
            GeometryReader { geo in
                ZStack {
                    // Subtle gradient background
                    mediumBackground

                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                                MediumStationCell(station: station, config: config)
                                    .frame(maxWidth: .infinity)

                                if index < stations.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.15))
                                }
                            }
                        }

                        // Bottom bar with refresh + unit toggle
                        HStack {
                            Button(intent: RefreshWindIntent()) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 9, weight: .semibold))
                                    if let date = stations.first?.lastUpdate {
                                        Text(widgetRelativeTime(date))
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                }
                                .foregroundStyle(config.colorTheme == .light ? .black.opacity(0.4) : .white.opacity(0.4))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button(intent: ToggleWindUnitIntent()) {
                                Text(config.windUnit.symbol)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(config.colorTheme == .light ? .black.opacity(0.4) : .white.opacity(0.4))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((config.colorTheme == .light ? Color.black : Color.white).opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mediumBackground: some View {
        switch config.colorTheme {
        case .light:
            LinearGradient(
                colors: [Color(white: 0.95), Color(white: 0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .colorful:
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct MediumStationCell: View {
    let station: WidgetStationData
    let config: AnemWidgetConfig

    private func convertedWind(_ knots: Double) -> Int {
        Int(config.windUnit.convert(fromKnots: knots))
    }

    private var textColor: Color {
        config.colorTheme == .light ? .black : .white
    }

    var body: some View {
        VStack(spacing: 8) {
            // Station name (shortened for widget)
            Text(shortenStationName(station.name, maxLength: 10))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)

            // Direction indicator
            if config.showDirection {
                WindDirectionIndicator(
                    direction: station.direction,
                    size: 32,
                    color: windColor(station.wind)
                )
            }

            // Wind values
            HStack(spacing: 4) {
                Text("\(convertedWind(station.wind))")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(windColor(station.wind))

                if config.showGustSpeed {
                    Text("/")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.4))

                    Text("\(convertedWind(station.gust))")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(windColor(station.gust).opacity(0.85))
                }
            }

            // Status
            HStack(spacing: 4) {
                if config.showOnlineStatus {
                    Circle()
                        .fill(station.isOnline ? Color.green : Color.red.opacity(0.8))
                        .frame(width: 6, height: 6)
                }

                if config.showDirection {
                    Text(cardinalDirection(station.direction))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.5))
                }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Large Widget (Redesigned Dashboard)

struct LargeWidget: View {
    let stations: [WidgetStationData]
    let config: AnemWidgetConfig
    let forecast: WidgetForecastData?
    let tide: WidgetTideData?
    let waveBuoy: WidgetWaveBuoyData?

    private var isDark: Bool {
        config.colorTheme != .light
    }

    private var textColor: Color {
        isDark ? .white : .black
    }

    private var mainStation: WidgetStationData? {
        stations.first
    }

    private func convertedWind(_ knots: Double) -> Int {
        Int(config.windUnit.convert(fromKnots: knots))
    }

    var body: some View {
        if stations.isEmpty {
            EmptyWidget()
        } else {
            GeometryReader { geo in
                ZStack {
                    largeBackground

                    VStack(spacing: 0) {
                        // MARK: Hero Section — Main Station
                        if let station = mainStation {
                            heroSection(station, width: geo.size.width)
                        }

                        // MARK: Data Strip — Forecast | Tide | Wave
                        dataStrip
                            .padding(.horizontal, 12)
                            .padding(.top, 10)

                        // MARK: Other Stations
                        if stations.count > 1 {
                            otherStationsSection(Array(stations.dropFirst().prefix(4)))
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                        }

                        Spacer(minLength: 0)

                        // Bottom action bar
                        HStack {
                            Button(intent: RefreshWindIntent()) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10, weight: .semibold))
                                    if let date = mainStation?.lastUpdate {
                                        Text(widgetRelativeTime(date))
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                }
                                .foregroundStyle(textColor.opacity(0.4))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button(intent: ToggleWindUnitIntent()) {
                                Text(config.windUnit.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(textColor.opacity(0.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(textColor.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
    }

    // MARK: - Hero Section

    private func heroSection(_ station: WidgetStationData, width: CGFloat) -> some View {
        ZStack {
            // Colored background gradient based on wind
            heroGradient(wind: station.wind)

            HStack(spacing: 0) {
                // Left: Name + Wind value
                VStack(alignment: .leading, spacing: 2) {
                    // Header row
                    HStack(spacing: 5) {
                        Image(systemName: "wind")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Le Vent")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }

                    // Station name
                    Text(shortenStationName(station.name, maxLength: 16))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    // Big wind value
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(convertedWind(station.wind))")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)

                        VStack(alignment: .leading, spacing: 1) {
                            // Gust
                            if config.showGustSpeed {
                                HStack(spacing: 2) {
                                    Image(systemName: "wind")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("\(convertedWind(station.gust))")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(.white.opacity(0.75))
                            }
                            Text(config.windUnit.symbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }

                    // Status
                    if config.showOnlineStatus || config.showLastUpdate {
                        HStack(spacing: 4) {
                            if config.showOnlineStatus {
                                Circle()
                                    .fill(station.isOnline ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                            }
                            if config.showLastUpdate, let date = station.lastUpdate {
                                Text(heroRelativeTime(date))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                }

                Spacer(minLength: 12)

                // Right: Direction compass
                if config.showDirection {
                    VStack(spacing: 4) {
                        Spacer()

                        ZStack {
                            // Outer ring
                            Circle()
                                .fill(.white.opacity(0.12))
                                .frame(width: 64, height: 64)

                            // Cardinal labels
                            ForEach(Array(["N", "E", "S", "O"].enumerated()), id: \.offset) { idx, label in
                                Text(label)
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .offset(
                                        x: 26 * sin(Double(idx) * .pi / 2),
                                        y: -26 * cos(Double(idx) * .pi / 2)
                                    )
                            }

                            // Arrow
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(station.direction + 180))
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        }

                        Text(cardinalDirection(station.direction))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))

                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    private func heroGradient(wind: Double) -> some View {
        LinearGradient(
            colors: heroColors(for: wind),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            LinearGradient(
                colors: [.white.opacity(0.08), .clear, .black.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func heroColors(for wind: Double) -> [Color] {
        switch wind {
        case ..<7:  return [Color(hex: "4A90D9"), Color(hex: "357ABD")]
        case ..<12: return [Color(hex: "2E9E83"), Color(hex: "1D7A64")]
        case ..<18: return [Color(hex: "48B85E"), Color(hex: "2D8C42")]
        case ..<24: return [Color(hex: "E8A838"), Color(hex: "C78C2E")]
        case ..<30: return [Color(hex: "E86838"), Color(hex: "C54E28")]
        case ..<38: return [Color(hex: "D84545"), Color(hex: "B52F2F")]
        default:    return [Color(hex: "9B4DCA"), Color(hex: "7B38A8")]
        }
    }

    private func heroRelativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 0 { return "a jour" }
        if seconds < 60 { return "a l'instant" }
        if seconds < 3600 { return "il y a \(seconds / 60)min" }
        return "il y a \(seconds / 3600)h"
    }

    // MARK: - Data Strip (3 columns)

    private var dataStrip: some View {
        HStack(spacing: 8) {
            // Forecast column
            if let forecast = forecast {
                forecastCard(forecast)
                    .frame(height: 90)
            } else {
                forecastPlaceholderCard
                    .frame(height: 90)
            }

            // Tide column
            if let tide = tide {
                tideCard(tide)
                    .frame(height: 90)
            } else {
                tidePlaceholderCard
                    .frame(height: 90)
            }

            // Wave column
            if let wave = waveBuoy {
                waveCard(wave)
                    .frame(height: 90)
            } else {
                wavePlaceholderCard
                    .frame(height: 90)
            }
        }
    }

    // MARK: - Forecast Card

    private func forecastCard(_ forecast: WidgetForecastData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Previsions")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(textColor.opacity(0.5))

            // Mini bar chart
            HStack(spacing: 3) {
                ForEach(forecast.next6Hours) { hour in
                    VStack(spacing: 2) {
                        Spacer(minLength: 0)

                        // Wind value on top
                        Text("\(Int(hour.windSpeed))")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(windColor(hour.windSpeed))

                        // Bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(windColor(hour.windSpeed))
                            .frame(height: barHeight(for: hour.windSpeed, maxH: 36))

                        // Hour label
                        Text(hourString(hour.time))
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.4))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func barHeight(for wind: Double, maxH: CGFloat = 28) -> CGFloat {
        let minH: CGFloat = 4
        let normalized = min(wind / 35.0, 1.0)
        return minH + (maxH - minH) * normalized
    }

    private func hourString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        return formatter.string(from: date)
    }

    // MARK: - Tide Card

    private func tideCard(_ tide: WidgetTideData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "water.waves")
                    .font(.system(size: 9, weight: .bold))
                Text("Marees")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(textColor.opacity(0.5))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(tide.nextEvents.prefix(2)) { event in
                    HStack(spacing: 3) {
                        // Type badge
                        Text(event.type.label)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(event.type == .high ? Color(hex: "4A90D9") : .cyan)
                            .frame(width: 22)

                        Text(tideTimeString(event.time))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(textColor.opacity(0.9))

                        Text(String(format: "%.1f", event.height))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.4))
                    }
                }
            }

            Spacer(minLength: 0)

            if let coef = tide.coefficient {
                HStack(spacing: 3) {
                    Text("Coef")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.35))
                    Text("\(coef)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(coefColor(coef))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func coefColor(_ coef: Int) -> Color {
        switch coef {
        case ..<45: return .green
        case ..<70: return .cyan
        case ..<90: return .orange
        default: return .red
        }
    }

    private func tideTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Wave Card

    private func waveCard(_ wave: WidgetWaveBuoyData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "water.waves.and.arrow.up")
                    .font(.system(size: 9, weight: .bold))
                Text("Houle")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(textColor.opacity(0.5))

            // Wave height hero value
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(wave.waveHeightDisplay)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
                Text("m")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.cyan.opacity(0.6))
            }

            Spacer(minLength: 0)

            // Period + temp row
            VStack(alignment: .leading, spacing: 2) {
                if let tp = wave.tp {
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 8, weight: .semibold))
                        Text("\(Int(tp))s")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(textColor.opacity(0.5))
                }
                if let temp = wave.seaTemp {
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 8, weight: .semibold))
                        Text("\(Int(temp))°C")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(textColor.opacity(0.5))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - Other Stations Section

    private func otherStationsSection(_ others: [WidgetStationData]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(others.enumerated()), id: \.element.id) { index, station in
                HStack(spacing: 8) {
                    // Direction arrow
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(windColor(station.wind))
                        .rotationEffect(.degrees(station.direction + 180))
                        .frame(width: 14)

                    // Name
                    Text(shortenStationName(station.name, maxLength: 12))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.85))
                        .lineLimit(1)

                    Spacer()

                    // Cardinal direction
                    if config.showDirection {
                        Text(cardinalDirection(station.direction))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.35))
                    }

                    // Wind / Gust
                    HStack(spacing: 2) {
                        Text("\(convertedWind(station.wind))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(windColor(station.wind))

                        if config.showGustSpeed {
                            Text("/")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(textColor.opacity(0.25))
                            Text("\(convertedWind(station.gust))")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(windColor(station.gust).opacity(0.7))
                        }
                    }

                    // Unit (only on first row)
                    if index == 0 {
                        Text(config.windUnit.symbol)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.3))
                            .frame(width: 24, alignment: .trailing)
                    } else {
                        Color.clear.frame(width: 24)
                    }
                }
                .padding(.vertical, 6)

                if index < others.count - 1 {
                    Divider()
                        .background(textColor.opacity(0.08))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(cardBackground)
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(textColor.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(textColor.opacity(0.05), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var largeBackground: some View {
        switch config.colorTheme {
        case .light:
            LinearGradient(
                colors: [Color(white: 0.96), Color(white: 0.91)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .colorful:
            LinearGradient(
                colors: [Color(hex: "0F1923"), Color(hex: "0A1118")],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            LinearGradient(
                colors: [Color(white: 0.10), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Placeholder Cards

    private var forecastPlaceholderCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Previsions")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(textColor.opacity(0.5))

            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(spacing: 2) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(textColor.opacity(0.1))
                            .frame(height: 16)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(textColor.opacity(0.07))
                            .frame(height: 6)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var tidePlaceholderCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "water.waves")
                    .font(.system(size: 9, weight: .bold))
                Text("Marees")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(textColor.opacity(0.5))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(textColor.opacity(0.1))
                            .frame(width: 22, height: 10)
                        Text("--:--")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(textColor.opacity(0.2))
                    }
                }
            }

            Spacer(minLength: 0)

            Text("Coef --")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(textColor.opacity(0.2))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var wavePlaceholderCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "water.waves.and.arrow.up")
                    .font(.system(size: 9, weight: .bold))
                Text("Houle")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(textColor.opacity(0.5))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("--")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor.opacity(0.2))
                Text("m")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(textColor.opacity(0.15))
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text("--s")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.15))
                Text("--°C")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(textColor.opacity(0.15))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
    }
}


// MARK: - Empty Widget

struct EmptyWidget: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(white: 0.15),
                        Color(white: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 56, height: 56)

                        Image(systemName: "star.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }

                    VStack(spacing: 4) {
                        Text("Aucun favori")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Ajoutez des spots favoris\ndans l'application")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }
}

// MARK: - Components

struct WidgetBackground: View {
    let wind: Double
    let gust: Double
    let theme: WidgetColorTheme

    var body: some View {
        ZStack {
            // Base gradient based on theme
            switch theme {
            case .light:
                LinearGradient(
                    colors: [Color(white: 0.95), Color(white: 0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .dark:
                LinearGradient(
                    colors: [Color(white: 0.15), Color(white: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .colorful, .auto:
                LinearGradient(
                    colors: backgroundColors(for: wind),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Subtle overlay for depth (only for colorful)
            if theme == .colorful || theme == .auto {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.1),
                        Color.clear,
                        Color.black.opacity(0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func backgroundColors(for wind: Double) -> [Color] {
        switch wind {
        case ..<7:
            return [Color(hex: "4A90D9"), Color(hex: "357ABD")]
        case ..<12:
            return [Color(hex: "2E9E83"), Color(hex: "1D7A64")]
        case ..<18:
            return [Color(hex: "48B85E"), Color(hex: "2D8C42")]
        case ..<24:
            return [Color(hex: "E8A838"), Color(hex: "C78C2E")]
        case ..<30:
            return [Color(hex: "E86838"), Color(hex: "C54E28")]
        case ..<38:
            return [Color(hex: "D84545"), Color(hex: "B52F2F")]
        default:
            return [Color(hex: "9B4DCA"), Color(hex: "7B38A8")]
        }
    }
}

struct WindDirectionIndicator: View {
    let direction: Double
    let size: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: size, height: size)

            // Arrow - direction indicates where wind comes FROM, so add 180° to show where it blows TO
            Image(systemName: "location.north.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(color)
                .rotationEffect(.degrees(direction + 180))
        }
    }
}

struct StatusBadge: View {
    let isOnline: Bool
    let lastUpdate: Date?
    var showStatus: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            if showStatus {
                Circle()
                    .fill(isOnline ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                    .shadow(color: isOnline ? .green.opacity(0.5) : .red.opacity(0.5), radius: 3)
            }

            if let date = lastUpdate {
                Text(relativeTime(date))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 0 { return "à jour" }
        if seconds < 60 { return "à l'instant" }
        if seconds < 3600 { return "il y a \(seconds / 60) min" }
        if seconds < 86400 { return "il y a \(seconds / 3600)h" }
        return "il y a \(seconds / 86400)j"
    }
}

// MARK: - Lock Screen Circular Widget

struct LockScreenCircularWidget: View {
    let station: WidgetStationData?
    let config: AnemWidgetConfig

    private func convertedWind(_ knots: Double) -> Int {
        Int(config.windUnit.convert(fromKnots: knots))
    }

    var body: some View {
        if let station = station {
            ZStack {
                // Background gauge based on wind strength
                AccessoryWidgetBackground()

                VStack(spacing: 0) {
                    // Wind value
                    Text("\(convertedWind(station.wind))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)

                    // Unit
                    Text(config.windUnit.symbol)
                        .font(.system(size: 9, weight: .medium))
                        .opacity(0.7)
                }
            }
            .widgetLabel {
                Text(shortenStationName(station.name, maxLength: 12))
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "wind")
                    .font(.system(size: 20))
            }
        }
    }
}

// MARK: - Lock Screen Rectangular Widget

struct LockScreenRectangularWidget: View {
    let station: WidgetStationData?
    let config: AnemWidgetConfig

    private func convertedWind(_ knots: Double) -> Int {
        Int(config.windUnit.convert(fromKnots: knots))
    }

    var body: some View {
        if let station = station {
            HStack(spacing: 10) {
                // Wind direction arrow
                ZStack {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 36, height: 36)

                    Image(systemName: "location.north.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .rotationEffect(.degrees(station.direction + 180))
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Station name (shortened for lock screen)
                    Text(shortenStationName(station.name, maxLength: 14))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    // Wind values
                    HStack(spacing: 4) {
                        Text("\(convertedWind(station.wind))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))

                        Text("/")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.5)

                        Text("\(convertedWind(station.gust))")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .opacity(0.8)

                        Text(config.windUnit.symbol)
                            .font(.system(size: 10, weight: .medium))
                            .opacity(0.6)
                    }
                }

                Spacer()
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "wind")
                    .font(.system(size: 20))
                Text("Aucun favori")
                    .font(.system(size: 13, weight: .medium))
            }
            .opacity(0.6)
        }
    }
}

// MARK: - Lock Screen Inline Widget

struct LockScreenInlineWidget: View {
    let station: WidgetStationData?
    let config: AnemWidgetConfig

    private func convertedWind(_ knots: Double) -> Int {
        Int(config.windUnit.convert(fromKnots: knots))
    }

    var body: some View {
        if let station = station {
            HStack(spacing: 4) {
                Image(systemName: "wind")
                Text("\(shortenStationName(station.name, maxLength: 8)): \(convertedWind(station.wind))/\(convertedWind(station.gust)) \(config.windUnit.symbol)")
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "wind")
                Text("Le Vent")
            }
        }
    }
}

// MARK: - Name Shortening Helper

/// Shortens long station names for widgets with limited space
/// Examples: "Pointe de la Torche" → "P. Torche", "Saint-Gilles-Croix-de-Vie" → "St-Gilles"
private func widgetRelativeTime(_ date: Date) -> String {
    let seconds = Int(-date.timeIntervalSinceNow)
    if seconds < 0 { return "a jour" }
    if seconds < 60 { return "a l'instant" }
    if seconds < 3600 { return "\(seconds / 60)min" }
    return "\(seconds / 3600)h"
}

private func shortenStationName(_ name: String, maxLength: Int = 12) -> String {
    // If name is short enough, return as-is
    if name.count <= maxLength {
        return name
    }

    // Known abbreviations for common stations
    let knownAbbreviations: [String: String] = [
        "Pointe de la Torche": "P. Torche",
        "Pointe de Penmarch": "Penmarch",
        "Saint-Gilles-Croix-de-Vie": "St-Gilles",
        "Saint-Jean-de-Luz": "St-Jean-Luz",
        "Saint-Jean-de-Monts": "St-Jean-Monts",
        "La Tranche-sur-Mer": "La Tranche",
        "Les Sables-d'Olonne": "Les Sables",
        "Port-la-Nouvelle": "Pt-la-Nvelle",
        "Île de Noirmoutier": "Noirmoutier",
        "Île de Ré": "Île de Ré",
        "Presqu'île de Quiberon": "Quiberon",
        "Pointe du Raz": "Pte du Raz",
        "Cap Fréhel": "Cap Fréhel",
        "Baie de Douarnenez": "Douarnenez",
        "Anse de Bertheaume": "Bertheaume",
        "Fort-Bloqué": "Fort-Bloqué",
        "Port Louis": "Port Louis",
        "Belle-Île-en-Mer": "Belle-Île",
        "Île de Groix": "Groix",
        "Île aux Moines": "Île Moines",
        "Guidel-Plages": "Guidel",
        "Plage des Grands Sables": "Gds Sables",
        "Plage de Trestraou": "Trestraou",
        "Anse de Dinan": "A. Dinan"
    ]

    // Check for known abbreviation
    if let abbrev = knownAbbreviations[name] {
        return abbrev
    }

    // Try to shorten with common patterns
    var shortened = name

    // Replace common prefixes
    let replacements: [(String, String)] = [
        ("Pointe de ", "Pte "),
        ("Pointe du ", "Pte "),
        ("Pointe ", "Pte "),
        ("Saint-", "St-"),
        ("Sainte-", "Ste-"),
        ("Plage de ", ""),
        ("Plage du ", ""),
        ("Plage des ", ""),
        ("Île de ", ""),
        ("Île d'", ""),
        ("Baie de ", ""),
        ("Anse de ", "A. "),
        ("Port de ", ""),
        ("-sur-Mer", ""),
        ("-en-Mer", ""),
        ("-Plages", ""),
        ("-les-Bains", "")
    ]

    for (pattern, replacement) in replacements {
        if shortened.contains(pattern) {
            shortened = shortened.replacingOccurrences(of: pattern, with: replacement)
        }
    }

    // If still too long, truncate
    if shortened.count > maxLength {
        shortened = String(shortened.prefix(maxLength - 1)) + "…"
    }

    return shortened
}

// MARK: - Color Helpers

private func windColor(_ knots: Double) -> Color {
    switch knots {
    case ..<7:
        return Color(red: 0.70, green: 0.93, blue: 1.00)
    case ..<11:
        return Color(red: 0.33, green: 0.85, blue: 0.92)
    case ..<17:
        return Color(red: 0.35, green: 0.89, blue: 0.52)
    case ..<22:
        return Color(red: 0.97, green: 0.90, blue: 0.33)
    case ..<28:
        return Color(red: 0.98, green: 0.67, blue: 0.23)
    case ..<34:
        return Color(red: 0.95, green: 0.22, blue: 0.26)
    case ..<41:
        return Color(red: 0.83, green: 0.20, blue: 0.67)
    case ..<48:
        return Color(red: 0.55, green: 0.24, blue: 0.78)
    default:
        return Color(red: 0.39, green: 0.24, blue: 0.63)
    }
}

private func cardinalDirection(_ degrees: Double) -> String {
    let directions = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
    let index = Int((degrees + 22.5).truncatingRemainder(dividingBy: 360) / 45)
    return directions[max(0, min(index, 7))]
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Widget Configuration

struct AnemOuestWidget: Widget {
    let kind: String = "AnemOuestWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                AnemOuestWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) { Color.clear }
            } else {
                AnemOuestWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Le Vent")
        .description("Vent en temps réel de vos spots favoris")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews

// MARK: - Sample Data for Previews

private let previewForecast: WidgetForecastData = {
    let now = Date()
    let hours = (0..<6).map { i -> WidgetForecastHour in
        let time = Calendar.current.date(byAdding: .hour, value: i, to: now)!
        return WidgetForecastHour(
            time: time,
            windSpeed: Double([14, 18, 22, 25, 23, 20][i]),
            gustSpeed: Double([20, 26, 30, 34, 32, 28][i]),
            windDirection: Double([270, 275, 280, 285, 280, 275][i]),
            weatherCode: [0, 1, 2, 2, 1, 0][i]
        )
    }
    return WidgetForecastData(stationId: "1", stationName: "Glénan", hourly: hours, lastUpdate: now)
}()

private let previewTide: WidgetTideData = {
    let now = Date()
    return WidgetTideData(
        locationName: "Concarneau",
        events: [
            WidgetTideEvent(time: Calendar.current.date(byAdding: .hour, value: 2, to: now)!, height: 4.8, type: .high),
            WidgetTideEvent(time: Calendar.current.date(byAdding: .hour, value: 8, to: now)!, height: 1.2, type: .low)
        ],
        coefficient: 85,
        lastUpdate: now
    )
}()

private let previewWave = WidgetWaveBuoyData(
    id: "02911", name: "Pierres Noires", region: "bretagne",
    hm0: 1.8, tp: 10, direction: 280, seaTemp: 14,
    isOnline: true, lastUpdate: Date()
)

#Preview("Small - Light wind", as: .systemSmall) {
    AnemOuestWidget()
} timeline: {
    WindEntry(date: .now, favorites: [
        WidgetStationData(id: "1", name: "Glénan", source: "WC", wind: 8, gust: 12, direction: 275, isOnline: true, lastUpdate: Date())
    ], config: AnemWidgetConfig(), forecast: nil, tide: nil, waveBuoy: nil)
}

#Preview("Small - Strong wind", as: .systemSmall) {
    AnemOuestWidget()
} timeline: {
    WindEntry(date: .now, favorites: [
        WidgetStationData(id: "1", name: "Penmarch", source: "WC", wind: 28, gust: 38, direction: 310, isOnline: true, lastUpdate: Date())
    ], config: AnemWidgetConfig(), forecast: nil, tide: nil, waveBuoy: nil)
}

#Preview("Medium", as: .systemMedium) {
    AnemOuestWidget()
} timeline: {
    WindEntry(date: .now, favorites: [
        WidgetStationData(id: "1", name: "Glénan", source: "WC", wind: 18, gust: 25, direction: 275, isOnline: true, lastUpdate: Date()),
        WidgetStationData(id: "2", name: "Penmarch", source: "WC", wind: 24, gust: 34, direction: 290, isOnline: true, lastUpdate: Date()),
        WidgetStationData(id: "3", name: "Belle-Île", source: "WC", wind: 12, gust: 16, direction: 260, isOnline: false, lastUpdate: Date())
    ], config: AnemWidgetConfig(), forecast: nil, tide: nil, waveBuoy: nil)
}

#Preview("Large - Dashboard", as: .systemLarge) {
    AnemOuestWidget()
} timeline: {
    WindEntry(date: .now, favorites: [
        WidgetStationData(id: "1", name: "Glénan", source: "WC", wind: 18, gust: 25, direction: 275, isOnline: true, lastUpdate: Date()),
        WidgetStationData(id: "2", name: "Penmarch", source: "WC", wind: 24, gust: 34, direction: 290, isOnline: true, lastUpdate: Date()),
        WidgetStationData(id: "3", name: "Belle-Île", source: "WC", wind: 12, gust: 16, direction: 260, isOnline: true, lastUpdate: Date()),
        WidgetStationData(id: "4", name: "Groix", source: "WC", wind: 32, gust: 42, direction: 300, isOnline: true, lastUpdate: Date()),
        WidgetStationData(id: "5", name: "Quiberon", source: "WC", wind: 20, gust: 28, direction: 285, isOnline: true, lastUpdate: Date())
    ], config: AnemWidgetConfig(), forecast: previewForecast, tide: previewTide, waveBuoy: previewWave)
}

#Preview("Large - Light theme", as: .systemLarge) {
    AnemOuestWidget()
} timeline: {
    WindEntry(date: .now, favorites: [
        WidgetStationData(id: "1", name: "Glénan", source: "WC", wind: 22, gust: 30, direction: 270, isOnline: true, lastUpdate: Date()),
        WidgetStationData(id: "2", name: "Penmarch", source: "WC", wind: 15, gust: 20, direction: 280, isOnline: true, lastUpdate: Date()),
        WidgetStationData(id: "3", name: "Lorient", source: "FFVL", wind: 10, gust: 14, direction: 250, isOnline: true, lastUpdate: Date())
    ], config: {
        var c = AnemWidgetConfig()
        c.colorTheme = .light
        return c
    }(), forecast: previewForecast, tide: previewTide, waveBuoy: previewWave)
}

#Preview("Empty", as: .systemSmall) {
    AnemOuestWidget()
} timeline: {
    WindEntry(date: .now, favorites: [], config: AnemWidgetConfig(), forecast: nil, tide: nil, waveBuoy: nil)
}

#Preview("Lock Screen - Circular", as: .accessoryCircular) {
    AnemOuestWidget()
} timeline: {
    WindEntry(date: .now, favorites: [
        WidgetStationData(id: "1", name: "Glénan", source: "WC", wind: 18, gust: 25, direction: 275, isOnline: true, lastUpdate: Date())
    ], config: AnemWidgetConfig(), forecast: nil, tide: nil, waveBuoy: nil)
}

#Preview("Lock Screen - Rectangular", as: .accessoryRectangular) {
    AnemOuestWidget()
} timeline: {
    WindEntry(date: .now, favorites: [
        WidgetStationData(id: "1", name: "Glénan", source: "WC", wind: 18, gust: 25, direction: 275, isOnline: true, lastUpdate: Date())
    ], config: AnemWidgetConfig(), forecast: nil, tide: nil, waveBuoy: nil)
}

#Preview("Lock Screen - Inline", as: .accessoryInline) {
    AnemOuestWidget()
} timeline: {
    WindEntry(date: .now, favorites: [
        WidgetStationData(id: "1", name: "Glénan", source: "WC", wind: 18, gust: 25, direction: 275, isOnline: true, lastUpdate: Date())
    ], config: AnemWidgetConfig(), forecast: nil, tide: nil, waveBuoy: nil)
}
