//
//  WidgetDataService.swift
//  PackageTraker
//
//  Writes package data to App Group shared storage for Widget
//

import Foundation

/// App Group 共享存儲標識
let appGroupIdentifier = "group.com.kenny.PackageTraker"

/// Widget 用的包裹摘要資料
struct WidgetPackageData: Codable {
    let id: String // UUID string
    let trackingNumber: String
    let carrierRawValue: String
    let carrierDisplayName: String
    let customName: String?
    let statusRawValue: String
    let statusDisplayName: String
    let latestDescription: String?
    let pickupLocation: String?
    let storeName: String?
    let pickupCode: String?
    let pickupDeadline: String?
    let updatedAt: Date
    let latestEventTimestamp: Date?

    /// 自定義解碼：讓舊版 JSON（沒有新欄位）也能正常解碼
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        trackingNumber = try c.decode(String.self, forKey: .trackingNumber)
        carrierRawValue = try c.decode(String.self, forKey: .carrierRawValue)
        carrierDisplayName = try c.decode(String.self, forKey: .carrierDisplayName)
        customName = try c.decodeIfPresent(String.self, forKey: .customName)
        statusRawValue = try c.decode(String.self, forKey: .statusRawValue)
        statusDisplayName = try c.decode(String.self, forKey: .statusDisplayName)
        latestDescription = try c.decodeIfPresent(String.self, forKey: .latestDescription)
        pickupLocation = try c.decodeIfPresent(String.self, forKey: .pickupLocation)
        storeName = try c.decodeIfPresent(String.self, forKey: .storeName)
        pickupCode = try c.decodeIfPresent(String.self, forKey: .pickupCode)
        pickupDeadline = try c.decodeIfPresent(String.self, forKey: .pickupDeadline)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        latestEventTimestamp = try c.decodeIfPresent(Date.self, forKey: .latestEventTimestamp)
    }

    /// 主 App 寫入用
    init(id: String, trackingNumber: String, carrierRawValue: String, carrierDisplayName: String,
         customName: String?, statusRawValue: String, statusDisplayName: String,
         latestDescription: String?, pickupLocation: String?, storeName: String?,
         pickupCode: String?, pickupDeadline: String?, updatedAt: Date, latestEventTimestamp: Date?) {
        self.id = id
        self.trackingNumber = trackingNumber
        self.carrierRawValue = carrierRawValue
        self.carrierDisplayName = carrierDisplayName
        self.customName = customName
        self.statusRawValue = statusRawValue
        self.statusDisplayName = statusDisplayName
        self.latestDescription = latestDescription
        self.pickupLocation = pickupLocation
        self.storeName = storeName
        self.pickupCode = pickupCode
        self.pickupDeadline = pickupDeadline
        self.updatedAt = updatedAt
        self.latestEventTimestamp = latestEventTimestamp
    }
}

/// 預計算的 Widget 統計值（對應首頁 StatType 的 10 種統計）
struct WidgetStatValues: Codable {
    let pendingPickup: Int
    let deliveredLast30Days: Int
    let thisMonthSpending: Double
    let pendingAmount: Double
    let last30DaysSpending: Double
    let thisMonthDelivered: Int
    let inTransit: Int
    let avgDeliveryDays: Double       // 負數表示無資料
    let spendingDeltaCurrent: Double
    let spendingDeltaPrevious: Double
    let codPendingAmount: Double
}

/// Widget 資料服務 — 寫入共享 UserDefaults
class WidgetDataService {

    static let shared = WidgetDataService()

    private let sharedDefaults: UserDefaults?
    private let dataKey = "widgetPackages"
    private let tierKey = "subscriptionTier"
    private let statsKey = "widgetStats"

