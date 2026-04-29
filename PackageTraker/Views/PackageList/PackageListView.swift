import SwiftUI
import SwiftData
import WidgetKit

/// 包裹清單主頁
struct PackageListView: View {
    @Binding var pendingPackageId: UUID?
    @Binding var showAddPackage: Bool
    @Binding var prefillCarrier: String?
    @Binding var prefillTrackingNumber: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(PackageRefreshService.self) private var refreshService
    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage("hideDeliveredPackages") private var hideDeliveredPackages = false
    @AppStorage("selectedStat1") private var selectedStat1RawValue: String = StatType.defaultStat1.rawValue
    @AppStorage("selectedStat2") private var selectedStat2RawValue: String = StatType.defaultStat2.rawValue

    @Query(filter: #Predicate<Package> { !$0.isArchived },
           sort: \Package.lastUpdated, order: .reverse)
    private var packages: [Package]

    @State private var viewModel: PackageListViewModel?
    @State private var showAddMethodSheet = false
    @State private var showManualAdd = false
    @State private var showAICarrierSelect = false
    @State private var showPaywall = false
    @State private var paywallLifetimeOnly = false
    @State private var paywallFromAddFlow = false
    @State private var paywallTrigger: PaywallTrigger = .general
    @State private var pendingAddAction: PendingAddAction = .none
    @State private var selectedPackage: Package?
    @State private var sheetStatType: StatType?

    // AI 試用 upsell
    @State private var showAITrialUpsell = false

    // 包裹額度預警 banner
    @State private var quotaBannerDismissed = false
    @State private var promoBannerDismissed = false
    @State private var milestoneBannerDismissed = false
    @ObservedObject private var promoManager = LaunchPromoManager.shared
    @ObservedObject private var milestonePromo = MilestonePromoManager.shared

    // 編輯、完成、刪除
    @State private var packageToEdit: Package?
    @State private var packageToMarkComplete: Package?
    @State private var showCompleteConfirmation = false
    @State private var packageToDelete: Package?
    @State private var showDeleteConfirmation = false

    // 統計編輯
    @State private var editingStatSlot: Int?

    // Hero 動畫用的 Namespace
    @Namespace private var heroNamespace

    private var vm: PackageListViewModel {
        viewModel ?? PackageListViewModel(modelContext: modelContext, refreshService: refreshService)
    }

