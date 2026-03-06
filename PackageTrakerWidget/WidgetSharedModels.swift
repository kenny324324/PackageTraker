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
