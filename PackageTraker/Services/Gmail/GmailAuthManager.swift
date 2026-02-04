//
//  GmailAuthManager.swift
//  PackageTraker
//
//  Gmail OAuth 認證管理
//

import Foundation
import SwiftUI
import AuthenticationServices
import Combine

/// Gmail 認證管理器
/// 負責處理 Google OAuth 登入流程
@MainActor
final class GmailAuthManager: ObservableObject {

    // MARK: - ObservableObject Conformance

    nonisolated let objectWillChange = ObservableObjectPublisher()

    // MARK: - Observable Properties

    private(set) var isSignedIn = false {
        willSet { objectWillChange.send() }
    }
    private(set) var userEmail: String? {
        willSet { objectWillChange.send() }
    }
    private(set) var isLoading = false {
        willSet { objectWillChange.send() }
    }
    private(set) var lastError: GmailError? {
        willSet { objectWillChange.send() }
    }

    // MARK: - Private Properties

    private let tokenStorage = GmailTokenStorage.shared
    private let gmailScope = "https://www.googleapis.com/auth/gmail.readonly"

    // Google OAuth 設定
    // 注意：需要在 Google Cloud Console 建立 OAuth 憑證後填入
    private var clientID: String {
        // 從 Info.plist 讀取 Client ID
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
    }

    private var redirectURI: String {
        // 從 Info.plist 讀取反向 Client ID 作為 URL Scheme
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            return ""
        }
        // Google 的反向 Client ID 格式：com.googleusercontent.apps.{clientID}
        let components = clientID.components(separatedBy: ".")
        if let reversedClientID = components.first {
            return "com.googleusercontent.apps.\(reversedClientID):/oauthredirect"
        }
        return ""
    }

    // MARK: - Singleton

    static let shared = GmailAuthManager()

    private init() {
        // 初始化時檢查是否已有儲存的登入狀態
        restoreSession()
    }

    // MARK: - Public Methods

    /// 開始 Google 登入流程
    func signIn() async throws {
        guard !clientID.isEmpty else {
            throw GmailError.signInFailed(underlying: NSError(
                domain: "GmailAuthManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "未設定 Google Client ID，請在 Info.plist 中配置 GIDClientID"]
            ))
        }

        isLoading = true
        lastError = nil

        defer { isLoading = false }

        // 建構 OAuth URL
        let authURL = buildAuthURL()

        // 使用 ASWebAuthenticationSession 進行認證
        let callbackURL = try await performWebAuth(url: authURL)

        // 處理回調，交換 authorization code 取得 tokens
        try await handleCallback(url: callbackURL)
    }

    /// 登出
    func signOut() {
        tokenStorage.clearAll()
        isSignedIn = false
        userEmail = nil
        lastError = nil
    }

    /// 取得有效的 access token（自動刷新過期的 token）
    func getValidAccessToken() async throws -> String {
        guard isSignedIn else {
            throw GmailError.notSignedIn
        }

        // 檢查 token 是否過期
        if tokenStorage.isTokenExpired() {
            try await refreshToken()
        }

        guard let token = tokenStorage.getAccessToken() else {
            throw GmailError.notSignedIn
        }

        return token
    }

    /// 處理 OAuth 回調 URL（從 App Delegate 或 SceneDelegate 呼叫）
    func handleURL(_ url: URL) -> Bool {
        // 檢查是否為我們的 OAuth 回調
        guard url.scheme?.contains("googleusercontent") == true else {
            return false
        }

        // URL 會被 ASWebAuthenticationSession 自動處理
        return true
    }

    // MARK: - Private Methods

    private func restoreSession() {
        if tokenStorage.hasStoredTokens {
            isSignedIn = true
            userEmail = tokenStorage.getEmail()
        }
    }

    private func buildAuthURL() -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!

        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "\(gmailScope) email profile"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        return components.url!
    }

    private func performWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: redirectURI.components(separatedBy: ":").first
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError {
                    if error.code == .canceledLogin {
                        continuation.resume(throwing: GmailError.signInCancelled)
                    } else {
                        continuation.resume(throwing: GmailError.signInFailed(underlying: error))
                    }
                    return
                }

                if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: GmailError.signInFailed(underlying: nil))
                }
            }

            session.presentationContextProvider = WebAuthPresentationContext.shared
            session.prefersEphemeralWebBrowserSession = false

            if !session.start() {
                continuation.resume(throwing: GmailError.signInFailed(underlying: nil))
            }
        }
    }

    private func handleCallback(url: URL) async throws {
        // 從回調 URL 提取 authorization code
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GmailError.signInFailed(underlying: NSError(
                domain: "GmailAuthManager",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "無法從回調 URL 取得授權碼"]
            ))
        }

        // 交換 code 取得 tokens
        try await exchangeCodeForTokens(code: code)
    }

    private func exchangeCodeForTokens(code: String) async throws {
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailError.signInFailed(underlying: nil)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        // 計算過期時間
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        // 取得使用者 email
        let email = try await fetchUserEmail(accessToken: tokenResponse.accessToken)

        // 儲存 tokens
        try tokenStorage.storeTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: expiresAt,
            email: email
        )

        // 更新狀態
        isSignedIn = true
        userEmail = email
    }

    private func refreshToken() async throws {
        guard let refreshToken = tokenStorage.getRefreshToken() else {
            signOut()
            throw GmailError.tokenRefreshFailed
        }

        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "refresh_token": refreshToken,
            "client_id": clientID,
            "grant_type": "refresh_token"
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            signOut()
            throw GmailError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        try tokenStorage.updateAccessToken(tokenResponse.accessToken, expiresAt: expiresAt)
    }

    private func fetchUserEmail(accessToken: String) async throws -> String {
        let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!

        var request = URLRequest(url: userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GmailError.signInFailed(underlying: nil)
        }

        let userInfo = try JSONDecoder().decode(UserInfo.self, from: data)
        return userInfo.email
    }
}

// MARK: - Response Models

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

private struct UserInfo: Decodable {
    let email: String
}

// MARK: - Web Auth Presentation Context

private class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // 取得目前最上層的 window
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
