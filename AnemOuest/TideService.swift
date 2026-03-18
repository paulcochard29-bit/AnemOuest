import Foundation
import CoreLocation
import SwiftUI
import Combine

// MARK: - Tide Models

struct TidePort: Identifiable, Equatable, Codable {
    let cst: String
    let name: String
    let lat: Double
    let lon: Double
    let region: String

    var id: String { cst }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    static func == (lhs: TidePort, rhs: TidePort) -> Bool {
        lhs.cst == rhs.cst
    }
}

struct TideEvent: Identifiable, Codable {
    let type: String           // "high" or "low"
    let date: String           // "2026-01-26"
    let time: String           // "09:58"
    let datetime: String       // ISO8601
    let height: Double         // meters
    let coefficient: Int?      // coefficient (only for high tide)

    var id: String { datetime }

    var isHighTide: Bool { type == "high" }

    var parsedDateTime: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: datetime) {
            return date
        }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: datetime)
    }

    /// Formatted time display (converted to local timezone from UTC datetime)
    var timeDisplay: String {
        guard let date = parsedDateTime else { return time }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Formatted height display
    var heightDisplay: String {
        String(format: "%.2fm", height)
    }

    /// Coefficient display
    var coefficientDisplay: String {
        guard let coef = coefficient else { return "" }
        return String(coef)
    }

    /// Color based on coefficient
    var coefficientColor: Color {
        guard let coef = coefficient else { return .secondary }
        switch coef {
        case ..<40:
            return .blue           // Mortes eaux
        case ..<70:
            return .green          // Coefficients moyens
        case ..<95:
            return .orange         // Vives eaux
        default:
            return .red            // Grandes marees
        }
    }
}

struct NextTide: Codable {
    let time: String           // ISO8601
    let height: Double
    let coefficient: Int?

    var parsedTime: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: time) {
            return date
        }
        // Fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: time)
    }

    var timeDisplay: String {
        guard let date = parsedTime else { return time.contains("T") ? String(time.split(separator: "T").last?.prefix(5) ?? "") : "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct TideData: Codable {
    let port: TidePort
    let tides: [TideEvent]
    let nextHighTide: NextTide?
    let nextLowTide: NextTide?
    let todayCoefficient: Int?
    let fetchedAt: String

    /// Get tides for a specific date
    func tidesForDate(_ date: Date) -> [TideEvent] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)
        return tides.filter { $0.date == dateStr }
    }

    /// Get today's tides
    var todayTides: [TideEvent] {
        tidesForDate(Date())
    }

    /// Get next tide (high or low)
    var nextTide: (type: String, time: Date, height: Double, coefficient: Int?)? {
        if let nextHigh = nextHighTide?.parsedTime,
           let nextLow = nextLowTide?.parsedTime {
            if nextHigh < nextLow {
                return ("high", nextHigh, nextHighTide!.height, nextHighTide!.coefficient)
            } else {
                return ("low", nextLow, nextLowTide!.height, nil)
            }
        }

        if let nextHigh = nextHighTide?.parsedTime {
            return ("high", nextHigh, nextHighTide!.height, nextHighTide!.coefficient)
        }

        if let nextLow = nextLowTide?.parsedTime {
            return ("low", nextLow, nextLowTide!.height, nil)
        }

        return nil
    }
}

// MARK: - API Response Models

struct TidePortsResponse: Codable {
    let ports: [TidePort]
    let count: Int
}

// MARK: - Tide Service

class TideService: ObservableObject {
    static let shared = TideService()

    private let baseURL = "https://api.levent.live/api/tide"

    @Published var ports: [TidePort] = []
    @Published var currentTideData: TideData?
    @Published var selectedPort: TidePort?
    @Published var isLoading = false
    @Published var error: String?

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Fetch Ports

    func fetchPorts() async -> [TidePort] {
        guard let url = URL(string: "\(baseURL)?list=true") else { return [] }

        do {
            let request = AppConstants.apiRequest(url: url)
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(TidePortsResponse.self, from: data)

            await MainActor.run {
                self.ports = response.ports
            }

            return response.ports
        } catch {
            print("Error fetching tide ports: \(error)")
            return []
        }
    }

    // MARK: - Fetch Tide Data

    func fetchTideData(for port: TidePort, duration: Int = 11) async -> TideData? {
        return await fetchTideData(portCode: port.cst, duration: duration)
    }

    func fetchTideData(portCode: String, duration: Int = 11) async -> TideData? {
        guard let url = URL(string: "\(baseURL)?port=\(portCode)&duration=\(duration)") else { return nil }

        await MainActor.run {
            self.isLoading = true
            self.error = nil
        }

        do {
            let request = AppConstants.apiRequest(url: url)
            let (data, _) = try await URLSession.shared.data(for: request)
            let tideData = try JSONDecoder().decode(TideData.self, from: data)

            await MainActor.run {
                self.currentTideData = tideData
                self.isLoading = false
            }

            return tideData
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
            print("Error fetching tide data: \(error)")
            return nil
        }
    }

    // MARK: - Find Nearest Port

    func findNearestPort(to coordinate: CLLocationCoordinate2D) -> TidePort? {
        guard !ports.isEmpty else { return nil }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return ports.min { port1, port2 in
            let loc1 = CLLocation(latitude: port1.lat, longitude: port1.lon)
            let loc2 = CLLocation(latitude: port2.lat, longitude: port2.lon)
            return location.distance(from: loc1) < location.distance(from: loc2)
        }
    }

    // MARK: - Fetch Tide for Location

    func fetchTideForLocation(_ coordinate: CLLocationCoordinate2D, duration: Int = 11) async -> TideData? {
        // Ensure ports are loaded
        if ports.isEmpty {
            _ = await fetchPorts()
        }

        guard let nearestPort = findNearestPort(to: coordinate) else { return nil }

        await MainActor.run {
            self.selectedPort = nearestPort
        }

        return await fetchTideData(for: nearestPort, duration: duration)
    }
}

// MARK: - Tide Coefficient Description

extension Int {
    var coefficientDescription: String {
        switch self {
        case ..<40:
            return "Mortes eaux"
        case ..<70:
            return "Coefficient moyen"
        case ..<95:
            return "Vives eaux"
        case ..<100:
            return "Vives eaux fortes"
        case ..<110:
            return "Grandes marees"
        default:
            return "Tres grandes marees"
        }
    }
}
