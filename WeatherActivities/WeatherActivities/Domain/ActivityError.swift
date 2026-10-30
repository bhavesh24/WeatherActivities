import Foundation

/// Every failure the app can surface.
///
/// Lower layers translate their own errors (`URLError`, `DecodingError`, HTTP status codes)
/// into this type, so presentation code never needs to know about transport details.
enum ActivityError: Error, Equatable, Sendable {
    case invalidQuery
    case offline
    case timedOut
    case server(statusCode: Int, reason: String?)
    case invalidResponse
    case noForecastData
    case unknown
}

extension ActivityError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Enter at least 2 characters to search for a city."
        case .offline:
            return "You appear to be offline. Check your connection and try again."
        case .timedOut:
            return "The request took too long. Please try again."
        case let .server(statusCode, reason):
            if let reason, !reason.isEmpty {
                return "The weather service rejected the request: \(reason)"
            }
            return "The weather service is unavailable right now (HTTP \(statusCode)). Please try again later."
        case .invalidResponse:
            return "The weather service returned data we couldn't understand."
        case .noForecastData:
            return "No forecast is available for this location right now."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
}

extension ActivityError {
    /// Normalises any thrown error into an `ActivityError`.
    ///
    /// Cancellation is deliberately *not* handled here: callers catch `CancellationError`
    /// first, because a cancelled request is not something to show the user.
    static func from(_ error: Error) -> ActivityError {
        if let activityError = error as? ActivityError {
            return activityError
        }
        if let urlError = error as? URLError {
            return map(urlError: urlError)
        }
        if error is DecodingError {
            return .invalidResponse
        }
        return .unknown
    }

    static func map(urlError: URLError) -> ActivityError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .unknown
        }
    }
}
