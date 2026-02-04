import SwiftUI

/// 物流商定義
enum Carrier: String, CaseIterable, Identifiable, Codable {
    // 國際快遞（走 AfterShip）
    case dhl
    case fedex
    case ups
    case sfExpress      // 順豐速運
    case yanwen
    case cainiao        // 菜鳥

    // 台灣宅配（走本地爬蟲）
    case tcat           // 黑貓宅急便
    case hct            // 新竹物流
    case ecan           // 宅配通
    case postTW         // 中華郵政

    // 超商取貨（走本地爬蟲）
    case sevenEleven    // 7-11 交貨便
    case familyMart     // 全家店到店
    case hiLife         // 萊爾富
    case okMart         // OK 超商

    // 電商自有（僅 Deep Link）
    case shopee         // 蝦皮店到店

    // 其他
    case other

    var id: String { rawValue }

    /// 物流商顯示名稱
    var displayName: String {
        switch self {
        case .dhl:          return "DHL"
        case .fedex:        return "FedEx"
        case .ups:          return "UPS"
        case .sfExpress:    return String(localized: "carrier.sfExpress")
        case .yanwen:       return "Yanwen"
        case .cainiao:      return "Cainiao"
        case .tcat:         return String(localized: "carrier.tcat")
        case .hct:          return String(localized: "carrier.hct")
        case .ecan:         return String(localized: "carrier.ecan")
        case .postTW:       return String(localized: "carrier.postTW")
        case .sevenEleven:  return String(localized: "carrier.sevenEleven")
        case .familyMart:   return String(localized: "carrier.familyMart")
        case .hiLife:       return String(localized: "carrier.hiLife")
        case .okMart:       return String(localized: "carrier.okMart")
        case .shopee:       return String(localized: "carrier.shopee")
        case .other:        return String(localized: "carrier.other")
        }
    }

    /// Logo 縮寫（用於 placeholder）
    var abbreviation: String {
        switch self {
        case .dhl:          return "DHL"
        case .fedex:        return "FDX"
        case .ups:          return "UPS"
        case .sfExpress:    return "SF"
        case .yanwen:       return "YW"
        case .cainiao:      return "CN"
        case .tcat:         return "黑貓"
        case .hct:          return "新竹"
        case .ecan:         return "宅配"
        case .postTW:       return "郵局"
        case .sevenEleven:  return "711"
        case .familyMart:   return "全家"
        case .hiLife:       return "萊富"
        case .okMart:       return "OK"
        case .shopee:       return "蝦皮"
        case .other:        return "?"
        }
    }

    /// Logo 圖片名稱（Assets 中的圖片）
    var logoImageName: String? {
        switch self {
        case .sevenEleven:  return "SevenEleven"
        case .familyMart:   return "FamilyMart"
        case .okMart:       return "OKMart"
        case .shopee:       return "Shopee"
        default:            return nil
        }
    }
    
    /// Logo 背景顏色
    var brandColor: Color {
        switch self {
        case .dhl:          return Color(red: 1.0, green: 0.8, blue: 0.0)    // DHL 黃
        case .fedex:        return Color(red: 0.3, green: 0.1, blue: 0.5)    // FedEx 紫
        case .ups:          return Color(red: 0.4, green: 0.25, blue: 0.1)   // UPS 棕
        case .sfExpress:    return Color(red: 0.0, green: 0.0, blue: 0.0)    // 順豐 黑
        case .yanwen:       return Color(red: 0.2, green: 0.4, blue: 0.8)    // 藍
        case .cainiao:      return Color(red: 1.0, green: 0.4, blue: 0.0)    // 菜鳥 橘
        case .tcat:         return Color(red: 0.0, green: 0.0, blue: 0.0)    // 黑貓 黑
        case .hct:          return Color(red: 0.0, green: 0.5, blue: 0.3)    // 新竹 綠
        case .ecan:         return Color(red: 0.8, green: 0.2, blue: 0.2)    // 宅配通 紅
        case .postTW:       return Color(red: 0.0, green: 0.5, blue: 0.0)    // 郵局 綠
        case .sevenEleven:  return .white                                    // 7-11 白底
        case .familyMart:   return .white                                    // 全家 白底
        case .hiLife:       return Color(red: 1.0, green: 0.3, blue: 0.0)    // 萊爾富 橘
        case .okMart:       return .white                                    // OK 白底
        case .shopee:       return Color(hex: "EA501F")                      // 蝦皮 橘紅 (官方色)
        case .other:        return .gray
        }
    }

    /// Logo 文字顏色
    var textColor: Color {
        switch self {
        case .sevenEleven, .familyMart, .okMart:
            return .black  // 白底用黑字
        case .dhl, .cainiao:
            return .black
        default:
            return .white
        }
    }

    /// 預設取貨地點（用於分類顯示）
    var defaultPickupLocation: String {
        switch self {
        case .sevenEleven:  return String(localized: "carrier.sevenEleven")
        case .familyMart:   return String(localized: "carrier.familyMart")
        case .okMart:       return String(localized: "carrier.okMart")
        case .shopee:       return String(localized: "carrier.shopee")
        default:            return displayName
        }
    }

    /// 支援的物流商（用於 AddPackageView）
    static let supportedCarriers: [Carrier] = [
        .sevenEleven,
        .familyMart,
        .okMart,
        .shopee
    ]

    /// parcel-tw API 的 platform 值
    var parcelTwPlatform: String? {
        switch self {
        case .sevenEleven:  return "seven_eleven"
        case .familyMart:   return "family_mart"
        case .okMart:       return "okmart"
        case .shopee:       return "shopee"
        default:            return nil
        }
    }

    /// Track.TW 物流商 UUID
    /// 用於 track.tw/carrier/{uuid}/{trackingNumber} 查詢
    var trackTwUUID: String? {
        switch self {
        case .sevenEleven:  return "9a980809-8865-4741-9f0a-3daaaa7d9e19"
        case .familyMart:   return "9a980968-0ecf-4ee5-8765-fbeaed8a524e"
        case .shopee:       return "9a98100c-c984-463d-82a6-ae86ec4e0b8a"
        case .tcat:         return "9a98160d-27e3-40ab-9357-9d81466614e0"
        case .hct:          return "9a9840bc-a5d9-4c4a-8cd2-a79031b4ad53"
        case .okMart:       return "9a980d97-1101-4adb-87eb-78266878b384"
        case .ecan:         return "9a984351-dc4f-405b-971c-671220c75f21"
        case .hiLife:       return "9a980b17-d9e3-4e1b-9c67-d0e0c6c5e3a4"  // 需確認
        case .postTW:       return "9a981f5c-6e8a-4d2b-8c1a-5f3e2d1c0b9a"  // 需確認
        default:            return nil
        }
    }

    /// 追蹤方式
    enum TrackingMethod {
        case trackTw    // 透過 Track.TW 平台
        case aftership  // 透過 AfterShip API（國際）
        case manual     // 手動更新
    }

    var trackingMethod: TrackingMethod {
        if trackTwUUID != nil {
            return .trackTw
        }
        switch self {
        case .dhl, .fedex, .ups, .yanwen, .cainiao:
            return .aftership
        default:
            return .manual
        }
    }
}
