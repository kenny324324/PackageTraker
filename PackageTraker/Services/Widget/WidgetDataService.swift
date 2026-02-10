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
            .prefix(5)

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
                updatedAt: pkg.lastUpdated
            )
        }

        if let encoded = try? JSONEncoder().encode(Array(widgetData)) {
            defaults.set(encoded, forKey: dataKey)
        }
    }

    /// 更新訂閱層級（讓 Widget 知道是否為 Pro）
    func updateSubscriptionTier(_ tier: SubscriptionTier) {
        sharedDefaults?.set(tier.rawValue, forKey: tierKey)
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
