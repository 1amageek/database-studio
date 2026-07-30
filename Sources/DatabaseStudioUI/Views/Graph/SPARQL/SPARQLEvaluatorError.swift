import Foundation

/// SPARQL 実行時のエラー
enum SPARQLEvaluatorError: Error, Sendable, LocalizedError {
    case typeError(String)
    case unboundVariable(String)
    case divisionByZero
    case invalidRegex(String)
    case resultTooLarge(Int)
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .typeError(let message):
            return "Type error: \(message)"
        case .unboundVariable(let name):
            return "Unbound variable: ?\(name)"
        case .divisionByZero:
            return "Division by zero"
        case .invalidRegex(let pattern):
            return "Invalid regex pattern: \(pattern)"
        case .resultTooLarge(let count):
            return "Result set too large (\(count) rows). Add a LIMIT clause."
        case .unsupportedOperation(let operation):
            return "Unsupported operation: \(operation)"
        }
    }
}
