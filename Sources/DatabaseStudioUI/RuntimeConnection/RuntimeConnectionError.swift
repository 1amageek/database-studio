import Foundation

enum RuntimeConnectionError: Error, LocalizedError {
    case notConnected

    var errorDescription: String? {
        "Connect to a database runtime before executing this operation."
    }
}
