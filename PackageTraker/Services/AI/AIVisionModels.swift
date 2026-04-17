//
//  AIVisionModels.swift
//  PackageTraker
//
//  AI Vision recognition result models
//

import Foundation

/// AI 辨識結果
struct AIVisionResult: Codable {
    let trackingNumber: String?
    let carrier: String?
    let pickupLocation: String?
    let pickupCode: String?
    let packageName: String?
    let estimatedDelivery: String?
    let purchasePlatform: String?
    let amount: String?
    let confidence: Double?

    /// 嘗試模糊比對物流商名稱
    var detectedCarrier: Carrier? {
        guard let carrierName = carrier?.lowercased() else { return nil }

        let mappings: [(keywords: [String], carrier: Carrier)] = [
            // 超商取貨
            (["蝦皮", "shopee", "spx"], .shopee),
            (["7-11", "7-eleven", "統一", "交貨便", "賣貨便"], .sevenEleven),
            (["全家", "familymart", "family"], .familyMart),
            (["ok超商", "okmart", "ok mart"], .okMart),
            (["萊爾富", "hilife", "hi-life"], .hiLife),
            // 國內宅配
            (["黑貓", "tcat", "t-cat", "宅急便"], .tcat),
            (["新竹物流", "hct"], .hct),
            (["宅配通", "ecan", "e-can"], .ecan),
            (["中華郵政", "郵局", "post", "chunghwa"], .postTW),
            // 電商物流
            (["pchome", "網家速配", "網家"], .pchome),
            (["momo", "富昇物流", "富昇"], .momo),
            (["嘉里", "大榮", "kerry"], .kerry),
            (["台灣快遞", "taiwan express", "嘉里快遞"], .taiwanExpress),
            // 國際快遞
            (["順豐", "sf express", "sf"], .sfExpress),
            (["菜鳥", "cainiao"], .cainiao),
            (["dhl"], .dhl),
            (["fedex", "聯邦快遞"], .fedex),
            (["ups"], .ups),
            // 其他
            (["海關", "關務署", "customs"], .customs),
        ]

        for mapping in mappings {
            for keyword in mapping.keywords {
                if carrierName.contains(keyword) {
                    return mapping.carrier
                }
            }
        }

        return nil
    }

    /// 嘗試比對購買平台
    var detectedPlatform: String? {
        guard let platform = purchasePlatform else { return nil }
        let lowered = platform.lowercased()

        let mappings: [(keywords: [String], name: String)] = [
            (["shopee", "蝦皮"], "蝦皮購物"),
            (["taobao", "淘寶"], "淘寶"),
            (["pchome"], "PChome 24h"),
            (["momo"], "momo購物網"),
            (["yahoo"], "Yahoo購物中心"),
            (["amazon"], "Amazon"),
        ]

        for mapping in mappings {
            for keyword in mapping.keywords {
                if lowered.contains(keyword) {
                    return mapping.name
                }
            }
        }

        return platform
    }

    /// 數字金額
    var numericAmount: Double? {
        guard let amount = amount else { return nil }
        // 移除非數字字元（保留小數點）
        let cleaned = amount.filter { $0.isNumber || $0 == "." }
        return Double(cleaned)
    }
}

/// AI Vision 錯誤
enum AIVisionError: LocalizedError {
    case subscriptionRequired
    case invalidImage
    case apiKeyMissing
    case apiError(statusCode: Int?, rawMessage: String?)
    case parseError
    case sdkNotAvailable
    case dailyLimitReached
    case freeTrialExhausted
    case proRequired

    var isQuotaExceeded: Bool {
        switch self {
        case .apiError(let statusCode, let rawMessage):
            if statusCode == 429 {
                return true
            }

            guard let rawMessage else { return false }
            let lowered = rawMessage.lowercased()
            return lowered.contains("quota") || lowered.contains("rate limit")
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired, .proRequired:
            return String(localized: "ai.error.subscriptionRequired")
        case .invalidImage:
            return String(localized: "error.imageLoadFailed")
        case .apiKeyMissing:
            return String(localized: "ai.error.apiKeyMissing")
        case .apiError:
            if isQuotaExceeded {
                return String(localized: "ai.error.quotaExceeded")
            }
            return String(localized: "ai.error.serviceUnavailable")
        case .parseError:
            return String(localized: "ai.error.parseFailed")
        case .sdkNotAvailable:
            return String(localized: "ai.error.sdkNotAvailable")
        case .dailyLimitReached:
            return String(localized: "ai.error.dailyLimitReached")
        case .freeTrialExhausted:
            return String(localized: "aiTrial.exhausted.subtitle")
        }
    }
}
