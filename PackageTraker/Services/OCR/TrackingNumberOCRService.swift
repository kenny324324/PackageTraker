//
//  TrackingNumberOCRService.swift
//  PackageTraker
//
//  OCR service for recognizing tracking numbers from screenshots
//

import Foundation
import Vision
import UIKit

/// OCR 辨識結果
struct OCRResult {
    /// 自動辨識到的物流單號候選
    let trackingNumberCandidates: [TrackingNumberCandidate]

    /// 所有辨識到的文字（備案用）
    let allRecognizedTexts: [RecognizedText]

    /// 是否成功辨識到單號
    var hasTrackingNumbers: Bool {
        !trackingNumberCandidates.isEmpty
    }
}

/// 單號候選
struct TrackingNumberCandidate: Identifiable {
    let id = UUID()
    let trackingNumber: String
    let suggestedCarrier: Carrier?
    let confidence: Float

    var displayText: String {
        if let carrier = suggestedCarrier {
            return "\(trackingNumber) (\(carrier.displayName))"
        }
        return trackingNumber
    }
}

/// 辨識到的文字片段
struct RecognizedText: Identifiable {
    let id = UUID()
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

// MARK: - Tracking Pattern (shared between OCR and CarrierDetector)

/// 統一的物流單號辨識 pattern
struct TrackingPattern {
    let regex: String
    let carrier: Carrier?
    let confidence: Float

    /// 所有 OCR 辨識用 pattern（從高信心度到低信心度排列）
    static let ocrPatterns: [TrackingPattern] = [
        // 蝦皮店到店：TW + 12位數字 + H/F = 15字元
        TrackingPattern(regex: "^TW[0-9]{12}[HF]$", carrier: .shopee, confidence: 0.98),

        // 蝦皮 SPX：SPXTE/SPXRT + 數字
        TrackingPattern(regex: "^SPXTE[0-9]{10,15}$", carrier: .shopee, confidence: 0.95),
        TrackingPattern(regex: "^SPXRT[0-9]{10,15}$", carrier: .shopee, confidence: 0.95),
        TrackingPattern(regex: "^SPX[A-Z]{2}[0-9]{10,15}$", carrier: .shopee, confidence: 0.90),

        // 中華郵政國際：2 字母 + 9 數字 + TW
        TrackingPattern(regex: "^[A-Z]{2}[0-9]{9}TW$", carrier: .postTW, confidence: 0.95),

        // 萊爾富：HL 開頭
        TrackingPattern(regex: "^HL[0-9]{10,15}$", carrier: .hiLife, confidence: 0.95),

        // 順豐：SF 開頭
        TrackingPattern(regex: "^SF[0-9]{12,15}$", carrier: .sfExpress, confidence: 0.95),

        // 全家店到店：T 開頭 + 數字
        TrackingPattern(regex: "^T[0-9]{9,12}$", carrier: .familyMart, confidence: 0.95),

        // 宅配通：E 開頭 + 數字
        TrackingPattern(regex: "^E[0-9]{11,12}$", carrier: .ecan, confidence: 0.90),

        // 菜鳥：LP 開頭
        TrackingPattern(regex: "^LP[0-9]{15,18}$", carrier: .cainiao, confidence: 0.90),

        // 通用蝦皮格式（TW + 數字，無結尾字母）
        TrackingPattern(regex: "^TW[0-9]{10,15}$", carrier: .shopee, confidence: 0.85),

        // 7-ELEVEN 交貨便：純數字 10-15 位
        TrackingPattern(regex: "^[0-9]{10,15}$", carrier: .sevenEleven, confidence: 0.80),

        // 全家（2 字母 + 數字）
        TrackingPattern(regex: "^[A-Z]{2}[0-9]{10,13}$", carrier: .familyMart, confidence: 0.70),

        // 黑貓宅急便：12 碼純數字
        TrackingPattern(regex: "^[0-9]{12}$", carrier: .tcat, confidence: 0.65),

        // 新竹物流：10-11 碼純數字
        TrackingPattern(regex: "^[0-9]{10,11}$", carrier: .hct, confidence: 0.60),

        // 中華郵政國內：13 碼純數字
        TrackingPattern(regex: "^[0-9]{13}$", carrier: .postTW, confidence: 0.50),
    ]
}

/// 物流單號 OCR 辨識服務
class TrackingNumberOCRService {

    // MARK: - Singleton

