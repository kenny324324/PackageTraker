import Foundation
import SwiftUI

/// 通知管理器：協調通知邏輯與用戶偏好
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    // 通知偏好設定（從 UserDefaults 讀取）
    private var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "notificationsEnabled")
    }

    private var arrivalNotificationEnabled: Bool {
        UserDefaults.standard.bool(forKey: "arrivalNotificationEnabled")
    }

    private var pickupReminderEnabled: Bool {
        UserDefaults.standard.bool(forKey: "pickupReminderEnabled")
    }

    private let notificationService = NotificationService.shared

    private init() {}

    // MARK: - 包裹狀態變化處理

    /// 處理包裹狀態變化
    func handleStatusChange(package: Package, oldStatus: TrackingStatus, newStatus: TrackingStatus) {
        // 檢查是否啟用通知
        guard notificationsEnabled, arrivalNotificationEnabled else { return }

        // 偵測到貨：從非到貨狀態 -> 已到貨狀態
        if !oldStatus.isPendingPickup && newStatus.isPendingPickup {
            Task {
                let status = await notificationService.getAuthorizationStatus()
                guard status == .authorized else { return }

                notificationService.scheduleArrivalNotification(for: package)
            }
        }
    }

    // MARK: - 每日取貨提醒

    /// 更新每日取貨提醒
    func updateDailyPickupReminder(packages: [Package]) {
        // 先取消舊的提醒
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-pickup-reminder"])

        // 檢查是否啟用
        guard notificationsEnabled, pickupReminderEnabled else { return }

        Task {
            let status = await notificationService.getAuthorizationStatus()
            guard status == .authorized else { return }

            // 篩選待取件的包裹
            let pendingPackages = packages.filter { $0.status.isPendingPickup && !$0.isArchived }

            if !pendingPackages.isEmpty {
                notificationService.schedulePickupReminder(for: pendingPackages)
            }
        }
    }
}
