import StoreKit
import UIKit

/// 在「爽點」自動觸發 App Store 評分提示
@MainActor
struct ReviewPromptService {

    // MARK: - UserDefaults Keys

    private static let lastPromptDateKey = "reviewPrompt_lastDate"
    private static let totalPackagesAddedKey = "reviewPrompt_totalAdded"
    private static let promptCountKey = "reviewPrompt_count"
    private static let promptCountYearKey = "reviewPrompt_countYear"

    // MARK: - 門檻常數

    private static let minimumPackagesAdded = 3
    private static let cooldownDays = 120
    private static let maxPromptsPerYear = 3

    // MARK: - Public API

    /// 記錄新增包裹（每次成功 addPackage 時呼叫）
    static func recordPackageAdded() {
        let current = UserDefaults.standard.integer(forKey: totalPackagesAddedKey)
        UserDefaults.standard.set(current + 1, forKey: totalPackagesAddedKey)
    }

    /// 嘗試觸發評分視窗（在爽點呼叫，內部判斷是否符合所有條件）
    static func requestReviewIfAppropriate() {
        guard meetsAllConditions() else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        AppStore.requestReview(in: scene)

        // 更新追蹤狀態
        UserDefaults.standard.set(Date(), forKey: lastPromptDateKey)

        let currentYear = Calendar.current.component(.year, from: Date())
        let storedYear = UserDefaults.standard.integer(forKey: promptCountYearKey)
        var count = UserDefaults.standard.integer(forKey: promptCountKey)

        if storedYear != currentYear {
            // 新的一年，重置計數
            count = 1
            UserDefaults.standard.set(currentYear, forKey: promptCountYearKey)
        } else {
            count += 1
        }

        UserDefaults.standard.set(count, forKey: promptCountKey)
    }

    // MARK: - Private

    private static func meetsAllConditions() -> Bool {
        let defaults = UserDefaults.standard

        // 條件 1：累計新增 ≥ 3 筆包裹
        let totalAdded = defaults.integer(forKey: totalPackagesAddedKey)
        guard totalAdded >= minimumPackagesAdded else { return false }

        // 條件 2：距離上次彈出 ≥ 120 天
        if let lastDate = defaults.object(forKey: lastPromptDateKey) as? Date {
            let daysSinceLast = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            guard daysSinceLast >= cooldownDays else { return false }
        }

        // 條件 3：該年度彈出次數 < 3
        let currentYear = Calendar.current.component(.year, from: Date())
        let storedYear = defaults.integer(forKey: promptCountYearKey)
        let count = defaults.integer(forKey: promptCountKey)

        if storedYear == currentYear && count >= maxPromptsPerYear {
            return false
        }

        return true
    }
}
