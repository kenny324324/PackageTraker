//
//  FirebasePushService.swift
//  PackageTraker
//
//  FCM Token 管理：註冊推播、上傳/清除 Token（支援多裝置）
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UIKit

@MainActor
final class FirebasePushService: NSObject, ObservableObject {
    static let shared = FirebasePushService()

    @Published var fcmToken: String?

    private let db = Firestore.firestore()

    /// 當前裝置的唯一 ID（同 app 同裝置固定）
    private var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    private override init() {
        super.init()
        Messaging.messaging().delegate = self
    }

    // MARK: - 註冊推播

    func registerForPushNotifications() async {
        let granted = await NotificationService.shared.requestAuthorization()
        guard granted else {
            print("[FCM] Notification permission denied")
            return
        }

        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - 上傳 Token（多裝置：寫入 fcmTokens map）

    func uploadToken() async {
        guard let userId = Auth.auth().currentUser?.uid,
              let token = fcmToken else {
            return
        }

        do {
            try await db.collection("users").document(userId).setData([
                "fcmTokens.\(deviceId)": [
                    "token": token,
                    "lastActive": FieldValue.serverTimestamp()
                ],
                "lastActive": FieldValue.serverTimestamp()
            ], merge: true)
            print("[FCM] ✅ Token uploaded for device \(deviceId)")
        } catch {
            print("[FCM] ❌ Failed to upload token: \(error.localizedDescription)")
        }
    }

    // MARK: - 清除 Token（登出時只刪除當前裝置）

    func clearToken() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        do {
            try await db.collection("users").document(userId).updateData([
                "fcmTokens.\(deviceId)": FieldValue.delete()
            ])
            print("[FCM] ✅ Token cleared for device \(deviceId)")
        } catch {
            print("[FCM] ❌ Failed to clear token: \(error.localizedDescription)")
        }
    }
}

// MARK: - MessagingDelegate

extension FirebasePushService: MessagingDelegate {
    nonisolated func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        print("[FCM] Token received: \(fcmToken ?? "nil")")

        Task { @MainActor in
            self.fcmToken = fcmToken
            if Auth.auth().currentUser != nil {
                await self.uploadToken()
            }
        }
    }
}