    static let shared = TrackingNumberOCRService()

    private init() {}

    // MARK: - Context Keywords

    /// 上下文關鍵字（出現在附近的文字可提高候選信心度）
    private let contextKeywords: Set<String> = [
        "追蹤編號", "追蹤號碼", "取貨編號", "取件編號", "單號",
        "貨運單號", "物流編號", "配送編號", "寄件編號", "取貨碼", "取件碼",
        "tracking", "trackingnumber", "trackingno", "number", "shipment", "delivery",
        "追踪编号", "取货编号", "快递单号", "物流单号", "蝦皮店到店",
    ]

    /// 蝦皮場景關鍵字（用於候選排序偏好）
    private let shopeeContextKeywords: Set<String> = [
        "蝦皮", "蝦皮店到店", "店到店", "SPX", "SHOPEE",
    ]

    /// 物流商關鍵字提示（平台與物流商分離判斷）
    private let carrierHintKeywords: [(keywords: [String], carrier: Carrier)] = [
        (["全家", "FAMILYMART"], .familyMart),
        (["7-11", "711", "統一超商", "交貨便", "SEVEN"], .sevenEleven),
        (["萊爾富", "HILIFE"], .hiLife),
        (["OKMART", "OK超商", "OK MART"], .okMart),
    ]

    // MARK: - Public Methods

    /// 從圖片辨識物流單號
    func recognizeTrackingNumbers(from image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        // 執行 OCR
        let recognizedTexts = try await performOCR(on: cgImage)

        // 偵測上下文關鍵字位置
        let keywordYPositions = findKeywordYPositions(from: recognizedTexts)

        // 從辨識結果中尋找物流單號（含多行合併）
        let candidates = findTrackingNumberCandidates(
            from: recognizedTexts,
            keywordYPositions: keywordYPositions
        )

        return OCRResult(
            trackingNumberCandidates: candidates,
            allRecognizedTexts: recognizedTexts
        )
    }

    // MARK: - Private Methods

    /// 執行 OCR 文字辨識
    private func performOCR(on cgImage: CGImage) async throws -> [RecognizedText] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                var recognizedTexts: [RecognizedText] = []
                for observation in observations {
                    let topCandidates = observation.topCandidates(3)
                    for candidate in topCandidates {
                        recognizedTexts.append(RecognizedText(
                            text: candidate.string,
                            confidence: candidate.confidence,
                            boundingBox: observation.boundingBox
                        ))
                    }
                }

                continuation.resume(returning: recognizedTexts)
            }

            // 設定辨識參數
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
            request.usesLanguageCorrection = false // 單號不需要語言校正

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    /// 尋找上下文關鍵字的 Y 座標
    private func findKeywordYPositions(from texts: [RecognizedText]) -> [CGFloat] {
        var positions: [CGFloat] = []
        for text in texts {
            let cleaned = text.text
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
            if contextKeywords.contains(where: { cleaned.contains($0) }) {
                positions.append(text.boundingBox.midY)
            }
        }
        return positions
    }

