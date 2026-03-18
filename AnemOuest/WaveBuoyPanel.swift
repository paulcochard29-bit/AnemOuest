import SwiftUI
import Charts

// MARK: - Wave Buoy Bottom Panel

struct WaveBuoyBottomPanel: View {
    let buoy: WaveBuoy
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onClose: () -> Void

    @State private var history: [WaveHistoryPoint] = []
    @State private var isLoadingHistory = false
    @State private var waveTimeFrame: Int = 48  // hours

    // Touch selection state
    @State private var selectedDate: Date?
    @State private var selectedHm0: Double?
    @State private var selectedHmax: Double?
    @GestureState private var dragOffset: CGFloat = 0
    @State private var showShareSheet = false
    @State private var showWaveForecastComparison = false
    @State private var isInteractingWithChart = false

    private let hm0Color = Color.cyan
    private let hmaxColor = Color.orange

    /// Midnight boundaries within the data range (for day separators)
    private var midnights: [Date] {
        guard let first = filteredHistory.first?.timestamp, let last = filteredHistory.last?.timestamp else { return [] }
        let cal = Calendar.current
        var date = cal.startOfDay(for: first)
        if date <= first { date = cal.date(byAdding: .day, value: 1, to: date)! }
        var results: [Date] = []
        while date < last {
            results.append(date)
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        return results
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d"
        return f
    }()

    private var filteredHistory: [WaveHistoryPoint] {
        let cutoff = Date().addingTimeInterval(-Double(waveTimeFrame) * 3600)
        return history.filter { $0.timestamp >= cutoff }
    }

    private var xAxisStride: Int {
        switch waveTimeFrame {
        case 2:  return 1
        case 6:  return 2
        case 24: return 6
        default: return 12
        }
    }

    private func seaTempColor(_ temp: Double) -> Color {
        switch temp {
        case ..<10: return .blue
        case ..<14: return .cyan
        case ..<18: return .teal
        case ..<22: return .green
        case ..<26: return .orange
        default: return .red
        }
    }

    private var measurementAgo: String? {
        guard let date = buoy.lastUpdate else { return nil }
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

    var body: some View {
        VStack(spacing: 12) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 4)

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(buoy.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(buoy.status.isOnline ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text("CANDHIS")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        if let ago = measurementAgo {
                            Text("• \(ago)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }

                        Button {
                            showWaveForecastComparison = true
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

                Spacer()

                Button { showShareSheet = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)

                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            // Stats cards - row 1
            HStack(spacing: 10) {
                WaveStatCard(title: "Hm0", value: buoy.hm0.map { String(format: "%.1f m", $0) } ?? "—", color: hm0Color)
                WaveStatCard(title: "Hmax", value: buoy.hmax.map { String(format: "%.1f m", $0) } ?? "—", color: .orange)
                WaveStatCard(title: "Période", value: buoy.tp.map { String(format: "%.1f s", $0) } ?? "—", color: .primary)
            }

            // Stats cards - row 2
            HStack(spacing: 10) {
                if let dir = buoy.direction {
                    WaveStatCardWithArrow(title: "Direction", value: "\(Int(dir))°", direction: dir, color: .blue)
                } else {
                    WaveStatCard(title: "Direction", value: "—", color: .primary)
                }

                if let hm0 = buoy.hm0 {
                    let energyJm2 = (1025.0 * 9.81 * hm0 * hm0) / 16.0
                    let energyKJ = energyJm2 / 1000.0
                    WaveStatCard(title: "Énergie", value: String(format: "%.1f kJ", energyKJ), color: .yellow)
                } else {
                    WaveStatCard(title: "Énergie", value: "—", color: .primary)
                }

                if let temp = buoy.seaTemp {
                    WaveStatCard(title: "Temp. eau", value: String(format: "%.1f°C", temp), color: seaTempColor(temp))
                } else {
                    WaveStatCard(title: "Temp. eau", value: "—", color: .primary)
                }
            }

            // Wave history chart
            waveHistoryChart
        }
        .padding(14)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 22))
        .shadow(radius: 14)
        .offset(y: max(0, dragOffset))
        .simultaneousGesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    guard !isInteractingWithChart else { return }
                    if value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width) * 2 {
                        state = value.translation.height
                    }
                }
                .onEnded { value in
                    guard !isInteractingWithChart else { return }
                    if value.translation.height > 50 && abs(value.translation.height) > abs(value.translation.width) * 2 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            onClose()
                        }
                    }
                }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            await loadHistory()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareWaveSheet(buoy: buoy, history: history)
        }
        .sheet(isPresented: $showWaveForecastComparison) {
            WaveForecastComparisonView(
                buoyName: buoy.name,
                buoyId: buoy.id,
                latitude: buoy.latitude,
                longitude: buoy.longitude,
                fallbackHistory: history
            )
        }
    }

    private func loadHistory() async {
        isLoadingHistory = true
        history = await WaveBuoyService.shared.fetchHistory(buoyId: buoy.id)
        isLoadingHistory = false
    }

    @ViewBuilder
    private var waveHistoryChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Période", selection: $waveTimeFrame) {
                Text("2 h").tag(2)
                Text("6 h").tag(6)
                Text("24 h").tag(24)
                Text("48 h").tag(48)
            }
            .pickerStyle(.segmented)

            HStack {
                if let date = selectedDate {
                    HStack(spacing: 12) {
                        Text(date.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "fr_FR"))))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        if let hm0 = selectedHm0 {
                            HStack(spacing: 4) {
                                Circle().fill(hm0Color).frame(width: 6, height: 6)
                                Text(String(format: "%.1fm", hm0))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(hm0Color)
                            }
                        }

                        if let hmax = selectedHmax {
                            HStack(spacing: 4) {
                                Circle().fill(hmaxColor).frame(width: 6, height: 6)
                                Text(String(format: "%.1fm", hmax))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(hmaxColor)
                            }
                        }
                    }
                } else {
                    Text("Historique")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoadingHistory {
                    ProgressView()
                        .scaleEffect(0.7)
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
                .frame(height: 120)
            } else if !filteredHistory.isEmpty {
                Chart {
                    ForEach(filteredHistory) { point in
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

                    ForEach(filteredHistory.filter { $0.hmax != nil }) { point in
                        LineMark(
                            x: .value("Heure", point.timestamp),
                            y: .value("Hmax", point.hmax!),
                            series: .value("Type", "Hmax")
                        )
                        .foregroundStyle(hmaxColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(filteredHistory) { point in
                        LineMark(
                            x: .value("Heure", point.timestamp),
                            y: .value("Hm0", point.hm0),
                            series: .value("Type", "Hm0")
                        )
                        .foregroundStyle(hm0Color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }

                    // Day separators at midnight
                    ForEach(midnights, id: \.self) { midnight in
                        RuleMark(x: .value("Midnight", midnight))
                            .foregroundStyle(.white.opacity(0.25))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                Text(Self.dayFormatter.string(from: midnight).uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                    }

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
                    AxisMarks(values: .stride(by: .hour, count: xAxisStride)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel(format: waveTimeFrame <= 6 ? .dateTime.hour().minute() : .dateTime.hour())
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.1))
                        AxisValueLabel()
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isInteractingWithChart = true
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
                                        isInteractingWithChart = false
                                        selectedDate = nil
                                        selectedHm0 = nil
                                        selectedHmax = nil
                                    }
                            )
                    }
                }
                .frame(height: 140)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.15))
                )

                // Legend
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(hm0Color).frame(width: 6, height: 6)
                        Text("Hm0").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(hmaxColor, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .frame(width: 14, height: 2)
                        Text("Hmax").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private static let chartHaptic: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()

    private func updateSelectedValues(for date: Date) {
        let data = filteredHistory
        guard !data.isEmpty else { return }

        // Binary-ish nearest lookup (data is sorted by timestamp)
        var nearest = data[0]
        var minDist = abs(data[0].timestamp.timeIntervalSince(date))

        for point in data {
            let dist = abs(point.timestamp.timeIntervalSince(date))
            if dist < minDist {
                minDist = dist
                nearest = point
            } else if dist > minDist {
                break // Data is sorted, so we've passed the nearest point
            }
        }

        let oldHm0 = selectedHm0
        selectedHm0 = nearest.hm0
        selectedHmax = nearest.hmax

        // Only haptic when value changes
        if oldHm0 != nearest.hm0 {
            Self.chartHaptic.impactOccurred(intensity: 0.3)
            Self.chartHaptic.prepare()
        }
    }
}

// MARK: - Wave Chart Tooltip

struct WaveChartTooltip: View {
    let date: Date
    let hm0: Double?
    let hmax: Double?
    let hm0Color: Color
    let hmaxColor: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(date.formatted(.dateTime.hour().minute()))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            if let hm0 = hm0 {
                HStack(spacing: 4) {
                    Circle().fill(hm0Color).frame(width: 6, height: 6)
                    Text(String(format: "%.1fm", hm0))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(hm0Color)
                }
            }

            if let hmax = hmax {
                HStack(spacing: 4) {
                    Circle().fill(hmaxColor).frame(width: 6, height: 6)
                    Text(String(format: "%.1fm", hmax))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(hmaxColor)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Wave Stat Cards

struct WaveStatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.15), lineWidth: 1)
        )
    }
}

struct WaveStatCardWithArrow: View {
    let title: String
    let value: String
    let direction: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(direction + 180))
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.15), lineWidth: 1)
        )
    }
}
