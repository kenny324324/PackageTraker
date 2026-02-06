//
//  TrackTwAPIClient.swift
//  PackageTraker
//
//  Track.TW API 低階 HTTP 客戶端
//

import Foundation

/// Track.TW API HTTP 客戶端
final class TrackTwAPIClient {

    // MARK: - Singleton

    static let shared = TrackTwAPIClient()

    // MARK: - Constants

    private let baseURL = "https://track.tw/api/v1"
    private let tokenStorage = TrackTwTokenStorage.shared
    private let session = URLSession.shared

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private init() {}

    // MARK: - Public API

    /// 取得使用者資訊
    func getUserProfile() async throws -> TrackTwUserProfile {
        let request = try makeRequest(endpoint: "/user/profile")
        return try await execute(request)
    }

    /// 取得可用物流廠商列表
    func getAvailableCarriers() async throws -> [TrackTwCarrier] {
        let request = try makeRequest(endpoint: "/carrier/available")
        return try await execute(request)
    }

    /// 匯入包裹
    func importPackages(
        carrierId: String,
        trackingNumbers: [String],
        notifyState: String = "inactive"
    ) async throws -> TrackTwImportResponse {
        let body: [String: Any] = [
            "carrier_id": carrierId,
            "tracking_number": trackingNumbers,
            "notify_state": notifyState
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let request = try makeRequest(endpoint: "/package/import", method: "POST", body: bodyData)
        return try await execute(request)
    }

    /// 取得包裹列表
    func getPackages(folder: String, page: Int = 1, size: Int = 50) async throws -> TrackTwPackageListResponse {
        let request = try makeRequest(endpoint: "/package/all/\(folder)?page=\(page)&size=\(size)")
        return try await execute(request)
    }

    /// 查詢包裹追蹤詳情
    func getTracking(relationId: String) async throws -> TrackTwTrackingResponse {
        let request = try makeRequest(endpoint: "/package/tracking/\(relationId)")
        return try await execute(request)
    }

    /// 變更包裹狀態（archive / delete）
    func updatePackageState(relationId: String, action: String) async throws -> TrackTwStateResponse {
        let request = try makeRequest(
            endpoint: "/package/state/\(relationId)/\(action)",
            method: "PATCH"
        )
        return try await execute(request)
    }

    // MARK: - Internal

    private func makeRequest(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil
    ) throws -> URLRequest {
        guard let token = tokenStorage.getToken() else {
            throw TrackingError.unauthorized
        }

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw TrackingError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "?"
        print("[API] \(method) \(url)")

        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            print("[API] Body: \(bodyString)")
        }

        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("[API] 網路錯誤: \(error.localizedDescription)")
            throw TrackingError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[API] 無效回應（非 HTTP）")
            throw TrackingError.invalidResponse
        }

        let responseString = String(data: data, encoding: .utf8) ?? "(無法解碼)"
        print("[API] HTTP \(httpResponse.statusCode) 回應: \(responseString)")

        switch httpResponse.statusCode {
        case 200...299:
            do {
                let decoded = try decoder.decode(T.self, from: data)
                print("[API] 解碼成功 (\(T.self))")
                return decoded
            } catch {
                print("[API] 解碼失敗: \(error)")
                throw TrackingError.parsingError(message: error.localizedDescription)
            }

        case 302, 401:
            print("[API] 認證失敗 (HTTP \(httpResponse.statusCode))")
            throw TrackingError.unauthorized

        case 404:
            print("[API] 找不到單號 (404)")
            throw TrackingError.trackingNumberNotFound

        case 422:
            if let errorResponse = try? decoder.decode(TrackTwErrorResponse.self, from: data) {
                print("[API] 伺服器錯誤 (422): \(errorResponse.message)")
                throw TrackingError.serverError(message: errorResponse.message)
            }
            print("[API] 無效單號 (422)")
            throw TrackingError.invalidTrackingNumber

        case 429:
            print("[API] 請求過於頻繁 (429)")
            throw TrackingError.rateLimited

        default:
            if let errorResponse = try? decoder.decode(TrackTwErrorResponse.self, from: data) {
                print("[API] 伺服器錯誤 (\(httpResponse.statusCode)): \(errorResponse.message)")
                throw TrackingError.serverError(message: errorResponse.message)
            }
            print("[API] 未知錯誤 (HTTP \(httpResponse.statusCode))")
            throw TrackingError.serverError(message: "HTTP \(httpResponse.statusCode)")
        }
    }
}
