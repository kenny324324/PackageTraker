import Foundation

/// 追蹤服務錯誤類型
enum TrackingError: Error, LocalizedError {
    case unsupportedCarrier(Carrier)
    case networkError(underlying: Error)
    case parsingError(message: String)
    case trackingNumberNotFound
    case invalidResponse
    case rateLimited
    case invalidTrackingNumber
    case unauthorized
    case serverError(message: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedCarrier(let carrier):
            return String(
                format: String(localized: "error.unsupportedCarrier"),
                carrier.displayName
            )
        case .networkError:
            return String(localized: "error.networkError")
        case .parsingError(let msg):
            return String(
                format: String(localized: "error.parsingError"),
                msg
            )
        case .trackingNumberNotFound:
            return String(localized: "error.trackingNumberNotFound")
        case .invalidResponse:
            return String(localized: "error.invalidResponse")
        case .rateLimited:
            return String(localized: "error.rateLimited")
        case .invalidTrackingNumber:
            return String(localized: "error.invalidTrackingNumber")
        case .unauthorized:
            return String(localized: "error.unauthorized")
        case .serverError(let message):
            return String(
                format: String(localized: "error.serverError"),
                message
            )
        }
    }
}
