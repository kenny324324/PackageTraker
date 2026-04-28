import Foundation
import SwiftUI
import SwiftData
import Observation
import WidgetKit

/// 集中管理所有包裹刷新邏輯
/// 由 PackageTrakerApp 建立並透過 environment 注入
/// @MainActor 確保 ModelContext 存取安全（API 網路 I/O 仍透過 await 懸停並行）
@MainActor
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
    private let refreshingNumbers = RefreshingNumbersStore()

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
        let didStart = await refreshingNumbers.begin(package.trackingNumber)
        guard didStart else { return false }

        // 紀錄首次同步狀態：用於修補「匯入即已到貨，沒有 transition 不觸發 Cloud Functions」的洞
        let wasFirstSync = package.events.isEmpty
        let oldStatus = package.status

        do {
            let result = try await trackingManager.track(package: package)
            await refreshingNumbers.end(package.trackingNumber)
            // 取消的任務不寫入結果
            guard !Task.isCancelled else { return false }
            applyTrackingResult(result, to: package)
            try? context.save()

            // 首次同步若狀態已是「已到貨」，本地觸發到貨通知
            // （Cloud Functions onDocumentUpdated 只看狀態變化，匯入時沒有 before status，永遠不會 fire）
            if wasFirstSync, package.status == .arrivedAtStore {
                NotificationManager.shared.handleStatusChange(
                    package: package,
                    oldStatus: oldStatus,
                    newStatus: package.status
                )
            }
            // 不回寫 Firestore：Scheduler 是 Firestore 狀態的唯一寫入者，
            // Client 刷新只更新本地 SwiftData 供即時顯示。
            // 避免 Client + Scheduler 同時寫入觸發多次 onDocumentUpdated 推播。
            // 更新 Widget 資料
            updateWidgetFromContext(context)
            return true
        } catch is CancellationError {
            await refreshingNumbers.end(package.trackingNumber)
            return false
        } catch let error as URLError where error.code == .cancelled {
            await refreshingNumbers.end(package.trackingNumber)
            return false
        } catch {
            await refreshingNumbers.end(package.trackingNumber)
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
            var inFlight = 0

            for package in packagesToRefresh {
                guard !Task.isCancelled else { break }

                if inFlight >= maxConcurrent {
                    if await group.next() != nil {
                        completedCount += 1
                        batchProgress = Double(completedCount) / Double(total)
                        inFlight -= 1
                    } else {
                        break
                    }
                }

                inFlight += 1
                group.addTask {
                    _ = await self.refreshPackage(package, in: context)
                }
            }

            while inFlight > 0 {
                if await group.next() != nil {
                    completedCount += 1
                    batchProgress = Double(completedCount) / Double(total)
                    inFlight -= 1
                } else {
                    break
                }
            }
        }

        batchProgress = 1.0
        lastBatchRefreshDate = Date()
        isBatchRefreshing = false

        // 更新 Widget 資料
        WidgetDataService.shared.updateWidgetData(packages: packages)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - 帶 Timeout 的批次刷新（用於 Splash）

    /// 帶 timeout 的批次刷新，超時後放棄未完成的包裹
    nonisolated func refreshAllWithTimeout(
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
            // 第一個完成（刷新或 timeout）後取消剩餘的
            await group.next()
            group.cancelAll()
            // withTaskGroup scope 隱式等待所有 child task 結束，安全清理
        }
    }

    // MARK: - 過期檢查

    /// 判斷包裹資料是否過期（預設 5 分鐘）
    func isStale(_ package: Package, threshold: TimeInterval = 300) -> Bool {
        Date().timeIntervalSince(package.lastUpdated) > threshold
    }

    // MARK: - Widget 更新

    /// 從 ModelContext 讀取所有未歸檔包裹並更新 Widget
    private func updateWidgetFromContext(_ context: ModelContext) {
        let descriptor = FetchDescriptor<Package>(
            predicate: #Predicate<Package> { !$0.isArchived }
        )
        if let packages = try? context.fetch(descriptor) {
            WidgetDataService.shared.updateWidgetData(packages: packages)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - 結果寫入（唯一實作）

    /// 將 API 追蹤結果寫入 Package model
    private func applyTrackingResult(_ result: TrackingResult, to package: Package) {
        // 評分提示（爽點：包裹到店）
        if result.currentStatus == .arrivedAtStore && package.status != .arrivedAtStore {
            ReviewPromptService.requestReviewIfAppropriate()
        }

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

        if let relationId = result.relationId, package.trackTwRelationId != relationId {
            package.trackTwRelationId = relationId
        }

        // 使用確定性 UUID：同一事件在每次刷新時產生相同 ID，避免 Firestore 重複文件
        let newEvents = result.events.map { eventDTO in
            let deterministicId = TrackingEvent.deterministicId(
                trackingNumber: package.trackingNumber,
                timestamp: eventDTO.timestamp,
                description: eventDTO.description
            )
            let event = TrackingEvent(
                id: deterministicId,
                timestamp: eventDTO.timestamp,
                status: eventDTO.status,
                description: eventDTO.description,
                location: eventDTO.location
            )
            event.package = package
            return event
        }
        package.events = newEvents

        // Track.TW 不回傳取件期限。狀態為「已到貨」且為超商類別時，
        // 用「最早到店事件 + carrier.pickupHoldDays」自動回填，
        // 不覆寫使用者手動填或 API 回傳的既有值。
        if package.pickupDeadline == nil,
           package.status == .arrivedAtStore,
           let computed = package.computedPickupDeadline {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_TW")
            formatter.dateFormat = "yyyy-MM-dd"
            package.pickupDeadline = formatter.string(from: computed)
        }
    }
}

// MARK: - Refreshing Numbers Store

private actor RefreshingNumbersStore {
    private var storage: Set<String> = []

    func begin(_ trackingNumber: String) -> Bool {
        guard !storage.contains(trackingNumber) else { return false }
        storage.insert(trackingNumber)
        return true
    }

    func end(_ trackingNumber: String) {
        storage.remove(trackingNumber)
    }
}
