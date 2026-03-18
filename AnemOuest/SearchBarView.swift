import SwiftUI
import CoreLocation

// MARK: - Search Result Model

enum SearchResultType {
    case windStation(WindStation)
    case kiteSpot(KiteSpot)
    case surfSpot(SurfSpot)
    case paraglidingSpot(ParaglidingSpot)
}

struct SearchResult: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let type: SearchResultType
    let iconName: String
    let iconColor: Color
    var score: Int = 0
}

// MARK: - Search History

struct SearchHistoryEntry: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let timestamp: Date

    static func == (lhs: SearchHistoryEntry, rhs: SearchHistoryEntry) -> Bool {
        lhs.id == rhs.id
    }
}

final class SearchHistory {
    static let shared = SearchHistory()
    private let key = "searchHistory"
    private let maxEntries = 10

    func entries() -> [SearchHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func add(_ entry: SearchHistoryEntry) {
        var list = entries().filter { $0.id != entry.id }
        list.insert(entry, at: 0)
        if list.count > maxEntries { list = Array(list.prefix(maxEntries)) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func remove(_ entry: SearchHistoryEntry) {
        let list = entries().filter { $0.id != entry.id }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Fuzzy Matching

/// Scores how well `query` matches `target`. Returns 0 for no match, higher = better.
/// Prefers: exact prefix > word-boundary match > substring > fuzzy sequential.
private func fuzzyScore(query: String, target: String) -> Int {
    let q = query.lowercased()
    let t = target.lowercased()

    // Exact prefix match — best score
    if t.hasPrefix(q) {
        return 1000 + (100 - t.count) // shorter name = better
    }

    // Exact substring match
    if t.contains(q) {
        // Bonus if it starts at a word boundary
        if let range = t.range(of: q) {
            let idx = t.distance(from: t.startIndex, to: range.lowerBound)
            if idx == 0 {
                return 900
            }
            let charBefore = t[t.index(range.lowerBound, offsetBy: -1)]
            if charBefore == " " || charBefore == "-" || charBefore == "'" {
                return 800 + (100 - idx) // word boundary match
            }
            return 600 + (100 - idx)
        }
        return 600
    }

    // Fuzzy sequential match: all query chars appear in order in target
    var score = 0
    var tIdx = t.startIndex
    var consecutive = 0
    var matched = 0

    for qChar in q {
        var found = false
        while tIdx < t.endIndex {
            if t[tIdx] == qChar {
                matched += 1
                consecutive += 1
                score += consecutive * 2 // bonus for consecutive matches
                // Word boundary bonus
                if tIdx == t.startIndex {
                    score += 5
                } else {
                    let prev = t[t.index(before: tIdx)]
                    if prev == " " || prev == "-" || prev == "'" {
                        score += 3
                    }
                }
                tIdx = t.index(after: tIdx)
                found = true
                break
            } else {
                consecutive = 0
            }
            tIdx = t.index(after: tIdx)
        }
        if !found { return 0 } // query char not found → no match
    }

    // Only accept if we matched all query chars and at least 60% of query length
    guard matched == q.count else { return 0 }

    // Base fuzzy score (lower than substring)
    return 200 + score + (matched * 10)
}

// MARK: - Search Bar View

struct SearchBarView: View {
    @Binding var isPresented: Bool
    @State private var searchText: String = ""
    @State private var history: [SearchHistoryEntry] = []
    @FocusState private var isTextFieldFocused: Bool

    // Data sources
    let windStations: [WindStation]
    let kiteSpots: [KiteSpot]
    let surfSpots: [SurfSpot]
    let paraglidingSpots: [ParaglidingSpot]

    // Selection callbacks
    var onSelectStation: (WindStation) -> Void
    var onSelectKiteSpot: (KiteSpot) -> Void
    var onSelectSurfSpot: (SurfSpot) -> Void
    var onSelectParaglidingSpot: (ParaglidingSpot) -> Void

    private var results: [SearchResult] {
        guard searchText.count >= 2 else { return [] }
        let query = searchText

        var all: [(result: SearchResult, score: Int)] = []

        // Wind stations
        for station in windStations {
            let score = fuzzyScore(query: query, target: station.name)
            if score > 0 {
                all.append((SearchResult(
                    id: "station_\(station.stableId)",
                    name: station.name,
                    subtitle: "Station \(station.source.displayName)",
                    type: .windStation(station),
                    iconName: "sensor.fill",
                    iconColor: station.source.color,
                    score: score
                ), score))
            }
        }

        // Kite spots
        for spot in kiteSpots {
            let score = fuzzyScore(query: query, target: spot.name)
            if score > 0 {
                all.append((SearchResult(
                    id: "kite_\(spot.id)",
                    name: spot.name,
                    subtitle: "Kite · \(spot.level.rawValue) · \(spot.orientation)",
                    type: .kiteSpot(spot),
                    iconName: "wind",
                    iconColor: .orange,
                    score: score
                ), score))
            }
        }

        // Surf spots
        for spot in surfSpots {
            let score = fuzzyScore(query: query, target: spot.name)
            if score > 0 {
                all.append((SearchResult(
                    id: "surf_\(spot.id)",
                    name: spot.name,
                    subtitle: "Surf · \(spot.level.rawValue) · \(spot.waveType.rawValue)",
                    type: .surfSpot(spot),
                    iconName: "water.waves",
                    iconColor: .cyan,
                    score: score
                ), score))
            }
        }

        // Paragliding spots
        for spot in paraglidingSpots {
            let score = fuzzyScore(query: query, target: spot.name)
            if score > 0 {
                let typeLabel = spot.type.rawValue
                all.append((SearchResult(
                    id: "paragliding_\(spot.id)",
                    name: spot.name,
                    subtitle: "Parapente · \(typeLabel)",
                    type: .paraglidingSpot(spot),
                    iconName: "arrow.up.right.circle.fill",
                    iconColor: .red,
                    score: score
                ), score))
            }
        }

        // Sort by score descending, take top 20
        return all
            .sorted { $0.score > $1.score }
            .prefix(20)
            .map { $0.result }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            searchField
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Results or history
            if !results.isEmpty {
                resultsList
            } else if searchText.count >= 2 {
                emptyState
            } else if searchText.isEmpty && !history.isEmpty {
                historySection
            }

            Spacer()
        }
        .background(Color(.systemBackground))
        .onAppear {
            isTextFieldFocused = true
            history = SearchHistory.shared.entries()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 16, weight: .medium))

            TextField("Rechercher un spot ou une station…", text: $searchText)
                .focused($isTextFieldFocused)
                .font(.system(size: 16))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Button("Annuler") {
                dismiss()
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .modifier(LiquidGlassCapsuleModifier())
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recherches récentes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    SearchHistory.shared.clear()
                    history = []
                } label: {
                    Text("Effacer")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)

            LazyVStack(spacing: 2) {
                ForEach(history) { entry in
                    Button {
                        searchText = entry.name
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(entry.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                SearchHistory.shared.remove(entry)
                                history = SearchHistory.shared.entries()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(results) { result in
                    Button {
                        selectResult(result)
                    } label: {
                        resultRow(result)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .frame(maxHeight: 400)
    }

    private func resultRow(_ result: SearchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(result.iconColor)
                .frame(width: 32, height: 32)
                .background(result.iconColor.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Aucun résultat")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    // MARK: - Selection

    private func selectResult(_ result: SearchResult) {
        Analytics.searched(resultsCount: 1)
        // Save to history
        SearchHistory.shared.add(SearchHistoryEntry(
            id: result.id,
            name: result.name,
            subtitle: result.subtitle,
            timestamp: Date()
        ))

        switch result.type {
        case .windStation(let station):
            onSelectStation(station)
        case .kiteSpot(let spot):
            onSelectKiteSpot(spot)
        case .surfSpot(let spot):
            onSelectSurfSpot(spot)
        case .paraglidingSpot(let spot):
            onSelectParaglidingSpot(spot)
        }
        dismiss()
    }

    private func dismiss() {
        isTextFieldFocused = false
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = false
        }
    }
}
