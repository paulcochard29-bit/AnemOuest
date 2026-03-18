import SwiftUI
import WidgetKit

struct WidgetSettingsView: View {
    @StateObject private var favoritesManager = FavoritesManager.shared
    @State private var config = AnemWidgetConfig()
    @State private var favorites: [WidgetStationData] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Widget Carré (Small)
                Section {
                    NavigationLink {
                        StationPickerView(
                            title: "Widget Carré",
                            subtitle: "Sélectionnez le spot à afficher",
                            maxSelection: 1,
                            selectedIds: config.smallWidgetStationId.map { [$0] } ?? [],
                            favorites: favorites,
                            onSave: { ids in
                                config.smallWidgetStationId = ids.first
                                saveConfig()
                            }
                        )
                    } label: {
                        HStack {
                            WidgetPreviewIcon(type: .small)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Widget Carré")
                                    .font(.system(size: 15, weight: .semibold))

                                if let stationId = config.smallWidgetStationId,
                                   let station = favorites.first(where: { $0.id == stationId }) {
                                    Text(station.name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Premier favori par défaut")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()
                        }
                    }
                } header: {
                    Text("Widgets")
                } footer: {
                    Text("Affiche 1 spot avec détails complets")
                }

                // MARK: - Widget Rectangle (Medium)
                Section {
                    NavigationLink {
                        StationPickerView(
                            title: "Widget Rectangle",
                            subtitle: "Sélectionnez jusqu'à 3 spots",
                            maxSelection: 3,
                            selectedIds: config.mediumWidgetStationIds,
                            favorites: favorites,
                            onSave: { ids in
                                config.mediumWidgetStationIds = ids
                                saveConfig()
                            }
                        )
                    } label: {
                        HStack {
                            WidgetPreviewIcon(type: .medium)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Widget Rectangle")
                                    .font(.system(size: 15, weight: .semibold))

                                if !config.mediumWidgetStationIds.isEmpty {
                                    let names = config.mediumWidgetStationIds.compactMap { id in
                                        favorites.first(where: { $0.id == id })?.name
                                    }
                                    Text(names.joined(separator: ", "))
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("3 premiers favoris par défaut")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()
                        }
                    }
                } footer: {
                    Text("Affiche jusqu'à 3 spots côte à côte")
                }

                // MARK: - Widget Grand (Large)
                Section {
                    NavigationLink {
                        StationPickerView(
                            title: "Widget Grand",
                            subtitle: "Sélectionnez jusqu'à 6 spots",
                            maxSelection: 6,
                            selectedIds: config.largeWidgetStationIds,
                            favorites: favorites,
                            onSave: { ids in
                                config.largeWidgetStationIds = ids
                                saveConfig()
                            }
                        )
                    } label: {
                        HStack {
                            WidgetPreviewIcon(type: .large)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Widget Grand")
                                    .font(.system(size: 15, weight: .semibold))

                                if !config.largeWidgetStationIds.isEmpty {
                                    Text("\(config.largeWidgetStationIds.count) spot(s) sélectionné(s)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("6 premiers favoris par défaut")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()
                        }
                    }
                } footer: {
                    Text("Affiche jusqu'à 6 spots en grille")
                }

                // MARK: - Options d'affichage
                Section {
                    Toggle(isOn: $config.showGustSpeed) {
                        Label("Rafales", systemImage: "wind")
                    }
                    .onChange(of: config.showGustSpeed) { _, _ in saveConfig() }

                    Toggle(isOn: $config.showDirection) {
                        Label("Direction du vent", systemImage: "location.north.fill")
                    }
                    .onChange(of: config.showDirection) { _, _ in saveConfig() }

                    Toggle(isOn: $config.showLastUpdate) {
                        Label("Dernière mise à jour", systemImage: "clock")
                    }
                    .onChange(of: config.showLastUpdate) { _, _ in saveConfig() }

                    Toggle(isOn: $config.showOnlineStatus) {
                        Label("Statut en ligne", systemImage: "circle.fill")
                    }
                    .onChange(of: config.showOnlineStatus) { _, _ in saveConfig() }
                } header: {
                    Text("Affichage")
                }

                // MARK: - Unités
                Section {
                    Picker(selection: $config.windUnit) {
                        ForEach(WindUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    } label: {
                        Label("Unité de vent", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    }
                    .onChange(of: config.windUnit) { _, _ in saveConfig() }
                } header: {
                    Text("Unités")
                } footer: {
                    Text("L'unité sera appliquée à tous les widgets")
                }

                // MARK: - Thème
                Section {
                    Picker(selection: $config.colorTheme) {
                        ForEach(WidgetColorTheme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    } label: {
                        Label("Thème", systemImage: "paintpalette")
                    }
                    .onChange(of: config.colorTheme) { _, _ in saveConfig() }
                } header: {
                    Text("Apparence")
                } footer: {
                    switch config.colorTheme {
                    case .auto:
                        Text("Le thème s'adapte au mode clair/sombre du système")
                    case .light:
                        Text("Fond clair pour tous les widgets")
                    case .dark:
                        Text("Fond sombre pour tous les widgets")
                    case .colorful:
                        Text("Fond coloré selon l'intensité du vent")
                    }
                }

                // MARK: - Actions
                Section {
                    Button {
                        refreshWidgets()
                    } label: {
                        Label("Actualiser les widgets", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive) {
                        resetConfig()
                    } label: {
                        Label("Réinitialiser les réglages", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadConfig()
                loadFavorites()
            }
        }
    }

    private func loadConfig() {
        config = AppGroupManager.shared.loadConfiguration()
    }

    private func loadFavorites() {
        favorites = AppGroupManager.shared.loadFavoritesForWidget()
    }

    private func saveConfig() {
        AppGroupManager.shared.saveConfiguration(config)
        refreshWidgets()
    }

    private func resetConfig() {
        config = AnemWidgetConfig()
        saveConfig()
    }

    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Widget Preview Icon

struct WidgetPreviewIcon: View {
    enum WidgetType {
        case small, medium, large
    }

    let type: WidgetType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width, height: height)

            // Mini content preview
            VStack(spacing: 2) {
                switch type {
                case .small:
                    Text("18")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                case .medium:
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 12, height: 20)
                        }
                    }
                case .large:
                    VStack(spacing: 3) {
                        HStack(spacing: 3) {
                            ForEach(0..<2, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.5))
                                    .frame(width: 16, height: 12)
                            }
                        }
                        HStack(spacing: 3) {
                            ForEach(0..<2, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.5))
                                    .frame(width: 16, height: 12)
                            }
                        }
                    }
                }
            }
        }
        .padding(.trailing, 12)
    }

