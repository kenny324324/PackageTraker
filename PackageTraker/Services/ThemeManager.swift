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
            selectedThemeRawValue = newValue.rawValue
        }
    }
    
    /// 當前主題色
    var currentColor: Color {
        selectedTheme.color
    }
    
    private init() {}
}
