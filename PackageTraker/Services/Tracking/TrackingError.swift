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

    var errorDescription: String? {
        switch self {
        case .unsupportedCarrier(let carrier):
            return "不支援 \(carrier.displayName)"
        case .networkError:
            return "網路連線失敗，請稍後再試"
        case .parsingError(let msg):
            return "解析失敗：\(msg)"
        case .trackingNumberNotFound:
            return "查無此單號"
        case .invalidResponse:
            return "物流商回應異常"
        case .rateLimited:
            return "查詢過於頻繁，請稍後再試"
        case .invalidTrackingNumber:
            return "單號格式不正確"
        }
    }
}
