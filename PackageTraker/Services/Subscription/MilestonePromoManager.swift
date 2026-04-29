//
//  MilestonePromoManager.swift
//  PackageTraker
//
//  1000 用戶里程碑慶祝活動：買斷限時 1290（30 天），由 Remote Config 開關
//

import Foundation
import Combine
import FirebaseRemoteConfig

@MainActor
final class MilestonePromoManager: ObservableObject {
    static let shared = MilestonePromoManager()

    // MARK: - Constants

    /// 活動開關
    static let remoteEnabledKey = "milestone_promo_enabled"

    /// 活動結束時間（ISO8601 字串）
    static let remoteEndDateKey = "milestone_promo_end_date_iso8601"

    /// 活動標題（可選，方便調文案）
    static let remoteTitleKey = "milestone_promo_title"

    /// 「最後倒數」階段門檻：剩餘天數 <= 此值則切紅紫配色
    static let finalCountdownThreshold = 3

    /// UserDefaults：是否已彈過 milestone sheet（僅彈一次）
    private static let hasShownSheetKey = "milestoneHasShownSheet"

    /// UserDefaults：是否已在「最後倒數」階段重彈過 sheet（彈一次）
    private static let hasShownFinalSheetKey = "milestoneHasShownFinalSheet"

    // MARK: - Published State

    /// Remote Config 是否啟用
    @Published private(set) var isEnabledByRemote: Bool = false

    /// 活動結束時間
    @Published private(set) var endDate: Date?

    /// 自訂標題（Remote Config 帶入；空字串為使用內建文案）
    @Published private(set) var customTitle: String = ""

    /// 剩餘秒數
    @Published private(set) var remainingSeconds: TimeInterval = 0

    private var timer: Timer?

    // MARK: - Computed

    /// 剩餘整數天數（向上取整，避免顯示 0 天）
    var remainingDays: Int {
        let days = Int(ceil(remainingSeconds / 86400))
        return max(0, days)
    }

    /// 是否進入「最後倒數」階段
    var isFinalCountdown: Bool {
        guard isPromoActive else { return false }
        return remainingDays <= Self.finalCountdownThreshold
    }

    /// 優惠是否進行中
    var isPromoActive: Bool {
        guard FeatureFlags.milestonePromoEnabled else { return false }
        guard !SubscriptionManager.shared.isPro else { return false }
        guard isEnabledByRemote else { return false }
        guard let end = endDate else { return false }
        return Date() < end
    }

    /// 是否已彈過 milestone sheet
    var hasShownSheet: Bool {
        UserDefaults.standard.bool(forKey: Self.hasShownSheetKey)
    }

    /// 是否已彈過「最後倒數」sheet
    var hasShownFinalSheet: Bool {
        UserDefaults.standard.bool(forKey: Self.hasShownFinalSheetKey)
    }

    // MARK: - Init

    private init() {
        loadFromRemoteConfigCacheOnly()
        startTimerIfNeeded()
    }

    // MARK: - Public

    /// 標記 milestone sheet 已彈出
    func markSheetShown() {
        UserDefaults.standard.set(true, forKey: Self.hasShownSheetKey)
    }

    /// 標記「最後倒數」sheet 已彈出
    func markFinalSheetShown() {
        UserDefaults.standard.set(true, forKey: Self.hasShownFinalSheetKey)
    }

    /// 從 Remote Config 重新讀取（呼叫前須先 fetchAndActivate）
    func reloadFromRemoteConfig() {
        loadFromRemoteConfigCacheOnly()
        startTimerIfNeeded()
    }

    // MARK: - Private

    /// 從目前已 activate 的 Remote Config 讀取（不會主動 fetch；caller 需確保已 fetch）
    private func loadFromRemoteConfigCacheOnly() {
        let rc = RemoteConfig.remoteConfig()

        isEnabledByRemote = rc.configValue(forKey: Self.remoteEnabledKey).boolValue

        let endIso = rc.configValue(forKey: Self.remoteEndDateKey).stringValue ?? ""
        if !endIso.isEmpty {
            endDate = Self.parseISO8601(endIso)
        } else {
            endDate = nil
        }

        customTitle = rc.configValue(forKey: Self.remoteTitleKey).stringValue ?? ""
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // 先試 fractional + timezone
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: trimmed) { return date }

        // fallback: 純日期 yyyy-MM-dd（Asia/Taipei 結束於當天 23:59:59）
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "Asia/Taipei")
        df.dateFormat = "yyyy-MM-dd"
        if let day = df.date(from: trimmed),
           let endOfDay = Calendar(identifier: .gregorian).date(bySettingHour: 23, minute: 59, second: 59, of: day) {
            return endOfDay
        }
        return nil
    }

    // MARK: - Timer

    private func startTimerIfNeeded() {
        timer?.invalidate()
        timer = nil

        guard let end = endDate else {
            remainingSeconds = 0
            return
        }
        let remaining = end.timeIntervalSince(Date())
        guard remaining > 0 else {
            remainingSeconds = 0
            return
        }
        remainingSeconds = remaining

        // 每 60 秒更新一次（剩餘天數變動才會重渲染）
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let newRemaining = end.timeIntervalSince(Date())
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
    /// 測試用：強制啟用，從現在起 30 天
    func debugForceActivate(days: Int = 30) {
        isEnabledByRemote = true
        endDate = Date().addingTimeInterval(TimeInterval(days) * 86400)
        startTimerIfNeeded()
    }

    /// 測試用：模擬「最後倒數」階段
    func debugSimulateFinalCountdown(daysLeft: Int = 2) {
        isEnabledByRemote = true
        endDate = Date().addingTimeInterval(TimeInterval(daysLeft) * 86400)
        startTimerIfNeeded()
    }

    /// 測試用：強制過期
    func debugExpire() {
        isEnabledByRemote = true
        endDate = Date().addingTimeInterval(-1)
        startTimerIfNeeded()
    }

    /// 測試用：停用
    func debugDeactivate() {
        isEnabledByRemote = false
        endDate = nil
        startTimerIfNeeded()
    }

    /// 測試用：重置 sheet 已彈狀態
    func debugResetSheetShown() {
        UserDefaults.standard.removeObject(forKey: Self.hasShownSheetKey)
        UserDefaults.standard.removeObject(forKey: Self.hasShownFinalSheetKey)
    }
    #endif
}
