import Foundation
import CoreLocation
import SwiftUI
import Combine
import Charts

// MARK: - Wave Buoy Model

struct WaveBuoy: Identifiable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let depth: Int              // Depth in meters
    let status: BuoyStatus
    let region: String

    // Real-time wave data (optional)
    var hm0: Double?            // Significant wave height (meters)
    var hmax: Double?           // Maximum wave height (meters)
    var tp: Double?             // Peak period (seconds)
    var direction: Double?      // Wave direction (degrees)
    var spread: Double?         // Spread at peak (degrees)
    var seaTemp: Double?        // Sea temperature (°C)
    var lastUpdate: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Formatted wave height display (e.g. "1.5m")
    var waveHeightDisplay: String {
        guard let hm0 = hm0 else { return "—" }
        return String(format: "%.1fm", hm0)
    }

    /// Formatted period display (e.g. "8s")
    var periodDisplay: String {
        guard let tp = tp else { return "" }
        return String(format: "%.1fs", tp)
    }

    /// Color based on wave height (similar to wind scale)
    var waveColor: Color {
        guard let hm0 = hm0 else { return .gray }
        switch hm0 {
        case ..<0.5:
            return Color(red: 0.70, green: 0.93, blue: 1.00) // Light blue - calm
        case ..<1.0:
            return Color(red: 0.33, green: 0.85, blue: 0.92) // Cyan
        case ..<1.5:
            return Color(red: 0.35, green: 0.89, blue: 0.52) // Green
        case ..<2.0:
            return Color(red: 0.97, green: 0.90, blue: 0.33) // Yellow
        case ..<2.5:
            return Color(red: 0.98, green: 0.67, blue: 0.23) // Orange
        case ..<3.0:
            return Color(red: 0.95, green: 0.22, blue: 0.26) // Red
        case ..<4.0:
            return Color(red: 0.83, green: 0.20, blue: 0.67) // Pink
        default:
            return Color(red: 0.55, green: 0.24, blue: 0.78) // Purple - very rough
        }
    }

    /// UIColor version for MapKit annotations
    var waveUIColor: UIColor {
        guard let hm0 = hm0 else { return .gray }
        switch hm0 {
        case ..<0.5:
            return UIColor(red: 0.70, green: 0.93, blue: 1.00, alpha: 1)
        case ..<1.0:
            return UIColor(red: 0.33, green: 0.85, blue: 0.92, alpha: 1)
        case ..<1.5:
            return UIColor(red: 0.35, green: 0.89, blue: 0.52, alpha: 1)
        case ..<2.0:
            return UIColor(red: 0.97, green: 0.90, blue: 0.33, alpha: 1)
        case ..<2.5:
            return UIColor(red: 0.98, green: 0.67, blue: 0.23, alpha: 1)
        case ..<3.0:
            return UIColor(red: 0.95, green: 0.22, blue: 0.26, alpha: 1)
        case ..<4.0:
            return UIColor(red: 0.83, green: 0.20, blue: 0.67, alpha: 1)
        default:
            return UIColor(red: 0.55, green: 0.24, blue: 0.78, alpha: 1)
        }
    }

    static func == (lhs: WaveBuoy, rhs: WaveBuoy) -> Bool {
        lhs.id == rhs.id
    }
}

enum BuoyStatus: String, Codable {
    case active = "TOTALE"      // Real-time data available
    case limited = "LIMITE"     // Limited data
    case offline = "AUCUNE"     // No data

    var isOnline: Bool {
        self == .active || self == .limited
    }
}

// MARK: - Wave History Model

struct WaveHistoryPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let hm0: Double          // Significant wave height
    let hmax: Double?        // Maximum wave height
    let tp: Double?          // Peak period
}

// MARK: - API Response Models

private struct CANDHISResponse: Decodable {
    let buoys: [CANDHISBuoy]
    let count: Int
    let timestamp: String
}

private struct CANDHISBuoyWithHistory: Decodable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let depth: Int
    let status: String
    let region: String
    let hm0: Double?
    let tp: Double?
    let hmax: Double?
    let lastUpdate: String?
    let history: [CANDHISHistoryPoint]?
}

private struct CANDHISHistoryPoint: Decodable {
    let timestamp: String
    let hm0: Double
    let hmax: Double?
    let tp: Double?
}

private struct CANDHISBuoy: Decodable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let depth: Int
    let status: String
    let region: String
    let hm0: Double?
    let hmax: Double?
    let tp: Double?
    let direction: Double?
    let spread: Double?
    let seaTemp: Double?
    let lastUpdate: String?
}

