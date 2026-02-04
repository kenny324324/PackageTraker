import SwiftUI

/// 付款方式
enum PaymentMethod: String, CaseIterable, Identifiable {
    case prepaid = "prepaid"    // 已付款
    case cod = "cod"            // 貨到付款（Cash on Delivery）
    case free = "free"          // 免運/贈品
    
    var id: String { rawValue }
    
    /// 顯示名稱
    var displayName: String {
        switch self {
        case .prepaid:  return String(localized: "payment.prepaid")
        case .cod:      return String(localized: "payment.cod")
        case .free:     return String(localized: "payment.free")
        }
    }
    
    /// 圖標
    var iconName: String {
        switch self {
        case .prepaid:  return "creditcard.fill"
        case .cod:      return "banknote.fill"
        case .free:     return "gift.fill"
        }
    }
    
    /// 顏色
    var color: Color {
        switch self {
        case .prepaid:  return .green
        case .cod:      return .orange
        case .free:     return .blue
        }
    }
}
