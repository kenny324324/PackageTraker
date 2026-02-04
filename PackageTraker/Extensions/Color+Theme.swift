import SwiftUI

extension Color {
    // MARK: - 背景色

    /// 主背景色（深黑）
    static let appBackground = Color(hex: "0D0D0D")

    /// 卡片背景色（深灰）
    static let cardBackground = Color(hex: "1C1C1E")

    /// 次要卡片背景（稍亮）
    static let secondaryCardBackground = Color(hex: "2C2C2E")

    // MARK: - 強調色

    /// 主強調色（根據主題設定動態變化）
    static var appAccent: Color {
        ThemeManager.shared.currentColor
    }

    /// 次要強調色
    static let secondaryAccent = Color(hex: "5AC8FA")

    // MARK: - 文字色

    /// 主要文字（白色）
    static let primaryText = Color.white

    /// 次要文字（灰色）
    static let secondaryText = Color(hex: "8E8E93")

    /// 第三層文字（更淡）
    static let tertiaryText = Color(hex: "636366")

    // MARK: - Hex 初始化

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    func secondaryCardStyle() -> some View {
        self
            .padding(12)
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
