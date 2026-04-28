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

/// 從 Firestore 讀回的裝置端通知設定快照（用於診斷比對）
struct RemoteNotificationSettings: Equatable {
    var enabled: Bool
    var arrivalNotification: Bool
    var shippedNotification: Bool
    var pickupReminder: Bool
    var lastTokenUploadAt: Date?

    /// 是否與本機 UserDefaults 一致
    func matchesLocal() -> Bool {
        let d = UserDefaults.standard
        return enabled == d.bool(forKey: "notificationsEnabled")
            && arrivalNotification == d.bool(forKey: "arrivalNotificationEnabled")
            && shippedNotification == d.bool(forKey: "shippedNotificationEnabled")
            && pickupReminder == d.bool(forKey: "pickupReminderEnabled")
    }
}

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

        // 確保已快取的 token 被上傳
        // （處理 didReceiveRegistrationToken 在 Auth 恢復前觸發的時序問題）
        await uploadToken()
    }

    // MARK: - 上傳 Token（多裝置：寫入 fcmTokens map，含裝置通知設定）

    @discardableResult
    func uploadToken() async -> Bool {
        guard let userId = Auth.auth().currentUser?.uid,
              let token = fcmToken else {
            return false
        }

        let defaults = UserDefaults.standard
        do {
            // 必須使用 updateData — setData(merge:true) 會把 dot-notation key 當作字面欄位名，
            // 而 updateData 才會正確解析成巢狀 field path（fcmTokens -> deviceId -> ...）
            try await db.collection("users").document(userId).updateData([
                "fcmTokens.\(deviceId)": [
                    "token": token,
                    "lastActive": FieldValue.serverTimestamp(),
                    "lastTokenUploadAt": FieldValue.serverTimestamp(),
                    "notificationSettings": [
                        "enabled": defaults.bool(forKey: "notificationsEnabled"),
                        "arrivalNotification": defaults.bool(forKey: "arrivalNotificationEnabled"),
                        "shippedNotification": defaults.bool(forKey: "shippedNotificationEnabled"),
                        "pickupReminder": defaults.bool(forKey: "pickupReminderEnabled")
                    ]
                ] as [String: Any],
                "lastActive": FieldValue.serverTimestamp()
            ])
            print("[FCM] ✅ Token uploaded for device \(deviceId)")
            return true
        } catch {
            print("[FCM] ❌ Failed to upload token: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 同步裝置通知設定到 Firestore

    /// 將當前裝置的通知設定同步到 fcmTokens map 中
    @discardableResult
    func syncDeviceNotificationSettings() async -> Bool {
        guard let userId = Auth.auth().currentUser?.uid else { return false }

        let defaults = UserDefaults.standard
        let settings: [String: Any] = [
            "enabled": defaults.bool(forKey: "notificationsEnabled"),
            "arrivalNotification": defaults.bool(forKey: "arrivalNotificationEnabled"),
            "shippedNotification": defaults.bool(forKey: "shippedNotificationEnabled"),
            "pickupReminder": defaults.bool(forKey: "pickupReminderEnabled")
        ]

        do {
            try await db.collection("users").document(userId).updateData([
                "fcmTokens.\(deviceId).notificationSettings": settings,
                "fcmTokens.\(deviceId).lastTokenUploadAt": FieldValue.serverTimestamp()
            ])
            print("[FCM] ✅ Device notification settings synced")
            return true
        } catch {
            print("[FCM] ❌ Failed to sync notification settings: \(error.localizedDescription)")
            return false
        }
    }

    /// 觸發背景同步（無回傳值，用於 onChange 等不需 await 的場景）
    func syncDeviceNotificationSettingsInBackground() {
        Task { _ = await syncDeviceNotificationSettings() }
    }

    // MARK: - 讀取 Firestore 端的通知設定（診斷用）

    /// 從 Firestore 讀取當前裝置的 notificationSettings 快照
    func fetchRemoteNotificationSettings() async -> RemoteNotificationSettings? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }

        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            guard let data = doc.data(),
                  let tokens = data["fcmTokens"] as? [String: Any],
                  let device = tokens[deviceId] as? [String: Any] else {
                return nil
            }
            let settings = device["notificationSettings"] as? [String: Any] ?? [:]
            let lastUpload = (device["lastTokenUploadAt"] as? Timestamp)?.dateValue()
                ?? (device["lastActive"] as? Timestamp)?.dateValue()

            return RemoteNotificationSettings(
                enabled: settings["enabled"] as? Bool ?? true,
                arrivalNotification: settings["arrivalNotification"] as? Bool ?? true,
                shippedNotification: settings["shippedNotification"] as? Bool ?? true,
                pickupReminder: settings["pickupReminder"] as? Bool ?? true,
                lastTokenUploadAt: lastUpload
            )
        } catch {
            print("[FCM] ❌ Failed to fetch remote settings: \(error.localizedDescription)")
            return nil
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
