import SwiftUI

/// 首頁統計卡片類型
enum StatType: String, CaseIterable, Identifiable, Codable {
    case pendingPickup          // 待取件
    case deliveredLast30Days    // 近30天已取
    case thisMonthSpending      // 本月總花費
    case pendingAmount          // 待取包裹金額
    case last30DaysSpending     // 近30天總花費
    case thisMonthDelivered     // 本月已取
    case inTransit              // 運送中
    case avgDeliveryDays        // 平均配送天數
    case spendingDelta          // 相較上月花費
    case codPendingAmount       // 貨到付款待付

    var id: String { rawValue }

    /// SF Symbol 圖示
    var icon: String {
        switch self {
        case .pendingPickup:        return "shippingbox.fill"
        case .deliveredLast30Days:  return "checkmark.rectangle.stack.fill"
        case .thisMonthSpending:    return "dollarsign.circle.fill"
        case .pendingAmount:        return "banknote.fill"
        case .last30DaysSpending:   return "yensign.circle.fill"
        case .thisMonthDelivered:   return "checkmark.seal.fill"
        case .inTransit:            return "truck.box.fill"
        case .avgDeliveryDays:      return "clock.badge.checkmark.fill"
        case .spendingDelta:        return "chart.line.uptrend.xyaxis"
        case .codPendingAmount:     return "creditcard.fill"
        }
    }

    /// 圖示顏色
    var iconColor: Color {
        switch self {
        case .pendingPickup:        return .orange
        case .deliveredLast30Days:  return .green
        case .thisMonthSpending:    return .blue
        case .pendingAmount:        return .yellow
        case .last30DaysSpending:   return .cyan
        case .thisMonthDelivered:   return .mint
        case .inTransit:            return .indigo
        case .avgDeliveryDays:      return .purple
        case .spendingDelta:        return .red
        case .codPendingAmount:     return .orange
        }
    }

    /// 本地化標籤
    var localizedLabel: String {
        switch self {
        case .pendingPickup:        return String(localized: "stat.pendingPickup")
        case .deliveredLast30Days:  return String(localized: "stat.deliveredLast30Days")
        case .thisMonthSpending:    return String(localized: "stat.thisMonthSpending")
        case .pendingAmount:        return String(localized: "stat.pendingAmount")
        case .last30DaysSpending:   return String(localized: "stat.last30DaysSpending")
        case .thisMonthDelivered:   return String(localized: "stat.thisMonthDelivered")
        case .inTransit:            return String(localized: "stat.inTransit")
        case .avgDeliveryDays:      return String(localized: "stat.avgDeliveryDays")
        case .spendingDelta:        return String(localized: "stat.spendingDelta")
        case .codPendingAmount:     return String(localized: "stat.codPendingAmount")
        }
    }

    /// 預設選擇
    static let defaultStat1: StatType = .pendingPickup
    static let defaultStat2: StatType = .deliveredLast30Days
}

// MARK: - StatValue

/// 統計卡片的顯示值
enum StatValue {
    case integer(Int)
    case currency(Double)
    case text(String)
    case days(Double)
    case delta(current: Double, previous: Double)

    /// 格式化顯示字串
    var displayString: String {
        switch self {
        case .integer(let n):
            return "\(n)"
        case .currency(let amount):
            return Self.formatCurrency(amount)
        case .text(let str):
            return str
        case .days(let avg):
            if avg < 0 {
                return "--"
            }
            if avg == avg.rounded() {
                return "\(Int(avg)) " + String(localized: "stat.unit.days")
            }
            return String(format: "%.1f ", avg) + String(localized: "stat.unit.days")
        case .delta(let current, let previous):
            let diff = current - previous
            if current == 0 && previous == 0 {
                return "$0"
            }
            let formatted = Self.formatCurrency(abs(diff))
            if diff > 0 {
                return "\u{2191}" + formatted  // ↑
            } else if diff < 0 {
                return "\u{2193}" + formatted  // ↓
            }
            return formatted
        }
    }

    /// delta 的顏色（花費增加紅色，減少綠色）
    var deltaColor: Color {
        if case .delta(let current, let previous) = self {
            if current > previous { return .red }
            if current < previous { return .green }
        }
        return .primary
    }

    /// 是否為整數類型（用於判斷是否使用動畫數字）
    var isInteger: Bool {
        if case .integer = self { return true }
        return false
    }

    /// 取得整數值（用於 RollingNumberView）
    var integerValue: Int {
        if case .integer(let n) = self { return n }
        return 0
    }

    private static func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}
