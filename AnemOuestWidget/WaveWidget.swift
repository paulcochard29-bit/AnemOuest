//
//  WaveWidget.swift
//  AnemOuestWidget
//
//  Wave buoy widget for home screen and lock screen
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Provider

struct WaveProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaveEntry {
        WaveEntry(date: Date(), buoys: Self.sampleData, config: AnemWidgetConfig())
    }

    func getSnapshot(in context: Context, completion: @escaping (WaveEntry) -> ()) {
        let config = AppGroupManager.shared.loadConfiguration()
        let buoys = getBuoysForFamily(context.family)
        let entry = WaveEntry(
            date: Date(),
            buoys: buoys.isEmpty ? Self.sampleData : buoys,
            config: config
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            let _ = await WaveWidgetDataFetcher.shared.refreshData()

            let config = AppGroupManager.shared.loadConfiguration()
            let buoys = getBuoysForFamily(context.family)

            let entry = WaveEntry(date: Date(), buoys: buoys, config: config)

            // Refresh every 30 minutes (wave data changes slower)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func getBuoysForFamily(_ family: WidgetFamily) -> [WidgetWaveBuoyData] {
        switch family {
        case .systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return AppGroupManager.shared.getWaveBuoysForSmallWidget()
        case .systemMedium:
            return AppGroupManager.shared.getWaveBuoysForMediumWidget()
        default:
            return AppGroupManager.shared.getWaveBuoysForSmallWidget()
        }
    }

    private static let sampleData: [WidgetWaveBuoyData] = [
        WidgetWaveBuoyData(id: "1", name: "Les Pierres Noires", region: "Bretagne", hm0: 1.8, tp: 10, direction: 280, seaTemp: 14.5, isOnline: true, lastUpdate: Date()),
        WidgetWaveBuoyData(id: "2", name: "Île d'Yeu", region: "Vendée", hm0: 1.2, tp: 8, direction: 270, seaTemp: 15.2, isOnline: true, lastUpdate: Date()),
        WidgetWaveBuoyData(id: "3", name: "Cap Ferret", region: "Aquitaine", hm0: 2.4, tp: 12, direction: 290, seaTemp: 16.0, isOnline: true, lastUpdate: Date())
    ]
}

// MARK: - Entry

struct WaveEntry: TimelineEntry {
    let date: Date
    let buoys: [WidgetWaveBuoyData]
    let config: AnemWidgetConfig
}

// MARK: - Main Widget View

struct WaveWidgetEntryView: View {
    var entry: WaveProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                WaveSmallWidget(buoy: entry.buoys.first, config: entry.config)
            case .systemMedium:
                WaveMediumWidget(buoys: Array(entry.buoys.prefix(3)), config: entry.config)
            case .accessoryCircular:
                WaveLockScreenCircular(buoy: entry.buoys.first)
            case .accessoryRectangular:
                WaveLockScreenRectangular(buoy: entry.buoys.first)
            case .accessoryInline:
                WaveLockScreenInline(buoy: entry.buoys.first)
            default:
                WaveSmallWidget(buoy: entry.buoys.first, config: entry.config)
            }
        }
    }
}

// MARK: - Small Widget

struct WaveSmallWidget: View {
    let buoy: WidgetWaveBuoyData?
    let config: AnemWidgetConfig

    var body: some View {
        if let buoy = buoy {
            GeometryReader { _ in
                ZStack {
                    // Background gradient based on wave height
                    WaveBackground(hm0: buoy.hm0)

                    VStack(alignment: .leading, spacing: 0) {
                        // Top: Name + Status
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(shortenBuoyName(buoy.name, maxLength: 16))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(buoy.isOnline ? Color.green : Color.red)
                                        .frame(width: 7, height: 7)
                                    Text(buoy.region)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }

                            Spacer()

                            // Wave direction indicator
                            if let direction = buoy.direction {
                                WaveDirectionIndicator(direction: direction, size: 36)
                            }
                        }

                        Spacer()

                        // Bottom: Wave Values
                        HStack(alignment: .bottom, spacing: 0) {
                            // Wave height
                            Text(buoy.waveHeightDisplay)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)

                            VStack(alignment: .leading, spacing: 2) {
                                // Period
                                if let tp = buoy.tp {
                                    HStack(spacing: 3) {
                                        Image(systemName: "timer")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("\(Int(tp))s")
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                    }
                                    .foregroundStyle(.white.opacity(0.85))
                                }

                                // Unit
                                Text("m")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding(.leading, 8)
                            .padding(.bottom, 6)

                            Spacer()

                            // Sea temp
                            if let temp = buoy.seaTemp {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Image(systemName: "thermometer.medium")
                                        .font(.system(size: 12))
                                    Text("\(Int(temp))°")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.bottom, 6)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        } else {
            WaveEmptyWidget()
        }
    }
}

// MARK: - Medium Widget

struct WaveMediumWidget: View {
    let buoys: [WidgetWaveBuoyData]
    let config: AnemWidgetConfig

    var body: some View {
        if buoys.isEmpty {
            WaveEmptyWidget()
        } else {
            GeometryReader { _ in
                ZStack {
                    // Gradient background
                    LinearGradient(
                        colors: [Color(hex: "1A5276"), Color(hex: "0E3D5C")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(buoys.enumerated()), id: \.element.id) { index, buoy in
                                WaveMediumCell(buoy: buoy)
                                    .frame(maxWidth: .infinity)

                                if index < buoys.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.15))
                                }
                            }
                        }

                        // Refresh bar
                        HStack {
                            Button(intent: RefreshWaveIntent()) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 9, weight: .semibold))
                                    if let date = buoys.first?.lastUpdate {
                                        Text(waveRelativeTime(date))
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                }
                                .foregroundStyle(.white.opacity(0.4))
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    }
                }
            }
        }
    }
}

