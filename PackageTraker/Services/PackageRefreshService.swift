import Foundation
import SwiftUI
import SwiftData
import Observation

/// 集中管理所有包裹刷新邏輯
/// 由 PackageTrakerApp 建立並透過 environment 注入
@Observable
final class PackageRefreshService {

    /// 批次刷新進度（0.0 ~ 1.0）
    var batchProgress: Double = 0

    /// 是否正在批次刷新
    var isBatchRefreshing = false

    /// 最後一次批次刷新完成時間
    var lastBatchRefreshDate: Date?

    private let trackingManager = TrackingManager()

    /// 正在刷新中的單號（防止同一包裹重複呼叫 API）
    private var refreshingNumbers: Set<String> = []

    // MARK: - 單一包裹刷新

    /// 刷新單一包裹並立即寫入 SwiftData
    /// - Returns: true 表示有實際刷新（非跳過）
    @discardableResult
    func refreshPackage(_ package: Package, in context: ModelContext) async -> Bool {
        // 任務已取消就直接返回
        guard !Task.isCancelled else { return false }

        // 已完成且有事件的包裹不再刷新
        guard !package.status.isCompleted || package.events.isEmpty else {
            return false
        }

        // 不支援的物流商跳過
        guard trackingManager.isAutoTrackingSupported(for: package.carrier) else {
            return false
        }

        // 防止同一包裹同時刷新
        guard !refreshingNumbers.contains(package.trackingNumber) else {
            return false
        }
        refreshingNumbers.insert(package.trackingNumber)
        defer { refreshingNumbers.remove(package.trackingNumber) }

        do {
            let result = try await trackingManager.track(package: package)
            // 取消的任務不寫入結果
            guard !Task.isCancelled else { return false }
            applyTrackingResult(result, to: package)
            try? context.save()
            return true
        } catch is CancellationError {
            // timeout 取消是正常行為，不印錯誤
            return false
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch {
            // 被包裝在 TrackingError.networkError 裡的取消也靜默處理
            if case TrackingError.networkError(let underlying) = error,
               underlying is CancellationError || (underlying as? URLError)?.code == .cancelled {
                return false
            }
            print("❌ 刷新包裹 \(package.trackingNumber) 失敗: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 批次刷新（帶進度）

    /// 批次刷新多個包裹，每個包裹完成後立即 save（漸進式 UI 更新）
    func refreshAll(_ packages: [Package], in context: ModelContext, maxConcurrent: Int = 3) async {
        let packagesToRefresh = packages.filter { package in
            (!package.status.isCompleted || package.events.isEmpty) &&
            trackingManager.isAutoTrackingSupported(for: package.carrier)
        }

        guard !packagesToRefresh.isEmpty else {
            batchProgress = 1.0
            return
        }

        isBatchRefreshing = true
        batchProgress = 0
        let total = packagesToRefresh.count

        await withTaskGroup(of: Void.self) { group in
            var completedCount = 0

            for (index, package) in packagesToRefresh.enumerated() {
                if index >= maxConcurrent {
                    await group.next()
                    completedCount += 1
                    batchProgress = Double(completedCount) / Double(total)
                }

                group.addTask {
                    _ = await self.refreshPackage(package, in: context)
                }
            }

            // 等待剩餘任務
            for await _ in group {
                completedCount += 1
                batchProgress = Double(completedCount) / Double(total)
            }
        }

        batchProgress = 1.0
        lastBatchRefreshDate = Date()
        isBatchRefreshing = false
    }

    // MARK: - 帶 Timeout 的批次刷新（用於 Splash）

    /// 帶 timeout 的批次刷新，超時後放棄未完成的包裹
    func refreshAllWithTimeout(
        _ packages: [Package],
        in context: ModelContext,
        timeout: TimeInterval = 10.0,
        maxConcurrent: Int = 3
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.refreshAll(packages, in: context, maxConcurrent: maxConcurrent)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            }
            // 先完成的那個結束後，取消另一個
            await group.next()
            group.cancelAll()
        }

        batchProgress = 1.0
        isBatchRefreshing = false
        lastBatchRefreshDate = Date()
    }

    // MARK: - 過期檢查

    /// 判斷包裹資料是否過期（預設 5 分鐘）
    func isStale(_ package: Package, threshold: TimeInterval = 300) -> Bool {
        Date().timeIntervalSince(package.lastUpdated) > threshold
    }

    // MARK: - 結果寫入（唯一實作）

    /// 將 API 追蹤結果寫入 Package model
    private func applyTrackingResult(_ result: TrackingResult, to package: Package) {
        package.status = result.currentStatus
        package.lastUpdated = Date()

        if let latestEvent = result.events.first {
            package.latestDescription = latestEvent.description
            if let location = latestEvent.location, !location.isEmpty {
                package.pickupLocation = location
            }
        }

        if let storeName = result.storeName { package.storeName = storeName }
        if let serviceType = result.serviceType { package.serviceType = serviceType }
        if let pickupDeadline = result.pickupDeadline { package.pickupDeadline = pickupDeadline }

        package.events.removeAll()
        for eventDTO in result.events {
            let event = TrackingEvent(
                timestamp: eventDTO.timestamp,
                status: eventDTO.status,
                description: eventDTO.description,
                location: eventDTO.location
            )
            event.package = package
            package.events.append(event)
        }
    }
}
