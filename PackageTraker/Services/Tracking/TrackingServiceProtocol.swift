import Foundation

/// 追蹤服務協定
protocol TrackingServiceProtocol {
    /// 支援的物流商列表
    var supportedCarriers: [Carrier] { get }

    /// 追蹤包裹
    /// - Parameters:
    ///   - number: 物流單號
    ///   - carrier: 物流商
    /// - Returns: 追蹤結果
    func track(number: String, carrier: Carrier) async throws -> TrackingResult
}
