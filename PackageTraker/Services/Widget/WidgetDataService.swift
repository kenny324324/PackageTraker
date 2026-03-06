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
    let updatedAt: Date
    let latestEventTimestamp: Date?

    /// 自定義解碼：讓舊版 JSON（沒有 latestEventTimestamp）也能正常解碼
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
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        latestEventTimestamp = try c.decodeIfPresent(Date.self, forKey: .latestEventTimestamp)
    }

    /// 主 App 寫入用
    init(id: String, trackingNumber: String, carrierRawValue: String, carrierDisplayName: String,
         customName: String?, statusRawValue: String, statusDisplayName: String,
         latestDescription: String?, pickupLocation: String?, storeName: String?,
         updatedAt: Date, latestEventTimestamp: Date?) {
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
        self.updatedAt = updatedAt
        self.latestEventTimestamp = latestEventTimestamp
    }
}

/// Widget 資料服務 — 寫入共享 UserDefaults
class WidgetDataService {

    static let shared = WidgetDataService()

    private let sharedDefaults: UserDefaults?
    private let dataKey = "widgetPackages"
    private let tierKey = "subscriptionTier"

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
                updatedAt: pkg.lastUpdated,
                latestEventTimestamp: pkg.latestEventTimestamp
            )
        }

        if let encoded = try? JSONEncoder().encode(Array(widgetData)) {
            defaults.set(encoded, forKey: dataKey)
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
