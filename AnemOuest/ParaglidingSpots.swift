//
//  ParaglidingSpots.swift
//  AnemOuest
//
//  Spots de parapente — Source: SpotAir / FFVL
//

import Foundation
import CoreLocation
import SwiftUI

// MARK: - Paragliding Spot Model

struct ParaglidingSpot: Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let altitude: Int
    let orientations: [String]         // ["N", "NE", "NW"] directions favorables
    let orientationsDefavo: [String]   // ["S", "SE"] directions défavorables
    let type: ParaglidingSpotType
    let level: ParaglidingLevel?
    let spotDescription: String?
    let city: String?
    let isValid: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var orientationString: String {
        orientations.isEmpty ? "—" : orientations.joined(separator: ",")
    }
}

// MARK: - Enums

enum ParaglidingSpotType: String {
    case takeoff = "Décollage"
    case landing = "Atterrissage"
    case trainingSlope = "Pente-école"
    case winch = "Treuil"
    case other = "Autre"

    static func fromAPI(_ value: Int) -> ParaglidingSpotType {
        switch value {
        case 1: return .takeoff
        case 2: return .landing
        case 3: return .trainingSlope
        case 7: return .winch
        default: return .other
        }
    }

    static func fromString(_ string: String) -> ParaglidingSpotType {
        switch string {
        case "takeoff": return .takeoff
        case "landing": return .landing
        case "trainingSlope": return .trainingSlope
        case "winch": return .winch
        default: return .other
        }
    }

    var icon: String {
        switch self {
        case .takeoff: return "arrow.up.circle.fill"
        case .landing: return "arrow.down.circle.fill"
        case .trainingSlope: return "figure.walk.circle.fill"
        case .winch: return "arrow.up.to.line.circle.fill"
        case .other: return "mappin.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .takeoff: return .green
        case .landing: return .blue
        case .trainingSlope: return .orange
        case .winch: return .purple
        case .other: return .secondary
        }
    }
}

enum ParaglidingLevel: Int {
    case ippi3 = 3
    case ippi4 = 4
    case ippi5 = 5

    var displayName: String {
        switch self {
        case .ippi3: return "Brevet initial"
        case .ippi4: return "Brevet pilote"
        case .ippi5: return "Pilote confirmé"
        }
    }

    var shortName: String {
        switch self {
        case .ippi3: return "IPPI 3"
        case .ippi4: return "IPPI 4"
        case .ippi5: return "IPPI 5"
        }
    }

    var color: Color {
        switch self {
        case .ippi3: return .green
        case .ippi4: return .orange
        case .ippi5: return .red
        }
    }

    var icon: String {
        switch self {
        case .ippi3: return "3.circle.fill"
        case .ippi4: return "4.circle.fill"
        case .ippi5: return "5.circle.fill"
        }
    }
}

// MARK: - Paragliding Condition Rating

struct ParaglidingConditionRating {
    let score: Int           // 0-100
    let windScore: Int       // 0-40
    let directionScore: Int  // 0-35
    let gustScore: Int       // 0-25
    let summary: String
    let details: [String]

