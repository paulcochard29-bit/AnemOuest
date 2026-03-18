import Foundation
import os.log

/// Logger conditionnel - Affiche les logs uniquement en mode DEBUG
/// En production (Release), tous les logs sont désactivés pour les performances
enum Log {

    private static let subsystem = Bundle.main.bundleIdentifier ?? "AnemOuest"

    // Catégories de logs - marked nonisolated(unsafe) since Logger is thread-safe
    nonisolated(unsafe) private static let networkLogger = Logger(subsystem: subsystem, category: "Network")
    nonisolated(unsafe) private static let dataLogger = Logger(subsystem: subsystem, category: "Data")
    nonisolated(unsafe) private static let uiLogger = Logger(subsystem: subsystem, category: "UI")
    nonisolated(unsafe) private static let widgetLogger = Logger(subsystem: subsystem, category: "Widget")
    nonisolated(unsafe) private static let generalLogger = Logger(subsystem: subsystem, category: "General")

    // MARK: - Public API

    /// Log général (debug uniquement)
    nonisolated static func debug(_ message: String) {
        #if DEBUG
        generalLogger.debug("\(message)")
        #endif
    }

    /// Log réseau (API calls, etc.)
    nonisolated static func network(_ message: String) {
        #if DEBUG
        networkLogger.debug("🌐 \(message)")
        #endif
    }

    /// Log données (parsing, cache, etc.)
    nonisolated static func data(_ message: String) {
        #if DEBUG
        dataLogger.debug("📦 \(message)")
        #endif
    }

    /// Log UI (interactions, animations, etc.)
    nonisolated static func ui(_ message: String) {
        #if DEBUG
        uiLogger.debug("🎨 \(message)")
        #endif
    }

    /// Log widget (App Group, data sharing, etc.)
    nonisolated static func widget(_ message: String) {
        #if DEBUG
        widgetLogger.debug("📱 \(message)")
        #endif
    }

    /// Log d'erreur (toujours affiché, même en Release)
    nonisolated static func error(_ message: String) {
        generalLogger.error("❌ \(message)")
    }

    /// Log d'avertissement
    nonisolated static func warning(_ message: String) {
        #if DEBUG
        generalLogger.warning("⚠️ \(message)")
        #endif
    }

    /// Log de succès
    nonisolated static func success(_ message: String) {
        #if DEBUG
        generalLogger.info("✅ \(message)")
        #endif
    }
}