// MARK: - Wave Buoy Service

@MainActor
final class WaveBuoyService: ObservableObject {
    static let shared = WaveBuoyService()

    @Published var buoys: [WaveBuoy] = []
    @Published var isLoading: Bool = false
    @Published var lastError: Error? = nil

    private let apiBaseUrl = "https://api.levent.live/api"

    private init() {}

    func fetchBuoys() async {
        isLoading = true
        lastError = nil

        do {
            guard let url = URL(string: "\(apiBaseUrl)/candhis") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(CANDHISResponse.self, from: data)

            let dateFormatter = ISO8601DateFormatter()

            var parsedBuoys = response.buoys.map { buoy -> WaveBuoy in
                let status: BuoyStatus
                switch buoy.status {
                case "TOTALE": status = .active
                case "LIMITE": status = .limited
                default: status = .offline
                }

                let lastUpdate: Date?
                if let dateStr = buoy.lastUpdate {
                    lastUpdate = dateFormatter.date(from: dateStr)
                } else {
                    lastUpdate = nil
                }

                return WaveBuoy(
                    id: buoy.id,
                    name: buoy.name,
                    latitude: buoy.lat,
                    longitude: buoy.lon,
                    depth: buoy.depth,
                    status: status,
                    region: buoy.region,
                    hm0: buoy.hm0,
                    hmax: buoy.hmax,
                    tp: buoy.tp,
                    direction: buoy.direction,
                    spread: buoy.spread,
                    seaTemp: buoy.seaTemp,
                    lastUpdate: lastUpdate
                )
            }

            buoys = parsedBuoys
            isLoading = false

            // Trigger wave accuracy comparisons in background
            let activeBuoysForAccuracy = parsedBuoys.filter { $0.hm0 != nil }
            Task.detached {
                for buoy in activeBuoysForAccuracy {
                    guard let hm0 = buoy.hm0 else { continue }
                    WaveForecastAccuracyService.shared.compareWithActual(
                        buoyId: buoy.id,
                        latitude: buoy.latitude,
                        longitude: buoy.longitude,
                        actualHeight: hm0,
                        actualPeriod: buoy.tp ?? 0,
                        actualDirection: buoy.direction ?? 0
                    )
                }
            }
        } catch {
            lastError = error
            isLoading = false
            Log.error("WaveBuoyService error: \(error)")
        }
    }

    /// Filter buoys by region
    func buoys(in regions: [String]) -> [WaveBuoy] {
        if regions.isEmpty { return buoys }
        return buoys.filter { regions.contains($0.region) }
    }

    /// Get active buoys only
    var activeBuoys: [WaveBuoy] {
        buoys.filter { $0.status.isOnline }
    }

    /// Fetch history for a specific buoy
    func fetchHistory(buoyId: String) async -> [WaveHistoryPoint] {
        // 1. Try Vercel API cache first
        let apiPoints = await fetchHistoryFromAPI(buoyId: buoyId)
        if !apiPoints.isEmpty {
            return apiPoints
        }

        // 2. Fallback: scrape CANDHIS directly from iOS and push to Vercel
        Log.network("WaveBuoyService: No history in cache, scraping CANDHIS directly for \(buoyId)")
        return await scrapeAndPushHistory(buoyId: buoyId)
    }

    private func fetchHistoryFromAPI(buoyId: String) async -> [WaveHistoryPoint] {
        do {
            guard let url = URL(string: "\(apiBaseUrl)/candhis?id=\(buoyId)&history=true") else { return [] }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")
            let (data, _) = try await URLSession.shared.data(for: request)
            return parseHistoryResponse(data: data)
        } catch {
            Log.network("WaveBuoyService: API history failed: \(error.localizedDescription)")
            return []
        }
    }

