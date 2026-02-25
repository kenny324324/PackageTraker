//
//  AIVisionService.swift
//  PackageTraker
//
//  AI 截圖辨識服務 — 透過 Cloud Function 代理 Gemini API
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// AI 截圖辨識服務
@MainActor
class AIVisionService {

    // MARK: - Singleton

    static let shared = AIVisionService()

    private init() {}

    // MARK: - Constants

    private let maxImageDimension: CGFloat = 1024
    private let dailyLimit = 20

    // 本地快取 keys
    private let dailyCountKey = "ai.dailyUsage.count"
    private let dailyDateKey = "ai.dailyUsage.date"

    // MARK: - Firebase Functions

    private lazy var functions = Functions.functions(region: "asia-east1")

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
        let callable = functions.httpsCallable("getAIUsage")
        guard let result = try? await callable.call(),
              let data = result.data as? [String: Any] else {
            return (0, dailyLimit)
        }
        let used = data["used"] as? Int ?? 0
        // 更新本地快取
        UserDefaults.standard.set(used, forKey: dailyCountKey)
        UserDefaults.standard.set(taiwanDateString(), forKey: dailyDateKey)
        return (used, data["limit"] as? Int ?? dailyLimit)
    }

    // MARK: - Public Methods

    /// 分析包裹截圖（透過 Cloud Function 代理）
    func analyzePackageImage(_ image: UIImage) async throws -> AIVisionResult {
        // 壓縮圖片
        guard let imageData = compressImage(image) else {
            throw AIVisionError.invalidImage
        }

        let base64Image = imageData.base64EncodedString()

        // 呼叫 Cloud Function
        let callable = functions.httpsCallable("analyzePackageImage")
        callable.timeoutInterval = 60

        do {
            let result = try await callable.call([
                "imageBase64": base64Image,
                "mimeType": "image/jpeg",
            ])

            // 解析回傳結果
            guard let data = result.data as? [String: Any] else {
                throw AIVisionError.parseError
            }

            let aiResult = try parseCloudFunctionResult(data)

            // 成功後遞增本地快取
            incrementLocalUsageCount()

            return aiResult

        } catch {
            // 將 Cloud Function 錯誤轉換為 AIVisionError
            throw mapCloudFunctionError(error)
        }
    }

    // MARK: - Private Methods

    /// 壓縮圖片
    private func compressImage(_ image: UIImage) -> Data? {
        let resized = resizeImage(image, maxDimension: maxImageDimension)
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

    /// 解析 Cloud Function 回傳的 JSON
    private func parseCloudFunctionResult(_ data: [String: Any]) throws -> AIVisionResult {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        return try decoder.decode(AIVisionResult.self, from: jsonData)
    }

    /// 將 Cloud Function 錯誤對應到 AIVisionError
    private func mapCloudFunctionError(_ error: Error) -> AIVisionError {
        let nsError = error as NSError

        // Firebase Functions 錯誤
        if nsError.domain == FunctionsErrorDomain {
            switch FunctionsErrorCode(rawValue: nsError.code) {
            case .resourceExhausted:
                let message = nsError.localizedDescription.lowercased()
                if message.contains("daily") {
                    return .dailyLimitReached
                }
                return .apiError(statusCode: 429, rawMessage: nsError.localizedDescription)
            case .permissionDenied:
                return .proRequired
            case .unauthenticated:
                return .subscriptionRequired
            case .invalidArgument:
                return .invalidImage
            case .internal:
                return .apiError(statusCode: nil, rawMessage: nsError.localizedDescription)
            default:
                return .apiError(statusCode: nil, rawMessage: nsError.localizedDescription)
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

    /// 遞增本地用量快取
    private func incrementLocalUsageCount() {
        let today = taiwanDateString()
        let currentDate = UserDefaults.standard.string(forKey: dailyDateKey) ?? ""

        if currentDate != today {
            // 新的一天，重置
            UserDefaults.standard.set(1, forKey: dailyCountKey)
            UserDefaults.standard.set(today, forKey: dailyDateKey)
        } else {
            let current = UserDefaults.standard.integer(forKey: dailyCountKey)
            UserDefaults.standard.set(current + 1, forKey: dailyCountKey)
        }
    }

    /// 取得台灣時區日期字串 (yyyy-MM-dd)
    private func taiwanDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        return formatter.string(from: Date())
    }
}