    /// 從辨識結果中尋找物流單號候選
    private func findTrackingNumberCandidates(
        from texts: [RecognizedText],
        keywordYPositions: [CGFloat]
    ) -> [TrackingNumberCandidate] {
        var candidateMap: [String: TrackingNumberCandidate] = [:]
        let hasShopeeContext = containsShopeeContext(in: texts)
        let hintedCarrier = detectCarrierHint(in: texts)

        // 按 Y 座標排序（從上到下）
        let sortedTexts = texts.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        // 單行比對
        for text in sortedTexts {
            for searchableText in generateSearchableTexts(from: text.text) {
                let matched = matchAllPatterns(searchableText, confidence: text.confidence)
                for matchedCandidate in matched {
                    let boosted = applyContextBoost(
                        matchedCandidate,
                        textY: text.boundingBox.midY,
                        keywordYPositions: keywordYPositions
                    )
                    let key = candidateKey(for: boosted)
                    if let existing = candidateMap[key] {
                        if boosted.confidence > existing.confidence {
                            candidateMap[key] = boosted
                        }
                    } else {
                        candidateMap[key] = boosted
                    }
                }
            }
        }

        // 多行合併：嘗試相鄰行合併
        for i in 0..<sortedTexts.count {
            let textA = sortedTexts[i]
            for mergeCount in 2...3 {
                let endIndex = i + mergeCount - 1
                guard endIndex < sortedTexts.count else { continue }

                let mergeSlice = sortedTexts[i...endIndex]
                guard let firstY = mergeSlice.first?.boundingBox.midY,
                      let lastY = mergeSlice.last?.boundingBox.midY else {
                    continue
                }

                // Y 距離小於 0.1 才考慮合併，處理跨行斷裂
                let yDistance = abs(firstY - lastY)
                guard yDistance < 0.1 else { continue }

                let mergedRaw = mergeSlice.map(\.text).joined()
                let mergedConfidence = mergeSlice.map(\.confidence).min()! * 0.9

                for searchableText in generateSearchableTexts(from: mergedRaw) {
                    let matched = matchAllPatterns(searchableText, confidence: mergedConfidence)
                    for matchedCandidate in matched {
                        let boosted = applyContextBoost(
                            matchedCandidate,
                            textY: textA.boundingBox.midY,
                            keywordYPositions: keywordYPositions
                        )
                        let key = candidateKey(for: boosted)
                        if let existing = candidateMap[key] {
                            if boosted.confidence > existing.confidence {
                                candidateMap[key] = boosted
                            }
                        } else {
                            candidateMap[key] = boosted
                        }
                    }
                }
            }
        }

        // 後處理：去除低信心噪音、同單號只保留最高分，並限制建議數量
        let adjusted = candidateMap.values.map {
            applyContextSpecificBias(
                to: $0,
                hasShopeeContext: hasShopeeContext,
                hintedCarrier: hintedCarrier
            )
        }
        let sorted = adjusted.sorted { $0.confidence > $1.confidence }
        return postProcessCandidates(sorted, hasShopeeContext: hasShopeeContext, hintedCarrier: hintedCarrier)
    }

    /// 是否包含蝦皮上下文
    private func containsShopeeContext(in texts: [RecognizedText]) -> Bool {
        texts.contains { text in
            let normalized = normalizeOCRText(text.text)
            return shopeeContextKeywords.contains { normalized.contains($0) }
        }
    }

    /// 從畫面文字推測物流商提示（例如全家/7-11）
    private func detectCarrierHint(in texts: [RecognizedText]) -> Carrier? {
        for text in texts {
            let normalized = normalizeOCRText(text.text)
            for hint in carrierHintKeywords {
                if hint.keywords.contains(where: { normalized.contains($0) }) {
                    return hint.carrier
                }
            }
        }
        return nil
    }

    /// 場景化權重：蝦皮上下文時偏好 TW/SPX，抑制純數字噪音
    private func applyContextSpecificBias(
        to candidate: TrackingNumberCandidate,
        hasShopeeContext: Bool,
        hintedCarrier: Carrier?
    ) -> TrackingNumberCandidate {
        var score = candidate.confidence
        var carrier = candidate.suggestedCarrier
        let tracking = candidate.trackingNumber

        if hasShopeeContext && (tracking.hasPrefix("TW") || tracking.hasPrefix("SPX")) {
            score = min(score * 1.18, 1.0)
        }

        // 若畫面明確出現「全家/7-11」等關鍵字，覆蓋 TW/SPX 的預設物流商，避免誤設為 Shopee
        if let hintedCarrier, tracking.hasPrefix("TW") || tracking.hasPrefix("SPX") {
            carrier = hintedCarrier
            score = min(score * 1.08, 1.0)
        }

        if hasShopeeContext && tracking.allSatisfy(\.isNumber) {
            score *= 0.65
        }

        return TrackingNumberCandidate(
            trackingNumber: candidate.trackingNumber,
            suggestedCarrier: carrier,
            confidence: score
        )
    }

    /// 候選鍵值（相同單號與物流商視為同一候選）
    private func candidateKey(for candidate: TrackingNumberCandidate) -> String {
        "\(candidate.trackingNumber)|\(candidate.suggestedCarrier?.rawValue ?? "nil")"
    }

