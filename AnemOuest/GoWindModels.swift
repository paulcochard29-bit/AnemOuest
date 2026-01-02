import Foundation
import CoreLocation

// One entry from https://gowind.fr/php/anemo/carte_des_vents.json
struct GoWindStationDTO: Codable, Identifiable {
    let type: String
    let nom: String
    let icone: String?
    let now: String?
    let id: String
    let vmax: String?
    let vmoy: String?
    let ortexte: String?
    let couleur: String?
    let ordegre: String?
    let lat: String?
    let lon: String?
    let mode: String?
    let dern_r: Int?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon,
              let la = Double(lat), let lo = Double(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }

    var wind: Double? { Double(vmoy ?? "") }
    var gust: Double? { Double(vmax ?? "") }
    var dirDeg: Double? { Double(ordegre ?? "") }

    var isOnline: Bool {
        // mode:"ON" et dern_r == 0 (dans ton exemple)
        (mode?.uppercased() == "ON") && ((dern_r ?? 0) == 0)
    }

    var measuredAt: Date? {
        guard let now else { return nil }
        return GoWindDateParser.parse(now)
    }
}

// Local history sample for GoWind
struct GoWindHistorySample: Codable, Identifiable {
    let id: String          // unique id
    let t: Date
    let wind: Double?
    let gust: Double?
    let dir: Double?
}

enum GoWindDateParser {
    private static let f: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.timeZone = TimeZone.current
        df.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return df
    }()

    static func parse(_ s: String) -> Date? {
        f.date(from: s)
    }
}
