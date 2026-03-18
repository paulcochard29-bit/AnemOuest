import SwiftUI
import Charts

// MARK: - Chart Data Point

struct ChartDataPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let type: String
}

// MARK: - Wind Chart with Tooltip

struct WindChartWithTooltip: View {
    let samples: [WCChartSample]
    @Binding var touchX: Date?
    @Binding var touchWind: Double?
    @Binding var touchGust: Double?
    @Binding var touchDir: Double?

    private var windSamples: [WCChartSample] {
        samples.filter { $0.kind == .wind && $0.value.isFinite && $0.value >= 0 && $0.value <= 80 }
    }

    private var gustSamples: [WCChartSample] {
        samples.filter { $0.kind == .gust && $0.value.isFinite && $0.value >= 0 && $0.value <= 80 }
    }

    private var dirSamples: [WCChartSample] {
        samples.filter { $0.kind == .dir && $0.value.isFinite && $0.value >= 0 && $0.value <= 360 }
    }

    /// Midnight boundaries within the data range (for day separators)
    private var midnights: [Date] {
        guard let first = windSamples.first?.t, let last = windSamples.last?.t else { return [] }
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

    private var spansMultipleDays: Bool { !midnights.isEmpty }

    /// Convert a knots value to the current user unit
    private func convertValue(_ knots: Double) -> Double {
        WindUnit.current.convert(fromKnots: knots)
    }

    private var yMax: Double {
        let allValues = samples.filter {
            ($0.kind == .wind || $0.kind == .gust) &&
            $0.value.isFinite && $0.value >= 0 && $0.value <= 80
        }.map { convertValue($0.value) }
        let maxValue = allValues.max() ?? convertValue(20)
        let stride = yStride
        let rounded = ceil(maxValue / stride) * stride
        return max(rounded + stride, convertValue(20))
    }

    private var yStride: Double {
        // Adjust stride based on unit for nice round numbers
        switch WindUnit.current {
        case .knots:
            return 5
        case .kmh:
            return 10
        case .ms:
            return 2
        case .mph:
            return 5
        }
    }

    private let windColor = Color.blue
    private let gustColor = Color.red

    fileprivate static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d"
        return f
    }()

    fileprivate static let tooltipDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    private var hasGustData: Bool {
        guard !gustSamples.isEmpty else { return false }
        // Check if at least one gust value differs from its corresponding wind value
        for g in gustSamples {
            if let w = windSamples.first(where: { $0.t == g.t }), w.value != g.value {
                return true
            }
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(windColor)
                        .frame(width: 8, height: 8)
                    Text("Vent")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if hasGustData {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(gustColor, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .frame(width: 16, height: 2)
                        Text("Rafales")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(WindUnit.current.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Chart
            Chart {
                // Wind area fill
                ForEach(windSamples) { sample in
                    AreaMark(
                        x: .value("Time", sample.t),
                        yStart: .value("Min", 0),
                        yEnd: .value("Wind", convertValue(sample.value)),
                        series: .value("Type", "WindFill")
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [windColor.opacity(0.3), windColor.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Gust line (dashed) — hidden when gust == wind (no distinct gust data)
                if hasGustData {
                    ForEach(gustSamples) { sample in
                        LineMark(
                            x: .value("Time", sample.t),
                            y: .value("Gust", convertValue(sample.value)),
                            series: .value("Type", "Rafales")
                        )
                        .foregroundStyle(gustColor)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }

                // Wind line (solid)
                ForEach(windSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.t),
                        y: .value("Wind", convertValue(sample.value)),
                        series: .value("Type", "Vent")
                    )
                    .foregroundStyle(windColor)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
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

                // Touch cursor
                if let t = touchX {
                    RuleMark(x: .value("Time", t))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))

                    if let windValue = touchWind {
                        PointMark(
                            x: .value("Time", t),
                            y: .value("Wind", convertValue(windValue))
                        )
                        .foregroundStyle(windColor)
                        .symbolSize(100)
                        .symbol(.circle)
                    }
                    if hasGustData, let gustValue = touchGust {
                        PointMark(
                            x: .value("Time", t),
                            y: .value("Gust", convertValue(gustValue))
                        )
                        .foregroundStyle(gustColor)
                        .symbolSize(100)
                        .symbol(.circle)
                    }
                }
            }
            .chartLegend(.hidden)
            .chartYScale(domain: 0...yMax)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .stride(by: yStride)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    guard let plot = proxy.plotFrame else { return }
                                    let frame = geo[plot]
                                    let x = v.location.x - frame.origin.x
                                    let clampedX = min(max(x, 0), frame.width)
                                    if let date: Date = proxy.value(atX: clampedX) {
                                        touchX = date
                                        updateTouchValues(for: date)
                                    }
                                }
                                .onEnded { _ in
                                    touchX = nil
                                    touchWind = nil
                                    touchGust = nil
                                    touchDir = nil
                                }
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.black.opacity(0.15))
            )
            .overlay(alignment: .top) {
                if let t = touchX {
                    ChartTooltip(t: t, w: touchWind, g: touchGust, d: touchDir, showDate: spansMultipleDays)
                        .padding(.top, 8)
                }
            }
        }
    }

    private func updateTouchValues(for date: Date) {
        touchWind = nearestValue(in: windSamples, to: date)
        touchGust = nearestValue(in: gustSamples, to: date)
        touchDir = nearestValue(in: dirSamples, to: date)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.3)
    }

    private func nearestValue(in arr: [WCChartSample], to date: Date) -> Double? {
        guard !arr.isEmpty else { return nil }
        var best = arr[0]
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

// MARK: - Chart Tooltip

struct ChartTooltip: View {
    let t: Date
    let w: Double?
    let g: Double?
    let d: Double?
    var showDate: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(showDate
                 ? WindChartWithTooltip.tooltipDayFormatter.string(from: t)
                 : t.formatted(.dateTime.hour().minute()))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            if let dir = d {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(dir + 180))
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(colorForWind(w))
                    .frame(width: 6, height: 6)
                Text(fmt(w))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(colorForWind(w))
            }

            if let g, g != w {
                HStack(spacing: 4) {
                    Circle()
                        .fill(colorForWind(g))
                        .frame(width: 6, height: 6)
                    Text(fmt(g))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(colorForWind(g))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "--" }
        return "\(WindUnit.convertValue(v))"
    }

    private func colorForWind(_ v: Double?) -> Color {
        guard let v else { return .secondary }
        return windScale(v)
    }
}

// MARK: - Simple Tooltip (legacy)

struct Tooltip: View {
    let t: Date
    let w: Double?
    let g: Double?

    var body: some View {
        HStack(spacing: 10) {
            Text(t.formatted(.dateTime.hour().minute()))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(fmt(w))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color(w))

            Text("/")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(fmt(g))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color(g))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 14))
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(WindUnit.convertValue(v))"
    }

    private func color(_ v: Double?) -> Color {
        guard let v else { return .secondary }
        return windScale(v)
    }
}
