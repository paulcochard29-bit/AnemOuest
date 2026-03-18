import AppIntents
import WidgetKit

// MARK: - Refresh Widget Intent

struct RefreshWindIntent: AppIntent {
    static var title: LocalizedStringResource = "Actualiser le vent"
    static var description: IntentDescription = "Actualise les données vent du widget"

    func perform() async throws -> some IntentResult {
        await WidgetDataFetcher.shared.refreshAllData()
        WidgetCenter.shared.reloadTimelines(ofKind: "AnemOuestWidget")
        return .result()
    }
}

struct RefreshWaveIntent: AppIntent {
    static var title: LocalizedStringResource = "Actualiser les vagues"
    static var description: IntentDescription = "Actualise les données vagues du widget"

    func perform() async throws -> some IntentResult {
        let _ = await WaveWidgetDataFetcher.shared.refreshData()
        WidgetCenter.shared.reloadTimelines(ofKind: "WaveWidget")
        return .result()
    }
}

// MARK: - Cycle Station Intent (Small Widget)

struct CycleStationIntent: AppIntent {
    static var title: LocalizedStringResource = "Station suivante"
    static var description: IntentDescription = "Affiche la station favori suivante"

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.anemouest.shared")
        let favorites = AppGroupManager.shared.loadFavoritesForWidget()
        guard favorites.count > 1 else { return .result() }

        let currentIndex = defaults?.integer(forKey: "widgetCycleIndex") ?? 0
        let nextIndex = (currentIndex + 1) % favorites.count
        defaults?.set(nextIndex, forKey: "widgetCycleIndex")

        // Update the small widget station ID in config
        var config = AppGroupManager.shared.loadConfiguration()
        config.smallWidgetStationId = favorites[nextIndex].id
        AppGroupManager.shared.saveConfiguration(config)

        WidgetCenter.shared.reloadTimelines(ofKind: "AnemOuestWidget")
        return .result()
    }
}

// MARK: - Toggle Wind Unit Intent

struct ToggleWindUnitIntent: AppIntent {
    static var title: LocalizedStringResource = "Changer l'unite"
    static var description: IntentDescription = "Alterne entre noeuds, km/h, m/s"

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.anemouest.shared")
        let current = WindUnit.current
        let allUnits: [WindUnit] = [.knots, .kmh, .ms]
        let currentIdx = allUnits.firstIndex(of: current) ?? 0
        let nextUnit = allUnits[(currentIdx + 1) % allUnits.count]

        defaults?.set(nextUnit.rawValue, forKey: "windUnit")

        // Also update widget config
        var config = AppGroupManager.shared.loadConfiguration()
        config.windUnit = nextUnit
        AppGroupManager.shared.saveConfiguration(config)

        WidgetCenter.shared.reloadTimelines(ofKind: "AnemOuestWidget")
        return .result()
    }
}

// MARK: - Open Station Intent (deep link)

struct OpenStationIntent: AppIntent {
    static var title: LocalizedStringResource = "Ouvrir la station"
    static var description: IntentDescription = "Ouvre la station dans l'app"

    @Parameter(title: "Station ID")
    var stationId: String

    init() {
        self.stationId = ""
    }

    init(stationId: String) {
        self.stationId = stationId
    }

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
