//
//  GmailTokenStorage.swift
//  PackageTraker
//
//  Gmail Token 安全儲存（使用 Keychain）
//

import Foundation
import Security

/// Gmail Token 儲存管理
/// 使用 iOS Keychain 安全儲存 OAuth tokens
final class GmailTokenStorage {

    // MARK: - Constants

    private let service = "com.packagetraker.gmail"
    private let accessTokenKey = "accessToken"
    private let refreshTokenKey = "refreshToken"
    private let expiresAtKey = "expiresAt"
    private let emailKey = "email"

    // MARK: - Singleton

    static let shared = GmailTokenStorage()

    private init() {}

    // MARK: - Public Methods

    /// 儲存 tokens
    func storeTokens(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date,
        email: String
    ) throws {
        try save(key: accessTokenKey, value: accessToken)
        if let refreshToken = refreshToken {
            try save(key: refreshTokenKey, value: refreshToken)
        }
        try save(key: expiresAtKey, value: ISO8601DateFormatter().string(from: expiresAt))
        try save(key: emailKey, value: email)
    }

    /// 取得 access token
    func getAccessToken() -> String? {
        return load(key: accessTokenKey)
    }

    /// 取得 refresh token
    func getRefreshToken() -> String? {
        return load(key: refreshTokenKey)
    }

    /// 取得已登入的 email
    func getEmail() -> String? {
        return load(key: emailKey)
    }

    /// 取得 token 過期時間
    func getExpiresAt() -> Date? {
        guard let dateString = load(key: expiresAtKey) else { return nil }
        return ISO8601DateFormatter().date(from: dateString)
    }

    /// 檢查 token 是否已過期
    func isTokenExpired() -> Bool {
        guard let expiresAt = getExpiresAt() else { return true }
        // 提前 5 分鐘視為過期，以便有時間刷新
        return Date().addingTimeInterval(5 * 60) >= expiresAt
    }

    /// 更新 access token
    func updateAccessToken(_ token: String, expiresAt: Date) throws {
        try save(key: accessTokenKey, value: token)
        try save(key: expiresAtKey, value: ISO8601DateFormatter().string(from: expiresAt))
    }

    /// 清除所有儲存的資料
    func clearAll() {
        delete(key: accessTokenKey)
        delete(key: refreshTokenKey)
        delete(key: expiresAtKey)
        delete(key: emailKey)
    }

    /// 是否已有儲存的 tokens
    var hasStoredTokens: Bool {
        return getAccessToken() != nil
    }

    // MARK: - Keychain Operations

    private func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // 先嘗試刪除舊的值
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Keychain Error

enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "資料編碼失敗"
        case .saveFailed(let status):
            return "Keychain 儲存失敗 (status: \(status))"
        case .loadFailed(let status):
            return "Keychain 讀取失敗 (status: \(status))"
        }
    }
}
