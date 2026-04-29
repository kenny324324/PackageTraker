//
//  LaunchPromoManager.swift
//  PackageTraker
//
//  限時優惠管理：新用戶 24 小時買斷半價
//
//  判斷依據：Firestore /users/{uid}.createdAt（帳號建立時間）
//  - 帳號建立 >= featureDeployDate → 新用戶，從 createdAt 起算 24hr
//  - 帳號建立 < featureDeployDate → 老用戶，不給 launchPromo（v1.7.2 收斂）
//  - 未登入 → 不顯示（app 強制登入後才能進主畫面，理論上不會發生）
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class LaunchPromoManager: ObservableObject {
    static let shared = LaunchPromoManager()

    // MARK: - Constants

    /// 功能上線日期（帳號建立 < 此日的視為老用戶）
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
    private static let cachedAccountCreatedAtKey = "launchPromoAccountCreatedAt"
    private static let cachedAccountUidKey = "launchPromoAccountUid"

    // MARK: - Published State

    /// 優惠起始時間（即帳號建立時間，限新用戶）
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
        loadFromCache()
        startTimerIfNeeded()
    }

    // MARK: - Public

    /// 從 Firestore 載入帳號建立時間並決定優惠期間
    /// 由 PackageTrakerApp 在登入完成後呼叫
    func loadFromFirebaseAccount() async {
        guard let user = Auth.auth().currentUser else {
            clearPromo(reason: "no current user")
            return
        }

        // 檢查 cache：如果同一帳號已 cache 過，直接用 cache
        let cachedUid = UserDefaults.standard.string(forKey: Self.cachedAccountUidKey)
        if cachedUid == user.uid,
           let cachedDate = UserDefaults.standard.object(forKey: Self.cachedAccountCreatedAtKey) as? Date {
            apply(accountCreatedAt: cachedDate)
            return
        }

        // 從 Firestore 抓 createdAt（首次登入有 race condition，重試最多 3 次每次間隔 1 秒）
        let maxRetries = 3
        for attempt in 0..<maxRetries {
            do {
                let snapshot = try await Firestore.firestore().collection("users").document(user.uid).getDocument()
                if let data = snapshot.data(),
                   let timestamp = data["createdAt"] as? Timestamp {
                    let createdAt = timestamp.dateValue()
                    UserDefaults.standard.set(user.uid, forKey: Self.cachedAccountUidKey)
                    UserDefaults.standard.set(createdAt, forKey: Self.cachedAccountCreatedAtKey)
                    apply(accountCreatedAt: createdAt)
                    return
                }
                // 文件還沒寫進去（首次登入競態），等 1 秒重試
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(for: .seconds(1))
                }
            } catch {
                print("[LaunchPromo] Failed to load createdAt (attempt \(attempt + 1)): \(error.localizedDescription)")
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }

        // 重試 3 次都沒拿到 → 視為老用戶（保守做法，不誤發 promo）
        clearPromo(reason: "createdAt unavailable after retries")
    }

    /// 登出時清除狀態
    func clearOnSignOut() {
        UserDefaults.standard.removeObject(forKey: Self.cachedAccountUidKey)
        UserDefaults.standard.removeObject(forKey: Self.cachedAccountCreatedAtKey)
        clearPromo(reason: "sign out")
    }

    // MARK: - Private

    private func loadFromCache() {
        // 啟動時用 cache 先給一個值，等待 loadFromFirebaseAccount() 同步刷新
        guard let cachedDate = UserDefaults.standard.object(forKey: Self.cachedAccountCreatedAtKey) as? Date else {
            return
        }
        apply(accountCreatedAt: cachedDate)
    }

    /// 套用帳號建立時間，計算 promoStartDate
    private func apply(accountCreatedAt: Date) {
        guard accountCreatedAt >= Self.featureDeployDate else {
            // 老用戶（4/8 前建立）→ 不給 promo
            clearPromo(reason: "old account, before featureDeployDate")
            return
        }
        promoStartDate = accountCreatedAt
        UserDefaults.standard.set(accountCreatedAt, forKey: Self.promoStartDateKey)
        startTimerIfNeeded()
    }

    private func clearPromo(reason: String) {
        promoStartDate = nil
        UserDefaults.standard.removeObject(forKey: Self.promoStartDateKey)
        remainingSeconds = 0
        timer?.invalidate()
        timer = nil
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

    /// 模擬老用戶（清掉 promo + cache 標記為 4/8 前）
    func debugSimulateOldUser() {
        let oldDate = Date().addingTimeInterval(-30 * 86400) // 30 天前
        UserDefaults.standard.set(oldDate, forKey: Self.cachedAccountCreatedAtKey)
        clearPromo(reason: "debug: simulate old user")
    }
    #endif
}
