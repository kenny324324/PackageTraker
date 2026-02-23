import Foundation

/// 物流商辨識器
/// 根據單號格式自動辨識可能的物流商
struct CarrierDetector {

    /// 辨識結果
    struct DetectionResult {
        let carrier: Carrier
        let confidence: Double  // 0.0 ~ 1.0
    }

    /// 正則匹配規則
    /// 規則來源：各物流商官網、Track.TW 實際單號、AfterShip/17TRACK 格式文件
    /// 排列順序：高特徵性前綴規則在前，通用數字規則在後（避免被先匹配到）
    private static let patterns: [(regex: String, carrier: Carrier, confidence: Double)] = [

        // ═══ 超商取貨 ═══

        // 7-11 交貨便：TW + 12-15 位數字 + 可選字母
        // 來源：Track.TW 實際單號 (TW259426993523H)
        (#"^TW\d{12,15}[A-Z]?$"#, .sevenEleven, 0.95),

        // 萊爾富：HL + 10-15 位數字
        // 來源：Track.TW 實際單號
        (#"^HL\d{10,15}$"#, .hiLife, 0.9),

        // ═══ 電商物流 ═══

        // 蝦皮店到店 SPX：SPXTE/SPXRT/SPX + 2字母 + 數字
        // 來源：Track.TW 實際單號、蝦皮 app
        (#"^SPXTE\d{10,15}$"#, .shopee, 0.95),
        (#"^SPXRT\d{10,15}$"#, .shopee, 0.95),
        (#"^SPX[A-Z]{2}\d{10,15}$"#, .shopee, 0.9),

        // PChome 網家速配：12 碼數字，以 12 開頭
        // 來源：Track.TW 實際單號 (125710493260, 125033438042, 124045900605)
        (#"^12\d{10}$"#, .pchome, 0.9),

        // momo 富昇物流：12 碼數字，以 300 開頭
        // 來源：Track.TW 實際單號 (300498983411, 300497563376, 300416014964)
        (#"^300\d{9}$"#, .momo, 0.95),

        // ═══ 國際快遞 ═══

        // 順豐速運：SF + 12-15 位數字
        // 來源：順豐官網
        (#"^SF\d{12,15}$"#, .sfExpress, 0.95),

        // UPS：1Z + 16 碼英數（最常見格式）
        // 來源：UPS 官網、Wikipedia Tracking number
        (#"^1Z[A-Z0-9]{16}$"#, .ups, 0.95),

        // DHL Express：JD + 18 位數字 或 JJD + 16 位數字（快遞提單）
        // 來源：TrackingAdvice DHL Tracking Numbers
        (#"^JD\d{18}$"#, .dhl, 0.9),
        (#"^JJD\d{16}$"#, .dhl, 0.9),

        // FedEx SmartPost：92 + 18-20 位數字
        // 來源：Ship24 FedEx Tracking Number Guide
        (#"^92\d{18,20}$"#, .fedex, 0.85),

        // FedEx Door Tag：DT + 12 位數字
        // 來源：FedEx 官網
        (#"^DT\d{12}$"#, .fedex, 0.9),

        // 菜鳥：LP + 15-18 位數字
        // 來源：Track.TW
        (#"^LP\d{15,18}$"#, .cainiao, 0.9),

        // ═══ 台灣宅配 ═══

        // 宅配通：E + 11-12 位數字
        // 來源：Track.TW 實際單號
        (#"^E\d{11,12}$"#, .ecan, 0.9),

        // 中華郵政國際：2 字母 + 9 數字 + TW
        // 來源：萬國郵聯 S10 標準
        (#"^[A-Z]{2}\d{9}TW$"#, .postTW, 0.95),

        // 台灣快遞：2-3 字母前綴 + 9-12 位數字（如 TBK101901611）
        // 來源：AfterShip Kerry Express Taiwan
        (#"^[A-Z]{2,3}\d{9,12}$"#, .taiwanExpress, 0.6),

        // 全家店到店：2 字母 + 10-13 位數字（通用格式，較低信心度）
        // 來源：Track.TW 實際單號
        // 注意：此規則較通用，放在台灣快遞之後避免搶先匹配
        (#"^[A-Z]{2}\d{10,13}$"#, .familyMart, 0.7),

        // ═══ 純數字規則（低特徵性，放最後）═══

        // 黑貓宅急便：12 碼純數字（排除 PChome 12 開頭）
        // 來源：Track.TW 實際單號
        (#"^\d{12}$"#, .tcat, 0.7),

        // 嘉里大榮物流：10-11 碼純數字
        // 來源：Track.TW 實際單號 (96310238467, 74302130221, 6694211241)
        // 注意：與新竹物流格式重疊，信心度相同
        (#"^\d{10,11}$"#, .kerry, 0.5),

        // 新竹物流：10-11 碼純數字
        // 來源：Track.TW 實際單號
        // 注意：與嘉里大榮格式重疊，需搭配 AI 辨識判斷
        (#"^\d{10,11}$"#, .hct, 0.5),

        // DHL Express：10 碼純數字（通用格式）
        // 來源：DHL 官網
        (#"^\d{10}$"#, .dhl, 0.4),

        // FedEx：15 碼純數字
        // 來源：FedEx 官網
        (#"^\d{15}$"#, .fedex, 0.5),

        // 中華郵政國內掛號：13 碼純數字
        // 來源：中華郵政官網
        (#"^\d{13}$"#, .postTW, 0.5),
    ]

    /// 從單號偵測可能的物流商
    /// - Parameter trackingNumber: 物流單號
    /// - Returns: 可能的物流商列表，按信心度排序
    static func detect(_ trackingNumber: String) -> [DetectionResult] {
        let trimmed = trackingNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")

        guard !trimmed.isEmpty else { return [] }

        var results: [DetectionResult] = []

        for pattern in patterns {
            if let _ = trimmed.range(of: pattern.regex, options: .regularExpression) {
                results.append(DetectionResult(
                    carrier: pattern.carrier,
                    confidence: pattern.confidence
                ))
            }
        }

        // 按信心度排序（高到低）
        return results.sorted { $0.confidence > $1.confidence }
    }

    /// 取得最可能的物流商（信心度最高的）
    static func detectBest(_ trackingNumber: String) -> DetectionResult? {
        detect(trackingNumber).first
    }

    /// 驗證單號格式是否有效
    static func isValidFormat(_ trackingNumber: String) -> Bool {
        let trimmed = trackingNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")

        // 基本格式驗證：5-50 字元，只允許字母、數字
        let validPattern = #"^[A-Z0-9]{5,50}$"#
        return trimmed.range(of: validPattern, options: .regularExpression) != nil
    }
}

// MARK: - Carrier 擴展
extension Carrier {
    /// 常用的台灣物流商（用於快速選擇）
    static var commonTaiwanCarriers: [Carrier] {
        [.sevenEleven, .familyMart, .shopee, .tcat, .hct]
    }

    /// 所有超商取貨
    static var convenienceStores: [Carrier] {
        [.sevenEleven, .familyMart, .hiLife, .okMart]
    }

    /// 所有台灣宅配
    static var taiwanDelivery: [Carrier] {
        [.tcat, .hct, .ecan, .postTW]
    }
}
