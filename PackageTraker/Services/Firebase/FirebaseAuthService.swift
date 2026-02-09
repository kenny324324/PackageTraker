//
//  FirebaseAuthService.swift
//  PackageTraker
//
//  Firebase Authentication 整合：管理 Apple Sign In 登入流程
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

/// Firebase 認證服務：處理 Apple Sign In 與用戶管理
@MainActor
final class FirebaseAuthService: NSObject, ObservableObject {
    static let shared = FirebaseAuthService()

    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false

    private var currentNonce: String?
    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?

    private override init() {
        super.init()

        // 監聽認證狀態變化
        authStateListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
        }
    }

    deinit {
        if let handle = authStateListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Apple Sign In

    /// 開始 Apple Sign In 流程，產生 nonce 並配置請求
    func startSignInWithAppleFlow() -> ASAuthorizationAppleIDRequest {
        let nonce = randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = sha256(nonce)

        return request
    }

    /// 使用 Apple Sign In 的 credential 登入 Firebase
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let nonce = currentNonce,
              let appleIDToken = credential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        isLoading = true
        defer { isLoading = false }

        let result = try await Auth.auth().signIn(with: firebaseCredential)
        currentUser = result.user

        // 初次登入時在 Firestore 建立用戶資料
        await createUserProfileIfNeeded(user: result.user, credential: credential)
    }

    /// 登出
    func signOut() throws {
        try Auth.auth().signOut()
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: - Firestore 用戶資料

    /// 首次登入時建立用戶 profile
    private func createUserProfileIfNeeded(user: User, credential: ASAuthorizationAppleIDCredential) async {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.uid)

        // 檢查是否已存在
        let userDoc = try? await userRef.getDocument()
        if userDoc?.exists == true {
            // 更新 lastActive
            try? await userRef.updateData([
                "lastActive": FieldValue.serverTimestamp()
            ])
            return
        }

        // 建立新用戶資料
        let userData: [String: Any] = [
            "appleId": credential.user,
            "email": credential.email ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "lastActive": FieldValue.serverTimestamp(),
            "notificationSettings": [
                "enabled": true,
                "arrivalNotification": true,
                "pickupReminder": true
            ]
        ]

        try? await userRef.setData(userData)
    }

    // MARK: - Nonce 工具

    /// 產生隨機 nonce 字串
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }

        return String(nonce)
    }

    /// SHA256 雜湊
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()

        return hashString
    }
}

// MARK: - Auth Error

/// 認證錯誤
enum AuthError: LocalizedError {
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return String(localized: "auth.error.invalidCredential")
        }
    }
}
