import SwiftUI
import CoreLocation

struct SpotAlertConfigView: View {
    let spot: FavoriteSpot
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    @ObservedObject private var stationManager = WindStationManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var settings: SpotAlertSettings
    @State private var testResult: String?
    @State private var isTestingNotification = false

    init(spot: FavoriteSpot) {
        self.spot = spot
        _settings = State(initialValue: spot.alertSettings ?? (spot.type == .kite ? .defaultKite : .defaultSurf))
    }

    private let windDirections = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    private let weekdays = [
        (1, "Lun"), (2, "Mar"), (3, "Mer"), (4, "Jeu"),
        (5, "Ven"), (6, "Sam"), (7, "Dim")
    ]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Header
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(spot.type == .kite ? Color.orange : Color.cyan)
                                .frame(width: 44, height: 44)

                            Image(systemName: spot.type.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(spot.name)
                                .font(.headline)
                            Text(spot.type.displayName + " • " + spot.orientation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                // MARK: - Alertes
                Section {
                    Toggle(isOn: $settings.isEnabled) {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(settings.isEnabled ? .green : .secondary)
                                .frame(width: 20)
                            Text("Alertes actives")
                        }
                    }
                } footer: {
                    Text("Recevez une notification quand les conditions sont favorables")
                }

                // MARK: - Test notification (toujours visible)
                Section {
                    Button {
                        testNotification()
                    } label: {
                        HStack {
                            Spacer()
                            if isTestingNotification {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Label("Tester la notification", systemImage: "bell.badge")
                            Spacer()
                        }
                    }
                    .disabled(isTestingNotification)

                    if let result = testResult {
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Debug", systemImage: "ladybug")
                } footer: {
                    Text("Teste les conditions actuelles et envoie une notification si favorable")
                }

                if settings.isEnabled {
                    // MARK: - Conditions de vent
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Vent minimum")
                                Spacer()
                                Text("\(WindUnit.convertValue(settings.minWindSpeed)) \(WindUnit.current.symbol)")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.minWindSpeed, in: 5...35, step: 1)
                                .tint(.blue)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Vent maximum")
                                Spacer()
                                Text("\(WindUnit.convertValue(settings.maxWindSpeed)) \(WindUnit.current.symbol)")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.maxWindSpeed, in: 10...50, step: 1)
                                .tint(.orange)
                        }

                        Toggle(isOn: $settings.useSpotOrientation) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Orientation du spot")
                                Text(spot.orientation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !settings.useSpotOrientation {
                            DirectionPicker(
                                selection: Binding(
                                    get: { Set(settings.customWindDirections ?? []) },
                                    set: { settings.customWindDirections = Array($0) }
                                ),
                                directions: windDirections
                            )
                        }
                    } header: {
                        Label("Conditions de vent", systemImage: "wind")
                    }

                    // MARK: - Conditions de vagues (Surf only)
                    if spot.type == .surf {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Hauteur minimum")
                                    Spacer()
                                    Text(String(format: "%.1f m", settings.minWaveHeight ?? 0.5))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { settings.minWaveHeight ?? 0.5 },
                                        set: { settings.minWaveHeight = $0 }
                                    ),
                                    in: 0.3...2.0,
                                    step: 0.1
                                )
                                .tint(.cyan)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Hauteur maximum")
                                    Spacer()
                                    Text(String(format: "%.1f m", settings.maxWaveHeight ?? 2.5))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { settings.maxWaveHeight ?? 2.5 },
                                        set: { settings.maxWaveHeight = $0 }
                                    ),
                                    in: 0.5...4.0,
                                    step: 0.1
                                )
                                .tint(.blue)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Periode minimum")
                                    Spacer()
                                    Text("\(Int(settings.minWavePeriod ?? 8)) s")
                                        .foregroundStyle(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { settings.minWavePeriod ?? 8 },
                                        set: { settings.minWavePeriod = $0 }
                                    ),
                                    in: 5...15,
                                    step: 1
                                )
                                .tint(.purple)
                            }
                        } header: {
                            Label("Conditions de vagues", systemImage: "water.waves")
                        }

                        Section {
                            Picker("Maree preferee", selection: $settings.tidePreference) {
                                ForEach(TideAlertPreference.allCases, id: \.self) { pref in
                                    Label(pref.displayName, systemImage: pref.icon)
                                        .tag(pref)
                                }
                            }
                        } header: {
                            Label("Maree", systemImage: "water.waves.and.arrow.up")
                        }
                    }

                    // MARK: - Marée pour Kite (si le spot a une préférence)
                    if spot.type == .kite, let kiteTidePref = spot.kiteTidePreference,
                       let tidePref = KiteTidePreference(rawValue: kiteTidePref), tidePref != .all {
                        Section {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(tidePref.color.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: tidePref.icon)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(tidePref.color)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ce spot requiert: \(tidePref.displayName)")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Les alertes respecteront cette preference")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .listRowBackground(tidePref.color.opacity(0.08))
                        } header: {
                            Label("Maree du spot", systemImage: "water.waves.and.arrow.up")
                        } footer: {
                            Text("Vous ne recevrez des alertes que lorsque la maree sera compatible")
                        }
                    }

                    // MARK: - Score minimum
                    Section {
                        Picker("Score minimum", selection: $settings.minConditionScore) {
                            Text("Correct (40+)").tag(40)
                            Text("Bon (60+)").tag(60)
                            Text("Excellent (80+)").tag(80)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Label("Qualite des conditions", systemImage: "star.fill")
                    } footer: {
                        Text("Score calcule selon le vent, les vagues et la maree")
                    }

                    // MARK: - Horaires
                    Section {
                        HStack {
                            Text("De")
                            Spacer()
                            Picker("", selection: $settings.alertStartHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text("\(hour)h").tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 80)
                        }

                        HStack {
                            Text("A")
                            Spacer()
                            Picker("", selection: $settings.alertEndHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text("\(hour)h").tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 80)
                        }

                        DayPicker(selection: $settings.alertDays, days: weekdays)
                    } header: {
                        Label("Horaires d'alerte", systemImage: "clock")
                    } footer: {
                        Text("Notifications uniquement pendant ces horaires")
                    }

                    // MARK: - Alertes meteo
                    Section {
                        Toggle(isOn: $settings.alertOnRain) {
                            HStack(spacing: 10) {
                                Image(systemName: "cloud.rain")
                                    .foregroundStyle(.blue)
                                    .frame(width: 20)
                                Text("Alerte pluie")
                            }
                        }

                        Toggle(isOn: $settings.alertOnStorm) {
                            HStack(spacing: 10) {
                                Image(systemName: "cloud.bolt")
                                    .foregroundStyle(.yellow)
                                    .frame(width: 20)
                                Text("Alerte orage")
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "wind")
                                    .foregroundStyle(.red)
                                    .frame(width: 20)
                                Text("Rafales max")
                                Spacer()
                                Text("\(WindUnit.convertValue(settings.maxGustThreshold)) \(WindUnit.current.symbol)")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.maxGustThreshold, in: 30...60, step: 5)
                                .tint(.red)
                        }
                    } header: {
                        Label("Alertes meteo", systemImage: "exclamationmark.triangle")
                    } footer: {
                        Text("Soyez prevenu en cas de conditions dangereuses")
                    }

                    // MARK: - Alertes etendues
                    Section {
                        Toggle(isOn: $settings.alertOnWindTrend) {
                            HStack(spacing: 10) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundStyle(.green)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tendance vent")
                                    Text("Alerter quand le vent monte ou baisse")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if settings.alertOnWindTrend {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Variation minimum")
                                    Spacer()
                                    Text("\(WindUnit.convertValue(settings.windTrendThreshold)) \(WindUnit.current.symbol)")
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $settings.windTrendThreshold, in: 3...15, step: 1)
                                    .tint(.green)
                            }
                        }

                        Toggle(isOn: $settings.alertOnModelDisagreement) {
                            HStack(spacing: 10) {
                                Image(systemName: "square.stack.3d.up.trianglebadge.exclamationmark")
                                    .foregroundStyle(.purple)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Divergence modeles")
                                    Text("Quand AROME, GFS, etc. ne sont pas d'accord")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if settings.alertOnModelDisagreement {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Ecart minimum")
                                    Spacer()
                                    Text("\(WindUnit.convertValue(settings.modelDisagreementThreshold)) \(WindUnit.current.symbol)")
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $settings.modelDisagreementThreshold, in: 5...20, step: 1)
                                    .tint(.purple)
                            }
                        }

                        Toggle(isOn: $settings.alertBeforeTide) {
                            HStack(spacing: 10) {
                                Image(systemName: "water.waves.and.arrow.up")
                                    .foregroundStyle(.teal)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Rappel maree")
                                    Text("Prevenir avant pleine/basse mer")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if settings.alertBeforeTide {
                            Picker("Prevenir avant", selection: $settings.tideAlertMinutesBefore) {
                                Text("30 min").tag(30)
                                Text("1 heure").tag(60)
                                Text("1h30").tag(90)
                                Text("2 heures").tag(120)
                            }
                        }
                    } header: {
                        Label("Alertes etendues", systemImage: "bell.badge.waveform")
                    } footer: {
                        Text("Tendance vent, divergence modeles et rappels de maree")
                    }

                    // MARK: - Avance
                    Section {
                        Stepper(value: $settings.cooldownHours, in: 1...24) {
                            HStack {
                                Text("Delai entre alertes")
                                Spacer()
                                Text("\(settings.cooldownHours)h")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Stepper(value: $settings.forecastHoursAhead, in: 1...48) {
                            HStack {
                                Text("Prevenir a l'avance")
                                Spacer()
                                Text("\(settings.forecastHoursAhead)h")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Toggle(isOn: $settings.includeInBestSpotComparison) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Comparaison multi-spots")
                                Text("Inclure dans \"Meilleur spot\"")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Label("Avance", systemImage: "gearshape")
                    }
                }

                // MARK: - Supprimer des favoris
                Section {
                    Button(role: .destructive) {
                        favoritesManager.removeSpotFavorite(id: spot.id)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Retirer des favoris", systemImage: "heart.slash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        favoritesManager.setSpotAlertSettings(for: spot.id, settings: settings)
                        HapticManager.shared.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Test Notification

    private func testNotification() {
        isTestingNotification = true
        testResult = nil

        // Save current settings first
        favoritesManager.setSpotAlertSettings(for: spot.id, settings: settings)

        // Reset cooldown for this spot
        notificationManager.resetCooldown(for: spot.id)

        Task {
            // Fetch forecast for this spot
            var forecast: ForecastData?
            var surfForecast: SurfWaveForecast?
            var tideData: TideData?

            do {
                forecast = try await ForecastService.shared.fetchForecast(
                    latitude: spot.latitude,
                    longitude: spot.longitude
                )
            } catch {
                await MainActor.run {
                    testResult = "❌ Erreur prévision: \(error.localizedDescription)"
                    isTestingNotification = false
                }
                return
            }

            if spot.type == .surf {
                do {
                    let forecasts = try await SurfForecastService.shared.fetchForecastDirect(
                        latitude: spot.latitude,
                        longitude: spot.longitude
                    )
                    surfForecast = forecasts.first
                } catch {
                    // Continue without surf forecast
                }
            }

            // Fetch tide
            let coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
            tideData = await TideService.shared.fetchTideForLocation(coordinate)

            // Get updated spot with settings
            let updatedSpot = FavoriteSpot(
                id: spot.id,
                name: spot.name,
                type: spot.type,
                latitude: spot.latitude,
                longitude: spot.longitude,
                orientation: spot.orientation,
                addedAt: spot.addedAt,
                alertSettings: settings,
                kiteTidePreference: spot.kiteTidePreference
            )

            // Run test
            await MainActor.run {
                let result = notificationManager.testSpotNotification(
                    spot: updatedSpot,
                    forecast: forecast,
                    surfForecast: surfForecast,
                    tideData: tideData,
                    nearbyStations: stationManager.stations
                )
                testResult = result
                isTestingNotification = false
                HapticManager.shared.success()
            }
        }
    }
}

// MARK: - Direction Picker

private struct DirectionPicker: View {
    @Binding var selection: Set<String>
    let directions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Directions personnalisees")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(directions, id: \.self) { direction in
                    Button {
                        if selection.contains(direction) {
                            selection.remove(direction)
                        } else {
                            selection.insert(direction)
                        }
                        HapticManager.shared.selection()
                    } label: {
                        Text(direction)
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selection.contains(direction) ? Color.blue : Color(.systemGray5))
                            )
                            .foregroundStyle(selection.contains(direction) ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Day Picker

private struct DayPicker: View {
    @Binding var selection: Set<Int>
    let days: [(Int, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Jours actifs")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(days, id: \.0) { day in
                    Button {
                        if selection.contains(day.0) {
                            selection.remove(day.0)
                        } else {
                            selection.insert(day.0)
                        }
                        HapticManager.shared.selection()
                    } label: {
                        Text(day.1)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selection.contains(day.0) ? Color.blue : Color(.systemGray5))
                            )
                            .foregroundStyle(selection.contains(day.0) ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let sampleSpot = FavoriteSpot(
        id: "sample",
        name: "La Torche",
        type: .surf,
        latitude: 47.83,
        longitude: -4.35,
        orientation: "W,NW",
        addedAt: Date(),
        alertSettings: .defaultSurf
    )
    return SpotAlertConfigView(spot: sampleSpot)
}
