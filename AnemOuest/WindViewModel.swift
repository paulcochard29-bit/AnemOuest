import Foundation
import Combine

@MainActor
final class WindViewModel: ObservableObject {

    // MARK: - Published state (utilisé par ContentView)
    @Published var latestBySensorId: [String: WCWindObservation] = [:]
    @Published var samples: [WCChartSample] = []
    @Published var lastUpdatedAt: Date? = nil
    @Published var hadRecentError: Bool = false

    private var timer: AnyCancellable?

    // MARK: - Auto refresh
    func startAutoRefresh(
        sensorIds: [String],
        selectedSensorId: @escaping () -> String?,
        timeFrame: @escaping () -> Int,
        refreshIntervalSeconds: @escaping () -> Double
    ) {
        stopAutoRefresh()

        timer = Timer
            .publish(every: refreshIntervalSeconds(), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }

                Task {
                    do {
                        try await self.refreshAll(sensorIds: sensorIds)
                        if let id = selectedSensorId() {
                            await self.loadSelected(sensorId: id, timeFrame: timeFrame())
                        }
                        self.hadRecentError = false
                        self.lastUpdatedAt = Date()
                    } catch {
                        self.hadRecentError = true
                    }
                }
            }
    }

    func stopAutoRefresh() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Load selected sensor (graph)
    func loadSelected(sensorId: String, timeFrame: Int) async {
        do {
            let result = try await WindService.fetchChartWC(sensorId: sensorId, timeFrame: timeFrame)
            self.samples = result.samples
            self.latestBySensorId[sensorId] = result.latest
        } catch {
            self.hadRecentError = true
        }
    }

    // MARK: - Refresh all sensors (map)
    private func refreshAll(sensorIds: [String]) async throws {
        for id in sensorIds {
            let latest = try await WindService.fetchLatestWC(sensorId: id)
            latestBySensorId[id] = latest
        }
    }
}
