import SwiftUI
import SwiftData
import WidgetKit

/// 包裹清單主頁
struct PackageListView: View {
    @Binding var pendingPackageId: UUID?
    @Binding var showAddPackage: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(PackageRefreshService.self) private var refreshService
    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage("hideDeliveredPackages") private var hideDeliveredPackages = false

    @Query(filter: #Predicate<Package> { !$0.isArchived },
           sort: \Package.lastUpdated, order: .reverse)
    private var packages: [Package]

    @Query private var linkedAccounts: [LinkedEmailAccount]

    @State private var showAddMethodSheet = false
    @State private var showManualAdd = false
    @State private var showAICarrierSelect = false
    @State private var showPaywall = false
    @State private var paywallLifetimeOnly = false
    @State private var pendingAddAction: PendingAddAction = .none
    @State private var selectedPackage: Package?
    @State private var emailSyncStatus: String?
    @State private var showPendingSheet = false
    @State private var showDeliveredSheet = false

    // AI 試用 upsell
    @State private var showAITrialUpsell = false

    // 包裹額度預警 banner
    @State private var quotaBannerDismissed = false

    // 編輯、完成、刪除
    @State private var packageToEdit: Package?
    @State private var packageToMarkComplete: Package?
    @State private var showCompleteConfirmation = false
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
                    EmptyPackageListView()
                } else {
                    packageListContent
                }
            }
            .adaptiveGradientBackground()
            .navigationTitle(String(localized: "home.title"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .adaptiveNavigationStyle()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    addButton
                }
            }
            .sheet(isPresented: $showAddMethodSheet, onDismiss: {
                switch pendingAddAction {
                case .manualAdd:
                    showManualAdd = true
                case .aiScan:
                    showAICarrierSelect = true
                case .paywall(let lifetimeOnly):
                    paywallLifetimeOnly = lifetimeOnly
                    showPaywall = true
                case .aiTrialUpsell:
                    showAITrialUpsell = true
                case .none:
                    break
                }
                pendingAddAction = .none
                Task { await refreshPendingPackages() }
            }) {
                AddMethodSheet(
                    onManualAdd: {
                        pendingAddAction = .manualAdd
                        showAddMethodSheet = false
                    },
                    onAIScan: {
                        pendingAddAction = .aiScan
                        showAddMethodSheet = false
                    },
                    onShowPaywall: { lifetimeOnly in
                        pendingAddAction = .paywall(lifetimeOnly: lifetimeOnly)
                        showAddMethodSheet = false
                    },
                    onShowAITrialUpsell: {
                        pendingAddAction = .aiTrialUpsell
                        showAddMethodSheet = false
                    }
                )
            }
            .sheet(isPresented: $showManualAdd, onDismiss: {
                Task { await refreshPendingPackages() }
            }) {
                AddPackageView()
            }
            .sheet(isPresented: $showAICarrierSelect, onDismiss: {
                Task { await refreshPendingPackages() }
            }) {
                AICarrierSelectView()
            }
            .fullScreenCover(isPresented: $showPaywall, onDismiss: {
                showAddMethodSheet = true
            }) {
                PaywallView(lifetimeOnly: paywallLifetimeOnly)
            }
            .sheet(isPresented: $showAITrialUpsell, onDismiss: {
                showAddMethodSheet = true
            }) {
                AITrialUpsellView()
            }
            .sheet(item: $packageToEdit) { package in
                EditPackageSheet(package: package)
            }
            .overlay {
                Color.clear
                    .alert(String(localized: "detail.deleteConfirm"), isPresented: $showDeleteConfirmation) {
                        Button(String(localized: "common.delete"), role: .destructive) {
                            if let package = packageToDelete {
                                deletePackage(package)
                            }
                        }
                        Button(String(localized: "common.cancel"), role: .cancel) {
                            packageToDelete = nil
                        }
                    }
                    .tint(.white)
            }
            .overlay {
                Color.clear
                    .alert(String(localized: "detail.markCompleteConfirm"), isPresented: $showCompleteConfirmation) {
                        Button(String(localized: "detail.markComplete")) {
                            if let package = packageToMarkComplete {
                                markAsDelivered(package)
                            }
                        }
                        Button(String(localized: "common.cancel"), role: .cancel) {
                            packageToMarkComplete = nil
                        }
                    } message: {
                        Text(String(localized: "detail.markCompleteMessage"))
                    }
                    .tint(.white)
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
            .onChange(of: showAddPackage) { _, newValue in
                if newValue {
                    showAddMethodSheet = true
                    showAddPackage = false
                }
            }
            .onChange(of: pendingPackageId) { _, newValue in
                guard let targetId = newValue else { return }
                if let package = packages.first(where: { $0.id == targetId }) {
                    selectedPackage = package
                }
                pendingPackageId = nil
            }
            .task {
                // 啟動時同步 Widget 資料（確保既有包裹資料寫入 App Group）
                WidgetDataService.shared.updateWidgetData(packages: packages)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .toolbar(selectedPackage == nil ? .visible : .hidden, for: .tabBar)
        .preferredColorScheme(.dark)
    }

    private func deletePackage(_ package: Package) {
        let packageId = package.id
        let remainingPackages = packages.filter { $0.id != package.id }
        modelContext.delete(package)
        try? modelContext.save()
        packageToDelete = nil
        // 從 Firestore 刪除
        FirebaseSyncService.shared.deletePackage(packageId)
        // 更新 Widget
        WidgetDataService.shared.updateWidgetData(packages: remainingPackages)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func markAsDelivered(_ package: Package) {
        let now = Date()
        let description = String(localized: "detail.markCompleteEvent")

        package.status = .delivered
        package.lastUpdated = now
        package.latestDescription = description

        let event = TrackingEvent(
            id: TrackingEvent.deterministicId(trackingNumber: package.trackingNumber, timestamp: now, description: description),
            timestamp: now,
            status: .delivered,
            description: description
        )
        event.package = package
        package.events.append(event)

        try? modelContext.save()
        packageToMarkComplete = nil
        FirebaseSyncService.shared.syncPackage(package, includeStatus: true)

        WidgetDataService.shared.updateWidgetData(packages: packages)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Views

    private var packageListContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 包裹額度預警 Banner
                if !SubscriptionManager.shared.isPro && !quotaBannerDismissed {
                    let activeCount = filteredPackages.count
                    let maxCount = SubscriptionManager.shared.maxPackageCount
                    if activeCount >= maxCount {
                        ProNudgeBanner(
                            message: String(localized: "quota.full"),
                            icon: "exclamationmark.triangle.fill",
                            style: .critical,
                            onUpgrade: { showPaywall = true },
                            onDismiss: { quotaBannerDismissed = true }
                        )
                        .padding(.horizontal)
                    } else if activeCount >= maxCount - 1 {
                        ProNudgeBanner(
                            message: String(localized: "quota.almostFull"),
                            style: .warning,
                            onUpgrade: { showPaywall = true },
                            onDismiss: { quotaBannerDismissed = true }
                        )
                        .padding(.horizontal)
                    }
                }

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
                            onPackageMarkComplete: { package in
                                packageToMarkComplete = package
                                showCompleteConfirmation = true
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
        Button(action: { showAddMethodSheet = true }) {
            Image(systemName: "plus")
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Pending Add Action

private enum PendingAddAction {
    case none
    case manualAdd
    case aiScan
    case paywall(lifetimeOnly: Bool)
    case aiTrialUpsell
}

// MARK: - Empty State

struct EmptyPackageListView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ContentUnavailableView {
                Label(String(localized: "empty.title"), systemImage: "shippingbox")
            } description: {
                Text(String(localized: "empty.description"))
            }

            // Pro 功能亮點（免費用戶才顯示）
            if !subscriptionManager.isPro {
                proFeatureCard
            }

            Spacer()
        }
    }

    private var proFeatureCard: some View {
        VStack(spacing: 14) {
            Text(String(localized: "empty.proFeatures.title"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 3 列 x 2 行 grid
            let rows = proFeatures.chunked(into: 3)
            VStack(spacing: 12) {
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    HStack(spacing: 8) {
                        ForEach(rows[rowIndex], id: \.icon) { feature in
                            HStack(spacing: 6) {
                                Image(systemName: feature.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.yellow)
                                Text(String(localized: feature.text))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Button {
                showPaywall = true
            } label: {
                Text(String(localized: "empty.proFeatures.viewPlans"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            .padding(.top, 2)
        }
        .padding(16)
        .modifier(ProFeatureCardBackgroundModifier())
        .padding(.horizontal, 16)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    /// 與付費牆功能對比表一致的 6 項 Pro 功能
    private var proFeatures: [(icon: String, text: LocalizedStringResource)] {
        [
            ("shippingbox.fill", "paywall.comparison.packages"),
            ("sparkles", "paywall.comparison.ai"),
            ("chart.pie.fill", "paywall.comparison.spending"),
            ("bell.badge.fill", "paywall.comparison.notification"),
            ("apps.iphone", "paywall.comparison.widget"),
            ("paintpalette.fill", "paywall.comparison.themes"),
        ]
    }
}

// MARK: - Array Chunked Helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Pro Feature Card Background

private struct ProFeatureCardBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .background(
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
        } else {
            content
                .background(Color.secondaryCardBackground, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Previews

#Preview {
    PackageListView(pendingPackageId: .constant(nil), showAddPackage: .constant(false))
        .modelContainer(for: [Package.self, TrackingEvent.self, LinkedEmailAccount.self], inMemory: true)
        .environment(PackageRefreshService())
}
