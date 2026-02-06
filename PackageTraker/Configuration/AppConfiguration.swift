import Foundation

/// 應用配置：統一管理應用元數據，避免硬編碼
struct AppConfiguration {
    // MARK: - 應用資訊

    /// 應用名稱（本地化）
    static var appName: String {
        String(localized: "app.name")
    }

    /// 開發者名稱（本地化）
    static var developerName: String {
        String(localized: "app.developer")
    }

    /// 反饋郵箱
    static let feedbackEmail = "kenny4work324@gmail.com"

    // MARK: - 版本資訊

    /// 應用版本號
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// 編譯版本號（Build Number）
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// 完整版本字符串（版本 + 編譯）
    /// 例如："1.0.0 (1)"
    static var fullVersionString: String {
        "\(appVersion) (\(buildNumber))"
    }
}
