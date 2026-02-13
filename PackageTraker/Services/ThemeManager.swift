import SwiftUI
import Combine

/// 主題管理器 - 管理 App 的主題色彩
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    /// 選擇的主題色（使用 AppStorage 持久化）
    @AppStorage("selectedTheme") private var selectedThemeRawValue: String = ThemeColor.coffeeBrown.rawValue {
        didSet {
            objectWillChange.send()
        }
    }

    /// 當前選擇的主題色
    var selectedTheme: ThemeColor {
        get {
            ThemeColor(rawValue: selectedThemeRawValue) ?? .coffeeBrown
        }
        set {
            // 免費用戶只能用 coffeeBrown
            if FeatureFlags.subscriptionEnabled && !SubscriptionManager.shared.hasAllThemes && newValue != .coffeeBrown {
                return
            }
            selectedThemeRawValue = newValue.rawValue
            // 同步到 Firestore
            FirebaseSyncService.shared.syncUserPreferences(theme: newValue.rawValue)
        }
    }

    /// 當前主題色
    var currentColor: Color {
        selectedTheme.color
    }

    /// 訂閱過期時重置為預設主題
    func resetToDefaultIfNeeded() {
        if FeatureFlags.subscriptionEnabled && !SubscriptionManager.shared.hasAllThemes && selectedTheme != .coffeeBrown {
            selectedThemeRawValue = ThemeColor.coffeeBrown.rawValue
        }
    }

    private init() {}
}
