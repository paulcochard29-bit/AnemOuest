import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Control Center Widget: Quick Wind Check

struct AnemOuestWidgetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "Wind.AnemOuest.WindControl",
            provider: WindControlProvider()
        ) { value in
            ControlWidgetButton(action: OpenAppIntent()) {
                Label {
                    Text(value.display)
                } icon: {
                    Image(systemName: "wind")
                }
            }
        }
        .displayName("Vent")
        .description("Vent actuel de votre spot favori")
    }
}

// MARK: - Control Value Provider

extension AnemOuestWidgetControl {
    struct WindControlProvider: ControlValueProvider {
        var previewValue: WindControlValue {
            WindControlValue(stationName: "Glenan", wind: 18, gust: 25, unit: "nds")
        }

        func currentValue() async throws -> WindControlValue {
            let stations = AppGroupManager.shared.getStationsForSmallWidget()
            let config = AppGroupManager.shared.loadConfiguration()

            guard let station = stations.first else {
                return WindControlValue(stationName: "—", wind: 0, gust: 0, unit: config.windUnit.symbol)
            }

            let wind = Int(config.windUnit.convert(fromKnots: station.wind))
            let gust = Int(config.windUnit.convert(fromKnots: station.gust))

            return WindControlValue(
                stationName: station.name,
                wind: wind,
                gust: gust,
                unit: config.windUnit.symbol
            )
        }
    }
}

// MARK: - Control Value

struct WindControlValue {
    let stationName: String
    let wind: Int
    let gust: Int
    let unit: String

    var display: String {
        "\(stationName): \(wind)/\(gust) \(unit)"
    }
}

// MARK: - Open App Intent

struct OpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Ouvrir Le Vent"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
