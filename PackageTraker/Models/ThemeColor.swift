import SwiftUI

/// 主題顏色選項
enum ThemeColor: String, CaseIterable, Identifiable {
    case coffeeBrown    // 咖啡棕（預設）
    case forestGreen    // 森林綠
    case oceanBlue      // 深海藍
    case lavender       // 薰衣草
    case babyBlue       // 寶寶藍
    case eggshellWhite  // 蛋殼白
    case sakuraPink     // 櫻花粉
    case sunsetOrange   // 落日橙
    
    var id: String { rawValue }
    
    /// 顏色值
    var color: Color {
        switch self {
        case .coffeeBrown:    return Color(hex: "8B5A2B")
        case .forestGreen:    return Color(hex: "26631D")
        case .oceanBlue:      return Color(hex: "517CC2")
        case .lavender:       return Color(hex: "967BB6")
        case .babyBlue:       return Color(hex: "71D2F5")
        case .eggshellWhite:  return Color(hex: "F1EAD4")
        case .sakuraPink:     return Color(hex: "FFB5C3")
        case .sunsetOrange:   return Color(hex: "FF4E49")
        }
    }
    
    /// 本地化顯示名稱
    var displayName: String {
        switch self {
        case .coffeeBrown:    return String(localized: "theme.coffeeBrown")
        case .forestGreen:    return String(localized: "theme.forestGreen")
        case .oceanBlue:      return String(localized: "theme.oceanBlue")
        case .lavender:       return String(localized: "theme.lavender")
        case .babyBlue:       return String(localized: "theme.babyBlue")
        case .eggshellWhite:  return String(localized: "theme.eggshellWhite")
        case .sakuraPink:     return String(localized: "theme.sakuraPink")
        case .sunsetOrange:   return String(localized: "theme.sunsetOrange")
        }
    }
    
    /// 圖標名稱
    var iconName: String {
        switch self {
        case .coffeeBrown:    return "cup.and.saucer.fill"
        case .forestGreen:    return "leaf.fill"
        case .oceanBlue:      return "drop.fill"
        case .lavender:       return "sparkles"
        case .babyBlue:       return "cloud.fill"
        case .eggshellWhite:  return "egg.fill"
        case .sakuraPink:     return "heart.fill"
        case .sunsetOrange:   return "sun.max.fill"
        }
    }
}
