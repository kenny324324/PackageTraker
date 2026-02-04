//
//  TaiwaneseEmailParser.swift
//  PackageTraker
//
//  台灣電商/物流郵件解析器
//

import Foundation

/// 台灣電商/物流郵件解析器
final class TaiwaneseEmailParser {

    // MARK: - Singleton

    static let shared = TaiwaneseEmailParser()

    private let contentProcessor = EmailContentProcessor.shared

    private init() {}

    // MARK: - Email Source Detection

    /// 寄件者特徵（用於識別郵件來源）
    private let senderPatterns: [(pattern: String, source: EmailSource)] = [
        // 蝦皮
        ("@shopee\\.tw", .shopee),
        ("@spx\\.tw", .shopee),
        ("shopee", .shopee),

        // momo
        ("@momo\\.com\\.tw", .momo),
        ("momo購物", .momo),

        // PChome
        ("@pchome\\.com\\.tw", .pchome),
        ("pchome", .pchome),

        // 7-11（包含賣貨便）
        ("@myship\\.7-11\\.com\\.tw", .sevenEleven),
        ("myship.*7-11", .sevenEleven),
        ("@7-11\\.com\\.tw", .sevenEleven),
        ("7-eleven", .sevenEleven),
        ("交貨便", .sevenEleven),
        ("賣貨便", .sevenEleven),

        // 全家
        ("@family\\.com\\.tw", .familyMart),
        ("familymart", .familyMart),
        ("全家", .familyMart),

        // 黑貓
        ("@t-cat\\.com\\.tw", .tcat),
        ("黑貓", .tcat),
        ("宅急便", .tcat),

        // 順豐
        ("@sf-express\\.com", .sfExpress),
        ("順豐", .sfExpress)
    ]

    /// 主題特徵（用於補充識別）
    private let subjectPatterns: [(pattern: String, source: EmailSource)] = [
        ("蝦皮", .shopee),
        ("Shopee", .shopee),
        ("SPX", .shopee),
        ("momo", .momo),
        ("PChome", .pchome),
        ("24h", .pchome),
        ("7-11", .sevenEleven),
        ("7-ELEVEN", .sevenEleven),
        ("交貨便", .sevenEleven),
        ("賣貨便", .sevenEleven),
        ("全家", .familyMart),
        ("FamilyMart", .familyMart),
        ("黑貓", .tcat),
        ("宅急便", .tcat),
        ("順豐", .sfExpress),
        ("SF", .sfExpress)
    ]

    // MARK: - Tracking Number Patterns

    /// 物流單號 Regex 模式
    private let trackingPatterns: [(pattern: String, carrier: Carrier)] = [
        // 蝦皮 SPX 單號: SPX + 2字母 + 10-15數字
        ("SPX[A-Z]{2}\\d{10,15}", .shopee),

        // 蝦皮訂單號: 純數字 12-20 位
        ("\\d{15,20}", .shopee),

        // 7-11 賣貨便取貨代碼: N + 11位數字 (e.g., N01856100569)
        ("N\\d{11}", .sevenEleven),

        // 7-11 交貨便: TW + 12-15數字 + 可選字母
        ("TW\\d{12,15}[A-Z]?", .sevenEleven),

        // 7-11 EC 單號
        ("EC\\d{10,13}", .sevenEleven),

        // 全家店到店: 特定前綴 + 數字 (排除 CM 訂單編號)
        // 常見前綴: FA, FB, FC, WA, WB 等
        ("(?:FA|FB|FC|FD|WA|WB|WC|WD)\\d{10,13}", .familyMart),

        // 全家取件編號: 純數字 11 位
        ("\\b\\d{11}\\b", .familyMart),

        // 黑貓宅急便: 純12位數字
        ("\\b\\d{12}\\b", .tcat),

        // 順豐: SF + 12-15數字
        ("SF\\d{12,15}", .sfExpress),

        // 中華郵政: 純13位數字
        ("\\b\\d{13}\\b", .postTW)
    ]

    // MARK: - Pickup Code Patterns