    private init() {
        sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    /// 更新 Widget 資料（從主 App 呼叫）
    func updateWidgetData(packages: [Package]) {
        guard let defaults = sharedDefaults else { return }

        let activePackages = packages
            .filter { !$0.isArchived }
            .sorted(by: { $0.lastUpdated > $1.lastUpdated })

        let widgetData = activePackages.map { pkg in
            WidgetPackageData(
                id: pkg.id.uuidString,
                trackingNumber: pkg.trackingNumber,
                carrierRawValue: pkg.carrierRawValue,
                carrierDisplayName: pkg.carrier.displayName,
                customName: pkg.customName,
                statusRawValue: pkg.statusRawValue,
                statusDisplayName: pkg.status.displayName,
                latestDescription: pkg.latestDescription,
                pickupLocation: pkg.userPickupLocation ?? pkg.pickupLocation,
                storeName: pkg.storeName,
                pickupCode: pkg.pickupCode,
                pickupDeadline: pkg.pickupDeadline,
                updatedAt: pkg.lastUpdated,
                latestEventTimestamp: pkg.latestEventTimestamp
            )
        }

        if let encoded = try? JSONEncoder().encode(Array(widgetData)) {
            defaults.set(encoded, forKey: dataKey)
            defaults.synchronize()
        }

        // 同時更新統計值
        updateWidgetStats(packages: packages)
    }

    /// 更新統計值
    func updateWidgetStats(packages: [Package]) {
        guard let defaults = sharedDefaults else { return }

        let calendar = Calendar.current
        let now = Date()
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3600)

        let allActive = packages.filter { !$0.isArchived }

        let pendingPickup = allActive.filter { $0.status.isPendingPickup }.count

        let recentDelivered = allActive.filter {
            $0.status == .delivered && $0.lastUpdated > thirtyDaysAgo
        }
        let deliveredLast30Days = recentDelivered.count

        let thisMonthSpending = allActive
            .filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
            .compactMap(\.amount)
            .reduce(0, +)

        let pendingAmount = allActive
            .filter { $0.status.isPendingPickup }
            .compactMap(\.amount)
            .reduce(0, +)

        let allRecent = allActive.filter { $0.lastUpdated > thirtyDaysAgo || $0.createdAt > thirtyDaysAgo }
        let last30DaysSpending = allRecent
            .compactMap(\.amount)
            .reduce(0, +)

        let thisMonthDelivered = allActive.filter {
            $0.status == .delivered &&
            calendar.isDate($0.lastUpdated, equalTo: now, toGranularity: .month)
        }.count

        let inTransit = allActive.filter {
            $0.status == .shipped || $0.status == .inTransit
        }.count

        let deliveredWithDates = recentDelivered.compactMap { pkg -> Int? in
            guard let start = pkg.orderCreatedTimestamp,
                  let end = pkg.pickupEventTimestamp ?? pkg.latestEventTimestamp,
                  let days = calendar.dateComponents([.day], from: start, to: end).day,
                  days >= 0 else { return nil }
            return days
        }
        let avgDeliveryDays: Double = deliveredWithDates.isEmpty
            ? -1
            : Double(deliveredWithDates.reduce(0, +)) / Double(deliveredWithDates.count)

        let spendingDeltaCurrent = thisMonthSpending
        let spendingDeltaPrevious: Double = {
            guard let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now) else { return 0 }
            return allActive
                .filter { calendar.isDate($0.createdAt, equalTo: lastMonthDate, toGranularity: .month) }
                .compactMap(\.amount)
                .reduce(0, +)
        }()

        let codPendingAmount = allActive
            .filter { $0.status.isPendingPickup && $0.paymentMethod == .cod }
            .compactMap(\.amount)
            .reduce(0, +)

        let stats = WidgetStatValues(
            pendingPickup: pendingPickup,
            deliveredLast30Days: deliveredLast30Days,
            thisMonthSpending: thisMonthSpending,
            pendingAmount: pendingAmount,
            last30DaysSpending: last30DaysSpending,
            thisMonthDelivered: thisMonthDelivered,
            inTransit: inTransit,
            avgDeliveryDays: avgDeliveryDays,
            spendingDeltaCurrent: spendingDeltaCurrent,
            spendingDeltaPrevious: spendingDeltaPrevious,
            codPendingAmount: codPendingAmount
        )

        if let encoded = try? JSONEncoder().encode(stats) {
            defaults.set(encoded, forKey: statsKey)
            defaults.synchronize()
        }
    }

    /// 更新訂閱層級（讓 Widget 知道是否為 Pro）
    func updateSubscriptionTier(_ tier: SubscriptionTier) {
        sharedDefaults?.set(tier.rawValue, forKey: tierKey)
        sharedDefaults?.synchronize()
    }

    /// 讀取 Widget 資料（從 Widget Extension 呼叫）
    static func readWidgetData() -> [WidgetPackageData] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: "widgetPackages"),
              let packages = try? JSONDecoder().decode([WidgetPackageData].self, from: data) else {
            return []
        }
        return packages
    }

    /// 讀取統計值（從 Widget Extension 呼叫）
    static func readWidgetStats() -> WidgetStatValues? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: "widgetStats"),
              let stats = try? JSONDecoder().decode(WidgetStatValues.self, from: data) else {
            return nil
        }
        return stats
    }

    /// 讀取訂閱層級（從 Widget Extension 呼叫）
    static func readSubscriptionTier() -> SubscriptionTier {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let rawValue = defaults.string(forKey: "subscriptionTier"),
              let tier = SubscriptionTier(rawValue: rawValue) else {
            return .free
        }
        return tier
    }
}
