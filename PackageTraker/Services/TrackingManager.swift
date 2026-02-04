import Foundation
import SwiftUI
import Combine

/// 追蹤管理器
/// 負責協調所有追蹤服務
@MainActor
final class TrackingManager: ObservableObject {

    /// 追蹤服務列表
    private var services: [TrackingServiceProtocol] = []

    /// 是否正在載入
    @Published var isLoading = false

    /// 最後一次錯誤
    @Published var lastError: TrackingError?

    private let trackTwScraper = TrackTwScraper()
    private let parcelTwService = ParcelTwService()

    init() {
        // 服務列表（用於 isAutoTrackingSupported 等檢查）
        self.services = [
            trackTwScraper,
            parcelTwService
        ]
    }

    /// 追蹤單一包裹
    /// - Parameters:
    ///   - number: 物流單號
    ///   - carrier: 物流商
    /// - Returns: 追蹤結果
    func track(number: String, carrier: Carrier) async throws -> TrackingResult {
        isLoading = true
        lastError = nil

        defer { isLoading = false }

        // 使用 ParcelTwService（API 穩定）
        // 注意：track.tw 需要驗證碼，TrackTwScraper 無法直接解析
        if parcelTwService.supportedCarriers.contains(carrier) {
            do {
                return try await parcelTwService.track(number: number, carrier: carrier)
            } catch let error as TrackingError {
                lastError = error
                throw error
            } catch {
                let trackingError = TrackingError.networkError(underlying: error)
                lastError = trackingError
                throw trackingError
            }
        }

        // 其他物流商使用 TrackTwScraper（萊爾富等）
        if trackTwScraper.supportedCarriers.contains(carrier) {
            do {
                return try await trackTwScraper.track(number: number, carrier: carrier)
            } catch let error as TrackingError {
                lastError = error
                throw error
            } catch {
                let trackingError = TrackingError.networkError(underlying: error)
                lastError = trackingError
                throw trackingError
            }
        }

        // 如果沒有對應的服務，回傳「待處理」狀態
        return TrackingResult(
            trackingNumber: number,
            carrier: carrier,
            currentStatus: .pending,
            events: [],
            rawResponse: nil
        )
    }

    /// 批次更新所有包裹
    /// - Parameter packages: 包裹列表
    /// - Returns: 每個包裹的更新結果
    func refreshAll(packages: [Package]) async -> [UUID: Result<TrackingResult, Error>] {
        isLoading = true
        defer { isLoading = false }

        var results: [UUID: Result<TrackingResult, Error>] = [:]

        // 使用 TaskGroup 並行處理
        await withTaskGroup(of: (UUID, Result<TrackingResult, Error>).self) { group in
            for package in packages where !package.isArchived {
                group.addTask {
                    do {
                        let result = try await self.track(
                            number: package.trackingNumber,
                            carrier: package.carrier
                        )
                        return (package.id, .success(result))
                    } catch {
                        return (package.id, .failure(error))
                    }
                }
            }

            for await (id, result) in group {
                results[id] = result
            }
        }

        return results
    }

    /// 檢查物流商是否支援自動追蹤
    func isAutoTrackingSupported(for carrier: Carrier) -> Bool {
        services.contains { $0.supportedCarriers.contains(carrier) }
    }

    /// 取得物流商的外部追蹤連結
    func getExternalTrackingURL(trackingNumber: String, carrier: Carrier) -> URL? {
        // 各物流商的官方追蹤頁面
        let urlString: String? = switch carrier {
        case .tcat:
            "https://www.t-cat.com.tw/inquire/trace.aspx?no=\(trackingNumber)"
        case .hct:
            "https://www.hct.com.tw/search/searchgoods_con.aspx?no=\(trackingNumber)"
        case .sevenEleven:
            "https://eservice.7-11.com.tw/E-Tracking/search.aspx"
        case .familyMart:
            "https://www.famiport.com.tw/Web_Famiport/page/fami_ec_serv.aspx"
        case .postTW:
            "https://postserv.post.gov.tw/pstmail/main_mail.html"
        case .shopee:
            "shopee://order"  // Deep Link
        default:
            carrier.trackTwUUID.map { "https://track.tw/carrier/\($0)/\(trackingNumber)" }
        }

        return urlString.flatMap { URL(string: $0) }
    }
}
