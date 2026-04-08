//
//  LaunchPromoManager.swift
//  PackageTraker
//
//  限時優惠管理：新用戶 48 小時買斷半價
//

import Foundation
import Combine

@MainActor
class LaunchPromoManager: ObservableObject {
    static let shared = LaunchPromoManager()

    // MARK: - Constants

    /// 功能上線日期（舊用戶從此日起算 48hr）
    /// ⚠️ 上線前務必更新為實際部署日期
    static let featureDeployDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 8
        components.hour = 0
        components.minute = 0
        components.timeZone = TimeZone(identifier: "Asia/Taipei")
        return Calendar.current.date(from: components)!
    }()

    /// 優惠持續時間（24 小時）
    static let promoDuration: TimeInterval = 24 * 60 * 60

    private static let promoStartDateKey = "promoStartDate"

    // MARK: - Published State

    /// 優惠起始時間
    @Published private(set) var promoStartDate: Date?

    /// 剩餘秒數
    @Published private(set) var remainingSeconds: TimeInterval = 0

    private var timer: Timer?

    // MARK: - Computed

    /// 優惠是否進行中
    var isPromoActive: Bool {
        guard FeatureFlags.launchPromoEnabled else { return false }
        guard !SubscriptionManager.shared.isPro else { return false }
        guard let start = promoStartDate else { return false }
        let now = Date()
        return now >= start && now < start.addingTimeInterval(Self.promoDuration)
    }

    /// 優惠是否已過期
    var isPromoExpired: Bool {
        guard let start = promoStartDate else { return false }
        return Date() >= start.addingTimeInterval(Self.promoDuration)
    }

    /// 格式化倒數文字（天:時:分:秒）
    var countdownText: String {
        let total = max(0, Int(remainingSeconds))
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if d > 0 {
            return String(format: NSLocalizedString("promo.countdown.format.days", comment: ""), d, h, m, s)
        }
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: - Init

    private init() {
        loadOrInitializePromoStart()
        startTimerIfNeeded()
    }

    // MARK: - Setup

    private func loadOrInitializePromoStart() {
        // 已有 persisted 值
        if let saved = UserDefaults.standard.object(forKey: Self.promoStartDateKey) as? Date {
            promoStartDate = saved
            return
        }

        // 首次計算
        let firstLaunch = UserDefaults.standard.object(forKey: "appFirstLaunchDate") as? Date ?? Date()

        if firstLaunch >= Self.featureDeployDate {
            // 新用戶：從安裝日起算
            promoStartDate = firstLaunch
        } else {
            // 舊用戶：從首次打開新版起算
            promoStartDate = Date()
        }

        UserDefaults.standard.set(promoStartDate, forKey: Self.promoStartDateKey)
    }

    // MARK: - Timer

    private func startTimerIfNeeded() {
        timer?.invalidate()
        timer = nil

        guard let start = promoStartDate else { return }
        let endDate = start.addingTimeInterval(Self.promoDuration)
        let remaining = endDate.timeIntervalSince(Date())

        guard remaining > 0 else {
            remainingSeconds = 0
            return
        }

        remainingSeconds = remaining

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let newRemaining = endDate.timeIntervalSince(Date())
                if newRemaining <= 0 {
                    self.remainingSeconds = 0
                    self.timer?.invalidate()
                    self.timer = nil
                    self.objectWillChange.send()
                } else {
                    self.remainingSeconds = newRemaining
                }
            }
        }
    }

    // MARK: - Debug

    #if DEBUG
    func debugResetPromo() {
        let now = Date()
        promoStartDate = now
        UserDefaults.standard.set(now, forKey: Self.promoStartDateKey)
        startTimerIfNeeded()
    }

    func debugSetPromoStart(_ date: Date) {
        promoStartDate = date
        UserDefaults.standard.set(date, forKey: Self.promoStartDateKey)
        startTimerIfNeeded()
    }

    func debugExpirePromo() {
        let past = Date().addingTimeInterval(-Self.promoDuration - 1)
        debugSetPromoStart(past)
    }
    #endif
}
