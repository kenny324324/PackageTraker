//
//  ParsedEmailResult.swift
//  PackageTraker
//
//  郵件解析結果 DTO
//

import Foundation

/// 郵件來源（電商/物流商）
enum EmailSource: String, CaseIterable {
    // 電商平台
    case shopee = "shopee"
    case momo = "momo"
    case pchome = "pchome"

    // 物流商
    case sevenEleven = "7-11"
    case familyMart = "familymart"
    case tcat = "tcat"
    case sfExpress = "sf"

    // 未知
    case unknown = "unknown"

    /// 顯示名稱
    var displayName: String {
        switch self {
        case .shopee: return "蝦皮購物"
        case .momo: return "momo購物"
        case .pchome: return "PChome"
        case .sevenEleven: return "7-11"
        case .familyMart: return "全家"
        case .tcat: return "黑貓宅急便"
        case .sfExpress: return "順豐速運"
        case .unknown: return "未知來源"
        }
    }

    /// 對應的 Carrier 類型
    var carrier: Carrier? {
        switch self {
        case .shopee: return .shopee
        case .sevenEleven: return .sevenEleven
        case .familyMart: return .familyMart
        case .tcat: return .tcat
        case .sfExpress: return .sfExpress
        case .momo, .pchome, .unknown: return nil
        }
    }
}

/// 郵件解析結果
struct ParsedEmailResult: Identifiable {
    let id = UUID()

    /// 郵件來源
    let source: EmailSource

    /// 物流單號
    let trackingNumber: String

    /// 物流商
    let carrier: Carrier

    /// 取件碼（若有）
    let pickupCode: String?

    /// 取件門市（若有）
    let pickupLocation: String?

    /// 商品描述（若有）
    let orderDescription: String?

    /// 郵件日期
    let emailDate: Date

    /// 原始郵件 ID（用於去重）
    let emailMessageId: String?

    /// 是否為到店通知
    var isArrivalNotification: Bool {
        return pickupCode != nil || pickupLocation != nil
    }
}

/// 郵件元資料（從 Gmail API 取得）
struct GmailMessage: Identifiable {
    let id: String
    let threadId: String
    let subject: String
    let sender: String
    let receivedDate: Date
    let snippet: String
    let body: String
}

/// 郵件同步結果
struct EmailSyncResult {
    /// 成功解析的郵件數量
    let parsedCount: Int

    /// 新增的包裹數量
    let newPackagesCount: Int

    /// 更新的包裹數量
    let updatedPackagesCount: Int

    /// 解析失敗的郵件數量
    let failedCount: Int

    /// 同步時間
    let syncedAt: Date

    /// 錯誤訊息（若有）
    let errors: [String]

    /// 是否完全成功
    var isSuccess: Bool {
        return failedCount == 0 && errors.isEmpty
    }

    /// 摘要描述
    var summary: String {
        if newPackagesCount == 0 && updatedPackagesCount == 0 {
            return "沒有發現新的物流資訊"
        }

        var parts: [String] = []
        if newPackagesCount > 0 {
            parts.append("新增 \(newPackagesCount) 個包裹")
        }
        if updatedPackagesCount > 0 {
            parts.append("更新 \(updatedPackagesCount) 個包裹")
        }
        return parts.joined(separator: "，")
    }
}
