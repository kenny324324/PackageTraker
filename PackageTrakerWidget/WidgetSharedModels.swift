//
//  WidgetSharedModels.swift
//  PackageTrakerWidget
//
//  Shared models between main app and widget (duplicated for widget target)
//

import Foundation

/// App Group 共享存儲標識
let appGroupIdentifier = "group.com.kenny.PackageTraker"

/// Widget 用的包裹摘要資料
struct WidgetPackageData: Codable {
    let id: String
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

/// 訂閱層級
enum SubscriptionTier: String, Codable {
    case free = "free"
    case pro = "pro"
}

/// Widget 資料讀取
enum WidgetDataService {
    private static let dataKey = "widgetPackages"
    private static let tierKey = "subscriptionTier"

    /// 讀取 Widget 資料
    static func readWidgetData() -> [WidgetPackageData] {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: dataKey),
              let packages = try? JSONDecoder().decode([WidgetPackageData].self, from: data) else {
            return []
        }
        return packages
    }

    /// 讀取訂閱層級
    static func readSubscriptionTier() -> SubscriptionTier {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let rawValue = defaults.string(forKey: tierKey),
              let tier = SubscriptionTier(rawValue: rawValue) else {
            return .free
        }
        return tier
    }
}
