//
//  FishingView.swift
//  AnemOuest
//
//  Onglet pêche : score conditions, tables solunaires, créneaux, calendrier, espèces
//

import SwiftUI
import CoreLocation

// MARK: - Fishing View

struct FishingView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var tideService = TideService.shared
    @StateObject private var stationManager = WindStationManager.shared
    @StateObject private var favoritesManager = FavoritesManager.shared
    @StateObject private var waveBuoyService = WaveBuoyService.shared

    @State private var solunarData: SolunarData?
    @State private var conditions: FishingConditions?
    @State private var weekData: [(date: Date, solunar: SolunarData, conditions: FishingConditions)] = []
    @State private var selectedDay: Date = Date()
    @State private var pressureCurrent: Double?
    @State private var pressureTrend: Double?
    @State private var isLoading = true
    @State private var expandedSpeciesRegion: FishingRegion?
    @State private var locationName: String = ""
    @State private var tidePortName: String?
    @State private var windStationName: String?
    @State private var waveBuoyName: String?
    @State private var currentWaveHeight: Double?
    @State private var currentWavePeriod: Double?
    @State private var currentSeaTemp: Double?
    @State private var selectedLocation: ForecastLocation?
    @State private var showLocationPicker = false
    @State private var detectedRegion: FishingRegion?

    private let calendar = Calendar.current
    private let solunarService = SolunarService.shared
    private let fishingService = FishingService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isLoading {
                        loadingView
                    } else if let conditions = conditions, let solunar = solunarData {
                        locationBanner
                        scoreHeader(conditions)
                        solunarSection(solunar)
                        conditionsBreakdown(conditions)
                        windowsSection(conditions)
                        weekCalendarSection
                        speciesSection
                    } else {
                        noDataView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .navigationTitle("Pêche")
            .refreshable { await loadData() }
        }
        .task { await loadData() }
        .sheet(isPresented: $showLocationPicker) {
            FishingLocationPickerSheet(
                selectedLocation: $selectedLocation,
                isPresented: $showLocationPicker,
                locationManager: locationManager,
                favoritesManager: favoritesManager,
                tideService: tideService
            )
        }
        .onChange(of: selectedLocation?.name) { _, _ in
            isLoading = true
            Task { await loadData() }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Calcul des conditions...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private var noDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "fish.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Données non disponibles")
                .font(.headline)
            Text("Vérifiez votre connexion ou la localisation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Location Banner

    private var locationBanner: some View {
        Button {
            showLocationPicker = true
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.indigo)

                    Text(locationName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if let port = tidePortName {
                        HStack(spacing: 3) {
                            Image(systemName: "water.waves")
                                .font(.system(size: 9))
                            Text(port)
                                .font(.system(size: 11))
                        }
                    }

                    if let station = windStationName {
                        HStack(spacing: 3) {
                            Image(systemName: "wind")
                                .font(.system(size: 9))
                            Text(station)
                                .font(.system(size: 11))
                        }
                    }

                    if let buoy = waveBuoyName {
                        HStack(spacing: 3) {
                            Image(systemName: "water.waves.and.arrow.up")
                                .font(.system(size: 9))
                            Text(buoy)
                                .font(.system(size: 11))
                        }
                    }

                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Score Header

    private func scoreHeader(_ conditions: FishingConditions) -> some View {
        VStack(spacing: 14) {
            // Circular score
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 10)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: CGFloat(conditions.score) / 100.0)
                    .stroke(
                        conditions.color,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(conditions.score)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(conditions.color)
                    Text(conditions.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            Text("Conditions de pêche")
                .font(.headline)

            // Summary details (first 3)
            if !conditions.details.isEmpty {
                VStack(spacing: 4) {
                    ForEach(conditions.details.prefix(3), id: \.self) { detail in
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Wave info row
            if currentWaveHeight != nil || currentSeaTemp != nil {
                HStack(spacing: 12) {
                    if let h = currentWaveHeight {
                        Label(String(format: "%.1fm", h), systemImage: "water.waves.and.arrow.up")
                    }
                    if let p = currentWavePeriod {
                        Label(String(format: "%.0fs", p), systemImage: "clock.arrow.circlepath")
                    }
                    if let t = currentSeaTemp {
                        Label(String(format: "%.0f°C", t), systemImage: "thermometer.medium")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    // MARK: - Solunar Section

    private func solunarSection(_ solunar: SolunarData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(.indigo)
                Text("Tables solunaires")
                    .font(.headline)
                Spacer()
                // Rating stars
                HStack(spacing: 2) {
                    ForEach(0..<5) { i in
                        Image(systemName: i < solunar.rating ? "star.fill" : "star")
                            .font(.system(size: 11))
                            .foregroundStyle(i < solunar.rating ? .yellow : .secondary.opacity(0.3))
                    }
                }
            }

            // Moon phase info
            HStack(spacing: 16) {
                // Moon icon
                VStack(spacing: 4) {
                    Image(systemName: solunarService.moonPhaseIcon(solunar.moonPhase))
                        .font(.system(size: 36))
                        .foregroundStyle(.indigo)
                    Text(solunar.moonPhaseName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 90)

                // Sun/Moon times
                VStack(alignment: .leading, spacing: 6) {
                    timeRow(icon: "sunrise.fill", label: "Soleil", time: formatTime(solunar.sunRise), color: .orange)
                    timeRow(icon: "sunset.fill", label: "Coucher", time: formatTime(solunar.sunSet), color: .orange)
                    if let rise = solunar.moonRise {
                        timeRow(icon: "moonrise.fill", label: "Lune", time: formatTime(rise), color: .indigo)
                    }
                    if let set = solunar.moonSet {
                        timeRow(icon: "moonset.fill", label: "Coucher", time: formatTime(set), color: .indigo)
                    }
                }

                Spacer()

                // Illumination
                VStack(spacing: 4) {
                    Text("\(Int(solunar.moonIllumination))%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.indigo)
                    Text("Illumination")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // Solunar timeline
            solunarTimeline(solunar)
        }
        .padding(16)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private func timeRow(icon: String, label: String, time: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            Text(time)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
    }

    // MARK: - Solunar Timeline

    private func solunarTimeline(_ solunar: SolunarData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Périodes du jour")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let width = geometry.size.width
                let dayStart = calendar.startOfDay(for: solunar.date)
                let totalSeconds: Double = 24 * 3600

                ZStack(alignment: .leading) {
                    // Background bar
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 24)

                    // Daylight zone
                    let sunRiseX = solunar.sunRise.timeIntervalSince(dayStart) / totalSeconds * width
                    let sunSetX = solunar.sunSet.timeIntervalSince(dayStart) / totalSeconds * width
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.orange.opacity(0.1))
                        .frame(width: max(0, sunSetX - sunRiseX), height: 24)
                        .offset(x: sunRiseX)

                    // Major periods
                    ForEach(solunar.majorPeriods) { period in
                        let startX = max(0, period.start.timeIntervalSince(dayStart) / totalSeconds * width)
                        let endX = min(width, period.end.timeIntervalSince(dayStart) / totalSeconds * width)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.indigo.opacity(0.6))
                            .frame(width: max(0, endX - startX), height: 24)
                            .offset(x: startX)
                    }

                    // Minor periods
                    ForEach(solunar.minorPeriods) { period in
                        let startX = max(0, period.start.timeIntervalSince(dayStart) / totalSeconds * width)
                        let endX = min(width, period.end.timeIntervalSince(dayStart) / totalSeconds * width)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.indigo.opacity(0.3))
                            .frame(width: max(0, endX - startX), height: 24)
                            .offset(x: startX)
                    }

                    // Now marker
                    if calendar.isDateInToday(solunar.date) {
                        let nowX = Date().timeIntervalSince(dayStart) / totalSeconds * width
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2, height: 30)
                            .offset(x: nowX - 1)
                    }
                }

                // Hour labels
                HStack {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        if hour == 0 {
                            Text("0h")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        } else {
                            Spacer()
                            Text("\(hour)h")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .offset(y: 28)
            }
            .frame(height: 44)

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .indigo.opacity(0.6), label: "Majeure")
                legendItem(color: .indigo.opacity(0.3), label: "Mineure")
                legendItem(color: .orange.opacity(0.15), label: "Jour")
                HStack(spacing: 3) {
                    Rectangle().fill(.red).frame(width: 8, height: 2)
                    Text("Maintenant")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 8)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Conditions Breakdown

    private func conditionsBreakdown(_ conditions: FishingConditions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gauge.open.with.lines.needle.33percent")
                    .foregroundStyle(.indigo)
                Text("Détail des conditions")
                    .font(.headline)
            }

            scoreBar(label: "Solunaire", score: conditions.solunarScore, maxScore: 25, icon: "moon.fill", color: .indigo)
            scoreBar(label: "Marées", score: conditions.tideScore, maxScore: 20, icon: "water.waves", color: .blue)
            scoreBar(label: "Vent", score: conditions.windScore, maxScore: 20, icon: "wind", color: .cyan)
            scoreBar(label: "Mer", score: conditions.seaScore, maxScore: 20, icon: "water.waves.and.arrow.up", color: .teal)
            scoreBar(label: "Pression", score: conditions.pressureScore, maxScore: 15, icon: "barometer", color: .purple)
        }
        .padding(16)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private func scoreBar(label: String, score: Int, maxScore: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 70, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.8))
                        .frame(width: geometry.size.width * CGFloat(score) / CGFloat(maxScore))
                }
            }
            .frame(height: 8)

            Text("\(score)/\(maxScore)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: 22)
    }

    // MARK: - Windows Section

    private func windowsSection(_ conditions: FishingConditions) -> some View {
        Group {
            if !conditions.bestWindows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "clock.badge.checkmark")
                            .foregroundStyle(.indigo)
                        Text("Créneaux recommandés")
                            .font(.headline)
                    }

                    ForEach(conditions.bestWindows) { window in
                        windowCard(window)
                    }
                }
                .padding(16)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
            }
        }
    }

    private func windowCard(_ window: FishingWindow) -> some View {
        HStack(spacing: 12) {
            // Quality indicator
            Image(systemName: window.quality.icon)
                .font(.system(size: 16))
                .foregroundStyle(window.quality.color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                // Time range
                Text("\(formatTime(window.start)) - \(formatTime(window.end))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                // Reason
                Text(window.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Quality badge
            Text(window.quality == .excellent ? "Top" : window.quality == .good ? "Bon" : "OK")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(window.quality.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(window.quality.color.opacity(0.15), in: Capsule())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Week Calendar

    private var weekCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.indigo)
                Text("Prévisions 7 jours")
                    .font(.headline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(weekData, id: \.date) { dayData in
                        dayCard(dayData.date, solunar: dayData.solunar, conditions: dayData.conditions)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private func dayCard(_ date: Date, solunar: SolunarData, conditions: FishingConditions) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)

        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedDay = date
            }
            updateForSelectedDay(date)
            HapticManager.shared.selection()
        } label: {
            VStack(spacing: 6) {
                // Day name
                Text(shortDayName(date))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : (isToday ? .indigo : .secondary))

                // Day number
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .primary)

                // Score badge
                Text("\(conditions.score)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : conditions.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (isSelected ? Color.white.opacity(0.2) : conditions.color.opacity(0.15)),
                        in: Capsule()
                    )

                // Moon phase icon
                Image(systemName: solunarService.moonPhaseIcon(solunar.moonPhase))
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .indigo.opacity(0.6))
            }
            .frame(width: 65)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.indigo : (isToday ? Color.indigo.opacity(0.1) : Color(.systemGray6).opacity(0.5)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isToday && !isSelected ? Color.indigo.opacity(0.5) :
                        isSelected ? Color.indigo : Color.white.opacity(0.1),
                        lineWidth: isToday ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Species Section

    private var speciesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "fish.fill")
                    .foregroundStyle(.indigo)
                Text("Espèces de saison")
                    .font(.headline)
                Spacer()
                let monthName = Self.frenchMonthName()
                Text(monthName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Legend
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.indigo)
                        .frame(width: 6, height: 10)
                    Text("Pic")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.indigo.opacity(0.35))
                        .frame(width: 6, height: 10)
                    Text("Saison")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.red.opacity(0.6))
                        .frame(width: 6, height: 10)
                    Text("Interdit")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ForEach(FishingRegion.allCases) { region in
                regionRow(region, isDetected: region == detectedRegion)
            }
        }
        .padding(16)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
    }

    private func regionRow(_ region: FishingRegion, isDetected: Bool) -> some View {
        let allSpecies = region.species
        let inSeasonCount = allSpecies.filter { $0.isInSeason }.count
        let isExpanded = expandedSpeciesRegion == region

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSpeciesRegion = isExpanded ? nil : region
                }
            } label: {
                HStack {
                    Text(region.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    if isDetected {
                        Text("Votre zone")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.indigo, in: Capsule())
                    }

                    Spacer()

                    Text("\(inSeasonCount) en saison")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(allSpecies) { species in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                // Status icon: allowed or forbidden
                                if !species.closedMonths.isEmpty {
                                    Image(systemName: species.isFishingAllowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(species.isFishingAllowed ? .green : .red)
                                        .frame(width: 20)
                                } else {
                                    Image(systemName: species.icon)
                                        .font(.system(size: 12))
                                        .foregroundStyle(species.isInSeason ? .indigo : .secondary.opacity(0.4))
                                        .frame(width: 20)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(species.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(species.isInSeason ? .primary : .secondary)

                                        if !species.isFishingAllowed {
                                            Text("Interdit")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.red, in: Capsule())
                                        } else if species.isInPeak {
                                            Text("Pic")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.orange)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.15), in: Capsule())
                                        }
                                    }

                                    HStack(spacing: 6) {
                                        Text(species.technique)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)

                                        if let size = species.minimumSize {
                                            Text("Min. \(size)")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }

                                Spacer()

                                monthIndicator(months: species.months, peakMonths: species.peakMonths, closedMonths: species.closedMonths)
                            }

                            // Regulation note
                            if let reg = species.regulation {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 9))
                                    Text(reg)
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(.teal)
                                .padding(.leading, 30)
                            }
                        }
                        .padding(.vertical, 6)
                        .opacity(species.isFishingAllowed ? (species.isInSeason ? 1.0 : 0.5) : 0.6)

                        if species.id != allSpecies.last?.id {
                            Divider().opacity(0.3)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if region != FishingRegion.allCases.last {
                Divider().opacity(0.2)
            }
        }
    }

    private func monthIndicator(months: Set<Int>, peakMonths: Set<Int>, closedMonths: Set<Int> = []) -> some View {
        HStack(spacing: 1.5) {
            ForEach(1...12, id: \.self) { month in
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        closedMonths.contains(month) ? Color.red.opacity(0.6) :
                        peakMonths.contains(month) ? Color.indigo :
                        months.contains(month) ? Color.indigo.opacity(0.35) :
                        Color.secondary.opacity(0.1)
                    )
                    .frame(width: 4, height: 10)
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        let lat: Double
        let lon: Double
        let locName: String

        if let selected = selectedLocation {
            lat = selected.latitude
            lon = selected.longitude
            locName = selected.name
        } else if let userLoc = locationManager.userLocation {
            lat = userLoc.latitude
            lon = userLoc.longitude
            locName = "Ma position"
        } else {
            // Default: Quiberon (Bretagne)
            lat = 47.485
            lon = -3.12
            locName = "Quiberon (par défaut)"
        }

        // Compute solunar for today
        let todaySolunar = solunarService.calculate(for: Date(), latitude: lat, longitude: lon)

        // Fetch tide data
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let tideData = await tideService.fetchTideForLocation(coordinate)
        let portName = tideService.selectedPort?.name

        // Find nearest station for wind
        let nearestStation = findNearestStation(lat: lat, lon: lon)
        let wind = nearestStation?.wind
        let gust = nearestStation?.gust
        let stationName = nearestStation?.name

        // Get pressure from forecast
        await loadPressure(lat: lat, lon: lon)

        // Get wave data from nearest buoy or forecast fallback
        let (waveHeight, wavePeriod, seaTemp, buoyName) = await loadWaveData(lat: lat, lon: lon)

        // Evaluate conditions
        let todayConditions = fishingService.evaluate(
            solunar: todaySolunar,
            tideData: tideData,
            wind: wind,
            gust: gust,
            pressureCurrent: pressureCurrent,
            pressureTrend: pressureTrend,
            waveHeight: waveHeight,
            wavePeriod: wavePeriod,
            seaTemp: seaTemp
        )

        // Build week data (solunar only - no tide/wind/wave prediction per day)
        var week: [(date: Date, solunar: SolunarData, conditions: FishingConditions)] = []
        for offset in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) {
                let sol = solunarService.calculate(for: date, latitude: lat, longitude: lon)
                let cond: FishingConditions
                if offset == 0 {
                    cond = todayConditions
                } else {
                    cond = fishingService.evaluate(
                        solunar: sol,
                        tideData: nil,
                        wind: nil,
                        gust: nil,
                        pressureCurrent: nil,
                        pressureTrend: nil
                    )
                }
                week.append((date: date, solunar: sol, conditions: cond))
            }
        }

        let region = FishingService.detectRegion(latitude: lat, longitude: lon)

        await MainActor.run {
            self.locationName = locName
            self.tidePortName = portName
            self.windStationName = stationName
            self.waveBuoyName = buoyName
            self.currentWaveHeight = waveHeight
            self.currentWavePeriod = wavePeriod
            self.currentSeaTemp = seaTemp
            self.solunarData = todaySolunar
            self.conditions = todayConditions
            self.weekData = week
            self.detectedRegion = region
            if self.expandedSpeciesRegion == nil {
                self.expandedSpeciesRegion = region
            }
            self.isLoading = false
        }
    }

    private func loadPressure(lat: Double, lon: Double) async {
        do {
            let forecast = try await ForecastService.shared.fetchForecast(
                latitude: lat,
                longitude: lon,
                model: .arome
            )

            // Find current hour forecast
            let now = Date()
            let currentHour = forecast.hourly.min(by: {
                abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now))
            })

            // Find 3h ago for trend
            let threeHoursAgo = now.addingTimeInterval(-3 * 3600)
            let pastHour = forecast.hourly.min(by: {
                abs($0.time.timeIntervalSince(threeHoursAgo)) < abs($1.time.timeIntervalSince(threeHoursAgo))
            })

            await MainActor.run {
                self.pressureCurrent = currentHour?.pressureMSL
                if let current = currentHour?.pressureMSL, let past = pastHour?.pressureMSL {
                    self.pressureTrend = current - past
                }
            }
        } catch {
            // Pressure is optional, continue without it
        }
    }

    private func loadWaveData(lat: Double, lon: Double) async -> (height: Double?, period: Double?, temp: Double?, source: String?) {
        // Priority 1: Nearest CANDHIS buoy
        if waveBuoyService.buoys.isEmpty {
            await waveBuoyService.fetchBuoys()
        }

        if let buoy = findNearestBuoy(lat: lat, lon: lon), buoy.hm0 != nil {
            return (buoy.hm0, buoy.tp, buoy.seaTemp, buoy.name)
        }

        // Priority 2: Open-Meteo marine forecast
        do {
            let forecasts = try await SurfForecastService.shared.fetchForecastDirect(latitude: lat, longitude: lon)
            let now = Date()
            let current = forecasts.min(by: {
                abs($0.timestamp.timeIntervalSince(now)) < abs($1.timestamp.timeIntervalSince(now))
            })
            if let h = current?.waveHeight {
                return (h, current?.wavePeriod, nil, "Prévision marine")
            }
        } catch {
            // Wave data is optional
        }

        return (nil, nil, nil, nil)
    }

    private func findNearestBuoy(lat: Double, lon: Double) -> WaveBuoy? {
        let userLocation = CLLocation(latitude: lat, longitude: lon)
        let maxDistance: Double = 150_000 // 150km
        return waveBuoyService.buoys
            .filter { $0.status.isOnline && $0.hm0 != nil }
            .compactMap { buoy -> (buoy: WaveBuoy, distance: Double)? in
                let buoyLocation = CLLocation(latitude: buoy.latitude, longitude: buoy.longitude)
                let dist = userLocation.distance(from: buoyLocation)
                return dist <= maxDistance ? (buoy, dist) : nil
            }
            .min(by: { $0.distance < $1.distance })
            .map { $0.buoy }
    }

    private func findNearestStation(lat: Double, lon: Double) -> WindStation? {
        let userLocation = CLLocation(latitude: lat, longitude: lon)
        return stationManager.stations
            .filter { $0.isOnline && !$0.name.contains("Concorde") && !($0.wind == 0 && $0.gust == 0) }
            .min(by: {
                let loc1 = CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                let loc2 = CLLocation(latitude: $1.latitude, longitude: $1.longitude)
                return loc1.distance(from: userLocation) < loc2.distance(from: userLocation)
            })
    }

    private func updateForSelectedDay(_ date: Date) {
        if let dayData = weekData.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            solunarData = dayData.solunar
            conditions = dayData.conditions
        }
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/Paris")
        return formatter.string(from: date)
    }

    private static func frenchMonthName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "MMMM"
        return formatter.string(from: Date()).capitalized
    }

    private func shortDayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).capitalized
    }
}