    var color: Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .cyan
        case 40..<60: return .orange
        case 20..<40: return .red
        default: return .gray
        }
    }

    var label: String {
        switch score {
        case 80...100: return "Excellent"
        case 60..<80: return "Bon"
        case 40..<60: return "Moyen"
        case 20..<40: return "Médiocre"
        default: return "Mauvais"
        }
    }

    var icon: String {
        switch score {
        case 80...100: return "hand.thumbsup.fill"
        case 60..<80: return "hand.thumbsup"
        case 40..<60: return "hand.raised"
        case 20..<40: return "hand.thumbsdown"
        default: return "hand.thumbsdown.fill"
        }
    }

    /// Evaluate paragliding conditions from wind station data
    static func evaluate(wind: Double, gust: Double, direction: Double, spot: ParaglidingSpot) -> ParaglidingConditionRating {
        var windScore = 0
        var directionScore = 0
        var gustScore = 0
        var details: [String] = []

        // --- Wind speed score (0-40) ---
        // Paragliding: ideal ranges in knots (station data is in knots)
        let idealRange: ClosedRange<Double>
        let maxSafe: Double
        switch spot.level {
        case .ippi3:
            idealRange = 4...10
            maxSafe = 14
        case .ippi4:
            idealRange = 5...14
            maxSafe = 19
        case .ippi5:
            idealRange = 5...16
            maxSafe = 22
        case nil:
            idealRange = 5...14
            maxSafe = 19
        }

        if wind > maxSafe {
            windScore = 0
            details.append("Vent trop fort (\(WindUnit.convertValue(wind)) \(WindUnit.current.symbol)) — max \(WindUnit.convertValue(maxSafe)) \(WindUnit.current.symbol)")
        } else if idealRange.contains(wind) {
            let center = (idealRange.lowerBound + idealRange.upperBound) / 2
            let halfRange = (idealRange.upperBound - idealRange.lowerBound) / 2
            let distFromCenter = abs(wind - center)
            let centerFactor = max(0, 1 - (distFromCenter / halfRange))
            windScore = Int(25 + centerFactor * 15)
            details.append("Vent \(WindUnit.convertValue(wind)) \(WindUnit.current.symbol) — dans la plage idéale")
        } else if wind < idealRange.lowerBound {
            let deficit = idealRange.lowerBound - wind
            windScore = max(0, Int(20 - deficit * 3))
            details.append("Vent faible (\(WindUnit.convertValue(wind)) \(WindUnit.current.symbol))")
        } else {
            let excess = wind - idealRange.upperBound
            windScore = max(0, Int(20 - excess * 3))
            details.append("Vent fort (\(WindUnit.convertValue(wind)) \(WindUnit.current.symbol))")
        }

        // --- Direction score (0-35) ---
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let dirIndex = Int(round(direction / 45.0)) % 8
        let windDir = directions[dirIndex]

        // Check if wind matches favorable orientations
        let isFavorable = spot.orientations.contains { orient in
            windDir == orient ||
            (windDir.count == 2 && (String(windDir.prefix(1)) == orient || String(windDir.suffix(1)) == orient))
        }

        // Check if wind is in unfavorable orientations
        let isDefavorable = spot.orientationsDefavo.contains { orient in
            windDir == orient ||
            (windDir.count == 2 && (String(windDir.prefix(1)) == orient || String(windDir.suffix(1)) == orient))
        }

        if isFavorable {
            directionScore = 35
            details.append("Direction \(windDir) — favorable")
        } else if isDefavorable {
            directionScore = 0
            details.append("Direction \(windDir) — défavorable (\(spot.orientationsDefavo.joined(separator: ",")))")
        } else {
            // Check adjacent
            let allDirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            if let windIdx = allDirs.firstIndex(of: windDir) {
                let adj1 = allDirs[(windIdx + 1) % 8]
                let adj2 = allDirs[(windIdx + 7) % 8]
                let hasAdjacent = spot.orientations.contains(adj1) || spot.orientations.contains(adj2)
                directionScore = hasAdjacent ? 15 : 5
            }
            let idealStr = spot.orientations.isEmpty ? "—" : spot.orientations.joined(separator: ",")
            details.append("Direction \(windDir) — hors orientation (idéal: \(idealStr))")
        }

        // --- Gust score (0-25) ---
        let gustRatio = wind > 0 ? gust / wind : 2.0

        if gust > maxSafe {
            gustScore = 0
            details.append("Rafales dangereuses (\(Int(gust)) nds)")
        } else if gustRatio <= 1.3 {
            gustScore = 25
            details.append("Vent stable (rafales \(Int(gust)) nds)")
        } else if gustRatio <= 1.5 {
            gustScore = 18
            details.append("Rafales modérées (\(Int(gust)) nds)")
        } else if gustRatio <= 1.8 {
            gustScore = 10
            details.append("Rafales marquées (\(Int(gust)) nds)")
        } else {
            gustScore = 3
            details.append("Vent irrégulier (rafales \(Int(gust)) nds)")
        }

        let total = min(100, max(0, windScore + directionScore + gustScore))

        let summary: String
        switch total {
        case 80...100: summary = "Conditions excellentes"
        case 60..<80: summary = "Bonnes conditions"
        case 40..<60: summary = "Conditions moyennes"
        case 20..<40: summary = "Conditions difficiles"
        default: summary = "Conditions défavorables"
        }

        return ParaglidingConditionRating(
            score: total,
            windScore: windScore,
            directionScore: directionScore,
            gustScore: gustScore,
            summary: summary,
            details: details
        )
    }
}