    private var filteredPackages: [Package] {
        vm.filteredPackages(packages, hideDelivered: hideDeliveredPackages)
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredPackages.isEmpty {
                    emptyStateContent
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
            .sheet(item: $packageToEdit) { package in
                EditPackageSheet(package: package)
            }
            .overlay {
                Color.clear
                    .alert(String(localized: "detail.deleteConfirm"), isPresented: $showDeleteConfirmation) {
                        Button(String(localized: "common.delete"), role: .destructive) {
                            if let package = packageToDelete {
                                vm.deletePackage(package, allPackages: packages)
                                packageToDelete = nil
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
                                vm.markAsDelivered(package, allPackages: packages)
                                packageToMarkComplete = nil
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
            .sheet(item: $sheetStatType) { statType in
                PackageListSheetView(
                    title: statType.localizedLabel,
                    packages: vm.packagesForStat(statType, packages: packages)
                )
            }
            .navigationDestination(item: $selectedPackage) { package in
                PackageDetailView(package: package, namespace: heroNamespace)
                    .navigationTransition(.zoom(sourceID: package.id, in: heroNamespace))
            }
            .onChange(of: showAddPackage) { _, newValue in
                if newValue {
                    if prefillCarrier != nil || prefillTrackingNumber != nil {
                        showManualAdd = true
                    } else {
                        showAddMethodSheet = true
                    }
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
                viewModel = PackageListViewModel(modelContext: modelContext, refreshService: refreshService)
                WidgetDataService.shared.updateWidgetData(packages: packages)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .toolbar(selectedPackage == nil ? .visible : .hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        // 新增流程的 sheet 放在 NavigationStack 外層，避免 @Query 變更導致 sheet 內容重建
        .sheet(isPresented: $showAddMethodSheet, onDismiss: {
            switch pendingAddAction {
            case .manualAdd:
                showManualAdd = true
            case .aiScan:
                showAICarrierSelect = true
            case .paywall(let lifetimeOnly):
                paywallLifetimeOnly = lifetimeOnly
                paywallFromAddFlow = true
                paywallTrigger = lifetimeOnly ? .ai : .packages
                showPaywall = true
            case .aiTrialUpsell:
                showAITrialUpsell = true
            case .none:
                break
            }
            pendingAddAction = .none
            Task { await vm.refreshPendingPackages(packages) }
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
            prefillCarrier = nil
            prefillTrackingNumber = nil
            Task { await vm.refreshPendingPackages(packages) }
        }) {
            AddPackageView(
                prefillCarrier: Carrier.allCases.first(where: { $0.rawValue == prefillCarrier }),
                prefillTrackingNumber: prefillTrackingNumber
            )
        }
        .sheet(isPresented: $showAICarrierSelect, onDismiss: {
            Task { await vm.refreshPendingPackages(packages) }
        }) {
            AICarrierSelectView()
        }
        .fullScreenCover(isPresented: $showPaywall, onDismiss: {
            if paywallFromAddFlow {
                showAddMethodSheet = true
                paywallFromAddFlow = false
            }
        }) {
            PaywallView(lifetimeOnly: paywallLifetimeOnly, trigger: paywallTrigger)
        }
        .sheet(isPresented: $showAITrialUpsell, onDismiss: {
            showAddMethodSheet = true
        }) {
            AITrialUpsellView()
        }
        .sheet(item: $editingStatSlot) { slot in
            StatPickerSheet(
                slot: slot,
                selectedStat1: selectedStat1,
                selectedStat2: selectedStat2,
                isPro: !FeatureFlags.subscriptionEnabled || SubscriptionManager.shared.isPro,
                onSelect: { statType in
                    let otherStat = slot == 1 ? selectedStat2 : selectedStat1
                    if statType == otherStat {
                        let currentStat = slot == 1 ? selectedStat1 : selectedStat2
                        if slot == 1 {
                            selectedStat1RawValue = statType.rawValue
                            selectedStat2RawValue = currentStat.rawValue
                        } else {
                            selectedStat2RawValue = statType.rawValue
                            selectedStat1RawValue = currentStat.rawValue
                        }
                    } else {
                        if slot == 1 {
                            selectedStat1RawValue = statType.rawValue
                        } else {
                            selectedStat2RawValue = statType.rawValue
                        }
                    }
                    FirebaseSyncService.shared.syncUserPreferences(
                        selectedStat1: selectedStat1RawValue,
                        selectedStat2: selectedStat2RawValue
                    )
                    editingStatSlot = nil
                },
                onShowPaywall: {
                    editingStatSlot = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        paywallTrigger = .homeStats
                        showPaywall = true
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Views

    private var emptyStateContent: some View {
        VStack(spacing: 16) {
            // 限時優惠 / Milestone Banner（launchPromo > milestone）— 與 packageListContent 一致放在 stats 上方
            if !SubscriptionManager.shared.isPro {
                if promoManager.isPromoActive && !promoBannerDismissed {
                    PromoBanner(
                        onTap: { paywallTrigger = .general; showPaywall = true },
                        onDismiss: { promoBannerDismissed = true }
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                } else if milestonePromo.isPromoActive && !milestoneBannerDismissed {
                    MilestonePromoBanner(
                        onTap: {
                            AnalyticsService.logMilestonePromoBannerTapped()
                            paywallTrigger = .general
                            showPaywall = true
                        },
                        onDismiss: { milestoneBannerDismissed = true }
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }

            StatsSummaryView(
                stat1: (selectedStat1, vm.computeStatValue(selectedStat1, packages: packages)),
                stat2: (selectedStat2, vm.computeStatValue(selectedStat2, packages: packages)),
                onStat1Tap: statTapAction(for: selectedStat1),
                onStat2Tap: statTapAction(for: selectedStat2),
                onStat1Edit: { editingStatSlot = 1 },
                onStat2Edit: { editingStatSlot = 2 }
            )
            .padding(.horizontal)

            EmptyPackageListView()
                .frame(maxHeight: .infinity)
        }
    }

    private var packageListContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 包裹額度預警 Banner
                if !SubscriptionManager.shared.isPro && !quotaBannerDismissed {
                    let activeCount = packages.filter { !$0.isArchived && $0.status != .delivered }.count
                    let maxCount = SubscriptionManager.shared.maxPackageCount
                    if activeCount >= maxCount {
                        ProNudgeBanner(
                            message: String(localized: "quota.full"),
                            icon: "exclamationmark.triangle.fill",
                            style: .critical,
                            onUpgrade: { paywallTrigger = .packages; showPaywall = true },
                            onDismiss: { quotaBannerDismissed = true }
                        )
                        .padding(.horizontal)
                    } else if activeCount >= maxCount - 1 {
                        ProNudgeBanner(
                            message: String(localized: "quota.almostFull"),
                            style: .warning,
                            onUpgrade: { paywallTrigger = .packages; showPaywall = true },
                            onDismiss: { quotaBannerDismissed = true }
                        )
                        .padding(.horizontal)
                    }
                }

                // 限時優惠 Banner（launchPromo 優先；milestone 次之；同一時間只顯示一個）
                if !SubscriptionManager.shared.isPro {
                    if promoManager.isPromoActive && !promoBannerDismissed {
                        PromoBanner(
                            onTap: { paywallTrigger = .general; showPaywall = true },
                            onDismiss: { promoBannerDismissed = true }
                        )
                        .padding(.horizontal)
                    } else if milestonePromo.isPromoActive && !milestoneBannerDismissed {
                        MilestonePromoBanner(
                            onTap: {
                                AnalyticsService.logMilestonePromoBannerTapped()
                                paywallTrigger = .general
                                showPaywall = true
                            },
                            onDismiss: { milestoneBannerDismissed = true }
                        )
                        .padding(.horizontal)
                    }
                }

                // 統計摘要
                StatsSummaryView(
                    stat1: (selectedStat1, vm.computeStatValue(selectedStat1, packages: packages)),
                    stat2: (selectedStat2, vm.computeStatValue(selectedStat2, packages: packages)),
                    onStat1Tap: statTapAction(for: selectedStat1),
                    onStat2Tap: statTapAction(for: selectedStat2),
                    onStat1Edit: { editingStatSlot = 1 },
                    onStat2Edit: { editingStatSlot = 2 }
                )
                .padding(.horizontal)

                // 按物流商分組顯示
                ForEach(vm.groupedByCarrier(filteredPackages).keys.sorted(), id: \.self) { carrierName in
                    if let carrierPackages = vm.groupedByCarrier(filteredPackages)[carrierName] {
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
            await vm.refreshAllPackages(filteredPackages)
        }
    }

    // MARK: - Stat Helpers

    private var selectedStat1: StatType {
        guard !FeatureFlags.subscriptionEnabled || SubscriptionManager.shared.isPro else { return .defaultStat1 }
        return StatType(rawValue: selectedStat1RawValue) ?? .pendingPickup
    }

    private var selectedStat2: StatType {
        guard !FeatureFlags.subscriptionEnabled || SubscriptionManager.shared.isPro else { return .defaultStat2 }
        return StatType(rawValue: selectedStat2RawValue) ?? .deliveredLast30Days
    }

    private func statTapAction(for type: StatType) -> (() -> Void)? {
        return { sheetStatType = type }
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
    PackageListView(pendingPackageId: .constant(nil), showAddPackage: .constant(false), prefillCarrier: .constant(nil), prefillTrackingNumber: .constant(nil))
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
        .environment(PackageRefreshService())
}