    private func scrapeAndPushHistory(buoyId: String) async -> [WaveHistoryPoint] {
        do {
            // Fetch CANDHIS HTML directly (works from iOS, not from Vercel)
            let campParam = Data("camp=\(buoyId)".utf8).base64EncodedString()
            guard let url = URL(string: "https://candhis.cerema.fr/_public_/campagne.php?\(campParam)") else { return [] }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
            request.setValue("fr-FR,fr;q=0.9", forHTTPHeaderField: "Accept-Language")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }
            guard let html = String(data: data, encoding: .utf8), html.count > 1000 else { return [] }
            guard html.contains("arrDataPHP") else {
                Log.network("WaveBuoyService: CANDHIS HTML has no arrDataPHP for \(buoyId)")
                return []
            }

            // POST the HTML to Vercel for server-side parsing and caching
            guard let pushUrl = URL(string: "\(apiBaseUrl)/candhis") else { return [] }
            var pushRequest = URLRequest(url: pushUrl)
            pushRequest.httpMethod = "POST"
            pushRequest.timeoutInterval = 30
            pushRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            pushRequest.setValue(AppConstants.API.key, forHTTPHeaderField: "X-Api-Key")

            let body: [String: String] = ["id": buoyId, "html": html]
            pushRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (pushData, pushResponse) = try await URLSession.shared.data(for: pushRequest)
            guard let pushHttp = pushResponse as? HTTPURLResponse, pushHttp.statusCode == 200 else {
                Log.network("WaveBuoyService: Push failed with status \((pushResponse as? HTTPURLResponse)?.statusCode ?? 0)")
                return []
            }

            let points = parseHistoryResponse(data: pushData)
            Log.network("WaveBuoyService: Scraped & pushed \(points.count) history points for \(buoyId)")
            return points
        } catch {
            Log.network("WaveBuoyService: CANDHIS scrape failed: \(error.localizedDescription)")
            return []
        }
    }

    private func parseHistoryResponse(data: Data) -> [WaveHistoryPoint] {
        guard let response = try? JSONDecoder().decode(CANDHISBuoyWithHistory.self, from: data) else { return [] }
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        guard let historyData = response.history, !historyData.isEmpty else { return [] }
        return historyData.compactMap { point -> WaveHistoryPoint? in
            let date = dateFormatter.date(from: point.timestamp) ?? fallbackFormatter.date(from: point.timestamp)
            guard let validDate = date else { return nil }
            return WaveHistoryPoint(timestamp: validDate, hm0: point.hm0, hmax: point.hmax, tp: point.tp)
        }.sorted { $0.timestamp < $1.timestamp }
    }

}

// MARK: - Wave Buoy Detail View

struct WaveBuoyDetailView: View {
    let buoy: WaveBuoy

    @State private var history: [WaveHistoryPoint] = []
    @State private var isLoadingHistory = false

    // Touch selection state
    @State private var selectedDate: Date?
    @State private var selectedHm0: Double?
    @State private var selectedHmax: Double?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Wave height card
                    if let hm0 = buoy.hm0 {
                        waveHeightCard(hm0: hm0)
                    } else {
                        noDataCard
                    }

                    // Wave history chart
                    waveHistoryChart

                    // Details grid
                    detailsGrid

