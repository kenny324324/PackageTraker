//
//  AIVisionService.swift
//  PackageTraker
//
//  Google Gemini 2.0 Flash API integration for package screenshot analysis
//

import Foundation
import UIKit

/// AI 截圖辨識服務
@MainActor
class AIVisionService {

    // MARK: - Singleton

    static let shared = AIVisionService()

    private init() {}

    // MARK: - Constants

    private let modelName = "gemini-2.0-flash"
    private let maxImageDimension: CGFloat = 1024

    // MARK: - System Prompt

    private let systemPrompt = """
    You are a package tracking information extractor for Taiwan logistics.
    Analyze the screenshot and extract the following fields. Return ONLY valid JSON, no markdown.

    Required JSON format:
    {
      "trackingNumber": "the tracking/order number",
      "carrier": "carrier/logistics company name in Chinese or English",
      "pickupLocation": "pickup store name or address",
      "pickupCode": "pickup verification code if visible",
      "packageName": "product/package name if visible",
      "estimatedDelivery": "estimated delivery date if visible",
      "confidence": 0.95
    }

    Rules:
    - For fields not found in the image, use null
    - confidence is 0.0 to 1.0, how confident you are about trackingNumber
    - Common Taiwan carriers: 蝦皮店到店, 7-ELEVEN交貨便, 全家店到店, OK超商, 萊爾富, 黑貓宅急便, 新竹物流, 宅配通, 中華郵政, 順豐速運
    - Tracking number formats: TW + digits + H/F (Shopee), SPX... (Shopee), T + digits (FamilyMart), HL + digits (HiLife), SF + digits (SF Express), etc.
    - Return ONLY the JSON object, nothing else
    """

    // MARK: - Public Methods

    /// 分析包裹截圖
    func analyzePackageImage(_ image: UIImage) async throws -> AIVisionResult {
        // 訂閱檢查
        guard SubscriptionManager.shared.hasAIAccess else {
            throw AIVisionError.subscriptionRequired
        }

        // API Key 檢查
        let apiKey = Secrets.geminiAPIKey
        guard apiKey != "YOUR_GEMINI_API_KEY_HERE" && !apiKey.isEmpty else {
            throw AIVisionError.apiKeyMissing
        }

        // 壓縮圖片
        guard let imageData = compressImage(image) else {
            throw AIVisionError.invalidImage
        }

        // 呼叫 Gemini API
        let result = try await callGeminiAPI(imageData: imageData, apiKey: apiKey)
        return result
    }

    // MARK: - Private Methods

    /// 壓縮圖片
    private func compressImage(_ image: UIImage) -> Data? {
        // 縮小圖片
        let resized = resizeImage(image, maxDimension: maxImageDimension)
        // JPEG 壓縮
        return resized.jpegData(compressionQuality: 0.8)
    }

    /// 縮小圖片
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }

        let ratio = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 呼叫 Gemini REST API
    private func callGeminiAPI(imageData: Data, apiKey: String) async throws -> AIVisionResult {
        let base64Image = imageData.base64EncodedString()

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)")!

        let requestBody: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "parts": [
                        ["text": "Please analyze this package screenshot and extract tracking information."],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 512,
                "responseMimeType": "application/json"
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIVisionError.apiError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIVisionError.apiError("HTTP \(httpResponse.statusCode): \(body.prefix(200))")
        }

        // 解析 Gemini 回應
        return try parseGeminiResponse(data)
    }

    /// 解析 Gemini API 回應
    private func parseGeminiResponse(_ data: Data) throws -> AIVisionResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIVisionError.parseError
        }

        // 清理 JSON 文字（移除可能的 markdown code block）
        let cleanedText = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw AIVisionError.parseError
        }

        let decoder = JSONDecoder()
        return try decoder.decode(AIVisionResult.self, from: jsonData)
    }
}