    /// 取件碼模式
    private let pickupCodePatterns: [String] = [
        // 7-11 賣貨便取貨代碼: N + 11位數字
        "取貨代碼[：:﹕]?\\s*(N\\d{11})",

        // 蝦皮取件碼: X-X-X-X 或 X-X-XX-X 格式
        "\\d{1,2}-\\d{1,2}-\\d{1,2}-\\d{1,2}",

        // 全家取件碼: 純數字 8-12 位
        "取件(碼|代碼|密碼)[：:﹕]?\\s*(\\d{8,12})",

        // 7-11 取件碼/驗證碼
        "驗證碼[：:﹕]?\\s*(\\d{6,10})"
    ]

    // MARK: - Pickup Location Patterns

    /// 取件門市模式
    private let pickupLocationPatterns: [String] = [
        // 7-ELEVEN 門市 (e.g., "7-ELEVEN 福美門市", "至7-ELEVEN 福美完成取件")
        "至?7-ELEVEN\\s*([\\u4e00-\\u9fa5]+)(?:門市|店|完成取件)",
        "7-ELEVEN\\s*([\\u4e00-\\u9fa5]+門市)",

        // 蝦皮/全家/7-11 門市
        "(?:取件|取貨|門市|店鋪)[：:﹕]?\\s*([\\u4e00-\\u9fa5A-Za-z0-9]+(?:店|門市|便利商店|超商))",

        // 配送方式中的門市 (e.g., "店取：7-ELEVEN")
        "配送方式[：:﹕]?\\s*店取[：:﹕]?\\s*(7-ELEVEN|全家|萊爾富|OK)",

        // 地址格式
        "(?:地址|配送地址)[：:﹕]?\\s*([\\u4e00-\\u9fa5A-Za-z0-9\\-]+)"
    ]

    // MARK: - Public Methods

    /// 解析郵件
    func parseEmail(
        subject: String,
        sender: String,
        body: String,
        receivedDate: Date,
        messageId: String? = nil
    ) -> ParsedEmailResult? {
        // 1. 識別郵件來源
        let source = detectSource(sender: sender, subject: subject)

        // 將 HTML 轉為純文字
        let plainBody = contentProcessor.htmlToPlainText(body)
        let fullText = "\(subject)\n\(plainBody)"

        // 2. 提取物流單號
        guard let (trackingNumber, carrier) = extractTrackingNumber(from: fullText, source: source) else {
            return nil
        }

        // 3. 提取取件碼
        let pickupCode = extractPickupCode(from: fullText)

        // 4. 提取取件門市
        let pickupLocation = extractPickupLocation(from: fullText)

        // 5. 提取商品描述
        let orderDescription = extractOrderDescription(from: fullText, source: source)

        return ParsedEmailResult(
            source: source,
            trackingNumber: trackingNumber,
            carrier: carrier,
            pickupCode: pickupCode,
            pickupLocation: pickupLocation,
            orderDescription: orderDescription,
            emailDate: receivedDate,
            emailMessageId: messageId
        )
    }

    /// 檢查郵件是否可能包含物流資訊
    func mightContainTrackingInfo(subject: String, sender: String) -> Bool {
        let combinedText = "\(subject) \(sender)".lowercased()

        let keywords = [
            "出貨", "配送", "物流", "追蹤", "tracking",
            "shipping", "delivery", "到店", "取件", "取貨",
            "已送達", "派送", "寄送", "運送", "快遞",
            "包裹", "訂單", "order", "package"
        ]

        return keywords.contains { combinedText.contains($0) }
    }

    // MARK: - Private Methods