// MARK: - Paragliding Spot Bottom Panel

struct ParaglidingSpotBottomPanel: View {
    let spot: ParaglidingSpot
    let forecast: ForecastData?
    let forecastLoading: Bool
    let nearbyStation: WindStation?
    let nearbyWebcam: SpotAirWebcam?
    let onClose: () -> Void
    let onForecastTap: () -> Void

    @State private var showForecast = false
    @State private var selectedTab: Int = 0
    @State private var isExpanded: Bool = false
    @State private var showScoreDetails: Bool = false
    @GestureState private var dragOffset: CGFloat = 0

    // MARK: - Computed Properties

    private func directionAbbrev(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(round(degrees / 45.0)) % 8
        return directions[index]
    }

    private var navigabilityInfo: (isNavigable: Bool, reason: String, color: Color) {
        guard let station = nearbyStation, station.isOnline else {
            return (false, "Pas de données vent", .secondary)
        }

        let windDir = directionAbbrev(station.direction)

        let isFavorable = spot.orientations.contains { orient in
            windDir == orient ||
            (windDir.count == 2 && (String(windDir.prefix(1)) == orient || String(windDir.suffix(1)) == orient))
        }

        let isDefavorable = spot.orientationsDefavo.contains { orient in
            windDir == orient ||
            (windDir.count == 2 && (String(windDir.prefix(1)) == orient || String(windDir.suffix(1)) == orient))
        }

        if isDefavorable {
            return (false, "Direction défavorable (\(windDir))", .red)
        } else if isFavorable {
            return (true, "Direction favorable (\(windDir))", .green)
        } else {
            return (false, "Direction neutre (\(windDir))", .orange)
        }
    }

    private var windAssessment: (text: String, color: Color, icon: String)? {
        guard let station = nearbyStation, station.isOnline else { return nil }

        switch station.wind {
        case ..<3:
            return ("Pas de vent", .secondary, "wind")
        case 3..<5:
            return ("Vent faible", .blue, "wind")
        case 5..<11:
            return ("Conditions idéales", .green, "checkmark.circle.fill")
        case 11..<16:
            return ("Vent soutenu", .orange, "exclamationmark.triangle")
        default:
            return ("Vent fort — Danger", .red, "exclamationmark.triangle.fill")
        }
    }

    private func windScaleColor(_ knots: Double) -> Color {
        windScale(knots)
    }

    private var paraglidingRating: ParaglidingConditionRating? {
        guard let station = nearbyStation, station.isOnline else { return nil }
        return ParaglidingConditionRating.evaluate(
            wind: station.wind,
            gust: station.gust,
            direction: station.direction,
            spot: spot
        )
    }

    private var idealWindRange: ClosedRange<Double> {
        // Ranges in knots (nds)
        switch spot.level {
        case .ippi3: return 4...10
        case .ippi4: return 5...14
        case .ippi5: return 5...16
        case nil: return 5...14
        }
    }

    private var levelColor: Color {
        spot.level?.color ?? .secondary
    }

    private var spotTypeIcon: String {
        spot.type.icon
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)

