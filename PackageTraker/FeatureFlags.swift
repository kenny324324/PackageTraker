//
//  FeatureFlags.swift
//  PackageTraker
//
//  Feature flags for controlling app features
//

import Foundation

/// Feature flags for controlling app features
struct FeatureFlags {
    /// 訂閱服務
    static let subscriptionEnabled = true

    /// AI 截圖辨識（Phase C）
    static let aiVisionEnabled = true  // 測試用：暫時開啟

    /// iOS Widget（Phase D）
    static let widgetEnabled = true

    /// 個人統計儀表板（未來上線）
    static let personalStatsEnabled = true

    /// 限時優惠（新用戶 48hr 買斷半價）
    static let launchPromoEnabled = true

    /// 邀請碼系統
    static let referralEnabled = true
}
