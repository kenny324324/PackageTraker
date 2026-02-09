import SwiftUI

/// 統一的包裹追蹤狀態
enum TrackingStatus: String, CaseIterable, Identifiable, Codable {
    case pending        // 待出貨
    case shipped        // 已出貨
    case inTransit      // 配送中
    case arrivedAtStore // 已到貨
    case delivered      // 已取貨
    case returned       // 已退回

    var id: String { rawValue }

    /// 狀態顯示名稱
    var displayName: String {
        switch self {
        case .pending:        return String(localized: "status.pending")
        case .shipped:        return String(localized: "status.shipped")
        case .inTransit:      return String(localized: "status.inTransit")
        case .arrivedAtStore: return String(localized: "status.arrivedAtStore")
        case .delivered:      return String(localized: "status.delivered")
        case .returned:       return String(localized: "status.returned")
        }
    }

    /// 狀態對應顏色
    var color: Color {
        switch self {
        case .pending:        return .gray
        case .shipped:        return .orange
        case .inTransit:      return .blue
        case .arrivedAtStore: return .green
        case .delivered:      return .green
        case .returned:       return .red
        }
    }

    /// 狀態對應 SF Symbol
    var iconName: String {
        switch self {
        case .pending:        return "clock"
        case .shipped:        return "shippingbox"
        case .inTransit:      return "truck.box"
        case .arrivedAtStore: return "building.2"
        case .delivered:      return "checkmark.circle.fill"
        case .returned:       return "arrow.uturn.backward.circle.fill"
        }
    }

    /// 是否為待取件狀態（需要使用者行動）
    var isPendingPickup: Bool {
        self == .arrivedAtStore
    }

    /// 是否為已完成狀態（不需要再刷新）
    var isCompleted: Bool {
        self == .delivered || self == .returned
    }

    // MARK: - Track.TW Mapping

    /// 從 Track.TW 的 checkpoint_status + 狀態描述文字對應到 TrackingStatus
    static func fromTrackTw(checkpointStatus: String, statusDescription: String) -> TrackingStatus {
        switch checkpointStatus {
        case "delivered":
            return .delivered
        case "exception":
            if statusDescription.contains("退回") || statusDescription.contains("退貨") {
                return .returned
            }
            return .returned
        case "pending":
            return .pending
        case "transit":
            return mapTransitSubStatus(statusDescription)
        default:
            return .pending
        }
    }

    /// 根據中文描述細分 transit 狀態
    private static func mapTransitSubStatus(_ description: String) -> TrackingStatus {
        // 1. 尚未出貨（優先排除）
        //    「將於...後出貨」「等待出貨」「等待寄件」「準備出貨」「訂單成立」「訂單處理」
        if description.contains("將於") || description.contains("等待出貨") ||
           description.contains("等待寄件") || description.contains("準備出貨") ||
           description.contains("訂單成立") || description.contains("訂單處理") {
            return .pending
        }

        // 2. 已到門市/到店（待取件）
        //    「到店」「到門市」「待取」「可取貨」「配達」「已到達」「已送達」
        if description.contains("到店") || description.contains("到門市") ||
           description.contains("待取") || description.contains("可取貨") ||
           description.contains("配達") || description.contains("已到達") ||
           description.contains("已送達") {
            return .arrivedAtStore
        }

        // 3. 物流運送中
        //    「配送中」「運送中」「轉運」「理貨」「抵達」「派送」「投遞」
        if description.contains("配送中") || description.contains("運送中") ||
           description.contains("轉運") || description.contains("理貨") ||
           description.contains("抵達") || description.contains("派送") ||
           description.contains("投遞") {
            return .inTransit
        }

        // 4. 已出貨/已寄件（注意：前面已排除「將於...出貨」）
        //    「寄件」「出貨」「已收件」「已攬收」
        if description.contains("寄件") || description.contains("出貨") ||
           description.contains("已收件") || description.contains("已攬收") {
            return .shipped
        }

        // 5. 無法判斷，預設配送中
        return .inTransit
    }
}
