import Foundation

final class GoWindService {
    private let url = URL(string: "https://gowind.fr/php/anemo/carte_des_vents.json")!

    func fetchStations() async throws -> [GoWindStationDTO] {
        let (data, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        // Le JSON est généralement un tableau d’objets.
        // Si GoWind change le format, on ajustera.
        return try JSONDecoder().decode([GoWindStationDTO].self, from: data)
    }
}
