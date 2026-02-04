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
    private static let patterns: [(regex: String, carrier: Carrier, confidence: Double)] = [
        // === 超商取貨 ===
        // 7-11 交貨便：TW 開頭 + 12-15 位數字 + 可選字母
        (#"^TW\d{12,15}[A-Z]?$"#, .sevenEleven, 0.95),
        // 全家店到店：2 字母 + 10-13 位數字
        (#"^[A-Z]{2}\d{10,13}$"#, .familyMart, 0.7),
        // 萊爾富：HL 開頭
        (#"^HL\d{10,15}$"#, .hiLife, 0.9),

        // === 台灣宅配 ===
        // 黑貓宅急便：12 碼純數字
        (#"^\d{12}$"#, .tcat, 0.8),
        // 新竹物流：10-12 碼數字（與黑貓重疊，信心度較低）
        (#"^\d{10,11}$"#, .hct, 0.6),
        // 宅配通：特定格式
        (#"^E\d{11,12}$"#, .ecan, 0.9),
        // 中華郵政國際：2 字母 + 9 數字 + TW
        (#"^[A-Z]{2}\d{9}TW$"#, .postTW, 0.95),
        // 中華郵政國內掛號
        (#"^\d{13}$"#, .postTW, 0.5),

        // === 國際快遞 ===
        // 順豐速運：SF 開頭
        (#"^SF\d{12,15}$"#, .sfExpress, 0.95),
        // DHL：10 位數字
        (#"^\d{10}$"#, .dhl, 0.4),
        // FedEx：12 或 15 位數字
        (#"^\d{15}$"#, .fedex, 0.5),
        // 菜鳥：LP/CAINIAO 開頭或特定格式
        (#"^LP\d{15,18}$"#, .cainiao, 0.9),

        // === 電商 ===
        // 蝦皮店到店 SPX：SPXTE/SPXRT 開頭 + 數字
        (#"^SPXTE\d{10,15}$"#, .shopee, 0.95),
        (#"^SPXRT\d{10,15}$"#, .shopee, 0.95),
        (#"^SPX[A-Z]{2}\d{10,15}$"#, .shopee, 0.9),
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
