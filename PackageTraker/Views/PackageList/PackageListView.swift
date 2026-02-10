import SwiftUI
import SwiftData
import WidgetKit

/// 包裹清單主頁
struct PackageListView: View {
    @Binding var pendingPackageId: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(PackageRefreshService.self) private var refreshService
    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage("hideDeliveredPackages") private var hideDeliveredPackages = false

    @Query(filter: #Predicate<Package> { !$0.isArchived },
           sort: \Package.lastUpdated, order: .reverse)
    private var packages: [Package]

    @Query private var linkedAccounts: [LinkedEmailAccount]

    @State private var showAddPackage = false
    @State private var selectedPackage: Package?
    @State private var emailSyncStatus: String?
    @State private var showPendingSheet = false
    @State private var showDeliveredSheet = false

    // 編輯和刪除
    @State private var packageToEdit: Package?
    @State private var packageToDelete: Package?
    @State private var showDeleteConfirmation = false

    // Hero 動畫用的 Namespace
    @Namespace private var heroNamespace

    private let gmailAuthManager = GmailAuthManager.shared

    /// 30 天前的日期
    private var thirtyDaysAgo: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }

    /// 過濾後的包裹（最後狀態距今超過 30 天的不顯示，可選隱藏已取貨）
    private var filteredPackages: [Package] {
        packages.filter { package in
            // 隱藏已取貨的包裹
            if hideDeliveredPackages && package.status == .delivered {
                return false
            }
            // 使用最後狀態的時間（最新事件的時間）判斷
            if let latestEventTime = package.latestEventTimestamp {
                // 距今超過 30 天就不顯示
                return latestEventTime > thirtyDaysAgo
            }
            // 沒有事件的包裹，使用 lastUpdated
            return package.lastUpdated > thirtyDaysAgo
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredPackages.isEmpty {
                    EmptyPackageListView(onAddPackage: { showAddPackage = true })
                } else {
                    packageListContent
                }
            }
            .adaptiveGradientBackground()
            .navigationTitle(String(localized: "home.title"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    addButton
                }
            }
            .sheet(isPresented: $showAddPackage, onDismiss: {
                // 新增完畢後，自動刷新所有 pending 且無事件的包裹
                Task {
                    await refreshPendingPackages()
                }
            }) {
                AddPackageView()
            }
            .sheet(item: $packageToEdit) { package in
                EditPackageSheet(package: package)
            }
            .confirmationDialog(String(localized: "detail.deleteConfirm"), isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    if let package = packageToDelete {
                        deletePackage(package)
                    }
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    packageToDelete = nil
                }
            }
            .sheet(isPresented: $showPendingSheet) {
                PackageListSheetView(
                    title: String(localized: "sheet.pendingTitle"),
                    packages: pendingPackages
                )
            }
            .sheet(isPresented: $showDeliveredSheet) {
                PackageListSheetView(
                    title: String(localized: "sheet.deliveredTitle"),
                    packages: deliveredRecentPackages
                )
            }
            .navigationDestination(item: $selectedPackage) { package in
                PackageDetailView(package: package, namespace: heroNamespace)
                    .navigationTransition(.zoom(sourceID: package.id, in: heroNamespace))
            }
            .onChange(of: pendingPackageId) { _, newValue in
                guard let targetId = newValue else { return }
                if let package = packages.first(where: { $0.id == targetId }) {
                    selectedPackage = package
                }
                pendingPackageId = nil
            }
        }
        .toolbar(selectedPackage == nil ? .visible : .hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.3), value: selectedPackage)
        .preferredColorScheme(.dark)
    }

    private func deletePackage(_ package: Package) {
        let packageId = package.id
        modelContext.delete(package)
        try? modelContext.save()
        packageToDelete = nil
        // 從 Firestore 刪除
        FirebaseSyncService.shared.deletePackage(packageId)
        // 更新 Widget
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Views

    private var packageListContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 郵件同步狀態提示（功能暫時停用）
                if FeatureFlags.emailAutoImportEnabled, let status = emailSyncStatus {
                    emailSyncStatusBanner(status)
                        .padding(.horizontal)
                }

                // 統計摘要
                StatsSummaryView(
                    pendingCount: pendingPackages.count,
                    deliveredThisMonth: deliveredRecentPackages.count,
                    onPendingTap: { showPendingSheet = true },
                    onDeliveredTap: { showDeliveredSheet = true }
                )
                .padding(.horizontal)

                // 按物流商分組顯示（水平滾動列表自己處理 padding）
                ForEach(groupedByCarrier.keys.sorted(), id: \.self) { carrierName in
                    if let carrierPackages = groupedByCarrier[carrierName] {
                        PackageSectionView(
                            title: carrierName,
                            packages: carrierPackages,
                            namespace: heroNamespace,
                            onPackageTap: { package in
                                selectedPackage = package
                            },
                            onPackageEdit: { package in
                                packageToEdit = package
                            },
                            onPackageDelete: { package in
                                packageToDelete = package
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
            }
            .padding(.bottom)
        }
        .refreshable {
            await refreshAllPackages()
        }
    }

    private func emailSyncStatusBanner(_ status: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope.badge.fill")
                .foregroundStyle(.green)

            Text(status)
                .font(.caption)

            Spacer()

            Button {
                emailSyncStatus = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondaryCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Computed Properties

    private var pendingPackages: [Package] {
        allRecentPackages.filter { $0.status.isPendingPickup }
    }

    /// 30 天內已取貨的包裹（不受「隱藏已取貨」影響）
    private var deliveredRecentPackages: [Package] {
        allRecentPackages.filter { $0.status == .delivered }
    }

    /// 30 天內所有包裹（不含隱藏過濾，用於統計）
    private var allRecentPackages: [Package] {
        packages.filter { package in
            if let latestEventTime = package.latestEventTimestamp {
                return latestEventTime > thirtyDaysAgo
            }
            return package.lastUpdated > thirtyDaysAgo
        }
    }

    /// 按物流商分組
    private var groupedByCarrier: [String: [Package]] {
        Dictionary(grouping: filteredPackages) { package in
            package.carrier.displayName
        }
    }

    // MARK: - Actions

    private func refreshAllPackages() async {
        // 1. 先同步郵件中的新包裹（如果已連結 Gmail）
        // 注意：此功能暫時停用，由 FeatureFlags 控制
        if FeatureFlags.emailAutoImportEnabled && gmailAuthManager.isSignedIn {
            await syncEmailPackages()
        }

        // 2. 使用 refreshService 刷新（漸進式，每個包裹完成就 save）
        await refreshService.refreshAll(filteredPackages, in: modelContext)
    }

    private func syncEmailPackages() async {
        let gmailService = GmailService()
        let emailParser = TaiwaneseEmailParser.shared
        let trackingService = TrackTwAPIService()

        do {
            // 取得物流相關郵件
            let messages = try await gmailService.fetchTrackingEmails(maxResults: 30)
            print("[PackageSync] 📧 取得 \(messages.count) 封郵件")

            // 解析郵件（只取得單號，不判斷狀態）
            let results = emailParser.parseEmails(messages)
            print("[PackageSync] 📦 成功解析 \(results.count) 個包裹")

            // 去重：同一個單號只處理一次（保留最新的郵件）
            var uniqueResults: [String: ParsedEmailResult] = [:]
            for result in results {
                let key = result.trackingNumber
                if let existing = uniqueResults[key] {
                    // 保留日期較新的
                    if result.emailDate > existing.emailDate {
                        uniqueResults[key] = result
                    }
                } else {
                    uniqueResults[key] = result
                }
            }
            print("[PackageSync] 🔄 去重後剩餘 \(uniqueResults.count) 個包裹")
            for (_, result) in uniqueResults {
                print("[PackageSync]   - \(result.carrier.displayName): \(result.trackingNumber) (來源: \(result.source))")
            }

            // 處理每個單號：API 查詢成功才新增
            var newPackagesCount = 0

            for (_, result) in uniqueResults {
                let trackingNumber = result.trackingNumber

                // 檢查是否已存在
                let existingPackage = packages.first { $0.trackingNumber == trackingNumber }

                if existingPackage == nil {
                    // 新單號：先查詢 API，成功才新增
                    let apiResult = await verifyAndCreatePackage(
                        result: result,
                        using: trackingService
                    )

                    if apiResult {
                        newPackagesCount += 1
                        print("[PackageSync] ✅ 新增並驗證成功: \(trackingNumber)")
                    } else {
                        print("[PackageSync] ❌ API 驗證失敗，不新增: \(trackingNumber)")
                    }
                } else if let existing = existingPackage {
                    // 更新現有包裹的取件碼（如果有新的）
                    if let pickupCode = result.pickupCode, existing.pickupCode == nil {
                        existing.pickupCode = pickupCode
                    }
                    if let pickupLocation = result.pickupLocation, existing.pickupLocation == nil {
                        existing.pickupLocation = pickupLocation
                    }
                }
            }

            // 更新 LinkedEmailAccount 的同步狀態
            if let account = linkedAccounts.first {
                let summary = newPackagesCount > 0
                    ? "新增 \(newPackagesCount) 個包裹"
                    : "沒有新包裹"
                account.updateSyncStatus(summary: summary)

                // 記錄已同步的郵件 ID
                for message in messages {
                    account.markMessageAsSynced(message.id)
                }
            }

            // 顯示同步結果
            if newPackagesCount > 0 {
                emailSyncStatus = "從郵件中新增了 \(newPackagesCount) 個包裹"

                // 3 秒後自動隱藏
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        emailSyncStatus = nil
                    }
                }
            }

            try? modelContext.save()

        } catch {
            print("郵件同步失敗：\(error.localizedDescription)")
        }
    }

    /// 透過 API 驗證單號，成功才建立包裹
    private func verifyAndCreatePackage(
        result: ParsedEmailResult,
        using trackingService: TrackTwAPIService
    ) async -> Bool {
        let trackingNumber = result.trackingNumber
        let carrier = result.carrier

        // 檢查是否支援此物流商
        guard trackingService.supportedCarriers.contains(carrier) else {
            print("[PackageSync] ⏭️ 不支援的物流商: \(carrier.displayName)，直接新增（待手動確認）")
            // 不支援的物流商，還是新增包裹，但狀態為 pending
            let newPackage = Package(
                trackingNumber: trackingNumber,
                carrier: carrier,
                customName: result.orderDescription
            )
            newPackage.pickupCode = result.pickupCode
            newPackage.pickupLocation = result.pickupLocation
            newPackage.createdAt = result.emailDate
            modelContext.insert(newPackage)
            return true
        }

        print("[PackageSync] 🔍 API 驗證: \(trackingNumber)")
        do {
            let apiResult = try await trackingService.track(
                number: trackingNumber,
                carrier: carrier
            )

            // API 查詢成功，建立包裹
            let newPackage = Package(
                trackingNumber: trackingNumber,
                carrier: carrier,
                customName: result.orderDescription,
                status: apiResult.currentStatus
            )
            newPackage.trackTwRelationId = apiResult.relationId
            newPackage.pickupCode = result.pickupCode
            newPackage.pickupLocation = result.pickupLocation
            newPackage.createdAt = result.emailDate
            newPackage.lastUpdated = Date()
            newPackage.latestDescription = apiResult.events.first?.description

            // 添加追蹤事件
            for eventDTO in apiResult.events {
                let event = TrackingEvent(
                    timestamp: eventDTO.timestamp,
                    status: eventDTO.status,
                    description: eventDTO.description,
                    location: eventDTO.location
                )
                newPackage.events.append(event)
            }

            modelContext.insert(newPackage)
            try? modelContext.save()
            print("[PackageSync] ✅ API 驗證成功: \(trackingNumber) -> \(apiResult.currentStatus.displayName)")
            return true

        } catch {
            // API 查詢失敗，不新增包裹
            print("[PackageSync] ❌ API 驗證失敗: \(trackingNumber) - \(error.localizedDescription)")
            return false
        }
    }

    /// 自動刷新剛新增的 pending 包裹（無事件的）
    private func refreshPendingPackages() async {
        let pending = packages.filter { $0.status == .pending && $0.events.isEmpty }
        guard !pending.isEmpty else { return }

        print("🔄 自動刷新 \(pending.count) 個新增包裹")
        for package in pending {
            _ = await refreshService.refreshPackage(package, in: modelContext)
        }
    }

    private var addButton: some View {
        Button(action: { showAddPackage = true }) {
            Image(systemName: "plus")
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Empty State

struct EmptyPackageListView: View {
    var onAddPackage: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "empty.title"), systemImage: "shippingbox")
        } description: {
            Text(String(localized: "empty.description"))
        } actions: {
            Button(String(localized: "empty.addButton")) {
                onAddPackage()
            }
            .buttonStyle(.borderedProminent)
            .tint(.appAccent)
        }
    }
}

// MARK: - Previews

#Preview {
    PackageListView(pendingPackageId: .constant(nil))
        .modelContainer(for: [Package.self, TrackingEvent.self, LinkedEmailAccount.self], inMemory: true)
        .environment(PackageRefreshService())
}