    private func detectSource(sender: String, subject: String) -> EmailSource {
        let lowerSender = sender.lowercased()
        let lowerSubject = subject.lowercased()

        // 先檢查寄件者
        for (pattern, source) in senderPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lowerSender.startIndex..., in: lowerSender)
                if regex.firstMatch(in: lowerSender, range: range) != nil {
                    return source
                }
            }
        }

        // 再檢查主題
        for (pattern, source) in subjectPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lowerSubject.startIndex..., in: lowerSubject)
                if regex.firstMatch(in: lowerSubject, range: range) != nil {
                    return source
                }
            }
        }

        return .unknown
    }

    private func extractTrackingNumber(from text: String, source: EmailSource) -> (String, Carrier)? {
        // 7-ELEVEN 特殊處理：優先提取取貨代碼 (N + 11位數字)
        if source == .sevenEleven {
            // 先嘗試提取 取貨代碼：N01856100569 格式
            let sevenElevenPickupPattern = "取貨代碼[：:﹕]?\\s*(N\\d{11})"
            if let pickupCode = contentProcessor.extractInfo(from: text, pattern: sevenElevenPickupPattern) {
                // 清理提取結果，只保留 N + 數字
                let cleanedCode = pickupCode.replacingOccurrences(of: "[^N0-9]", with: "", options: .regularExpression)
                if cleanedCode.hasPrefix("N") && cleanedCode.count == 12 {
                    return (cleanedCode, .sevenEleven)
                }
            }

            // 直接尋找 N + 11位數字
            let directPattern = "N\\d{11}"
            if let pickupCode = contentProcessor.extractInfo(from: text, pattern: directPattern) {
                return (pickupCode, .sevenEleven)
            }
        }

        // 根據來源優先使用對應的模式
        var prioritizedPatterns = trackingPatterns

        // 根據識別的來源調整優先順序
        if let sourceCarrier = source.carrier {
            prioritizedPatterns.sort { lhs, rhs in
                if lhs.carrier == sourceCarrier { return true }
                if rhs.carrier == sourceCarrier { return false }
                return false
            }
        }

        for (pattern, carrier) in prioritizedPatterns {
            if let trackingNumber = contentProcessor.extractInfo(from: text, pattern: pattern) {
                // 驗證單號格式（排除太短或太長的結果）
                if trackingNumber.count >= 10 && trackingNumber.count <= 25 {
                    // 排除 CM 開頭的訂單編號（這是 7-ELEVEN 賣貨便的訂單號，不是追蹤碼）
                    if trackingNumber.hasPrefix("CM") {
                        continue
                    }

                    // 排除明顯的電話號碼格式（純數字單號才需要檢查）
                    if trackingNumber.allSatisfy({ $0.isNumber }) {
                        // 886 開頭是台灣國際電話格式
                        if trackingNumber.hasPrefix("886") {
                            continue
                        }
                        // 09 開頭是台灣手機號碼
                        if trackingNumber.hasPrefix("09") {
                            continue
                        }
                        // 0800/0900 等服務電話
                        if trackingNumber.hasPrefix("0800") || trackingNumber.hasPrefix("0900") {
                            continue
                        }
                        // 其他純數字單號：不在 parser 層面過濾，交給 API 驗證
                    }

                    return (trackingNumber, carrier)
                }
            }
        }

        return nil
    }

    private func extractPickupCode(from text: String) -> String? {
        // 7-ELEVEN 取貨代碼: N + 11位數字 (優先處理)
        let sevenElevenPattern = "取貨代碼[：:﹕]?\\s*(N\\d{11})"
        if let code = contentProcessor.extractInfo(from: text, pattern: sevenElevenPattern) {
            let cleanedCode = code.replacingOccurrences(of: "[^N0-9]", with: "", options: .regularExpression)
            if cleanedCode.hasPrefix("N") && cleanedCode.count == 12 {
                return cleanedCode
            }
        }

        // 直接匹配 N + 11位數字
        let directSevenElevenPattern = "N\\d{11}"
        if let code = contentProcessor.extractInfo(from: text, pattern: directSevenElevenPattern) {
            return code
        }

        for pattern in pickupCodePatterns {
            if let code = contentProcessor.extractInfo(from: text, pattern: pattern) {
                // 清理提取的取件碼（保留 N 字母和數字、連字號）
                let cleanedCode = code
                    .replacingOccurrences(of: "[^N0-9\\-]", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)

                if !cleanedCode.isEmpty {
                    return cleanedCode
                }
            }
        }

        // 特別處理蝦皮的 X-X-X-X 格式取件碼
        let shopeePattern = "\\d{1,2}-\\d{1,2}-\\d{1,2}-\\d{1,2}"
        if let code = contentProcessor.extractInfo(from: text, pattern: shopeePattern) {
            return code
        }

        return nil
    }

    private func extractPickupLocation(from text: String) -> String? {
        // 先嘗試提取 7-ELEVEN 門市 (e.g., "至7-ELEVEN 福美完成取件", "7-ELEVEN 福美門市")
        // 門市名稱通常是 2-4 個中文字，需要排除「完成取件」等動作詞
        let sevenElevenPatterns = [
            "7-ELEVEN\\s*([\\u4e00-\\u9fa5]{2,4})門市",           // 7-ELEVEN 福美門市
            "至7-ELEVEN\\s*([\\u4e00-\\u9fa5]{2,4})完成取件",      // 至7-ELEVEN 福美完成取件
            "7-ELEVEN\\s*([\\u4e00-\\u9fa5]{2,4})(?:店|$)"        // 7-ELEVEN 福美店 或結尾
        ]

        for pattern in sevenElevenPatterns {
            if let match = contentProcessor.extractInfo(from: text, pattern: pattern) {
                let storeName = match.trimmingCharacters(in: .whitespaces)
                // 排除動作詞
                let actionWords = ["完成", "取件", "取貨", "配送", "到店"]
                let isActionWord = actionWords.contains { storeName.contains($0) }
                if !storeName.isEmpty && storeName.count <= 6 && !isActionWord {
                    return "7-ELEVEN \(storeName)門市"
                }
            }
        }

        for pattern in pickupLocationPatterns {
            if let location = contentProcessor.extractInfo(from: text, pattern: pattern) {
                let cleanedLocation = location.trimmingCharacters(in: .whitespaces)
                if !cleanedLocation.isEmpty && cleanedLocation.count <= 50 {
                    return cleanedLocation
                }
            }
        }

        // 嘗試提取常見的便利商店名稱
        let storePatterns = [
            "7-ELEVEN\\s*[\\u4e00-\\u9fa5]+(?:門市|店)",
            "全家\\s*[\\u4e00-\\u9fa5]+店",
            "萊爾富\\s*[\\u4e00-\\u9fa5]+店",
            "OK\\s*[\\u4e00-\\u9fa5]+店"
        ]

        for pattern in storePatterns {
            if let location = contentProcessor.extractInfo(from: text, pattern: pattern) {
                return location.trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }

    private func extractOrderDescription(from text: String, source: EmailSource) -> String? {
        // 嘗試提取商品名稱
        let productPatterns = [
            "商品[：:﹕]?\\s*([\\u4e00-\\u9fa5A-Za-z0-9\\s]+)",
            "品名[：:﹕]?\\s*([\\u4e00-\\u9fa5A-Za-z0-9\\s]+)",
            "訂單內容[：:﹕]?\\s*([\\u4e00-\\u9fa5A-Za-z0-9\\s]+)"
        ]

        for pattern in productPatterns {
            if let description = contentProcessor.extractInfo(from: text, pattern: pattern) {
                let cleaned = description.trimmingCharacters(in: .whitespaces)
                // 限制描述長度
                if cleaned.count >= 2 && cleaned.count <= 100 {
                    return String(cleaned.prefix(100))
                }
            }
        }

        return nil
    }
}

// MARK: - Batch Processing

extension TaiwaneseEmailParser {

    /// 批量解析郵件
    func parseEmails(_ messages: [GmailMessage]) -> [ParsedEmailResult] {
        return messages.compactMap { message in
            parseEmail(
                subject: message.subject,
                sender: message.sender,
                body: message.body,
                receivedDate: message.receivedDate,
                messageId: message.id
            )
        }
    }

    /// 過濾可能包含物流資訊的郵件
    func filterTrackingEmails(_ messages: [GmailMessage]) -> [GmailMessage] {
        return messages.filter { message in
            mightContainTrackingInfo(subject: message.subject, sender: message.sender)
        }
    }
}
