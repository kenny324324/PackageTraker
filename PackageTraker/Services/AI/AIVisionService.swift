//
//  AIVisionService.swift
//  PackageTraker
//
//  AI 截圖辨識服務 — 透過 Cloud Function 代理 Gemini API
//

import Foundation
import UIKit
import FirebaseAuth

/// AI 截圖辨識服務
@MainActor
class AIVisionService {

    // MARK: - Singleton

    static let shared = AIVisionService()

    private init() {}

    // MARK: - Constants

    private let maxImageDimension: CGFloat = 768
    private let dailyLimit = 20

    // 本地快取 keys
    private let dailyCountKey = "ai.dailyUsage.count"
    private let dailyDateKey = "ai.dailyUsage.date"

    // MARK: - Cloud Function 直連（繞過 Firebase Functions SDK 的 async let 崩潰）

    private let cloudFunctionBaseURL = "https://asia-east1-packagetraker-e80b0.cloudfunctions.net"

    // MARK: - Usage Tracking

    /// 今日剩餘 AI 掃描次數（本地快取，非同步）
    var remainingScans: Int {
        let today = taiwanDateString()
        if UserDefaults.standard.string(forKey: dailyDateKey) != today {
            return dailyLimit
        }
        return max(0, dailyLimit - UserDefaults.standard.integer(forKey: dailyCountKey))
    }

    /// 從伺服器取得今日 AI 用量並更新本地快取
    func fetchUsageFromServer() async -> (used: Int, limit: Int) {
        guard let data = try? await callCloudFunction(name: "getAIUsage", data: nil, timeout: 15) else {
            return (0, dailyLimit)
        }
        let used = data["used"] as? Int ?? 0
        // 更新本地快取
        UserDefaults.standard.set(used, forKey: dailyCountKey)
        UserDefaults.standard.set(taiwanDateString(), forKey: dailyDateKey)
        return (used, data["limit"] as? Int ?? dailyLimit)
    }

    // MARK: - Public Methods

    /// AI + Track.TW 合併結果
    struct AnalyzeResult {
        let aiResult: AIVisionResult
        let trackingData: ServerTrackingData?
    }

    /// Server 端 Track.TW 回傳的追蹤資料
    struct ServerTrackingData {
        let relationId: String
        let events: [ServerTrackingEvent]
    }

    struct ServerTrackingEvent {
        let time: Int          // Unix timestamp
        let status: String     // 中文描述
        let checkpointStatus: String  // transit/delivered/pending/exception
    }

    /// 分析包裹截圖（透過 Cloud Function 代理，含 Track.TW import+track）
    func analyzePackageImage(_ image: UIImage, carrier: Carrier? = nil) async throws -> AnalyzeResult {
        // 壓縮圖片
        guard let imageData = compressImage(image) else {
            throw AIVisionError.invalidImage
        }

        let base64Image = imageData.base64EncodedString()

        do {
            var payload: [String: Any] = [
                "imageBase64": base64Image,
                "mimeType": "image/jpeg",
            ]
            // 傳 carrierUUID 讓 server 直接做 Track.TW
            if let uuid = carrier?.trackTwUUID {
                payload["carrierUUID"] = uuid
            }
            #if DEBUG
            payload["debug"] = true
            #endif

            let data = try await callCloudFunction(name: "analyzePackageImage", data: payload, timeout: 60)

            let aiResult = try parseCloudFunctionResult(data)

            // 解析 server 端 Track.TW 結果
            let trackingData = parseServerTrackingData(data)

            // 用 response 裡帶回的用量更新本地快取（省一次網路請求）
            if let usage = data["_usage"] as? [String: Any],
               let used = usage["used"] as? Int {
                UserDefaults.standard.set(used, forKey: dailyCountKey)
                UserDefaults.standard.set(taiwanDateString(), forKey: dailyDateKey)
            }

            // 免費用戶：遞增試用次數
            if !SubscriptionManager.shared.hasAIAccess {
                let current = UserDefaults.standard.integer(forKey: "aiTrialUsedCount")
                UserDefaults.standard.set(current + 1, forKey: "aiTrialUsedCount")
            }

            return AnalyzeResult(aiResult: aiResult, trackingData: trackingData)

        } catch {
            // 將 Cloud Function 錯誤轉換為 AIVisionError
            throw mapCloudFunctionError(error)
        }
    }

