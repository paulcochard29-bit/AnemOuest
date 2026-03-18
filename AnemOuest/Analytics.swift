//
//  Analytics.swift
//  AnemOuest
//
//  TelemetryDeck analytics — privacy-first, GDPR compliant
//

import Foundation
import TelemetryDeck

enum Analytics {

    static func initialize() {
        var config = TelemetryDeck.Config(appID: "057A2CA2-4ED5-4D75-85CA-A0E767DF3952")
        config.testMode = false
        TelemetryDeck.initialize(config: config)
    }

    // MARK: - App Lifecycle

    static func appOpened(count: Int) {
        TelemetryDeck.signal("app.opened", parameters: ["count": "\(count)"])
    }

    static func appBackgrounded() {
        TelemetryDeck.signal("app.backgrounded")
    }

    // MARK: - Navigation

    static func tabChanged(_ tab: String) {
        TelemetryDeck.signal("nav.tabChanged", parameters: ["tab": tab])
    }

    // MARK: - Stations

    static func stationSelected(name: String, source: String) {
        TelemetryDeck.signal("station.selected", parameters: ["stationName": name, "source": source])
    }

    static func forecastLoaded(stationId: String, source: String) {
        TelemetryDeck.signal("station.forecastLoaded", parameters: ["stationId": stationId, "source": source])
    }

    // MARK: - Favoris

    static func favoriteAdded(type: String, id: String) {
        TelemetryDeck.signal("favorite.added", parameters: ["type": type, "itemId": id])
    }

    static func favoriteRemoved(type: String, id: String) {
        TelemetryDeck.signal("favorite.removed", parameters: ["type": type, "itemId": id])
    }

    // MARK: - Alertes

    static func alertConfigured(type: String, id: String) {
        TelemetryDeck.signal("alert.configured", parameters: ["type": type, "itemId": id])
    }

    static func alertTriggered(type: String) {
        TelemetryDeck.signal("alert.triggered", parameters: ["type": type])
    }

    // MARK: - Partage

    static func shared(type: String, format: String) {
        TelemetryDeck.signal("share.created", parameters: ["type": type, "format": format])
    }

    // MARK: - Webcams

    static func webcamViewed(id: String) {
        TelemetryDeck.signal("webcam.viewed", parameters: ["webcamId": id])
    }

    // MARK: - Recherche

    static func searched(resultsCount: Int) {
        TelemetryDeck.signal("search.performed", parameters: ["resultsCount": "\(resultsCount)"])
    }

    // MARK: - Settings

    static func settingChanged(key: String, value: String) {
        TelemetryDeck.signal("setting.changed", parameters: ["key": key, "value": value])
    }

    static func sourceToggled(source: String, enabled: Bool) {
        TelemetryDeck.signal("setting.sourceToggled", parameters: ["source": source, "enabled": "\(enabled)"])
    }

    // MARK: - Overlays

    static func overlayToggled(type: String, enabled: Bool) {
        TelemetryDeck.signal("overlay.toggled", parameters: ["type": type, "enabled": "\(enabled)"])
    }

    // MARK: - Performance

    static func refreshCompleted(durationMs: Int, stationCount: Int, fromCache: Bool) {
        TelemetryDeck.signal("perf.refreshCompleted", parameters: [
            "durationMs": "\(durationMs)",
            "stationCount": "\(stationCount)",
            "fromCache": "\(fromCache)"
        ])
    }

    static func networkError(source: String, error: String) {
        TelemetryDeck.signal("perf.networkError", parameters: ["source": source, "error": error])
    }

    static func errorShown(type: String) {
        TelemetryDeck.signal("perf.errorShown", parameters: ["type": type])
    }
}