                    // Info section
                    infoSection
                }
                .padding()
            }
            .navigationTitle(buoy.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    statusBadge
                }
            }
            .task {
                await loadHistory()
            }
        }
    }

    private func loadHistory() async {
        isLoadingHistory = true
        history = await WaveBuoyService.shared.fetchHistory(buoyId: buoy.id)
        isLoadingHistory = false
    }

    private let hm0Color = Color.cyan
    private let hmaxColor = Color.orange

    @ViewBuilder
    private var waveHistoryChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with selection display
            HStack {
                if let date = selectedDate {
                    // Show selected values
                    HStack(spacing: 12) {
                        Text(date.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "fr_FR"))))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        if let hm0 = selectedHm0 {
                            HStack(spacing: 4) {
                                Circle().fill(hm0Color).frame(width: 6, height: 6)
                                Text(String(format: "%.1fm", hm0))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(hm0Color)
                            }
                        }

                        if let hmax = selectedHmax {
                            HStack(spacing: 4) {
                                Circle().fill(hmaxColor).frame(width: 6, height: 6)
                                Text(String(format: "%.1fm", hmax))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(hmaxColor)
                            }
                        }
                    }
                } else {
                    Label("Historique 48h", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                if isLoadingHistory {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if history.isEmpty && !isLoadingHistory {
                HStack {
                    Spacer()
                    Text("Historique non disponible")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 150)
            } else if !history.isEmpty {
                Chart {
                    // Area fill for Hm0
                    ForEach(history) { point in
                        AreaMark(
                            x: .value("Heure", point.timestamp),
                            yStart: .value("Min", 0),
                            yEnd: .value("Hm0", point.hm0),
                            series: .value("Type", "Hm0Fill")
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [hm0Color.opacity(0.3), hm0Color.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    // Hmax line (orange dashed)
                    ForEach(history.filter { $0.hmax != nil }) { point in
                        LineMark(
                            x: .value("Heure", point.timestamp),
                            y: .value("Hmax", point.hmax!),
                            series: .value("Type", "Hmax")
                        )
                        .foregroundStyle(hmaxColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.catmullRom)
                    }

                    // Hm0 line (cyan solid)
                    ForEach(history) { point in
                        LineMark(
                            x: .value("Heure", point.timestamp),
                            y: .value("Hm0", point.hm0),
                            series: .value("Type", "Hm0")
                        )
                        .foregroundStyle(hm0Color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }

                    // Selection cursor
                    if let date = selectedDate {
                        RuleMark(x: .value("Time", date))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))

                        if let hm0 = selectedHm0 {
                            PointMark(
                                x: .value("Time", date),
                                y: .value("Hm0", hm0)
                            )
                            .foregroundStyle(hm0Color)
                            .symbolSize(80)
                        }

                        if let hmax = selectedHmax {
                            PointMark(
                                x: .value("Time", date),
                                y: .value("Hmax", hmax)
                            )
                            .foregroundStyle(hmaxColor)
                            .symbolSize(80)
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 12)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel(format: .dateTime.hour())
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let frame = geo[plotFrame]
                                        let x = value.location.x - frame.origin.x
                                        let clampedX = min(max(x, 0), frame.width)
                                        if let date: Date = proxy.value(atX: clampedX) {
                                            selectedDate = date
                                            updateSelectedValues(for: date)
                                        }
                                    }
                                    .onEnded { _ in
                                        selectedDate = nil
                                        selectedHm0 = nil
                                        selectedHmax = nil
                                    }
                            )
                    }
                }
                .frame(height: 180)

                // Legend
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(hm0Color).frame(width: 8, height: 8)
                        Text("Hm0").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(hmaxColor, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .frame(width: 16, height: 2)
                        Text("Hmax").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private func updateSelectedValues(for date: Date) {
        // Find nearest point
        guard !history.isEmpty else { return }

        var nearest = history[0]
        var minDist = abs(history[0].timestamp.timeIntervalSince(date))

        for point in history {
            let dist = abs(point.timestamp.timeIntervalSince(date))
            if dist < minDist {
                minDist = dist
                nearest = point
            }
        }

        selectedHm0 = nearest.hm0
        selectedHmax = nearest.hmax

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.3)
    }

    private func waveHeightCard(hm0: Double) -> some View {
        VStack(spacing: 8) {
            Text("Hauteur significative")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", hm0))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(buoy.waveColor)
                Text("m")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }

            if let tp = buoy.tp {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text("Période: \(String(format: "%.1f", tp))s")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private var noDataCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "water.waves.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Données non disponibles")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private var detailsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            if let hmax = buoy.hmax {
                detailCard(
                    icon: "arrow.up.to.line",
                    title: "Hmax",
                    value: String(format: "%.1f m", hmax)
                )
            }

            // Energy: E = (ρ × g × Hm0²) / 16, ρ=1025 kg/m³, g=9.81 m/s²
            if let hm0 = buoy.hm0 {
                let energyKJ = (1025.0 * 9.81 * hm0 * hm0) / 16.0 / 1000.0
                detailCard(
                    icon: "bolt.fill",
                    title: "Énergie",
                    value: String(format: "%.1f kJ/m²", energyKJ)
                )
            }

            if let direction = buoy.direction {
                detailCard(
                    icon: "location.north.fill",
                    title: "Direction",
                    value: "\(Int(direction))°",
                    iconRotation: direction
                )
            }

            if let seaTemp = buoy.seaTemp {
                detailCard(
                    icon: "thermometer.medium",
                    title: "Temp. mer",
                    value: String(format: "%.1f°C", seaTemp)
                )
            }

            detailCard(
                icon: "arrow.down.to.line",
                title: "Profondeur",
                value: "\(buoy.depth)m"
            )

            detailCard(
                icon: "mappin.circle.fill",
                title: "Région",
                value: buoy.region.capitalized
            )
        }
    }

    private func detailCard(icon: String, title: String, value: String, iconRotation: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(iconRotation ?? 0))
                Spacer()
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("CANDHIS - Cerema", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Données houlographiques temps réel")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let lastUpdate = buoy.lastUpdate {
                Text("Mise à jour: \(lastUpdate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(buoy.status.isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(buoy.status.isOnline ? "En ligne" : "Hors ligne")
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .modifier(LiquidGlassCapsuleModifier())
    }
}
