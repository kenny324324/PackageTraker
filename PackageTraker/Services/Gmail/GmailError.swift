//
//  GmailError.swift
//  PackageTraker
//
//  Gmail 服務錯誤類型
//

import Foundation

/// Gmail 服務相關錯誤
enum GmailError: Error, LocalizedError {
    case notSignedIn
    case signInCancelled
    case signInFailed(underlying: Error?)
    case scopeNotGranted
    case tokenRefreshFailed
    case networkError(underlying: Error)
    case rateLimited
    case parsingError(message: String)
    case invalidResponse
    case noEmailsFound

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "尚未登入 Gmail"
        case .signInCancelled:
            return "登入已取消"
        case .signInFailed(let error):
            if let error = error {
                return "登入失敗：\(error.localizedDescription)"
            }
            return "登入失敗"
        case .scopeNotGranted:
            return "需要授權讀取郵件權限"
        case .tokenRefreshFailed:
            return "無法更新驗證，請重新登入"
        case .networkError:
            return "網路連線失敗，請稍後再試"
        case .rateLimited:
            return "請求過於頻繁，請稍後再試"
        case .parsingError(let message):
            return "郵件解析失敗：\(message)"
        case .invalidResponse:
            return "Gmail 回應異常"
        case .noEmailsFound:
            return "未找到物流相關郵件"
        }
    }
}
