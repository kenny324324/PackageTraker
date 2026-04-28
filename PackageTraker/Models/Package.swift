import Foundation
import SwiftData
import CryptoKit

/// 包裹資料模型（SwiftData）
@Model
final class Package {
    var id: UUID
    var trackingNumber: String
    var carrierRawValue: String  // Carrier.rawValue
    var customName: String?
    var pickupCode: String?         // 取件碼（如：6-5-29-14）
    var pickupLocation: String?     // 取貨地點（如：媽媽驛站、7-11景安店）
    var statusRawValue: String      // TrackingStatus.rawValue
    var lastUpdated: Date
    var createdAt: Date
    var isArchived: Bool
    var notifyShipped: Bool = true   // 寄件通知（Pro）
    var notifyInTransit: Bool = true // 運送中通知（Pro）
    var notifyArrived: Bool = true   // 到店通知（Pro）
    var latestDescription: String?  // 最新狀態描述
    
    // 額外資訊（7-11、全家等）
    var storeName: String?          // 取件門市名稱
    var serviceType: String?        // 服務類型（如：取貨付款）
    var pickupDeadline: String?     // 取件期限
    
    // 使用者輸入的包裹資訊
    var paymentMethodRawValue: String?  // 付款方式
    var amount: Double?                 // 金額
    var purchasePlatform: String?       // 購買平台
    var notes: String?                  // 備註
    var userPickupLocation: String?     // 使用者自訂的取貨地點
    var trackTwRelationId: String?      // Track.TW user-package-relation UUID

    /// 追蹤事件列表
    @Relationship(deleteRule: .cascade, inverse: \TrackingEvent.package)
    var events: [TrackingEvent] = []

    init(
        id: UUID = UUID(),
        trackingNumber: String,
        carrier: Carrier,
        customName: String? = nil,
        pickupCode: String? = nil,
        pickupLocation: String? = nil,
        status: TrackingStatus = .pending,
        lastUpdated: Date = Date(),
        createdAt: Date = Date(),
        isArchived: Bool = false,
        notifyShipped: Bool = true,
        notifyInTransit: Bool = true,
        notifyArrived: Bool = true,
        latestDescription: String? = nil,
        storeName: String? = nil,
        serviceType: String? = nil,
        pickupDeadline: String? = nil,
        paymentMethod: PaymentMethod? = nil,
        amount: Double? = nil,
        purchasePlatform: String? = nil,
        notes: String? = nil,
        userPickupLocation: String? = nil
    ) {
        self.id = id
        self.trackingNumber = trackingNumber
        self.carrierRawValue = carrier.rawValue
        self.customName = customName
        self.pickupCode = pickupCode
        self.pickupLocation = pickupLocation
        self.statusRawValue = status.rawValue
        self.lastUpdated = lastUpdated
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.notifyShipped = notifyShipped
        self.notifyInTransit = notifyInTransit
        self.notifyArrived = notifyArrived
        self.latestDescription = latestDescription
        self.storeName = storeName
        self.serviceType = serviceType
        self.pickupDeadline = pickupDeadline
        self.paymentMethodRawValue = paymentMethod?.rawValue
        self.amount = amount
        self.purchasePlatform = purchasePlatform
        self.notes = notes
        self.userPickupLocation = userPickupLocation
    }

    // MARK: - Computed Properties

    /// 物流商
    var carrier: Carrier {
        get { Carrier(rawValue: carrierRawValue) ?? .other }
        set { carrierRawValue = newValue.rawValue }
    }

