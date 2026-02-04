import SwiftUI

/// 購買平台清單
struct PurchasePlatform {
    /// 內建的常見購買平台
    static let builtInPlatforms: [String] = [
        "蝦皮購物",
        "momo購物網",
        "PChome 24h",
        "PChome商店街",
        "Yahoo購物中心",
        "露天拍賣",
        "博客來",
        "東森購物",
        "生活市集",
        "淘寶",
        "天貓",
        "Amazon",
        "蘋果官網",
        "KOCA",
        "CASETiFY",
        "7-11賣貨便",
        "全家好賣+",
        "官方網站",
        "實體店面",
        "代購",
        "其他"
    ]
    
    /// 根據關鍵字過濾平台
    static func filter(by keyword: String) -> [String] {
        if keyword.isEmpty {
            return builtInPlatforms
        }
        return builtInPlatforms.filter { 
            $0.localizedCaseInsensitiveContains(keyword) 
        }
    }
}
