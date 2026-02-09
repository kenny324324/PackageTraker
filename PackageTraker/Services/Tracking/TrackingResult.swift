import Foundation

/// 追蹤結果
struct TrackingResult {
    let trackingNumber: String
    let carrier: Carrier
    let currentStatus: TrackingStatus
    let events: [TrackingEventDTO]
    let rawResponse: String?  // 保留原始 HTML/JSON 供 debug
    var relationId: String?   // Track.TW relation ID（用於快取與重用）
    
    // 額外資訊（7-11、全家等）
    var storeName: String?       // 取件門市名稱
    var serviceType: String?     // 服務類型（如：取貨付款）
    var pickupDeadline: String?  // 取件期限
}

/// 追蹤事件 DTO（Data Transfer Object）
struct TrackingEventDTO {
    let timestamp: Date
    let status: TrackingStatus
    let description: String
    let location: String?
}
