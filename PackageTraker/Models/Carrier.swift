import SwiftUI

/// 物流商分類
enum CarrierCategory: String, CaseIterable, Identifiable {
    case convenienceStore  // 超商取貨
    case domestic          // 國內宅配
    case ecommerce         // 電商物流
    case international     // 國際快遞
    case other             // 其他

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .convenienceStore: return String(localized: "carrierCategory.convenienceStore")
        case .domestic:         return String(localized: "carrierCategory.domestic")
        case .ecommerce:        return String(localized: "carrierCategory.ecommerce")
        case .international:    return String(localized: "carrierCategory.international")
        case .other:            return String(localized: "carrierCategory.other")
        }
    }
}

/// 物流商定義
enum Carrier: String, CaseIterable, Identifiable, Codable {
    // 超商取貨
    case sevenEleven    // 7-11 交貨便
    case familyMart     // 全家店到店
    case hiLife         // 萊爾富
    case okMart         // OK 超商
    case shopee         // 蝦皮店到店

    // 國內宅配
    case tcat           // 黑貓宅急便
    case hct            // 新竹物流
    case ecan           // 宅配通
    case postTW         // 中華郵政

    // 電商物流
    case pchome         // PChome 網家速配
    case momo           // momo 富昇物流
    case kerry          // 嘉里大榮物流
    case taiwanExpress  // 台灣快遞

    // 國際快遞
    case dhl
    case fedex
    case ups
    case sfExpress      // 順豐速運
    case yanwen
    case cainiao        // 菜鳥

    // 其他
    case customs        // 關務署（海關）
    case other

    var id: String { rawValue }

    /// 物流商分類
    var category: CarrierCategory {
        switch self {
        case .sevenEleven, .familyMart, .hiLife, .okMart, .shopee:
            return .convenienceStore
        case .tcat, .hct, .ecan, .postTW:
            return .domestic
        case .pchome, .momo, .kerry, .taiwanExpress:
            return .ecommerce
        case .dhl, .fedex, .ups, .sfExpress, .yanwen, .cainiao:
            return .international
        case .customs, .other:
            return .other
        }
    }

    /// 物流商顯示名稱
    var displayName: String {
        switch self {
        case .dhl:            return "DHL Express"
        case .fedex:          return "FedEx"
        case .ups:            return "UPS"
        case .sfExpress:      return String(localized: "carrier.sfExpress")
        case .yanwen:         return "Yanwen"
        case .cainiao:        return "Cainiao"
        case .tcat:           return String(localized: "carrier.tcat")
        case .hct:            return String(localized: "carrier.hct")
        case .ecan:           return String(localized: "carrier.ecan")
        case .postTW:         return String(localized: "carrier.postTW")
        case .sevenEleven:    return String(localized: "carrier.sevenEleven")
        case .familyMart:     return String(localized: "carrier.familyMart")
        case .hiLife:         return String(localized: "carrier.hiLife")
        case .okMart:         return String(localized: "carrier.okMart")
        case .shopee:         return String(localized: "carrier.shopee")
        case .pchome:         return "PChome"
        case .momo:           return "momo"
        case .kerry:          return String(localized: "carrier.kerry")
        case .taiwanExpress:  return String(localized: "carrier.taiwanExpress")
        case .customs:        return String(localized: "carrier.customs")
        case .other:          return String(localized: "carrier.other")
        }
    }

    /// Logo 縮寫（用於 placeholder）
    var abbreviation: String {
        switch self {
        case .dhl:            return "DHL"
        case .fedex:          return "FDX"
        case .ups:            return "UPS"
        case .sfExpress:      return "SF"
        case .yanwen:         return "YW"
        case .cainiao:        return "CN"
        case .tcat:           return "黑貓"
        case .hct:            return "新竹"
        case .ecan:           return "宅配"
        case .postTW:         return "郵局"
        case .sevenEleven:    return "711"
        case .familyMart:     return "全家"
        case .hiLife:         return "萊富"
        case .okMart:         return "OK"
        case .shopee:         return "蝦皮"
        case .pchome:         return "PC"
        case .momo:           return "momo"
        case .kerry:          return "大榮"
        case .taiwanExpress:  return "台快"
        case .customs:        return "海關"
        case .other:          return "?"
        }
    }

    /// Logo 圖片名稱（Assets 中的圖片）
    var logoImageName: String? {
        switch self {
        case .sevenEleven:    return "SevenEleven"
        case .familyMart:     return "FamilyMart"
        case .hiLife:         return "HiLife"
        case .okMart:         return "OKMart"
        case .shopee:         return "Shopee"
        case .tcat:           return "Tcat"
        case .hct:            return "HCT"
        case .ecan:           return "Ecan"
        case .postTW:         return "PostTW"
        case .pchome:         return "PChome"
        case .momo:           return "Momo"
        case .kerry:          return "Kerry"
        case .dhl:            return "DHL"
        case .fedex:          return "FedEx"
        case .ups:            return "UPS"
        case .sfExpress:      return "SFExpress"
        case .customs:        return "Customs"
        default:              return nil  // yanwen, cainiao, taiwanExpress, other
        }
    }

