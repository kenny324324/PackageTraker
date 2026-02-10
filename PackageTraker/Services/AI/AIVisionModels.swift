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
    let confidence: Double?

    /// 嘗試模糊比對物流商名稱
    var detectedCarrier: Carrier? {
        guard let carrierName = carrier?.lowercased() else { return nil }

        let mappings: [(keywords: [String], carrier: Carrier)] = [
            (["蝦皮", "shopee", "spx"], .shopee),
            (["7-11", "7-eleven", "統一", "交貨便"], .sevenEleven),
            (["全家", "familymart", "family"], .familyMart),
            (["ok超商", "okmart", "ok mart"], .okMart),
            (["萊爾富", "hilife", "hi-life"], .hiLife),
            (["黑貓", "tcat", "t-cat", "宅急便"], .tcat),
            (["新竹物流", "hct"], .hct),
            (["宅配通", "ecan", "e-can"], .ecan),
            (["中華郵政", "郵局", "post", "chunghwa"], .postTW),
            (["順豐", "sf express", "sf"], .sfExpress),
            (["嘉里", "kerry"], .kerry),
            (["菜鳥", "cainiao"], .cainiao),
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
}

/// AI Vision 錯誤
enum AIVisionError: LocalizedError {
    case subscriptionRequired
    case invalidImage
    case apiKeyMissing
    case apiError(String)
    case parseError
    case sdkNotAvailable

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired:
            return String(localized: "ai.error.subscriptionRequired")
        case .invalidImage:
            return String(localized: "error.imageLoadFailed")
        case .apiKeyMissing:
            return String(localized: "ai.error.apiKeyMissing")
        case .apiError(let message):
            return String(localized: "ai.error.apiFailed") + ": \(message)"
        case .parseError:
            return String(localized: "ai.error.parseFailed")
        case .sdkNotAvailable:
            return String(localized: "ai.error.sdkNotAvailable")
        }
    }
}
