//
//  TrackTwAPIService.swift
//  PackageTraker
//
//  Track.TW API 追蹤服務適配器
//  實作 TrackingServiceProtocol，橋接 TrackTwAPIClient 到現有 app 介面
//

import Foundation

/// Track.TW API 追蹤服務
final class TrackTwAPIService: TrackingServiceProtocol {

    private let apiClient = TrackTwAPIClient.shared

    /// relation ID 快取：trackingNumber -> relationId
    /// 避免每次 refresh 都重新 import
    private var relationIdCache: [String: String] = [:]

    var supportedCarriers: [Carrier] {
        Carrier.allCases.filter { $0.trackTwUUID != nil }
    }

    func track(number: String, carrier: Carrier) async throws -> TrackingResult {
        guard let carrierUUID = carrier.trackTwUUID else {
            throw TrackingError.unsupportedCarrier(carrier)
        }

        // Step 1: 取得 relation ID（先查快取，再嘗試 import）
        let relationId = try await getRelationId(trackingNumber: number, carrierId: carrierUUID)

        // Step 2: 查詢追蹤詳情
        let tracking = try await apiClient.getTracking(relationId: relationId)

        // Step 3: 轉換為 TrackingResult
        return convertToTrackingResult(tracking, carrier: carrier)
    }

    /// 只匯入包裹（不查詢追蹤），回傳 relation ID
    /// 用於新增包裹時快速驗證 + 取得 relation ID
    func importOnly(number: String, carrier: Carrier) async throws -> String {
        guard let carrierUUID = carrier.trackTwUUID else {
            throw TrackingError.unsupportedCarrier(carrier)
        }

        return try await getRelationId(trackingNumber: number, carrierId: carrierUUID)
    }

    // MARK: - Relation ID Management

    /// 取得或建立 relation ID
    private func getRelationId(trackingNumber: String, carrierId: String) async throws -> String {
        // 優先使用快取
        if let cached = relationIdCache[trackingNumber] {
            return cached
        }

        // 呼叫 import（冪等，已匯入的會回傳現有 UUID）
        let importResult = try await apiClient.importPackages(
            carrierId: carrierId,
            trackingNumbers: [trackingNumber]
        )

        guard let relationId = importResult[trackingNumber] else {
            throw TrackingError.trackingNumberNotFound
        }

        // 快取 relation ID
        relationIdCache[trackingNumber] = relationId

        return relationId
    }

    /// 設定已知的 relation ID（從 Package model 載入時用）
    func setRelationId(_ relationId: String, for trackingNumber: String) {
        relationIdCache[trackingNumber] = relationId
    }

    // MARK: - Response Conversion

    private func convertToTrackingResult(
        _ response: TrackTwTrackingResponse,
        carrier: Carrier
    ) -> TrackingResult {
        // 轉換 package_history → [TrackingEventDTO]
        let events: [TrackingEventDTO] = response.packageHistory.map { entry in
            let timestamp = Date(timeIntervalSince1970: TimeInterval(entry.time))
            let status = TrackingStatus.fromTrackTw(
                checkpointStatus: entry.checkpointStatus,
                statusDescription: entry.status
            )
            let location = extractLocation(from: entry.status)

            return TrackingEventDTO(
                timestamp: timestamp,
                status: status,
                description: entry.status,
                location: location
            )
        }

        // 目前狀態：取最新的歷史記錄
        let currentStatus: TrackingStatus
        if let latest = response.packageHistory.first {
            currentStatus = TrackingStatus.fromTrackTw(
                checkpointStatus: latest.checkpointStatus,
                statusDescription: latest.status
            )
        } else {
            currentStatus = .pending
        }

        // 擷取門市名稱
        let storeName = extractLocation(from: response.packageHistory.first?.status)

        var result = TrackingResult(
            trackingNumber: response.trackingNumber,
            carrier: carrier,
            currentStatus: currentStatus,
            events: events,
            rawResponse: nil
        )
        result.storeName = storeName

        return result
    }

    /// 從狀態描述中擷取地點（如 [中和福美 - 智取店]）
    private func extractLocation(from status: String?) -> String? {
        guard let status = status else { return nil }
        let pattern = #"\[([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: status,
                range: NSRange(status.startIndex..., in: status)
              ),
              let range = Range(match.range(at: 1), in: status) else {
            return nil
        }
        return String(status[range])
    }
}