// MARK: - Location Picker Sheet

private struct FishingLocationPickerSheet: View {
    @Binding var selectedLocation: ForecastLocation?
    @Binding var isPresented: Bool

    @ObservedObject var locationManager: LocationManager
    @ObservedObject var favoritesManager: FavoritesManager
    @ObservedObject var tideService: TideService

    var body: some View {
        NavigationStack {
            List {
                // Current position
                if let userLocation = locationManager.userLocation {
                    Section("Position actuelle") {
                        Button {
                            selectLocation(name: "Ma position", latitude: userLocation.latitude, longitude: userLocation.longitude)
                        } label: {
                            Label("Ma position", systemImage: "location.fill")
                        }
                    }
                }

                // Favorite stations
                if !favoritesManager.favorites.isEmpty {
                    Section("Stations favorites") {
                        ForEach(favoritesManager.favorites) { favorite in
                            Button {
                                selectLocation(name: favorite.name, latitude: favorite.latitude, longitude: favorite.longitude)
                            } label: {
                                Label(favorite.name, systemImage: "wind")
                            }
                        }
                    }
                }

                // Favorite spots
                if !favoritesManager.favoriteSpots.isEmpty {
                    Section("Spots favoris") {
                        ForEach(favoritesManager.favoriteSpots) { spot in
                            Button {
                                selectLocation(name: spot.name, latitude: spot.latitude, longitude: spot.longitude)
                            } label: {
                                Label(spot.name, systemImage: "mappin.circle.fill")
                            }
                        }
                    }
                }

                // Tide ports
                if !tideService.ports.isEmpty {
                    Section("Ports de marée") {
                        ForEach(tideService.ports) { port in
                            Button {
                                selectLocation(name: port.name, latitude: port.lat, longitude: port.lon)
                            } label: {
                                Label(port.name, systemImage: "water.waves")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lieu de pêche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            if tideService.ports.isEmpty {
                _ = await tideService.fetchPorts()
            }
        }
    }

    private func selectLocation(name: String, latitude: Double, longitude: Double) {
        selectedLocation = ForecastLocation(name: name, latitude: latitude, longitude: longitude)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isPresented = false
        }
    }
}

#Preview {
    FishingView()
}
