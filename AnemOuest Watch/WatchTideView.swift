import SwiftUI

struct WatchTideView: View {
    @EnvironmentObject var data: WatchDataManager

    var body: some View {
        NavigationStack {
            Group {
                if data.isLoadingTides && data.tideData == nil {
                    ProgressView()
                } else if let tide = data.tideData {
                    TideContentView(tide: tide)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "water.waves")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("Marees indisponibles")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Button("Recharger") {
                            Task { await data.fetchTides() }
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.bordered)
                        .tint(.cyan)
                    }
                }
            }
            .navigationTitle("Marees")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await data.fetchTides() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                    }
                }
            }
        }
    }
}

// MARK: - Tide Content

struct TideContentView: View {
    let tide: WatchTideData

    private var todayTides: [WatchTide] {
        let today = DateFormatter.yyyyMMdd.string(from: Date())
        return tide.tides.filter { $0.date == today }
    }

    private var tomorrowTides: [WatchTide] {
        let tomorrow = DateFormatter.yyyyMMdd.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        return tide.tides.filter { $0.date == tomorrow }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Port + Coefficient
                HStack {
                    Text(tide.port.name)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let coeff = tide.todayCoefficient {
                        Text("Coeff \(coeff)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(coeffColor(coeff))
                    }
                }

                // Next tides summary
                HStack(spacing: 12) {
                    if let next = tide.nextHighTide {
                        NextTideCard(
                            icon: "arrow.up",
                            label: "PM",
                            time: next.localTime,
                            height: String(format: "%.1fm", next.height),
                            color: .cyan
                        )
                    }
                    if let next = tide.nextLowTide {
                        NextTideCard(
                            icon: "arrow.down",
                            label: "BM",
                            time: next.localTime,
                            height: String(format: "%.1fm", next.height),
                            color: .blue
                        )
                    }
                }

                // Today's tides
                if !todayTides.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Aujourd'hui")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        ForEach(todayTides) { t in
                            TideRow(tide: t)
                        }
                    }
                }

                // Tomorrow's tides
                if !tomorrowTides.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Demain")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        ForEach(tomorrowTides) { t in
                            TideRow(tide: t)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func coeffColor(_ coeff: Int) -> Color {
        if coeff >= 100 { return .red }
        if coeff >= 80 { return .orange }
        if coeff >= 60 { return .yellow }
        return .secondary
    }
}

// MARK: - Next Tide Card

struct NextTideCard: View {
    let icon: String
    let label: String
    let time: String
    let height: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)

            Text(time)
                .font(.system(size: 16, weight: .bold, design: .rounded))

            Text(height)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Tide Row

struct TideRow: View {
    let tide: WatchTide

    var body: some View {
        HStack {
            Image(systemName: tide.isHigh ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(tide.isHigh ? .cyan : .blue)

            Text(tide.localTime)
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Text(tide.heightText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            if let c = tide.coefficient {
                Text("\(c)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Date Formatter Helper

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
