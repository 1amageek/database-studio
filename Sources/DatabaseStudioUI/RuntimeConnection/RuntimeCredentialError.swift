import Foundation
import Security

enum RuntimeCredentialError: Error, LocalizedError {
    case status(OSStatus)
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .status(let status): "Keychain operation failed (\(status))."
        case .invalidEncoding: "The stored credential is not valid UTF-8."
        }
    }
}
