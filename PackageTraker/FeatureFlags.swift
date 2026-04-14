//
//  FeatureFlags.swift
//  PackageTraker
//
//  Feature flags for controlling app features
//

import Foundation

/// Feature flags for controlling app features
struct FeatureFlags {
    /// 郵件自動化功能（暫時停用，未來可能開放）
    /// 當設為 true 時，啟用以下功能：
    /// - 設定頁面的 Email 連結功能
    /// - 下拉刷新時的郵件同步
    /// - 背景郵件同步任務
    static let emailAutoImportEnabled = false

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