    private var width: CGFloat {
        switch type {
        case .small: return 44
        case .medium: return 70
        case .large: return 50
        }
    }

    private var height: CGFloat {
        switch type {
        case .small: return 44
        case .medium: return 36
        case .large: return 50
        }
    }
}

// MARK: - Station Picker View

struct StationPickerView: View {
    let title: String
    let subtitle: String
    let maxSelection: Int
    let selectedIds: [String]
    let favorites: [WidgetStationData]
    let onSave: ([String]) -> Void

    @State private var selection: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Default option
            Section {
                Button {
                    selection = []
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automatique")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)

                            Text(maxSelection == 1 ? "Utiliser le premier favori" : "Utiliser les \(maxSelection) premiers favoris")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if selection.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.system(size: 20))
                        }
                    }
                }
            }

            // Favorites selection
            Section {
                if favorites.isEmpty {
                    HStack {
                        Image(systemName: "star")
                            .foregroundStyle(.secondary)
                        Text("Aucun favori disponible")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(favorites) { station in
                        Button {
                            toggleSelection(station.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(station.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.primary)

                                    HStack(spacing: 8) {
                                        Text(station.source)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)

                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(station.isOnline ? Color.green : Color.red)
                                                .frame(width: 6, height: 6)
                                            Text(station.isOnline ? "En ligne" : "Hors ligne")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }

                                Spacer()

                                // Selection indicator
                                if let index = selection.firstIndex(of: station.id) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 24, height: 24)

                                        if maxSelection > 1 {
                                            Text("\(index + 1)")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.white)
                                        } else {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                } else {
                                    Circle()
                                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 2)
                                        .frame(width: 24, height: 24)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Sélection manuelle")
            } footer: {
                if maxSelection > 1 {
                    Text("Touchez les spots dans l'ordre souhaité. \(selection.count)/\(maxSelection) sélectionné(s).")
                } else {
                    Text("Sélectionnez le spot à afficher dans ce widget.")
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") {
                    onSave(selection)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            selection = selectedIds
        }
    }

    private func toggleSelection(_ id: String) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            if maxSelection == 1 {
                selection = [id]
            } else if selection.count < maxSelection {
                selection.append(id)
            }
        }
    }
}

#Preview {
    WidgetSettingsView()
}
