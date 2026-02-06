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

/// 物流單號 OCR 辨識服務
class TrackingNumberOCRService {
    
    // MARK: - Singleton
    
    static let shared = TrackingNumberOCRService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 從圖片辨識物流單號
    /// - Parameter image: 要辨識的圖片
    /// - Returns: OCR 辨識結果
    func recognizeTrackingNumbers(from image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }
        
        // 執行 OCR
        let recognizedTexts = try await performOCR(on: cgImage)
        
        // 從辨識結果中尋找物流單號
        let candidates = findTrackingNumberCandidates(from: recognizedTexts)
        
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
    
    /// 從辨識結果中尋找物流單號候選
    private func findTrackingNumberCandidates(from texts: [RecognizedText]) -> [TrackingNumberCandidate] {
        var candidates: [TrackingNumberCandidate] = []
        var seenNumbers = Set<String>()
        
        for text in texts {
            // 清理文字（移除空白、特殊字元）
            var cleanedText = text.text
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ".", with: "")
                .uppercased()
            
            // 修正常見 OCR 錯誤
            cleanedText = fixCommonOCRErrors(cleanedText)
            
            // 嘗試各種物流商的單號格式
            let matchedCandidates = matchTrackingNumberPatterns(cleanedText, confidence: text.confidence)
            
            for candidate in matchedCandidates {
                if !seenNumbers.contains(candidate.trackingNumber) {
                    seenNumbers.insert(candidate.trackingNumber)
                    candidates.append(candidate)
                }
            }
        }
        
        // 按信心度排序
        return candidates.sorted { $0.confidence > $1.confidence }
    }
    
    /// 修正常見 OCR 辨識錯誤
    private func fixCommonOCRErrors(_ text: String) -> String {
        var result = text
        
        // 蝦皮單號格式：TW + 12位數字 + H (共15字元)
        // 常見錯誤：H 後面多辨識出 O 或 0
        if result.hasPrefix("TW") && result.count == 16 {
            // 如果是 TW...H0 或 TW...HO，移除最後一個字元
            if result.hasSuffix("H0") || result.hasSuffix("HO") {
                result = String(result.dropLast())
            }
        }
        
        // 蝦皮單號：將中間的 O 替換為 0（數字位置）
        if result.hasPrefix("TW") && result.count >= 14 {
            // TW 後面應該都是數字，直到最後的 H 或 F
            let prefix = result.prefix(2) // TW
            let middle = String(result.dropFirst(2).dropLast(1)) // 中間數字部分
            let suffix = result.suffix(1) // 最後字母
            
            // 將中間部分的 O 替換為 0
            let fixedMiddle = middle.replacingOccurrences(of: "O", with: "0")
            result = prefix + fixedMiddle + suffix
        }
        
        return result
    }
    
    /// 比對物流單號格式
    private func matchTrackingNumberPatterns(_ text: String, confidence: Float) -> [TrackingNumberCandidate] {
        var candidates: [TrackingNumberCandidate] = []
        
        // 7-ELEVEN 交貨便：純數字，通常 10-15 位
        // 格式範例：1234567890123
        if let match = matchPattern(text, pattern: "^[0-9]{10,15}$") {
            candidates.append(TrackingNumberCandidate(
                trackingNumber: match,
                suggestedCarrier: .sevenEleven,
                confidence: confidence * 0.8 // 純數字可能是多種物流商
            ))
        }
        
        // 全家店到店：T 開頭 + 數字，約 10-12 位
        // 格式範例：T1234567890
        if let match = matchPattern(text, pattern: "^T[0-9]{9,12}$") {
            candidates.append(TrackingNumberCandidate(
                trackingNumber: match,
                suggestedCarrier: .familyMart,
                confidence: confidence * 0.95 // T 開頭很有特徵
            ))
        }
        
        // OK 超商：純數字或特定格式
        // 格式通常與 7-11 類似
        if let match = matchPattern(text, pattern: "^[0-9]{12,14}$") {
            // 如果還沒加過類似的候選
            if !candidates.contains(where: { $0.trackingNumber == match }) {
                candidates.append(TrackingNumberCandidate(
                    trackingNumber: match,
                    suggestedCarrier: .okMart,
                    confidence: confidence * 0.7
                ))
            }
        }
        
        // 蝦皮店到店：TW + 12位數字 + H/F = 15字元
        // 格式範例：TW259426993523H
        if let match = matchPattern(text, pattern: "^TW[0-9]{12}[HF]$") {
            candidates.append(TrackingNumberCandidate(
                trackingNumber: match,
                suggestedCarrier: .shopee,
                confidence: confidence * 0.98 // TW...H 格式非常有特徵
            ))
        }
        
        // 蝦皮其他格式：SPX 開頭
        if let match = matchPattern(text, pattern: "^(SPX|SPXTW)[A-Z0-9]{8,15}$") {
            if !candidates.contains(where: { $0.trackingNumber == match }) {
                candidates.append(TrackingNumberCandidate(
                    trackingNumber: match,
                    suggestedCarrier: .shopee,
                    confidence: confidence * 0.95
                ))
            }
        }
        
        // 通用蝦皮格式（TW + 數字，無結尾字母）
        if let match = matchPattern(text, pattern: "^TW[0-9]{10,14}$") {
            if !candidates.contains(where: { $0.trackingNumber == match }) {
                candidates.append(TrackingNumberCandidate(
                    trackingNumber: match,
                    suggestedCarrier: .shopee,
                    confidence: confidence * 0.8
                ))
            }
        }
        
        // 萊爾富：通常也是數字為主
        // 這裡用較低的信心度，因為格式與其他物流商重疊
        
        // 黑貓宅急便：通常 12 位數字
        if let match = matchPattern(text, pattern: "^[0-9]{12}$") {
            if !candidates.contains(where: { $0.trackingNumber == match && $0.suggestedCarrier == .sevenEleven }) {
                candidates.append(TrackingNumberCandidate(
                    trackingNumber: match,
                    suggestedCarrier: .tcat,
                    confidence: confidence * 0.6
                ))
            }
        }
        
        return candidates
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
            return "圖片格式不支援，請換一張圖片試試"
        case .recognitionFailed(let message):
            return "文字辨識異常：\(message)"
        }
    }
}
