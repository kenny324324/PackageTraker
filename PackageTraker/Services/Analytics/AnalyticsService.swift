//
//  AnalyticsService.swift
//  PackageTraker
//
//  Firebase Analytics 事件追蹤
//

import Foundation
import FirebaseAnalytics

/// 集中管理 Analytics 事件
enum AnalyticsService {

    // MARK: - AI 掃描

    static func logAIScanStarted() {
        Analytics.logEvent("ai_scan_started", parameters: nil)
    }

    static func logAIScanCompleted(carrier: String?, hasPickupCode: Bool) {
        Analytics.logEvent("ai_scan_completed", parameters: [
            "carrier": carrier ?? "unknown",
            "has_pickup_code": hasPickupCode,
        ])
    }

    static func logAIScanFailed(errorType: String, statusCode: Int? = nil) {
        var params: [String: Any] = ["error_type": errorType]
        if let code = statusCode { params["status_code"] = code }
        Analytics.logEvent("ai_scan_failed", parameters: params)
    }

    static func logAIDailyLimitHit(count: Int) {
        Analytics.logEvent("ai_daily_limit_hit", parameters: [
            "count": count,
        ])
    }

    // MARK: - 包裹

    static func logPackageAdded(carrier: String, source: String) {
        Analytics.logEvent("package_added", parameters: [
            "carrier": carrier,
            "source": source,
        ])
    }

    static func logPackageDeleted() {
        Analytics.logEvent("package_deleted", parameters: nil)
    }

    // MARK: - 訂閱

    static func logPaywallShown(trigger: String) {
        Analytics.logEvent("subscription_paywall_shown", parameters: [
            "trigger": trigger,
        ])
    }

    static func logSubscriptionPurchased(productId: String) {
        Analytics.logEvent("subscription_purchased", parameters: [
            "product_id": productId,
        ])
    }

    static func logSubscriptionRestored(productId: String) {
        Analytics.logEvent("subscription_restored", parameters: [
            "product_id": productId,
        ])
    }
}
