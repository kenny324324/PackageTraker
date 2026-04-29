import SwiftUI
import SwiftData

/// 首頁統計設定頁面
struct StatSettingsView: View {
    @AppStorage("selectedStat1") private var selectedStat1RawValue: String = StatType.defaultStat1.rawValue
    @AppStorage("selectedStat2") private var selectedStat2RawValue: String = StatType.defaultStat2.rawValue
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @Query(filter: #Predicate<Package> { !$0.isArchived },
           sort: \Package.lastUpdated, order: .reverse)
    private var packages: [Package]

    @ObservedObject private var promoManager = LaunchPromoManager.shared
    @ObservedObject private var milestonePromo = MilestonePromoManager.shared

    @State private var editingSlot: Int? = nil
    @State private var showPaywall = false
    @State private var promoBannerDismissed = false
    @State private var milestoneBannerDismissed = false

    private var isPro: Bool {
        !FeatureFlags.subscriptionEnabled || subscriptionManager.isPro
    }

    private var selectedStat1: StatType {
        guard isPro else { return .defaultStat1 }
        return StatType(rawValue: selectedStat1RawValue) ?? .pendingPickup
    }

    private var selectedStat2: StatType {
        guard isPro else { return .defaultStat2 }
        return StatType(rawValue: selectedStat2RawValue) ?? .deliveredLast30Days
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 預覽區（即時計算真實數字）
                previewSection

                // 說明
                Text(String(localized: "stats.settings.choose"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 選擇區
                slotsSection

                // Promo Banner（launchPromo 優先 → milestone）
                if !isPro {
                    if promoManager.isPromoActive && !promoBannerDismissed {
                        PromoBanner(
                            onTap: { showPaywall = true },
                            onDismiss: { promoBannerDismissed = true }
                        )
                    } else if milestonePromo.isPromoActive && !milestoneBannerDismissed {
                        MilestonePromoBanner(
                            onTap: {
                                AnalyticsService.logMilestonePromoBannerTapped()
                                showPaywall = true
                            },
                            onDismiss: { milestoneBannerDismissed = true }
                        )
                    }
                }
            }
            .padding()
        }
        .background(
            ZStack {
                Color.appBackground

                LinearGradient(
                    colors: [
                        themeManager.currentColor.opacity(0.5),
                        themeManager.currentColor.opacity(0.28),
                        themeManager.currentColor.opacity(0.12),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 350)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .ignoresSafeArea()
        )
        .navigationTitle(String(localized: "stats.settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(item: $editingSlot) { slot in
            StatPickerSheet(
                slot: slot,
                selectedStat1: selectedStat1,
                selectedStat2: selectedStat2,
                isPro: isPro,
                onSelect: { statType in
                    let otherStat = slot == 1 ? selectedStat2 : selectedStat1
                    if statType == otherStat {
                        // 交換：把目前的放到另一個 slot
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
                    syncToFirebase()
                    editingSlot = nil
                },
                onShowPaywall: {
                    editingSlot = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showPaywall = true
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(trigger: .homeStats)
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        HStack(spacing: 12) {
            previewCard(type: selectedStat1)
            previewCard(type: selectedStat2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 20)
    }

    private func previewCard(type: StatType) -> some View {
        let value = computeStatValue(type)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.subheadline)
                    .foregroundStyle(type.iconColor)

                Text(type.localizedLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(value.displayString)
                .font(.system(size: 28, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(value.deltaColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .adaptiveStatsCardStyle()
    }

    // MARK: - Slots Section

    private var slotsSection: some View {
        VStack(spacing: 0) {
            slotRow(slot: 1, current: selectedStat1)

            Divider()
                .background(Color.white.opacity(0.1))

            slotRow(slot: 2, current: selectedStat2)
        }
        .background {
            if #available(iOS 26, *) {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
            } else {
                RoundedRectangle(cornerRadius: 16).fill(Color.cardBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func slotRow(slot: Int, current: StatType) -> some View {
        let slotLabel = slot == 1
            ? String(localized: "stats.settings.slot1")
            : String(localized: "stats.settings.slot2")

        return Button {
            editingSlot = slot
        } label: {
            HStack(spacing: 12) {
                Text(slotLabel)
                    .foregroundStyle(.white)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: current.icon)
                        .foregroundStyle(current.iconColor)

                    Text(current.localizedLabel)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.2))
                .clipShape(Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Firebase Sync

    private func syncToFirebase() {
        FirebaseSyncService.shared.syncUserPreferences(
            selectedStat1: selectedStat1RawValue,
            selectedStat2: selectedStat2RawValue
        )
    }

    // MARK: - Stat Computation

    private var thirtyDaysAgo: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }

    private var allRecentPackages: [Package] {
        packages.filter { package in
            if let latestEventTime = package.latestEventTimestamp {
                return latestEventTime > thirtyDaysAgo
            }
            return package.lastUpdated > thirtyDaysAgo
        }
    }

    private func computeStatValue(_ type: StatType) -> StatValue {
        let calendar = Calendar.current
        let now = Date()

        switch type {
        case .pendingPickup:
            return .integer(packages.filter { $0.status.isPendingPickup }.count)

        case .deliveredLast30Days:
            return .integer(allRecentPackages.filter { $0.status == .delivered }.count)

        case .thisMonthSpending:
            let total = packages
                .filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
                .compactMap(\.amount)
                .reduce(0, +)
            return .currency(total)

        case .pendingAmount:
            let total = packages
                .filter { $0.status.isPendingPickup }
                .compactMap(\.amount)
                .reduce(0, +)
            return .currency(total)

        case .last30DaysSpending:
            let total = allRecentPackages
                .compactMap(\.amount)
                .reduce(0, +)
            return .currency(total)

        case .thisMonthDelivered:
            let count = packages.filter {
                $0.status == .delivered &&
                calendar.isDate($0.lastUpdated, equalTo: now, toGranularity: .month)
            }.count
            return .integer(count)

        case .inTransit:
            let count = packages.filter {
                $0.status == .shipped || $0.status == .inTransit
            }.count
            return .integer(count)

        case .avgDeliveryDays:
            let delivered = allRecentPackages.filter { $0.status == .delivered }
            let days = delivered.compactMap { pkg -> Int? in
                guard let start = pkg.orderCreatedTimestamp,
                      let end = pkg.pickupEventTimestamp ?? pkg.latestEventTimestamp,
                      let d = calendar.dateComponents([.day], from: start, to: end).day,
                      d >= 0 else { return nil }
                return d
            }
            guard !days.isEmpty else { return .days(-1) }
            return .days(Double(days.reduce(0, +)) / Double(days.count))

        case .spendingDelta:
            let thisMonth = packages
                .filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month) }
                .compactMap(\.amount)
                .reduce(0, +)
            let lastMonth: Double = {
                guard let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now) else { return 0 }
                return packages
                    .filter { calendar.isDate($0.createdAt, equalTo: lastMonthDate, toGranularity: .month) }
                    .compactMap(\.amount)
                    .reduce(0, +)
            }()
            return .delta(current: thisMonth, previous: lastMonth)

        case .codPendingAmount:
            let total = packages
                .filter { $0.status.isPendingPickup && $0.paymentMethod == .cod }
                .compactMap(\.amount)
                .reduce(0, +)
            return .currency(total)
        }
    }
}

// MARK: - Stat Picker Sheet

/// 半高 Sheet：選擇統計項目
struct StatPickerSheet: View {
    let slot: Int
    let selectedStat1: StatType
    let selectedStat2: StatType
    let isPro: Bool
    let onSelect: (StatType) -> Void
    let onShowPaywall: () -> Void

    @ObservedObject private var themeManager = ThemeManager.shared

    private var currentSelection: StatType {
        slot == 1 ? selectedStat1 : selectedStat2
    }

    private var otherSelection: StatType {
        slot == 1 ? selectedStat2 : selectedStat1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(StatType.allCases.enumerated()), id: \.element.id) { index, statType in
                        optionRow(statType: statType)

                        if index < StatType.allCases.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.1))
                        }
                    }
                }
                .background {
                    if #available(iOS 26, *) {
                        RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                    } else {
                        RoundedRectangle(cornerRadius: 16).fill(Color.cardBackground)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding()
            }
            .adaptiveBackground()
            .navigationTitle(
                slot == 1
                    ? String(localized: "stats.settings.slot1")
                    : String(localized: "stats.settings.slot2")
            )
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private func optionRow(statType: StatType) -> some View {
        let isSelected = statType == currentSelection
        let isOtherSlot = statType == otherSelection
        let isLocked = !isPro && !isSelected && !isOtherSlot

        return Button {
            if isLocked {
                onShowPaywall()
            } else {
                onSelect(statType)
            }
        } label: {
            HStack(spacing: 16) {
                // 圖示圓圈
                Circle()
                    .fill(statType.iconColor.opacity(isLocked ? 0.1 : 0.2))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: statType.icon)
                            .font(.body)
                            .foregroundStyle(isLocked ? statType.iconColor.opacity(0.5) : statType.iconColor)
                    }
                    .overlay {
                        if isLocked {
                            Circle()
                                .fill(.black.opacity(0.3))
                        }
                    }

                // 名稱
                Text(statType.localizedLabel)
                    .font(.body)
                    .foregroundStyle(isLocked ? Color.secondary : Color.white)

                Spacer()

                if isOtherSlot {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isLocked {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                        Image(systemName: "crown.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(.yellow.opacity(0.7))
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(themeManager.currentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Int + Identifiable (for sheet item)

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StatSettingsView()
    }
}
