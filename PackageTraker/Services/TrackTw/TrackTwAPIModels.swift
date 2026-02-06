//
//  TrackTwAPIModels.swift
//  PackageTraker
//
//  Track.TW API 回應模型
//

import Foundation

// MARK: - User Profile

/// GET /user/profile
struct TrackTwUserProfile: Codable {
    let email: String
    let name: String
    let pictureUrl: String
    let notifyTypeId: Int
    let telegram: Bool
    let line: Bool
}

// MARK: - Carrier

/// GET /carrier/available
struct TrackTwCarrier: Codable {
    let id: String
    let name: String
    let logo: String?
}

// MARK: - Package Import

/// POST /package/import 回應
/// Key: tracking_number, Value: UUID string
typealias TrackTwImportResponse = [String: String]

// MARK: - Package List (Paginated)

/// GET /package/all/{folder}
struct TrackTwPackageListResponse: Codable {
    let currentPage: Int
    let data: [TrackTwPackageRelation]
    let lastPage: Int
    let perPage: Int
    let total: Int
    let nextPageUrl: String?
    let prevPageUrl: String?
    let from: Int?
    let to: Int?
}

/// 使用者-包裹關聯（列表中的每個項目）
struct TrackTwPackageRelation: Codable {
    let id: String
    let createdAt: String
    let updatedAt: String
    let userId: String
    let packageId: String
    let note: String?
    let notifyState: String
    let state: String
    let package: TrackTwPackageDetail
}

/// 包裹詳情（嵌套在 relation 內）
struct TrackTwPackageDetail: Codable {
    let id: String
    let trackingNumber: String
    let carrierId: String
    let carrier: TrackTwCarrier
    let latestPackageHistory: TrackTwHistoryEntry?
}

// MARK: - Tracking Detail

/// GET /package/tracking/{uuid}
struct TrackTwTrackingResponse: Codable {
    let id: String
    let createdAt: String
    let updatedAt: String
    let carrierId: String
    let trackingNumber: String
    let packageHistory: [TrackTwHistoryEntry]
    let carrier: TrackTwCarrier
}

/// 追蹤歷史記錄
struct TrackTwHistoryEntry: Codable {
    let packageId: String
    let time: Int
    let status: String
    let checkpointStatus: String
    let createdAt: String
}

// MARK: - State Change

/// PATCH /package/state/{uuid}/{action}
struct TrackTwStateResponse: Codable {
    let success: Bool
}

// MARK: - Error Response

/// API 錯誤回應格式
struct TrackTwErrorResponse: Codable {
    let message: String
    let errors: [String: [String]]?
}
