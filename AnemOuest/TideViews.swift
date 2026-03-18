import SwiftUI
import Charts

// MARK: - Tide Widget (compact overlay)

struct TideWidget: View {
    let tideData: TideData
    let onTap: () -> Void

    private var nextTide: (type: String, time: Date, height: Double, coefficient: Int?)? {
        tideData.nextTide
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                // Port name
                Text(tideData.port.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    // Tide icon
                    Image(systemName: nextTide?.type == "high" ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(nextTide?.type == "high" ? .blue : .cyan)

                    VStack(alignment: .leading, spacing: 1) {
                        // Next tide time
                        if let next = nextTide {
                            HStack(spacing: 4) {
                                Text(next.type == "high" ? "PM" : "BM")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(next.type == "high" ? .blue : .cyan)
                                Text(timeFormatter.string(from: next.time))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                        }

                        // Coefficient
                        if let coef = tideData.todayCoefficient {
                            HStack(spacing: 3) {
                                Text("Coef")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text("\(coef)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(coefficientColor(coef))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .modifier(LiquidGlassRoundedModifier(cornerRadius: 12, useGlassEffect: true))
        }
        .buttonStyle(.plain)
    }

    private func coefficientColor(_ coef: Int) -> Color {
        switch coef {
        case ..<40: return .blue
        case ..<70: return .green
        case ..<95: return .orange
        default: return .red
        }
    }
}

// MARK: - Tide Detail View (full sheet)

struct TideDetailView: View {
    let initialTideData: TideData?
    @ObservedObject var tideService: TideService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPortIndex: Int = 0

    private var ports: [TidePort] { tideService.ports }

    // Always use service data when available (updated when port changes)
    // Service data is set on first load and updated when changing ports
    private var tideData: TideData? {
        tideService.currentTideData
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Port selector (always visible)
                    portSelector

                    if tideService.isLoading {
                        ProgressView("Chargement...")
                            .padding(.top, 40)
                    } else if let data = tideData {
                        // Today's coefficient card
                        coefficientCard(data)

                        // Next tides summary
                        nextTidesCard(data)

                        // Today's tides
                        todayTidesCard(data)

                        // Week overview
                        weekOverview(data)
                    } else {
                        ProgressView()
                            .padding(.top, 40)
                    }
                }
                .padding()
            }
            .navigationTitle("Marees")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if tideService.ports.isEmpty {
                Task {
                    _ = await tideService.fetchPorts()
                }
            }
        }
    }

    // MARK: - Port Selector

    private var portSelector: some View {
        HStack {
            Text("Port de reference")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if !ports.isEmpty {
                Menu {
                    ForEach(ports) { port in
                        Button(port.name) {
                            Task {
                                _ = await tideService.fetchTideData(for: port, duration: 11)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(tideData?.port.name ?? "Brest")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }

    // MARK: - Coefficient Card

    private func coefficientCard(_ data: TideData) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Coefficient du jour")
                    .font(.headline)
                Spacer()
            }

            if let coef = data.todayCoefficient {
                HStack(alignment: .bottom, spacing: 12) {
                    Text("\(coef)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(coefficientGradient(coef))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(coef.coefficientDescription)
                            .font(.subheadline.weight(.medium))
                        Text(dateFormatter.string(from: Date()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                Text("Non disponible")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private func coefficientGradient(_ coef: Int) -> LinearGradient {
        let colors: [Color]
        switch coef {
        case ..<40: colors = [.blue, .cyan]
        case ..<70: colors = [.green, .teal]
        case ..<95: colors = [.orange, .yellow]
        default: colors = [.red, .orange]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Next Tides Card

    private func nextTidesCard(_ data: TideData) -> some View {
        let lowFirst: Bool = {
            guard let lowTime = data.nextLowTide?.parsedTime,
                  let highTime = data.nextHighTide?.parsedTime else {
                return data.nextLowTide != nil
            }
            return lowTime < highTime
        }()

        return HStack(spacing: 12) {
            if lowFirst {
                if let nextLow = data.nextLowTide {
                    nextTideBox(
                        type: "Basse mer",
                        icon: "arrow.down.circle.fill",
                        color: .cyan,
                        time: nextLow.timeDisplay,
                        height: String(format: "%.2fm", nextLow.height),
                        coefficient: nil
                    )
                }
                if let nextHigh = data.nextHighTide {
                    nextTideBox(
                        type: "Pleine mer",
                        icon: "arrow.up.circle.fill",
                        color: .blue,
                        time: nextHigh.timeDisplay,
                        height: String(format: "%.2fm", nextHigh.height),
                        coefficient: nextHigh.coefficient
                    )
                }
            } else {
                if let nextHigh = data.nextHighTide {
                    nextTideBox(
                        type: "Pleine mer",
                        icon: "arrow.up.circle.fill",
                        color: .blue,
                        time: nextHigh.timeDisplay,
                        height: String(format: "%.2fm", nextHigh.height),
                        coefficient: nextHigh.coefficient
                    )
                }
                if let nextLow = data.nextLowTide {
                    nextTideBox(
                        type: "Basse mer",
                        icon: "arrow.down.circle.fill",
                        color: .cyan,
                        time: nextLow.timeDisplay,
                        height: String(format: "%.2fm", nextLow.height),
                        coefficient: nil
                    )
                }
            }
        }
    }

    private func nextTideBox(type: String, icon: String, color: Color, time: String, height: String, coefficient: Int?) -> some View {
        VStack(spacing: 10) {
            // Header with icon and type
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
                Text(type)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
            }

            // Time prominently displayed
            HStack(alignment: .firstTextBaseline) {
                Text(time)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
            }

            // Height and coefficient
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hauteur")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(height)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }

                Spacer()

                if let coef = coefficient {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Coef")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(coef)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(coefficientColor(coef))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(color.opacity(0.3), lineWidth: 1)
        )
    }

    private func coefficientColor(_ coef: Int) -> Color {
        switch coef {
        case ..<40: return .blue
        case ..<70: return .green
        case ..<95: return .orange
        default: return .red
        }
    }

    // MARK: - Today's Tides Card

    private func todayTidesCard(_ data: TideData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aujourd'hui")
                .font(.headline)

            ForEach(data.todayTides) { tide in
                HStack {
                    Image(systemName: tide.isHighTide ? "arrow.up" : "arrow.down")
                        .foregroundStyle(tide.isHighTide ? .blue : .cyan)
                        .frame(width: 24)

                    Text(tide.timeDisplay)
                        .font(.system(.body, design: .rounded, weight: .medium))

                    Spacer()

                    Text(tide.heightDisplay)
                        .foregroundStyle(.secondary)

                    if let coef = tide.coefficient {
                        Text("\(coef)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tide.coefficientColor.opacity(0.2))
                            .foregroundStyle(tide.coefficientColor)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)

                if tide.id != data.todayTides.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    // MARK: - Week Overview (Horizontal Scroll)

    private func weekOverview(_ data: TideData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cette semaine")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    TideCalendarView(tideData: data, tideService: tideService)
                } label: {
                    HStack(spacing: 4) {
                        Text("Calendrier")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "calendar")
                    }
                    .foregroundStyle(.cyan)
                }
            }

            // Horizontal scrollable week
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    let groupedTides = Dictionary(grouping: data.tides) { $0.date }
                    let sortedDates = groupedTides.keys.sorted()

                    ForEach(sortedDates.prefix(7), id: \.self) { date in
                        if let tides = groupedTides[date], let parsedDate = parseDate(date) {
                            dayCard(date: parsedDate, tides: tides)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private func dayCard(date: Date, tides: [TideEvent]) -> some View {
        let isCurrentDay = isToday(date)
        let maxCoef = tides.compactMap { $0.coefficient }.max()

        return VStack(spacing: 8) {
            // Day name
            Text(shortDayName(date))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isCurrentDay ? .white : .secondary)

            // Day number
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(isCurrentDay ? .white : .primary)

            // Coefficient badge
            if let coef = maxCoef {
                Text("\(coef)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isCurrentDay ? .white : coefficientColor(coef))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (isCurrentDay ? Color.white.opacity(0.2) : coefficientColor(coef).opacity(0.15)),
                        in: Capsule()
                    )
            }

            Divider()
                .frame(width: 40)
                .opacity(0.3)

            // Tides list
            VStack(spacing: 4) {
                ForEach(tides.prefix(4)) { tide in
                    HStack(spacing: 3) {
                        Image(systemName: tide.isHighTide ? "arrow.up" : "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(tide.isHighTide ? (isCurrentDay ? .white : .blue) : (isCurrentDay ? .white.opacity(0.7) : .cyan))
                        Text(tide.timeDisplay)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(isCurrentDay ? .white : .primary)
                    }
                }
            }
        }
        .frame(width: 70)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isCurrentDay ? Color.cyan : Color(.systemGray6).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isCurrentDay ? Color.cyan : Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func shortDayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date).prefix(3).uppercased()
    }

    private func dayRow(date: String, tides: [TideEvent]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Day header
            if let parsedDate = parseDate(date) {
                Text(dayName(parsedDate))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isToday(parsedDate) ? .blue : .primary)
            }

            // Tides for the day
            HStack(spacing: 12) {
                ForEach(tides) { tide in
                    HStack(spacing: 4) {
                        Image(systemName: tide.isHighTide ? "arrow.up" : "arrow.down")
                            .font(.system(size: 10))
                            .foregroundStyle(tide.isHighTide ? .blue : .cyan)
                        Text(tide.timeDisplay)
                            .font(.caption.weight(.medium))
                        if let coef = tide.coefficient {
                            Text("(\(coef))")
                                .font(.system(size: 9))
                                .foregroundStyle(tide.coefficientColor)
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func parseDate(_ dateStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateStr)
    }

    private func dayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date).capitalized
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}

// MARK: - Preview

// MARK: - Tide Chart Strip (for panel)

struct TideChartStrip: View {
    let tideData: TideData

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    // Get tides for next 24 hours
    private var upcomingTides: [TideEvent] {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now

        return tideData.tides.filter { tide in
            guard let tideDate = tide.parsedDateTime else { return false }
            return tideDate >= now.addingTimeInterval(-3600) && tideDate <= tomorrow
        }.sorted { t1, t2 in
            (t1.parsedDateTime ?? .distantPast) < (t2.parsedDateTime ?? .distantPast)
        }
    }

    // Generate curve points between tides
    private var curvePoints: [(date: Date, height: Double)] {
        var points: [(Date, Double)] = []
        let now = Date()

        // Add current time estimate
        if let firstTide = upcomingTides.first,
           firstTide.parsedDateTime != nil {
            // Estimate current height based on tide cycle
            let startDate = now.addingTimeInterval(-1800) // 30 min before
            points.append((startDate, estimateHeight(at: startDate)))
        }

        // Add all tide points
        for tide in upcomingTides {
            if let date = tide.parsedDateTime {
                points.append((date, tide.height))
            }
        }

        // Interpolate between points for smooth curve
        var interpolated: [(Date, Double)] = []
        for i in 0..<max(0, points.count - 1) {
            let start = points[i]
            let end = points[i + 1]

            interpolated.append(start)

            // Add intermediate points (sine curve)
            let duration = end.0.timeIntervalSince(start.0)
            let steps = 10
            for step in 1..<steps {
                let t = Double(step) / Double(steps)
                let date = start.0.addingTimeInterval(duration * t)
                // Sinusoidal interpolation
                let phase = t * .pi
                let height = start.1 + (end.1 - start.1) * (1 - cos(phase)) / 2
                interpolated.append((date, height))
            }
        }

        if let last = points.last {
            interpolated.append(last)
        }

        return interpolated
    }

    private func estimateHeight(at date: Date) -> Double {
        // Find surrounding tides
        let sorted = upcomingTides.compactMap { tide -> (Date, Double, Bool)? in
            guard let d = tide.parsedDateTime else { return nil }
            return (d, tide.height, tide.isHighTide)
        }

        guard sorted.count >= 2 else { return 3.0 }

        // Find the two closest tides
        for i in 0..<sorted.count - 1 {
            let before = sorted[i]
            let after = sorted[i + 1]

            if date >= before.0 && date <= after.0 {
                let progress = date.timeIntervalSince(before.0) / after.0.timeIntervalSince(before.0)
                let phase = progress * .pi
                return before.1 + (after.1 - before.1) * (1 - cos(phase)) / 2
            }
        }

        return sorted.first?.1 ?? 3.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "water.waves")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text(tideData.port.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if let coef = tideData.todayCoefficient {
                    HStack(spacing: 3) {
                        Text("Coef")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text("\(coef)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(coefficientColor(coef))
                    }
                }

                // Indicator for tappable action
                HStack(spacing: 4) {
                    Text("Voir détails")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.cyan)
            }

            // Chart
            if !curvePoints.isEmpty {
                Chart {
                    // Area under curve
                    ForEach(Array(curvePoints.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Time", point.date),
                            y: .value("Height", point.height)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan.opacity(0.3), .cyan.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    // Line
                    ForEach(Array(curvePoints.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Height", point.height)
                        )
                        .foregroundStyle(.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    // Tide markers
                    ForEach(upcomingTides) { tide in
                        if let date = tide.parsedDateTime {
                            PointMark(
                                x: .value("Time", date),
                                y: .value("Height", tide.height)
                            )
                            .foregroundStyle(tide.isHighTide ? .blue : .cyan)
                            .symbolSize(tide.isHighTide ? 60 : 50)

                            // Annotation
                            PointMark(
                                x: .value("Time", date),
                                y: .value("Height", tide.height)
                            )
                            .foregroundStyle(.clear)
                            .annotation(position: tide.isHighTide ? .top : .bottom) {
                                VStack(spacing: 1) {
                                    if !tide.isHighTide {
                                        Text(String(format: "%.1fm", tide.height))
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(tide.timeDisplay)
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                        .foregroundStyle(tide.isHighTide ? .blue : .cyan)
                                    if tide.isHighTide {
                                        Text(String(format: "%.1fm", tide.height))
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // Current time marker
                    RuleMark(x: .value("Now", Date()))
                        .foregroundStyle(.orange.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                            .font(.system(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let h = value.as(Double.self) {
                                Text(String(format: "%.0fm", h))
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .frame(height: 100)
            } else {
                // No data
                HStack {
                    Spacer()
                    Text("Données marées non disponibles")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(height: 60)
            }

            // Next tides summary (prochaine marée à gauche)
            HStack(spacing: 16) {
                let lowFirst: Bool = {
                    guard let lowTime = tideData.nextLowTide?.parsedTime,
                          let highTime = tideData.nextHighTide?.parsedTime else {
                        return tideData.nextLowTide != nil
                    }
                    return lowTime < highTime
                }()

                if lowFirst {
                    if let nextLow = tideData.nextLowTide {
                        tideSummaryChip(label: "BM", time: nextLow.timeDisplay, icon: "arrow.down", color: .cyan)
                    }
                    if let nextHigh = tideData.nextHighTide {
                        tideSummaryChip(label: "PM", time: nextHigh.timeDisplay, icon: "arrow.up", color: .blue)
                    }
                } else {
                    if let nextHigh = tideData.nextHighTide {
                        tideSummaryChip(label: "PM", time: nextHigh.timeDisplay, icon: "arrow.up", color: .blue)
                    }
                    if let nextLow = tideData.nextLowTide {
                        tideSummaryChip(label: "BM", time: nextLow.timeDisplay, icon: "arrow.down", color: .cyan)
                    }
                }

                Spacer()
            }
        }
        .padding(10)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }

    private func tideSummaryChip(label: String, time: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(time)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
    }

    private func coefficientColor(_ coef: Int) -> Color {
        switch coef {
        case ..<40: return .blue
        case ..<70: return .green
        case ..<95: return .orange
        default: return .red
        }
    }
}

// MARK: - Tide Calendar View

struct TideCalendarView: View {
    let tideData: TideData
    @ObservedObject var tideService: TideService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: Date? = nil

    private let calendar = Calendar.current

    // Group tides by date string for quick lookup
    private var tidesByDate: [String: [TideEvent]] {
        return Dictionary(grouping: tideData.tides) { $0.date }
    }

    // Available dates from the data
    private var availableDates: [Date] {
        let dates = tideData.tides.compactMap { tide -> Date? in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: tide.date)
        }
        return Array(Set(dates)).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with port info
                    forecastHeader

                    // Horizontal scrollable days
                    daysScrollView

                    // Selected day detail
                    if let selected = selectedDay {
                        selectedDayDetail(selected)
                    } else if let first = availableDates.first {
                        selectedDayDetail(first)
                            .onAppear { selectedDay = first }
                    }

                    // Coefficient legend
                    coefficientLegend

                    // Info about data source
                    dataSourceInfo
                }
                .padding()
            }
            .navigationTitle("Prévisions des marées")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Forecast Header

    private var forecastHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "water.waves")
                    .font(.system(size: 24))
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tideData.port.name)
                        .font(.title2.weight(.bold))
                    Text("\(availableDates.count) jours de prévisions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let coef = tideData.todayCoefficient {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Aujourd'hui")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Coef \(coef)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(coefficientColor(coef))
                    }
                }
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    // MARK: - Days Scroll View

    private var daysScrollView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sélectionnez un jour")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(availableDates, id: \.self) { date in
                        dayCard(date)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private func dayCard(_ date: Date) -> some View {
        let dateString = formatDateKey(date)
        let tides = tidesByDate[dateString] ?? []
        let maxCoef = tides.compactMap { $0.coefficient }.max()
        let isCurrentDay = calendar.isDateInToday(date)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false

        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedDay = date
            }
            HapticManager.shared.selection()
        } label: {
            VStack(spacing: 6) {
                // Day name
                Text(shortDayName(date))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : (isCurrentDay ? .cyan : .secondary))

                // Day number
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .primary)

                // Month (if first of month or first in list)
                if calendar.component(.day, from: date) == 1 || date == availableDates.first {
                    Text(shortMonthName(date))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }

                // Coefficient badge
                if let coef = maxCoef {
                    Text("\(coef)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : coefficientColor(coef))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (isSelected ? Color.white.opacity(0.2) : coefficientColor(coef).opacity(0.15)),
                            in: Capsule()
                        )
                } else {
                    Text("-")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                // Tide count dots
                HStack(spacing: 2) {
                    ForEach(0..<min(tides.count, 4), id: \.self) { i in
                        Circle()
                            .fill(tides[i].isHighTide ?
                                (isSelected ? Color.white.opacity(0.9) : Color.blue) :
                                (isSelected ? Color.white.opacity(0.6) : Color.cyan.opacity(0.7)))
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .frame(width: 65)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.cyan : (isCurrentDay ? Color.cyan.opacity(0.1) : Color(.systemGray6).opacity(0.5)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isCurrentDay && !isSelected ? Color.cyan.opacity(0.5) :
                        isSelected ? Color.cyan : Color.white.opacity(0.1),
                        lineWidth: isCurrentDay ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func shortMonthName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date).uppercased()
    }

    // MARK: - Data Source Info

    private var dataSourceInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Text("Données: SHOM (Service Hydrographique et Océanographique de la Marine). Prévisions limitées à ~11 jours.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }

    // MARK: - Selected Day Detail

    private func selectedDayDetail(_ date: Date) -> some View {
        let dateString = formatDateKey(date)
        let tides = tidesByDate[dateString] ?? []

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(fullDateString(date))
                    .font(.headline)
                Spacer()
                if let maxCoef = tides.compactMap({ $0.coefficient }).max() {
                    HStack(spacing: 4) {
                        Text("Coef max")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(maxCoef)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(coefficientColor(maxCoef))
                    }
                }
            }

            if tides.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "water.waves.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("Pas de données disponibles")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                // Tides timeline
                VStack(spacing: 0) {
                    ForEach(Array(tides.enumerated()), id: \.element.id) { index, tide in
                        HStack(spacing: 12) {
                            // Time column
                            VStack {
                                Text(tide.timeDisplay)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                            }
                            .frame(width: 50)

                            // Icon
                            ZStack {
                                Circle()
                                    .fill(tide.isHighTide ? Color.blue.opacity(0.15) : Color.cyan.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: tide.isHighTide ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(tide.isHighTide ? .blue : .cyan)
                            }

                            // Details
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tide.isHighTide ? "Pleine mer" : "Basse mer")
                                    .font(.subheadline.weight(.medium))
                                HStack(spacing: 12) {
                                    Text(tide.heightDisplay)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let coef = tide.coefficient {
                                        Text("Coef \(coef)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(tide.coefficientColor)
                                    }
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 10)

                        if index < tides.count - 1 {
                            HStack {
                                Spacer()
                                    .frame(width: 50)
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 2, height: 20)
                                    .padding(.leading, 17)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
    }

    // MARK: - Coefficient Legend

    private var coefficientLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Légende des coefficients")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                legendItem(range: "< 40", label: "Faible", color: .blue)
                legendItem(range: "40-69", label: "Moyen", color: .green)
                legendItem(range: "70-94", label: "Fort", color: .orange)
                legendItem(range: "≥ 95", label: "Vive-eau", color: .red)
            }
        }
        .padding()
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private func legendItem(range: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(range)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formatDateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func fullDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date).capitalized
    }

    private func shortDayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: date).prefix(3).uppercased()
    }

    private func coefficientColor(_ coef: Int) -> Color {
        switch coef {
        case ..<40: return .blue
        case ..<70: return .green
        case ..<95: return .orange
        default: return .red
        }
    }
}

#Preview {
    TideWidget(
        tideData: TideData(
            port: TidePort(cst: "BREST", name: "Brest", lat: 48.38, lon: -4.49, region: "bretagne"),
            tides: [],
            nextHighTide: NextTide(time: "2026-01-26T15:30:00.000Z", height: 6.5, coefficient: 78),
            nextLowTide: NextTide(time: "2026-01-26T09:15:00.000Z", height: 1.2, coefficient: nil),
            todayCoefficient: 78,
            fetchedAt: ""
        ),
        onTap: {}
    )
}
