import Foundation
import SwiftUI
import Combine

/// 追蹤管理器
/// 使用 Track.TW API 追蹤所有包裹
@MainActor
final class TrackingManager: ObservableObject {

    /// 是否正在載入
    @Published var isLoading = false

    /// 最後一次錯誤
    @Published var lastError: TrackingError?

    private let apiService = TrackTwAPIService()

    /// 追蹤單一包裹（傳入 Package 物件，自動載入 relation ID 快取）
    func track(package: Package) async throws -> TrackingResult {
        // 記錄舊狀態
        let oldStatus = package.status

        // 載入已儲存的 relation ID，避免重複 import
        if let relationId = package.trackTwRelationId {
            await apiService.setRelationId(relationId, for: package.trackingNumber)
        }

        let result = try await track(number: package.trackingNumber, carrier: package.carrier)

        // 偵測狀態變化，觸發通知
        if oldStatus != result.currentStatus {
            await NotificationManager.shared.handleStatusChange(
                package: package,
                oldStatus: oldStatus,
                newStatus: result.currentStatus
            )
        }

        return result
    }

    /// 追蹤單一包裹
    func track(number: String, carrier: Carrier) async throws -> TrackingResult {
        guard carrier.trackTwUUID != nil else {
            throw TrackingError.unsupportedCarrier(carrier)
        }

        do {
            return try await apiService.track(number: number, carrier: carrier)
        } catch let error as TrackingError {
            throw error
        } catch {
            throw TrackingError.networkError(underlying: error)
        }
    }

    /// 只匯入包裹（驗證單號 + 取得 relation ID），不查詢追蹤
    /// 用於新增包裹時，加速回應
    func importPackage(number: String, carrier: Carrier) async throws -> String {
        guard carrier.trackTwUUID != nil else {
            throw TrackingError.unsupportedCarrier(carrier)
        }
        return try await apiService.importOnly(number: number, carrier: carrier)
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
                // 載入已知的 relation ID 到快取
                if let relationId = package.trackTwRelationId {
                    await apiService.setRelationId(relationId, for: package.trackingNumber)
                }

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
        carrier.trackTwUUID != nil
    }

    /// 取得物流商的外部追蹤連結
    func getExternalTrackingURL(trackingNumber: String, carrier: Carrier) -> URL? {
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
            "shopee://order"
        default:
            carrier.trackTwUUID.map { "https://track.tw/carrier/\($0)/\(trackingNumber)" }
        }

        return urlString.flatMap { URL(string: $0) }
    }
}
