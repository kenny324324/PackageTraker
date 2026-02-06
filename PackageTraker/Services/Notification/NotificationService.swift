import Foundation
import UserNotifications

/// 通知服務：處理系統通知權限和排程本地通知
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    // MARK: - 權限管理

    /// 請求通知權限
    @MainActor
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Request notification permission failed: \(error)")
            return false
        }
    }

    /// 查詢當前授權狀態
    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - 排程通知

    /// 排程到貨通知
    func scheduleArrivalNotification(for package: Package) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.arrival.title")

        // 通知內容：「[品名] 已到達 [取貨地點]，請儘快取貨」
        let locationText = package.pickupLocation ?? String(localized: "notification.defaultLocation")
        let packageName = package.customName ?? package.trackingNumber
        content.body = String(format: String(localized: "notification.arrival.body"),
                             packageName,
                             locationText)
        content.sound = .default

        // 立即觸發（1 秒後）
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "arrival-\(package.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Schedule arrival notification failed: \(error)")
            }
        }
    }

    /// 排程取貨提醒（每日定時提醒）
    func schedulePickupReminder(for packages: [Package]) {
        guard !packages.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.pickup.title")
        content.body = String(format: String(localized: "notification.pickup.body"), packages.count)
        content.sound = .default

        // 每日早上 10:00 提醒
        var dateComponents = DateComponents()
        dateComponents.hour = 10
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let identifier = "daily-pickup-reminder"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Schedule pickup reminder failed: \(error)")
            }
        }
    }

    /// 取消特定包裹的所有通知
    func cancelNotifications(for package: Package) {
        let identifier = "arrival-\(package.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// 取消所有通知
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