struct WaveMediumCell: View {
    let buoy: WidgetWaveBuoyData

    var body: some View {
        VStack(spacing: 6) {
            // Buoy name (shortened for widget)
            Text(shortenBuoyName(buoy.name, maxLength: 10))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            // Wave icon with direction
            if let direction = buoy.direction {
                WaveDirectionIndicator(direction: direction, size: 30)
            } else {
                Image(systemName: "water.waves")
                    .font(.system(size: 18))
                    .foregroundStyle(.cyan)
            }

            // Wave height + period
            HStack(spacing: 4) {
                Text(buoy.waveHeightDisplay)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(waveColor(buoy.hm0))

                Text("m")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            // Period
            if let tp = buoy.tp {
                Text("\(Int(tp))s")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Status
            HStack(spacing: 4) {
                Circle()
                    .fill(buoy.isOnline ? Color.green : Color.red.opacity(0.8))
                    .frame(width: 6, height: 6)
                if let temp = buoy.seaTemp {
                    Text("\(Int(temp))°")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Lock Screen Circular

struct WaveLockScreenCircular: View {
    let buoy: WidgetWaveBuoyData?

    var body: some View {
        if let buoy = buoy {
            ZStack {
                AccessoryWidgetBackground()

                VStack(spacing: 0) {
                    Text(buoy.waveHeightDisplay)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)

                    Text("m")
                        .font(.system(size: 9, weight: .medium))
                        .opacity(0.7)
                }
            }
            .widgetLabel {
                Text(shortenBuoyName(buoy.name, maxLength: 12))
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "water.waves")
                    .font(.system(size: 18))
            }
        }
    }
}

// MARK: - Lock Screen Rectangular

struct WaveLockScreenRectangular: View {
    let buoy: WidgetWaveBuoyData?

    var body: some View {
        if let buoy = buoy {
            HStack(spacing: 10) {
                // Wave icon
                ZStack {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 36, height: 36)

                    Image(systemName: "water.waves")
                        .font(.system(size: 16, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Buoy name (shortened for lock screen)
                    Text(shortenBuoyName(buoy.name, maxLength: 14))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    // Wave values
                    HStack(spacing: 4) {
                        Text(buoy.waveHeightDisplay)
                            .font(.system(size: 18, weight: .bold, design: .rounded))

                        Text("m")
                            .font(.system(size: 11, weight: .medium))
                            .opacity(0.6)

                        if let tp = buoy.tp {
                            Text("•")
                                .opacity(0.4)
                            Text("\(Int(tp))s")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .opacity(0.8)
                        }
                    }
                }

                Spacer()
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "water.waves")
                    .font(.system(size: 18))
                Text("Aucune bouée")
                    .font(.system(size: 13, weight: .medium))
            }
            .opacity(0.6)
        }
    }
}

// MARK: - Lock Screen Inline

struct WaveLockScreenInline: View {
    let buoy: WidgetWaveBuoyData?

    var body: some View {
        if let buoy = buoy {
            HStack(spacing: 4) {
                Image(systemName: "water.waves")
                if let tp = buoy.tp {
                    Text("\(shortenBuoyName(buoy.name, maxLength: 8)): \(buoy.waveHeightDisplay)m • \(Int(tp))s")
                } else {
                    Text("\(shortenBuoyName(buoy.name, maxLength: 10)): \(buoy.waveHeightDisplay)m")
                }
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "water.waves")
                Text("Houle")
            }
        }
    }
}

// MARK: - Empty Widget

struct WaveEmptyWidget: View {
    var body: some View {
        GeometryReader { _ in
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "1A5276"), Color(hex: "0E3D5C")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 56, height: 56)

                        Image(systemName: "water.waves")
                            .font(.system(size: 26))
                            .foregroundStyle(.cyan)
                    }

                    VStack(spacing: 4) {
                        Text("Aucune bouée")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Ajoutez des bouées\nen favoris")
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

struct WaveBackground: View {
    let hm0: Double?

    var body: some View {
        LinearGradient(
            colors: backgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var backgroundColors: [Color] {
        guard let hm0 = hm0 else {
            return [Color(hex: "1A5276"), Color(hex: "0E3D5C")]
        }
        switch hm0 {
        case ..<0.5:
            return [Color(hex: "4A90D9"), Color(hex: "357ABD")] // Calm - light blue
        case ..<1.0:
            return [Color(hex: "2E9E9E"), Color(hex: "1D7A7A")] // Small - teal
        case ..<1.5:
            return [Color(hex: "2E8B57"), Color(hex: "1D6B42")] // Moderate - sea green
        case ..<2.0:
            return [Color(hex: "DAA520"), Color(hex: "B8860B")] // Medium - goldenrod
        case ..<2.5:
            return [Color(hex: "E86838"), Color(hex: "C54E28")] // Large - orange
        case ..<3.0:
            return [Color(hex: "D84545"), Color(hex: "B52F2F")] // Very large - red
        default:
            return [Color(hex: "8B4789"), Color(hex: "6B3069")] // Huge - purple
        }
    }
}

struct WaveDirectionIndicator: View {
    let direction: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: size, height: size)

            // Wave direction shows where waves come FROM
            Image(systemName: "arrow.down")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .rotationEffect(.degrees(direction))
        }
    }
}

// MARK: - Name Shortening Helper

/// Shortens long buoy names to initials for widgets with limited space
/// Examples: "Les Pierres Noires" → "LPN", "Île d'Yeu" → "Île d'Yeu"
private func waveRelativeTime(_ date: Date) -> String {
    let seconds = Int(-date.timeIntervalSinceNow)
    if seconds < 0 { return "a jour" }
    if seconds < 60 { return "a l'instant" }
    if seconds < 3600 { return "\(seconds / 60)min" }
    return "\(seconds / 3600)h"
}

private func shortenBuoyName(_ name: String, maxLength: Int = 12) -> String {
    // If name is short enough, return as-is
    if name.count <= maxLength {
        return name
    }

    // Known abbreviations for common buoys
    let knownAbbreviations: [String: String] = [
        "Les Pierres Noires": "LPN",
        "Pierres Noires": "PN",
        "Belle-Île": "Belle-Île",
        "Île d'Yeu": "Île d'Yeu",
        "Plateau du Four": "P. du Four",
        "Pointe de Penmarc'h": "Penmarc'h",
        "Cap Ferret": "Cap Ferret",
        "La Cotinière": "Cotinière",
        "Saint-Jean-de-Luz": "St-Jean-Luz",
        "Biarritz Grande Plage": "Biarritz",
        "Chassiron": "Chassiron"
    ]

    // Check for known abbreviation
    if let abbrev = knownAbbreviations[name] {
        return abbrev
    }

    // Generate initials from words
    let words = name.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-'")))
        .filter { !$0.isEmpty }

    // Filter out common articles/prepositions for cleaner initials
    let skipWords = Set(["de", "du", "des", "le", "la", "les", "l", "d"])
    let significantWords = words.filter { !skipWords.contains($0.lowercased()) }

    if significantWords.count >= 2 {
        // Create initials from significant words
        let initials = significantWords.compactMap { $0.first?.uppercased() }.joined()
        if initials.count >= 2 && initials.count <= 4 {
            return initials
        }
    }

    // Fallback: truncate with ellipsis
    let truncated = String(name.prefix(maxLength - 1))
    return truncated + "…"
}

// MARK: - Color Helper

private func waveColor(_ hm0: Double?) -> Color {
    guard let hm0 = hm0 else { return .gray }
    switch hm0 {
    case ..<0.5:
        return Color(hex: "7EC8E3") // Light blue
    case ..<1.0:
        return Color(hex: "50D4D4") // Cyan
    case ..<1.5:
        return Color(hex: "50D4AA") // Teal
    case ..<2.0:
        return Color(hex: "FFDA47") // Yellow
    case ..<2.5:
        return Color(hex: "FF9F43") // Orange
    case ..<3.0:
        return Color(hex: "FF6B6B") // Red
    default:
        return Color(hex: "C56CF0") // Purple
    }
}

// MARK: - Widget Configuration

struct WaveWidget: Widget {
    let kind: String = "WaveWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WaveProvider()) { entry in
            if #available(iOS 17.0, *) {
                WaveWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) { Color.clear }
            } else {
                WaveWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Houle")
        .description("Hauteur et période des vagues en temps réel")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Data Fetcher

actor WaveWidgetDataFetcher {
    static let shared = WaveWidgetDataFetcher()

    private init() {}

    func refreshData() async -> [WidgetWaveBuoyData] {
        let buoys = AppGroupManager.shared.loadWaveBuoysForWidget()
        guard !buoys.isEmpty else { return [] }

        var updatedBuoys: [WidgetWaveBuoyData] = []

        // Fetch fresh data from CANDHIS API
        for buoy in buoys {
            if let updated = await fetchBuoyData(buoy: buoy) {
                updatedBuoys.append(updated)
            } else {
                updatedBuoys.append(buoy)
            }
        }

        if !updatedBuoys.isEmpty {
            AppGroupManager.shared.saveWaveBuoysForWidget(updatedBuoys)
        }

        return updatedBuoys
    }

    private func fetchBuoyData(buoy: WidgetWaveBuoyData) async -> WidgetWaveBuoyData? {
        let urlString = "https://api.levent.live/api/candhis?id=\(buoy.id)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            var req = URLRequest(url: url)
            req.setValue("lv_R3POazDkm6rvLC5NKFNeTOwEu2oDnoN5", forHTTPHeaderField: "X-Api-Key")
            let (data, _) = try await URLSession.shared.data(for: req)
            let response = try JSONDecoder().decode(CANDHISWidgetResponse.self, from: data)

            guard let buoyData = response.buoys.first else { return nil }

            return WidgetWaveBuoyData(
                id: buoy.id,
                name: buoy.name,
                region: buoy.region,
                hm0: buoyData.hm0,
                tp: buoyData.tp,
                direction: buoyData.direction,
                seaTemp: buoyData.seaTemp,
                isOnline: buoyData.status == "TOTALE" || buoyData.status == "LIMITE",
                lastUpdate: Date()
            )
        } catch {
            return nil
        }
    }
}

// MARK: - API Response

private struct CANDHISWidgetResponse: Decodable {
    let buoys: [CANDHISWidgetBuoy]
}

private struct CANDHISWidgetBuoy: Decodable {
    let id: String
    let hm0: Double?
    let tp: Double?
    let direction: Double?
    let seaTemp: Double?
    let status: String?
}

// MARK: - Previews

#Preview("Wave Small", as: .systemSmall) {
    WaveWidget()
} timeline: {
    WaveEntry(date: .now, buoys: [
        WidgetWaveBuoyData(id: "1", name: "Les Pierres Noires", region: "Bretagne", hm0: 1.8, tp: 10, direction: 280, seaTemp: 14.5, isOnline: true, lastUpdate: Date())
    ], config: AnemWidgetConfig())
}

#Preview("Wave Medium", as: .systemMedium) {
    WaveWidget()
} timeline: {
    WaveEntry(date: .now, buoys: [
        WidgetWaveBuoyData(id: "1", name: "Pierres Noires", region: "Bretagne", hm0: 1.8, tp: 10, direction: 280, seaTemp: 14.5, isOnline: true, lastUpdate: Date()),
        WidgetWaveBuoyData(id: "2", name: "Île d'Yeu", region: "Vendée", hm0: 1.2, tp: 8, direction: 270, seaTemp: 15.2, isOnline: true, lastUpdate: Date()),
        WidgetWaveBuoyData(id: "3", name: "Cap Ferret", region: "Aquitaine", hm0: 2.4, tp: 12, direction: 290, seaTemp: 16.0, isOnline: true, lastUpdate: Date())
    ], config: AnemWidgetConfig())
}

#Preview("Wave Lock Circular", as: .accessoryCircular) {
    WaveWidget()
} timeline: {
    WaveEntry(date: .now, buoys: [
        WidgetWaveBuoyData(id: "1", name: "Pierres Noires", region: "Bretagne", hm0: 1.8, tp: 10, direction: 280, seaTemp: 14.5, isOnline: true, lastUpdate: Date())
    ], config: AnemWidgetConfig())
}

#Preview("Wave Lock Rectangular", as: .accessoryRectangular) {
    WaveWidget()
} timeline: {
    WaveEntry(date: .now, buoys: [
        WidgetWaveBuoyData(id: "1", name: "Pierres Noires", region: "Bretagne", hm0: 1.8, tp: 10, direction: 280, seaTemp: 14.5, isOnline: true, lastUpdate: Date())
    ], config: AnemWidgetConfig())
}
