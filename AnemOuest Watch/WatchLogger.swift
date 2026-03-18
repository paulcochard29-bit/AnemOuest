import Foundation
import os.log

enum WatchLog {
    private static let subsystem = "com.anemouest.watch"
    private static let logger = Logger(subsystem: subsystem, category: "Watch")

    nonisolated static func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message)")
        #endif
    }

    nonisolated static func error(_ message: String) {
        logger.error("\(message)")
    }

    nonisolated static func success(_ message: String) {
        #if DEBUG
        logger.info("\(message)")
        #endif
    }
}