    /// 追蹤狀態
    var status: TrackingStatus {
        get { TrackingStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }
    
    /// 付款方式
    var paymentMethod: PaymentMethod? {
        get { paymentMethodRawValue.flatMap { PaymentMethod(rawValue: $0) } }
        set { paymentMethodRawValue = newValue?.rawValue }
    }
    
    /// 格式化金額顯示
    var formattedAmount: String? {
        guard let amount = amount else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount))
    }

    /// 顯示用的名稱（優先使用自訂名稱）
    var displayName: String {
        customName ?? carrier.displayName
    }

    /// 顯示用的單號或取件碼
    var displayCode: String {
        pickupCode ?? trackingNumber
    }

    /// 首頁卡片主要文字（品名 或 單號，不含價格）
    var cardMainText: String {
        if let name = customName, !name.isEmpty {
            return name
        }
        return displayCode
    }
    
    /// 首頁顯示的取貨地點（優先使用者自訂）
    var displayPickupLocation: String {
        if let userLocation = userPickupLocation, !userLocation.isEmpty {
            return userLocation
        }
        return pickupLocation ?? carrier.displayName
    }

    /// 更新時間的相對描述
    var relativeUpdateTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }

    /// 取件成功的時間戳記（從事件中尋找）
    var pickupEventTimestamp: Date? {
        events.first { event in
            event.eventDescription.contains("取件成功") ||
            event.eventDescription.contains("已取貨") ||
            event.eventDescription.contains("已領取") ||
            event.eventDescription.contains("買家取件成功")
        }?.timestamp
    }
    
    /// 最後一個狀態的時間（最新事件的時間）
    var latestEventTimestamp: Date? {
        // events 按時間排序，最新的在前
        events.sorted { $0.timestamp > $1.timestamp }.first?.timestamp
    }
    
    /// 訂單成立時間（最早事件的時間）
    var orderCreatedTimestamp: Date? {
        // events 中最早的時間
        events.sorted { $0.timestamp < $1.timestamp }.first?.timestamp
    }
    
    /// 訂單成立時間的格式化顯示
    var formattedOrderCreatedTime: String {
        guard let orderTime = orderCreatedTimestamp else {
            return relativeUpdateTime
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: orderTime)
    }

    // MARK: - Pickup Deadline

    /// 第一次「到店」事件的時間戳記
    var arrivedAtStoreTimestamp: Date? {
        events
            .filter { $0.status == .arrivedAtStore }
            .sorted { $0.timestamp < $1.timestamp }
            .first?.timestamp
    }

    /// 自動計算的取件截止日期（到店時間 + carrier.pickupHoldDays 天）
    /// 截止時刻設為當天 23:59，符合超商取件實務
    var computedPickupDeadline: Date? {
        guard let arrivedAt = arrivedAtStoreTimestamp,
              let holdDays = carrier.pickupHoldDays else {
            return nil
        }
        let calendar = Calendar(identifier: .gregorian)
        guard let plus = calendar.date(byAdding: .day, value: holdDays, to: arrivedAt) else {
            return nil
        }
        return calendar.date(
            bySettingHour: 23, minute: 59, second: 59, of: plus
        ) ?? plus
    }

    /// 解析後的取件截止日期，優先使用 `pickupDeadline` 字串（手動填或同步寫回的）
    /// 若字串解析失敗則 fallback 到 `computedPickupDeadline`
    var resolvedPickupDeadline: Date? {
        if let str = pickupDeadline, !str.isEmpty {
            let formatters = ["yyyy-MM-dd", "yyyy/MM/dd", "MM/dd HH:mm", "MM/dd"]
            for fmt in formatters {
                let df = DateFormatter()
                df.locale = Locale(identifier: "zh_TW")
                df.dateFormat = fmt
                if let date = df.date(from: str) {
                    let calendar = Calendar(identifier: .gregorian)
                    return calendar.date(
                        bySettingHour: 23, minute: 59, second: 59, of: date
                    ) ?? date
                }
            }
        }
        return computedPickupDeadline
    }

    /// 距離取件截止還剩幾天（負數代表已過期，0 代表今天截止）
    var daysUntilPickupDeadline: Int? {
        guard let deadline = resolvedPickupDeadline else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfDeadline = calendar.startOfDay(for: deadline)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfDeadline).day
    }

    /// 取件截止日期的格式化顯示（MM/dd）
    var formattedPickupDeadlineDate: String? {
        guard let deadline = resolvedPickupDeadline else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: deadline)
    }

    /// 取件倒數顯示
    /// - parameter alwaysShowDays: true = 不論幾天都顯示「剩餘 X 天」（用於 sheet 列表）
    ///                              false = 5 天以上顯示 MM/dd（用於卡片，避免擁擠）
    /// 共用規則：
    ///   - 0 天：今天截止
    ///   - 負數：已逾期
    ///   - 3 天內 / 今天 / 已逾期：紅色
    /// 回傳 nil 代表沒有 deadline 資料，呼叫者請 fallback 到訂單日
    func pickupCountdownDisplay(alwaysShowDays: Bool = false) -> (text: String, isUrgent: Bool)? {
        guard let days = daysUntilPickupDeadline else { return nil }

        if days < 0 {
            return (String(localized: "card.daysLeft.expired"), true)
        }
        if days == 0 {
            return (String(localized: "card.daysLeft.today"), true)
        }
        if alwaysShowDays || days <= 4 {
            let text = String(format: String(localized: "card.daysLeft.format"), days)
            return (text, days <= 3)
        }
        // 5 天以上顯示日期（卡片用）
        guard let dateText = formattedPickupDeadlineDate else { return nil }
        return (dateText, false)
    }
}

/// 物流事件（詳情頁時間軸用）
@Model
final class TrackingEvent {
    var id: UUID
    var timestamp: Date
    var statusRawValue: String  // TrackingStatus.rawValue
    var eventDescription: String  // 'description' is reserved
    var location: String?

    var package: Package?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        status: TrackingStatus,
        description: String,
        location: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.statusRawValue = status.rawValue
        self.eventDescription = description
        self.location = location
    }

    // MARK: - Deterministic ID

    /// 根據內容產生確定性 UUID，避免同一事件在 Firestore 中產生重複文件
    static func deterministicId(trackingNumber: String, timestamp: Date, description: String) -> UUID {
        let key = "\(trackingNumber)|\(Int(timestamp.timeIntervalSince1970))|\(description)"
        let hash = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(hash.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50  // UUID version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: - Computed Properties

    /// 追蹤狀態
    var status: TrackingStatus {
        get { TrackingStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    /// 時間格式化
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: timestamp)
    }
}
