//
//  SubscriptionTier.swift
//  PackageTraker
//
//  Subscription tier and product definitions
//

import Foundation

/// 訂閱層級
enum SubscriptionTier: String, Codable {
    case free = "free"
    case pro = "pro"
}

/// 訂閱產品 ID
enum SubscriptionProductID: String, CaseIterable {
    case monthly = "com.kenny.PackageTraker.pro.monthly"
    case yearly = "com.kenny.PackageTraker.pro.yearly"
    case lifetime = "com.kenny.PackageTraker.pro.lifetime"
    case lifetimeLaunch = "com.kenny.PackageTraker.pro.lifetime.launch"
    case lifetimeMilestone = "com.kenny.PackageTraker.pro.lifetime.milestone"

    /// 所有買斷方案的 product ID
    static var allLifetimeIDs: Set<String> {
        [Self.lifetime.rawValue, Self.lifetimeLaunch.rawValue, Self.lifetimeMilestone.rawValue]
    }
}
