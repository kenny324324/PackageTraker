//
//  AIVisionService.swift
//  PackageTraker
//
//  Google Gemini 2.0 Flash API integration for package screenshot analysis
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore

/// AI 截圖辨識服務
@MainActor
class AIVisionService {

    // MARK: - Singleton

    static let shared = AIVisionService()

    private init() {}

    // MARK: - Constants

    private let modelName = "gemini-2.5-flash"
    private let maxImageDimension: CGFloat = 1024
    private let quotaAlertCooldown: TimeInterval = 30 * 60
    private let quotaAlertLastReportedAtKey = "ai.quotaAlert.lastReportedAt"

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
      "purchasePlatform": "e-commerce platform name (Shopee/蝦皮/淘寶/PChome/Momo/Yahoo etc.)",
      "amount": "order amount as number string (e.g. 199, 1280.50)",
      "confidence": 0.95
    }

    Rules:
    - For fields not found in the image, use null
    - confidence is 0.0 to 1.0, how confident you are about trackingNumber
    - Common Taiwan carriers: 蝦皮店到店, 7-ELEVEN交貨便, 全家店到店, OK超商, 萊爾富, 黑貓宅急便, 新竹物流, 宅配通, 中華郵政, 順豐速運
    - Tracking number formats: TW + digits + H/F (Shopee), SPX... (Shopee), T + digits (FamilyMart), HL + digits (HiLife), SF + digits (SF Express), etc.
    - For purchasePlatform, identify the e-commerce platform from logos, text, or app UI
    - For amount, extract the total price/amount, return digits only (no currency symbol)
    - Return ONLY the JSON object, nothing else
    """

    // MARK: - Public Methods

    /// 分析包裹截圖
    func analyzePackageImage(_ image: UIImage) async throws -> AIVisionResult {
        // 訂閱檢查 (測試時暫時關閉)
        // guard SubscriptionManager.shared.hasAIAccess else {
        //     throw AIVisionError.subscriptionRequired
        // }

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
                "maxOutputTokens": 2048,
                "responseMimeType": "application/json",
                "thinkingConfig": [
                    "thinkingBudget": 0  // 關閉思考模式，這是簡單的 JSON 提取任務
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        print("🚀 [AIVisionService] 呼叫 Gemini API: \(modelName)")
        print("📤 [AIVisionService] Request URL: \(maskedURLString(url))")
        print("📦 [AIVisionService] Request body size: \(jsonData.count) bytes (\(String(format: "%.1f", Double(jsonData.count) / 1024.0)) KB)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        // 建立乾淨的 URLSession，避免 Firebase SDK URL protocol 干擾
        let cleanConfig = URLSessionConfiguration.ephemeral
        cleanConfig.protocolClasses = []  // 跳過所有自定義 URL protocol
        cleanConfig.timeoutIntervalForRequest = 30
        cleanConfig.timeoutIntervalForResource = 60
        let cleanSession = URLSession(configuration: cleanConfig)

        print("🌐 [AIVisionService] 開始 POST 請求 (cleanSession, timeout=30s)...")
        let (data, response) = try await withHardTimeout(seconds: 25) {
            try await cleanSession.data(for: request)
        }
        print("✅ [AIVisionService] POST 請求完成")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [AIVisionService] Invalid response type")
            throw AIVisionError.apiError(statusCode: nil, rawMessage: "Invalid response")
        }

        print("📥 [AIVisionService] HTTP Status: \(httpResponse.statusCode)")

        let responseBody = String(data: data, encoding: .utf8) ?? ""
        print("📥 [AIVisionService] Response Body:\n\(responseBody)")

        guard httpResponse.statusCode == 200 else {
            print("❌ [AIVisionService] API Error: \(responseBody.prefix(500))")
            let rawBody = String(responseBody.prefix(1000))
            let apiError = AIVisionError.apiError(
                statusCode: httpResponse.statusCode,
                rawMessage: rawBody
            )

            if apiError.isQuotaExceeded {
                reportQuotaExceededIfNeeded(
                    statusCode: httpResponse.statusCode,
                    responseBody: rawBody
                )
            }

            throw apiError
        }

        // 解析 Gemini 回應
        return try parseGeminiResponse(data)
    }

    /// 解析 Gemini API 回應
    private func parseGeminiResponse(_ data: Data) throws -> AIVisionResult {
        print("🔍 [AIVisionService] 開始解析 Gemini 回應")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [AIVisionService] 無法解析為 JSON 物件")
            throw AIVisionError.parseError
        }

        print("📋 [AIVisionService] JSON keys: \(json.keys)")

        guard let candidates = json["candidates"] as? [[String: Any]] else {
            print("❌ [AIVisionService] 找不到 candidates 欄位")
            throw AIVisionError.parseError
        }

        print("📋 [AIVisionService] Candidates count: \(candidates.count)")

        guard let firstCandidate = candidates.first else {
            print("❌ [AIVisionService] Candidates 陣列為空")
            throw AIVisionError.parseError
        }

        print("📋 [AIVisionService] First candidate keys: \(firstCandidate.keys)")

        guard let content = firstCandidate["content"] as? [String: Any] else {
            print("❌ [AIVisionService] 找不到 content 欄位")
            throw AIVisionError.parseError
        }

        print("📋 [AIVisionService] Content keys: \(content.keys)")

        guard let parts = content["parts"] as? [[String: Any]] else {
            print("❌ [AIVisionService] 找不到 parts 欄位")
            throw AIVisionError.parseError
        }

        print("📋 [AIVisionService] Parts count: \(parts.count)")

        guard let firstPart = parts.first else {
            print("❌ [AIVisionService] Parts 陣列為空")
            throw AIVisionError.parseError
        }

        print("📋 [AIVisionService] First part keys: \(firstPart.keys)")

        guard let text = firstPart["text"] as? String else {
            print("❌ [AIVisionService] 找不到 text 欄位")
            throw AIVisionError.parseError
        }

        print("📝 [AIVisionService] 原始 AI 回應文字:\n\(text)")

        // 清理 JSON 文字（移除可能的 markdown code block）
        let cleanedText = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("🧹 [AIVisionService] 清理後的文字:\n\(cleanedText)")

        guard let jsonData = cleanedText.data(using: .utf8) else {
            print("❌ [AIVisionService] 無法轉換為 UTF8 data")
            throw AIVisionError.parseError
        }

        let decoder = JSONDecoder()
        do {
            let result = try decoder.decode(AIVisionResult.self, from: jsonData)
            print("✅ [AIVisionService] 成功解析 AI 結果: \(result)")
            return result
        } catch {
            print("❌ [AIVisionService] JSON 解碼失敗: \(error)")
            print("❌ [AIVisionService] 嘗試解碼的文字: \(cleanedText)")
            throw AIVisionError.parseError
        }
    }

    /// 當 AI 配額不足時，背景上報到 Firestore 供後端通知（含 30 分鐘節流）
    private func reportQuotaExceededIfNeeded(statusCode: Int, responseBody: String) {
        let now = Date().timeIntervalSince1970
        let lastSent = UserDefaults.standard.double(forKey: quotaAlertLastReportedAtKey)
        guard now - lastSent >= quotaAlertCooldown else { return }

        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ [AIVisionService] Skip quota alert reporting: user not authenticated")
            return
        }

        UserDefaults.standard.set(now, forKey: quotaAlertLastReportedAtKey)

        let payload: [String: Any] = [
            "type": "aiQuotaExceeded",
            "statusCode": statusCode,
            "source": "ios",
            "model": modelName,
            "userId": userId,
            "locale": Locale.preferredLanguages.first ?? "unknown",
            "appVersion": AppConfiguration.appVersion,
            "buildNumber": AppConfiguration.buildNumber,
            "message": String(responseBody.prefix(500)),
            "createdAt": FieldValue.serverTimestamp()
        ]

        Task {
            do {
                try await Firestore.firestore()
                    .collection("users")
                    .document(userId)
                    .collection("systemAlerts")
                    .document()
                    .setData(payload)
                print("📣 [AIVisionService] Quota alert reported to Firestore")
            } catch {
                print("⚠️ [AIVisionService] Failed to report quota alert: \(error.localizedDescription)")
            }
        }
    }

    /// 硬超時保護：避免 TCP black-hole 導致 URLSession timeout 無法觸發
    private func withHardTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                print("⏱️ [AIVisionService] Hard timeout after \(seconds)s")
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else {
                throw URLError(.unknown)
            }
            group.cancelAll()
            return result
        }
    }

    private func maskedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.queryItems = components.queryItems?.map { item in
            if item.name.lowercased() == "key" {
                return URLQueryItem(name: item.name, value: "***")
            }
            return item
        }

        return components.string ?? url.absoluteString
    }

}
