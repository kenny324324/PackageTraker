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
        "貨運單號", "物流編號", "配送編號", "寄件編號",
        "tracking", "trackingnumber", "trackingno",
        "追踪编号", "取货编号", "快递单号",
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

                let recognizedTexts = observations.compactMap { observation -> RecognizedText? in
                    guard let topCandidate = observation.topCandidates(1).first else {
                        return nil
                    }
                    return RecognizedText(
                        text: topCandidate.string,
                        confidence: topCandidate.confidence,
                        boundingBox: observation.boundingBox
                    )
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
        var candidates: [TrackingNumberCandidate] = []
        var seenNumbers = Set<String>()

        // 按 Y 座標排序（從上到下）
        let sortedTexts = texts.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        // 單行比對
        for text in sortedTexts {
            let cleanedText = cleanAndFixOCR(text.text)

            let matched = matchAllPatterns(cleanedText, confidence: text.confidence)
            for var candidate in matched {
                if !seenNumbers.contains(candidate.trackingNumber) {
                    // 上下文加成
                    candidate = applyContextBoost(candidate, textY: text.boundingBox.midY, keywordYPositions: keywordYPositions)
                    seenNumbers.insert(candidate.trackingNumber)
                    candidates.append(candidate)
                }
            }
        }

        // 多行合併：嘗試相鄰行合併
        for i in 0..<sortedTexts.count {
            for j in (i + 1)..<min(i + 3, sortedTexts.count) {
                let textA = sortedTexts[i]
                let textB = sortedTexts[j]

                // Y 距離小於 0.05 才考慮合併
                let yDistance = abs(textA.boundingBox.midY - textB.boundingBox.midY)
                guard yDistance < 0.05 else { continue }

                let merged = cleanAndFixOCR(textA.text + textB.text)
                let mergedConfidence = min(textA.confidence, textB.confidence) * 0.9

                let matched = matchAllPatterns(merged, confidence: mergedConfidence)
                for var candidate in matched {
                    if !seenNumbers.contains(candidate.trackingNumber) {
                        candidate = applyContextBoost(candidate, textY: textA.boundingBox.midY, keywordYPositions: keywordYPositions)
                        seenNumbers.insert(candidate.trackingNumber)
                        candidates.append(candidate)
                    }
                }
            }
        }

        // 按信心度排序
        return candidates.sorted { $0.confidence > $1.confidence }
    }

    /// 清理文字 + 修正常見 OCR 錯誤
    private func cleanAndFixOCR(_ rawText: String) -> String {
        var text = rawText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
            .uppercased()

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
        if result.hasPrefix("TW") && result.count >= 14 {
            let prefix = result.prefix(2)
            let middle = String(result.dropFirst(2).dropLast(1))
            let suffix = result.suffix(1)
            let fixedMiddle = fixDigitPart(middle)
            result = prefix + fixedMiddle + suffix
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