            // MARK: - Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        // Type badge
                        HStack(spacing: 3) {
                            Image(systemName: spot.type.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(spot.type.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(spot.type.color)

                        Text("•")
                            .foregroundStyle(.tertiary)

                        // Altitude
                        HStack(spacing: 2) {
                            Image(systemName: "mountain.2.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(spot.altitude)m")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)

                        // Level badge
                        if let level = spot.level {
                            Text("•")
                                .foregroundStyle(.tertiary)

                            HStack(spacing: 3) {
                                Circle()
                                    .fill(level.color)
                                    .frame(width: 8, height: 8)
                                Text(level.shortName)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(level.color)
                        }
                    }
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // MARK: - Stats Cards
            HStack(spacing: 10) {
                ParaglidingStatCard(
                    title: "Type",
                    value: spot.type.rawValue,
                    icon: spot.type.icon,
                    color: spot.type.color
                )
                ParaglidingStatCard(
                    title: "Altitude",
                    value: "\(spot.altitude)m",
                    icon: "mountain.2.fill",
                    color: .blue
                )
                ParaglidingStatCard(
                    title: "Orientation",
                    value: spot.orientationString,
                    icon: "safari",
                    color: .cyan
                )
            }

            // MARK: - Conditions actuelles (station proche)
            if let station = nearbyStation, station.isOnline {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Vent actuel")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(station.name)
                                .lineLimit(1)
                            let dist = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
                                .distance(from: CLLocation(latitude: station.latitude, longitude: station.longitude))
                            Text("à \(String(format: "%.1f", dist / 1000)) km")
                                .foregroundStyle(.quaternary)
                            if let lastUpdate = station.lastUpdate {
                                Text("•")
                                    .foregroundStyle(.quaternary)
                                Text(lastUpdate, style: .relative)
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 12) {
                        // Wind speed
                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(WindUnit.convertValue(station.wind))")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(windScaleColor(station.wind))
                                Text(WindUnit.current.symbol)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text("Moy.")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }

                        // Gust
                        VStack(spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(WindUnit.convertValue(station.gust))")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(windScaleColor(station.gust))
                                Text(WindUnit.current.symbol)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text("Rafales")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        // Direction arrow
                        VStack(spacing: 2) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 18, weight: .bold))
                                    .rotationEffect(.degrees(station.direction + 180))
                                    .foregroundStyle(.cyan)
                            }
                            Text(directionAbbrev(station.direction))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Navigability indicator
                    let navInfo = navigabilityInfo
                    HStack(spacing: 8) {
                        Image(systemName: navInfo.isNavigable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(navInfo.color)

                        Text(navInfo.reason)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(navInfo.color)

                        Spacer()

                        if let assessment = windAssessment {
                            HStack(spacing: 4) {
                                Image(systemName: assessment.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(assessment.text)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(assessment.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(assessment.color.opacity(0.15), in: Capsule())
                        }
                    }

                    // MARK: - Score (notation)
                    if let rating = paraglidingRating {
                        Divider().padding(.vertical, 2)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showScoreDetails.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: rating.icon)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(rating.color)
                                Text(rating.label)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(rating.color)
                                Text("—")
                                    .foregroundStyle(.secondary)
                                Text(rating.summary)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(rating.score)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(rating.color)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(showScoreDetails ? Color.blue : Color.gray.opacity(0.4))
                            }
                        }
                        .buttonStyle(.plain)

                        // Détails du score (dépliable)
                        if showScoreDetails {
                            VStack(spacing: 8) {
                                paraScoreDetailRow(
                                    label: "Vent",
                                    icon: rating.windScore >= 28 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                    iconColor: rating.windScore >= 28 ? .green : (rating.windScore >= 15 ? .orange : .red),
                                    current: "\(WindUnit.convertValue(station.wind)) \(WindUnit.current.symbol)",
                                    ideal: "\(WindUnit.convertValue(idealWindRange.lowerBound))-\(WindUnit.convertValue(idealWindRange.upperBound)) \(WindUnit.current.symbol)",
                                    score: rating.windScore,
                                    maxScore: 40
                                )
                                paraScoreDetailRow(
                                    label: "Direction",
                                    icon: rating.directionScore >= 25 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                    iconColor: rating.directionScore >= 25 ? .green : (rating.directionScore >= 10 ? .orange : .red),
                                    current: directionAbbrev(station.direction),
                                    ideal: spot.orientationString,
                                    score: rating.directionScore,
                                    maxScore: 35
                                )
                                paraScoreDetailRow(
                                    label: "Rafales",
                                    icon: rating.gustScore >= 18 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                    iconColor: rating.gustScore >= 18 ? .green : (rating.gustScore >= 8 ? .orange : .red),
                                    current: "\(WindUnit.convertValue(station.gust)) \(WindUnit.current.symbol)",
                                    ideal: "Ratio < 1.3",
                                    score: rating.gustScore,
                                    maxScore: 25
                                )

                                if !rating.details.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(rating.details, id: \.self) { detail in
                                            HStack(spacing: 6) {
                                                Circle()
                                                    .fill(Color.secondary.opacity(0.4))
                                                    .frame(width: 4, height: 4)
                                                Text(detail)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        }
                    }
                }
                .padding(12)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
            } else if nearbyStation == nil {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(.secondary)
                    Text("Aucune station à proximité")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
            } else {
                HStack {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.orange)
                    Text("Station hors ligne")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
            }

            // MARK: - Orientations défavorables warning
            if !spot.orientationsDefavo.isEmpty {
                if let station = nearbyStation, station.isOnline {
                    let windDir = directionAbbrev(station.direction)
                    let isDefavo = spot.orientationsDefavo.contains { orient in
                        windDir == orient ||
                        (windDir.count == 2 && (String(windDir.prefix(1)) == orient || String(windDir.suffix(1)) == orient))
                    }
                    if isDefavo {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Direction de vent défavorable — \(spot.orientationsDefavo.joined(separator: ", ")) déconseillé")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            // MARK: - Expand hint
            if !isExpanded {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Plus d'infos")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                }
            }

            // MARK: - Expanded content
            if isExpanded {
                // Webcam
                if let webcam = nearbyWebcam {
                    SpotAirWebcamView(webcam: webcam)
                }

                // Description
                if let desc = spot.spotDescription, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Description")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(desc)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
                }

                // City
                if let city = spot.city, !city.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(city)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                // Forecast
                if forecastLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Chargement prévisions...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else if let forecast = forecast {
                    Button {
                        onForecastTap()
                    } label: {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Voir les prévisions détaillées")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.blue)
                        .padding(12)
                        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                // Data source
                HStack {
                    Spacer()
                    Text("Source: SpotAir / FFVL")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 22))
        .shadow(radius: 14)
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if value.translation.height < -threshold {
                            isExpanded = true
                        } else if value.translation.height > threshold {
                            if isExpanded {
                                isExpanded = false
                            } else {
                                onClose()
                            }
                        }
                    }
                }
        )
    }

    // MARK: - Score Detail Row

    @ViewBuilder
    private func paraScoreDetailRow(label: String, icon: String, iconColor: Color, current: String, ideal: String, score: Int, maxScore: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 58, alignment: .leading)

            Text(current)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)

            Text(ideal)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(score)/\(maxScore)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Double(score) / Double(maxScore) >= 0.7 ? .green : (Double(score) / Double(maxScore) >= 0.4 ? .orange : .red))
                .frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: - Stat Card

private struct ParaglidingStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }
}

// MARK: - SpotAir Webcam View (with auto-refresh)

private struct SpotAirWebcamView: View {
    let webcam: SpotAirWebcam

    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var lastRefresh: Date?

