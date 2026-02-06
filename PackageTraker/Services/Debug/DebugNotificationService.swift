#if DEBUG
import Foundation
import UserNotifications

/// Debug 通知服務：用於測試通知功能（僅 DEBUG 模式）
final class DebugNotificationService {
    static let shared = DebugNotificationService()

    private let notificationService = NotificationService.shared

    private init() {}

    // MARK: - 測試通知

    /// 發送測試到貨通知
    func sendTestArrivalNotification(
        title: String = "測試到貨通知",
        body: String = "這是一則測試通知，您的包裹已到達取貨地點"
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "debug-test-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Debug] 發送測試通知失敗: \(error)")
            } else {
                print("[Debug] 測試通知已排程")
            }
        }
    }

    /// 發送測試取貨提醒
    func sendTestPickupReminder(count: Int = 3) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.pickup.title")
        content.body = String(format: String(localized: "notification.pickup.body"), count)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "debug-pickup-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Debug] 發送取貨提醒失敗: \(error)")
            } else {
                print("[Debug] 取貨提醒已排程")
            }
        }
    }

    /// 模擬狀態變化（運送中 → 已到貨）
    /// 會使用真實的通知格式
    func simulateStatusChange(
        packageName: String = "測試包裹",
        location: String = "7-11 景安門市"
    ) {
        // 建立臨時 Package 用於通知
        let mockPackage = Package(
            trackingNumber: "TEST\(Int.random(in: 100000...999999))",
            carrier: .sevenEleven,
            customName: packageName,
            pickupLocation: location,
            status: .arrivedAtStore
        )

        // 使用真實的通知服務發送
        notificationService.scheduleArrivalNotification(for: mockPackage)
        print("[Debug] 模擬狀態變化通知已排程: \(packageName) @ \(location)")
    }
}
#endif