    /// 解析 server 回傳的 _tracking 資料
    private func parseServerTrackingData(_ data: [String: Any]) -> ServerTrackingData? {
        guard let tracking = data["_tracking"] as? [String: Any],
              let relationId = tracking["relationId"] as? String else {
            return nil
        }

        var events: [ServerTrackingEvent] = []
        if let rawEvents = tracking["events"] as? [[String: Any]] {
            events = rawEvents.compactMap { e in
                guard let time = e["time"] as? Int,
                      let status = e["status"] as? String,
                      let checkpointStatus = e["checkpointStatus"] as? String else {
                    return nil
                }
                return ServerTrackingEvent(time: time, status: status, checkpointStatus: checkpointStatus)
            }
        }

        return ServerTrackingData(relationId: relationId, events: events)
    }

    // MARK: - Direct Cloud Function Call（繞過 HTTPSCallable）

    /// 直接用 URLSession 呼叫 Cloud Function，避免 Firebase Functions SDK
    /// 的 async let 在 iOS 26 Swift runtime 觸發 task deallocation crash
    private func callCloudFunction(
        name: String,
        data payload: [String: Any]?,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        // 取得 Firebase Auth ID token
        guard let user = Auth.auth().currentUser else {
            throw CloudFunctionError.unauthenticated
        }
        let idToken = try await user.getIDToken()

        // 建構 request
        let url = URL(string: "\(cloudFunctionBaseURL)/\(name)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        // Firebase callable 協定：body = {"data": <payload>}
        let body: [String: Any] = ["data": payload ?? NSNull()]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 發送請求
        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudFunctionError.invalidResponse
        }

        // 解析 JSON response
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            // 嘗試解析 error response
            if let errorJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let error = errorJson["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Unknown error"
                let status = error["status"] as? String ?? ""
                throw CloudFunctionError.functionError(
                    code: httpResponse.statusCode,
                    message: message,
                    status: status
                )
            }
            throw CloudFunctionError.invalidResponse
        }

        // HTTP error
        guard (200...299).contains(httpResponse.statusCode) else {
            let error = json["error"] as? [String: Any]
            let message = error?["message"] as? String ?? json["error"] as? String ?? "HTTP \(httpResponse.statusCode)"
            let status = error?["status"] as? String ?? ""
            throw CloudFunctionError.functionError(
                code: httpResponse.statusCode,
                message: message,
                status: status
            )
        }

        // Firebase callable 協定：response = {"result": <data>}
        guard let result = json["result"] as? [String: Any] else {
            throw CloudFunctionError.invalidResponse
        }

        return result
    }

    // MARK: - Private Methods

    /// 壓縮圖片
    private func compressImage(_ image: UIImage) -> Data? {
        let resized = resizeImage(image, maxDimension: maxImageDimension)
        return resized.jpegData(compressionQuality: 0.6)
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

    /// 解析 Cloud Function 回傳的 JSON
    private func parseCloudFunctionResult(_ data: [String: Any]) throws -> AIVisionResult {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        return try decoder.decode(AIVisionResult.self, from: jsonData)
    }

    /// 將 Cloud Function 錯誤對應到 AIVisionError
    private func mapCloudFunctionError(_ error: Error) -> AIVisionError {
        // 自訂 CloudFunctionError
        if let cfError = error as? CloudFunctionError {
            switch cfError {
            case .unauthenticated:
                return .subscriptionRequired
            case .functionError(let code, let message, let status):
                let msg = message.lowercased()
                // 429 或 RESOURCE_EXHAUSTED → quota
                if code == 429 || status == "RESOURCE_EXHAUSTED" {
                    if msg.contains("free trial") {
                        return .freeTrialExhausted
                    }
                    if msg.contains("daily") {
                        return .dailyLimitReached
                    }
                    return .apiError(statusCode: 429, rawMessage: message)
                }
                // 403 或 PERMISSION_DENIED
                if code == 403 || status == "PERMISSION_DENIED" {
                    return .proRequired
                }
                // 401 或 UNAUTHENTICATED
                if code == 401 || status == "UNAUTHENTICATED" {
                    return .subscriptionRequired
                }
                // 400 或 INVALID_ARGUMENT
                if code == 400 || status == "INVALID_ARGUMENT" {
                    return .invalidImage
                }
                return .apiError(statusCode: code, rawMessage: message)
            case .invalidResponse:
                return .parseError
            }
        }

        // 網路錯誤
        if let urlError = error as? URLError {
            return .apiError(statusCode: nil, rawMessage: urlError.localizedDescription)
        }

        // 解析錯誤
        if error is DecodingError {
            return .parseError
        }

        return .apiError(statusCode: nil, rawMessage: error.localizedDescription)
    }

    /// 取得台灣時區日期字串 (yyyy-MM-dd)
    private func taiwanDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        return formatter.string(from: Date())
    }
}

// MARK: - Cloud Function Error

private enum CloudFunctionError: Error {
    case unauthenticated
    case functionError(code: Int, message: String, status: String)
    case invalidResponse
}