    private var isPanoramic: Bool {
        // Detect from field of view metadata or from image aspect ratio
        if (webcam.fieldOfView ?? 0) > 120 { return true }
        if let img = loadedImage, img.size.width > img.size.height * 2.5 { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 6) {
            // Header
            HStack {
                Image(systemName: "camera.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(webcam.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if loadFailed {
                    Text("HORS LIGNE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15), in: Capsule())
                } else if webcam.isOnline {
                    Text("EN LIGNE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
            }

            // Image
            if isLoading && loadedImage == nil {
                ProgressView()
                    .frame(height: 100)
            } else if let uiImage = loadedImage {
                if isPanoramic {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 9))
                        Text("Panoramique — glisser pour voir")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: 180)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else if loadFailed {
                HStack {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    Text("Image indisponible")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 100)
            }

            // Last refresh + source
            HStack(spacing: 4) {
                if let refresh = lastRefresh {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                    Text(refresh, style: .relative)
                        .font(.system(size: 9))
                }

                if let sourceName = webcam.sourceName {
                    if lastRefresh != nil {
                        Text("•")
                            .font(.system(size: 9))
                    }
                    Text("Source : \(sourceName)")
                        .font(.system(size: 9))
                }
            }
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        isLoading = true
        loadFailed = false

        guard let url = URL(string: webcam.imageUrl) else {
            isLoading = false
            loadFailed = true
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    isLoading = false
                    loadFailed = true
                }
                return
            }
            await MainActor.run {
                loadedImage = image
                isLoading = false
                lastRefresh = Date()
            }
        } catch {
            await MainActor.run {
                isLoading = false
                loadFailed = loadedImage == nil
            }
        }
    }
}