    /// Logo 背景顏色
    var brandColor: Color {
        switch self {
        case .dhl:            return Color(red: 1.0, green: 0.8, blue: 0.0)    // DHL 黃
        case .fedex:          return Color(red: 0.3, green: 0.1, blue: 0.5)    // FedEx 紫
        case .ups:            return Color(red: 0.4, green: 0.25, blue: 0.1)   // UPS 棕
        case .sfExpress:      return Color(red: 0.0, green: 0.0, blue: 0.0)    // 順豐 黑
        case .yanwen:         return Color(red: 0.2, green: 0.4, blue: 0.8)    // 藍
        case .cainiao:        return Color(red: 1.0, green: 0.4, blue: 0.0)    // 菜鳥 橘
        case .tcat:           return Color(red: 0.0, green: 0.0, blue: 0.0)    // 黑貓 黑
        case .hct:            return Color(red: 0.0, green: 0.5, blue: 0.3)    // 新竹 綠
        case .ecan:           return Color(red: 0.8, green: 0.2, blue: 0.2)    // 宅配通 紅
        case .postTW:         return Color(red: 0.0, green: 0.5, blue: 0.0)    // 郵局 綠
        case .sevenEleven:    return .white                                    // 7-11 白底
        case .familyMart:     return .white                                    // 全家 白底
        case .hiLife:         return Color(red: 1.0, green: 0.3, blue: 0.0)    // 萊爾富 橘
        case .okMart:         return .white                                    // OK 白底
        case .shopee:         return Color(hex: "EA501F")                      // 蝦皮 橘紅
        case .pchome:         return Color(red: 0.8, green: 0.0, blue: 0.2)    // PChome 紅
        case .momo:           return Color(red: 0.6, green: 0.2, blue: 0.4)    // momo 紫紅
        case .kerry:          return Color(red: 0.0, green: 0.3, blue: 0.6)    // 大榮 藍
        case .taiwanExpress:  return Color(red: 0.2, green: 0.5, blue: 0.8)    // 台快 藍
        case .customs:        return Color(red: 0.3, green: 0.3, blue: 0.3)    // 海關 灰
        case .other:          return .gray
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

    /// 支援的物流商（所有有 Track.TW UUID 的物流商）
    static var supportedCarriers: [Carrier] {
        allCases.filter { $0.trackTwUUID != nil }
    }

    /// 依分類取得物流商
    static func carriers(for category: CarrierCategory) -> [Carrier] {
        supportedCarriers.filter { $0.category == category }
    }

    /// Track.TW 物流商 UUID
    var trackTwUUID: String? {
        switch self {
        case .sevenEleven:    return "9a980809-8865-4741-9f0a-3daaaa7d9e19"
        case .familyMart:     return "9a980968-0ecf-4ee5-8765-fbeaed8a524e"
        case .hiLife:         return "9a980b3f-450f-4564-b73e-2ebd867666b0"
        case .okMart:         return "9a980d97-1101-4adb-87eb-78266878b384"
        case .shopee:         return "9a98100c-c984-463d-82a6-ae86ec4e0b8a"
        case .tcat:           return "9a98160d-27e3-40ab-9357-9d81466614e0"
        case .hct:            return "9a9840bc-a5d9-4c4a-8cd2-a79031b4ad53"
        case .ecan:           return "9a984351-dc4f-405b-971c-671220c75f21"
        case .postTW:         return "9a9812d2-c275-4726-9bdc-2ae5b4c42c73"
        case .pchome:         return "9a981858-a4f4-484c-82ad-f1da04dcc5be"
        case .momo:           return "9a983a0c-2100-4da2-a98f-f7c83970dc35"
        case .kerry:          return "9a98424a-935f-4b23-9a94-a08e1db52944"
        case .taiwanExpress:  return "9bec8b8e-6903-471d-b04c-a85c1ead56a9"
        case .dhl:            return "9e2f3446-d91a-4b23-aa11-8a4bc40bde38"
        case .fedex:          return "9b8d0e69-d3b7-4fff-a066-50f9a81d8064"
        case .ups:            return "9b6d1f55-5a40-40ba-a16d-219d1f762192"
        case .sfExpress:      return "9b39c083-c77d-45a9-b403-2112bcddb1ae"
        case .customs:        return "9a98475f-1ba5-4371-bec5-b13cffd6d54b"
        default:              return nil
        }
    }

    /// 從 Track.TW UUID 反向查詢 Carrier
    static func fromTrackTwUUID(_ uuid: String) -> Carrier? {
        allCases.first { $0.trackTwUUID == uuid }
    }
}