    /// 收斂候選，避免 UI 出現過多建議
    private func postProcessCandidates(
        _ sorted: [TrackingNumberCandidate],
        hasShopeeContext: Bool,
        hintedCarrier: Carrier?
    ) -> [TrackingNumberCandidate] {
        // 先過濾掉太低分的候選，減少日期/金額誤判
        let baseThreshold: Float = 0.35
        let filtered = sorted.filter { $0.confidence >= baseThreshold }

        // 同一單號可能命中多個 carrier pattern，只保留最高信心的一筆
        var bestByTracking: [String: TrackingNumberCandidate] = [:]
        for candidate in filtered {
            if let existing = bestByTracking[candidate.trackingNumber] {
                if candidate.confidence > existing.confidence {
                    bestByTracking[candidate.trackingNumber] = candidate
                }
            } else {
                bestByTracking[candidate.trackingNumber] = candidate
            }
        }

        var deduped = bestByTracking.values.sorted { $0.confidence > $1.confidence }
        guard !deduped.isEmpty else { return [] }

        // 蝦皮上下文且無明確物流商提示時，偏好 TW/SPX 候選；有提示則不做硬過濾
        if hasShopeeContext && hintedCarrier == nil {
            let twOrSpx = deduped.filter {
                $0.trackingNumber.hasPrefix("TW") || $0.trackingNumber.hasPrefix("SPX")
            }
            if !twOrSpx.isEmpty {
                deduped = twOrSpx
            }
        }

        // 若有高分候選，抬高門檻僅保留接近最佳分數的建議
        let topConfidence = deduped[0].confidence
        let adaptiveThreshold: Float
        if topConfidence >= 0.85 {
            adaptiveThreshold = max(0.65, topConfidence - 0.18)
        } else if topConfidence >= 0.70 {
            adaptiveThreshold = max(0.50, topConfidence - 0.20)
        } else {
            adaptiveThreshold = 0.35
        }

        let narrowed = deduped.filter { $0.confidence >= adaptiveThreshold }
        return Array(narrowed.prefix(5))
    }

    /// 從原始 OCR 文字中抽可比對的字串（含整段與行內片段）
    private func generateSearchableTexts(from rawText: String) -> [String] {
        var results = Set<String>()
        let cleanedWhole = cleanAndFixOCR(rawText)
        if !cleanedWhole.isEmpty {
            results.insert(cleanedWhole)
        }

        let normalized = normalizeOCRText(rawText)
        let parts = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for part in parts where part.count >= 8 {
            let cleaned = cleanAndFixOCR(part)
            if !cleaned.isEmpty {
                results.insert(cleaned)
            }
        }

        // 從整行中直接擷取可能的單號片段（解決「前後夾雜中文或符號」造成 miss）
        for embedded in extractEmbeddedTrackingSegments(from: normalized) {
            let cleaned = cleanAndFixOCR(embedded)
            if !cleaned.isEmpty {
                results.insert(cleaned)
            }
        }

        return Array(results)
    }

