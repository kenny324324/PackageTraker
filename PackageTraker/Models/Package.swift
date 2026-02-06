import Foundation
import SwiftData

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
    
    /// 首頁卡片顯示文字（品名+價格 或 單號）- 已棄用，改用 cardMainText
    var cardDisplayText: String {
        if let name = customName, !name.isEmpty {
            if let amount = formattedAmount {
                return "\(name) \(amount)"
            }
            return name
        }
        return displayCode
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