    /// 從 OCR 原文中擷取常見物流單號片段（容許數字段出現 OCR 易錯字）
    private func extractEmbeddedTrackingSegments(from text: String) -> [String] {
        let patterns = [
            #"TW[0-9OILSBGZ]{10,15}[HF]?"#,
            #"SPX(?:TE|RT|[A-Z]{2})[0-9OILSBGZ]{10,15}"#,
            #"SF[0-9OILSBGZ]{12,15}"#,
            #"HL[0-9OILSBGZ]{10,15}"#,
            #"LP[0-9OILSBGZ]{15,18}"#,
            #"E[0-9OILSBGZ]{11,12}"#,
            #"T[0-9OILSBGZ]{9,12}"#,
            #"[A-Z]{2}[0-9OILSBGZ]{9}TW"#,
        ]

        var results: [String] = []
        let nsText = text as NSString

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: nsText.length)
            let matches = regex.matches(in: text, range: range)
            for match in matches where match.range.location != NSNotFound {
                results.append(nsText.substring(with: match.range))
            }
        }

        return results
    }

    /// OCR 文本正規化（全形轉半形 + 英文轉大寫）
    private func normalizeOCRText(_ text: String) -> String {
        text.applyingTransform(.fullwidthToHalfwidth, reverse: false)?
            .uppercased() ?? text.uppercased()
    }

    /// 清理文字 + 修正常見 OCR 錯誤
    private func cleanAndFixOCR(_ rawText: String) -> String {
        var text = normalizeOCRText(rawText)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: "／", with: "")
            .replacingOccurrences(of: "/", with: "")

        text = fixCommonOCRErrors(text)
        return text
    }

    /// 修正常見 OCR 辨識錯誤
    private func fixCommonOCRErrors(_ text: String) -> String {
        var result = text

        // 蝦皮單號格式：TW + 12位數字 + H (共15字元)
        // 常見錯誤：H 後面多辨識出 O 或 0
        if result.hasPrefix("TW") && result.count == 16 {
            if result.hasSuffix("H0") || result.hasSuffix("HO") {
                result = String(result.dropLast())
            }
        }

        // 已知前綴格式：數字部分的字母替換
        if result.hasPrefix("TW") && result.count >= 12 {
            let prefix = result.prefix(2)
            let rest = String(result.dropFirst(2))

            // Shopee 店到店：TW + 數字 + H/F
            if let last = rest.last, (last == "H" || last == "F"), rest.count >= 11 {
                let digitPart = String(rest.dropLast())
                result = prefix + fixDigitPart(digitPart) + String(last)
            } else {
                // 其他 TW 格式：TW + 純數字（末位也要修正）
                result = prefix + fixDigitPart(rest)
            }
        } else if result.hasPrefix("SF") && result.count >= 14 {
            let prefix = result.prefix(2)
            let rest = String(result.dropFirst(2))
            result = prefix + fixDigitPart(rest)
        } else if result.hasPrefix("HL") && result.count >= 12 {
            let prefix = result.prefix(2)
            let rest = String(result.dropFirst(2))
            result = prefix + fixDigitPart(rest)
        } else if result.hasPrefix("LP") && result.count >= 17 {
            let prefix = result.prefix(2)
            let rest = String(result.dropFirst(2))
            result = prefix + fixDigitPart(rest)
        } else if result.hasPrefix("E") && !result.hasPrefix("EX") && result.count >= 12 {
            let prefix = result.prefix(1)
            let rest = String(result.dropFirst(1))
            result = prefix + fixDigitPart(rest)
        } else if result.hasPrefix("T") && !result.hasPrefix("TW") && result.count >= 10 {
            let prefix = result.prefix(1)
            let rest = String(result.dropFirst(1))
            result = prefix + fixDigitPart(rest)
        } else if result.allSatisfy({ $0.isNumber || "OILSBGZ".contains($0) }) && result.count >= 10 {
            // 純數字字串：全面套用替換
            result = fixDigitPart(result)
        }

        return result
    }

    /// 修正應為數字的字串中的 OCR 錯誤
    private func fixDigitPart(_ text: String) -> String {
        var result = ""
        for char in text {
            switch char {
            case "O": result.append("0")
            case "I", "L": result.append("1")
            case "S": result.append("5")
            case "B": result.append("8")
            case "G": result.append("6")
            case "Z": result.append("2")
            default: result.append(char)
            }
        }
        return result
    }

    /// 比對所有 pattern
    private func matchAllPatterns(_ text: String, confidence: Float) -> [TrackingNumberCandidate] {
        var candidates: [TrackingNumberCandidate] = []
        var seenCombos = Set<String>() // "trackingNumber|carrier" 避免重複

        for pattern in TrackingPattern.ocrPatterns {
            if let match = matchPattern(text, pattern: pattern.regex) {
                let key = "\(match)|\(pattern.carrier?.rawValue ?? "nil")"
                if !seenCombos.contains(key) {
                    seenCombos.insert(key)
                    candidates.append(TrackingNumberCandidate(
                        trackingNumber: match,
                        suggestedCarrier: pattern.carrier,
                        confidence: confidence * pattern.confidence
                    ))
                }
            }
        }

        return candidates
    }

    /// 上下文關鍵字加成
    private func applyContextBoost(
        _ candidate: TrackingNumberCandidate,
        textY: CGFloat,
        keywordYPositions: [CGFloat]
    ) -> TrackingNumberCandidate {
        // 檢查是否有關鍵字在附近（Y 距離 < 0.1）
        let hasNearbyKeyword = keywordYPositions.contains { abs($0 - textY) < 0.1 }

        if hasNearbyKeyword {
            let boosted = min(candidate.confidence * 1.15, 1.0)
            return TrackingNumberCandidate(
                trackingNumber: candidate.trackingNumber,
                suggestedCarrier: candidate.suggestedCarrier,
                confidence: boosted
            )
        }

        return candidate
    }

    /// 使用正則表達式比對
    private func matchPattern(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range) {
            let matchRange = Range(match.range, in: text)!
            return String(text[matchRange])
        }

        return nil
    }
}

// MARK: - Errors

enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return String(localized: "error.imageLoadFailed")
        case .recognitionFailed(let message):
            return String(localized: "error.ocrFailed") + ": \(message)"
        }
    }
}
