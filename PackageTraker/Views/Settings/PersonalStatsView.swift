import SwiftUI
import SwiftData

/// 個人統計儀表板
struct PersonalStatsView: View {
    @Query private var allPackages: [Package]
    @ObservedObject private var appStats = AppStatsService.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var selectedCarrier: Carrier?
    @State private var selectedMonth: Date?
    @State private var selectedSpendingMonth: Date?
    @State private var selectedPlatform: String?
    @State private var selectedSpendingCarrier: Carrier?

    // MARK: - Computed Properties

    private var carrierRanking: [(carrier: Carrier, count: Int)] {
        let grouped = Dictionary(grouping: allPackages) { $0.carrier }
        return grouped
            .map { (carrier: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map { $0 }
    }

    private var monthlyTrend: [(month: Date, count: Int)] {
        let calendar = Calendar.current
        let now = Date()
        var months: [Date] = []
        for i in (0..<6).reversed() {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                let comp = calendar.dateComponents([.year, .month], from: date)
                if let monthStart = calendar.date(from: comp) {
                    months.append(monthStart)
                }
            }
        }
        let grouped = Dictionary(grouping: allPackages) { package -> Date in
            let comp = calendar.dateComponents([.year, .month], from: package.createdAt)
            return calendar.date(from: comp) ?? package.createdAt
        }
        return months.map { month in (month: month, count: grouped[month]?.count ?? 0) }
    }

    private var maxMonthlyCount: Int {
        monthlyTrend.map(\.count).max() ?? 1
    }

    // MARK: - Highlight Data

    /// 真實百分位排名（從 Firestore 門檻值比對）
    private var realPercentile: Int? {
        guard appStats.isLoaded else { return nil }
        return appStats.percentile(for: allPackages.count)
    }

    private var favoriteCarrier: (carrier: Carrier, percent: Int)? {
        guard let top = carrierRanking.first, allPackages.count > 0 else { return nil }
        let percent = Int(round(Double(top.count) / Double(allPackages.count) * 100))
        return (top.carrier, percent)
    }

    private var peakMonth: (month: Date, count: Int)? {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allPackages) { package -> Date in
            let comp = calendar.dateComponents([.year, .month], from: package.createdAt)
            return calendar.date(from: comp) ?? package.createdAt
        }
        return grouped
            .map { (month: $0.key, count: $0.value.count) }
            .max { $0.count < $1.count }
    }

    private var trackingDays: Int? {
        guard let earliest = allPackages.map(\.createdAt).min() else { return nil }
        return Calendar.current.dateComponents([.day], from: earliest, to: Date()).day
    }

    // MARK: - Spending Computed Properties

    private var packagesWithAmount: [Package] {
        allPackages.filter { $0.amount != nil && $0.amount! > 0 }
    }

    private var currentMonthSpending: Double {
        let calendar = Calendar.current
        return packagesWithAmount
            .filter { calendar.isDate($0.createdAt, equalTo: Date(), toGranularity: .month) }
            .compactMap(\.amount)
            .reduce(0, +)
    }

    private var lastMonthSpending: Double {
        let calendar = Calendar.current
        guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date()) else { return 0 }
        return packagesWithAmount
            .filter { calendar.isDate($0.createdAt, equalTo: lastMonth, toGranularity: .month) }
            .compactMap(\.amount)
            .reduce(0, +)
    }

    private var monthlySpendingTrend: [(month: Date, amount: Double)] {
        let calendar = Calendar.current
        let now = Date()
        var months: [Date] = []
        for i in (0..<6).reversed() {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                let comp = calendar.dateComponents([.year, .month], from: date)
                if let monthStart = calendar.date(from: comp) {
                    months.append(monthStart)
                }
            }
        }
        let grouped = Dictionary(grouping: packagesWithAmount) { package -> Date in
            let comp = calendar.dateComponents([.year, .month], from: package.createdAt)
            return calendar.date(from: comp) ?? package.createdAt
        }
        return months.map { month in
            let amount = grouped[month]?.compactMap(\.amount).reduce(0, +) ?? 0
            return (month: month, amount: amount)
        }
    }

    private var platformSpendingRanking: [(platform: String, amount: Double, count: Int)] {
        let otherLabel = String(localized: "stats.spending.platform.other")
        let grouped = Dictionary(grouping: packagesWithAmount) { $0.purchasePlatform ?? otherLabel }
        let all = grouped.map { (platform: $0.key, amount: $0.value.compactMap(\.amount).reduce(0, +), count: $0.value.count) }
            .sorted { $0.amount > $1.amount }

        if all.count <= 6 { return all }

        let top5 = Array(all.prefix(5))
        let rest = all.dropFirst(5)
        let otherAmount = rest.map(\.amount).reduce(0, +)
        let otherCount = rest.map(\.count).reduce(0, +)
        return top5 + [(platform: otherLabel, amount: otherAmount, count: otherCount)]
    }

    private var carrierSpendingRanking: [(carrier: Carrier, amount: Double)] {
        let grouped = Dictionary(grouping: packagesWithAmount) { $0.carrier }
        return grouped
            .map { (carrier: $0.key, amount: $0.value.compactMap(\.amount).reduce(0, +)) }
            .sorted { $0.amount > $1.amount }
            .prefix(3)
            .map { $0 }
    }

    private var allDeliverySpeedByCarrier: [(carrier: Carrier, avgDays: Double)] {
        let calendar = Calendar.current
        let delivered = allPackages.filter { $0.status == .delivered }

        var carrierDays: [Carrier: [Int]] = [:]
        for package in delivered {
            guard let start = package.orderCreatedTimestamp else { continue }
            let end = package.pickupEventTimestamp ?? package.latestEventTimestamp
            guard let endDate = end,
                  let startDay = calendar.dateInterval(of: .day, for: start)?.start,
                  let endDay = calendar.dateInterval(of: .day, for: endDate)?.start,
                  let days = calendar.dateComponents([.day], from: startDay, to: endDay).day,
                  days >= 0 else { continue }
            carrierDays[package.carrier, default: []].append(days)
        }

        return carrierDays
            .map { carrier, days in
                let avg = Double(days.reduce(0, +)) / Double(days.count)
                return (carrier: carrier, avgDays: avg)
            }
            .sorted { $0.avgDays < $1.avgDays }
    }

    private var deliverySpeedByCarrier: [(carrier: Carrier, avgDays: Double)] {
        Array(allDeliverySpeedByCarrier.prefix(3))
    }

    /// 全部物流商消費排行（不截斷）
    private var allCarrierSpendingRanking: [(carrier: Carrier, amount: Double)] {
        let grouped = Dictionary(grouping: packagesWithAmount) { $0.carrier }
        return grouped
            .map { (carrier: $0.key, amount: $0.value.compactMap(\.amount).reduce(0, +)) }
            .sorted { $0.amount > $1.amount }
    }

    // MARK: - Body

    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            if allPackages.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 24) {
                    PackageJarView(carriers: Array(allPackages.prefix(30).map(\.carrier)))

                    // Pro upsell banner（免費用戶）
                    if !SubscriptionManager.shared.isPro {
                        ProNudgeBanner(
                            message: String(localized: "stats.proNudge.message"),
                            icon: "crown.fill",
                            style: .info,
                            dismissible: false,
                            onUpgrade: { showPaywall = true }
                        )
                    }

                    highlightsSection
                    carrierRankingSection
                    monthlyTrendSection

                    // MARK: Pro 消費分析
                    spendingAnalyticsSection
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(trigger: .spending)
        }
        .navigationTitle(String(localized: "stats.personal.title"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .adaptiveGradientBackground()
        .task {
            if !appStats.isLoaded {
                await appStats.fetchStats()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(String(localized: "stats.personal.empty"), systemImage: "chart.bar.fill")
        }
        .foregroundStyle(.secondary)
        .padding(.top, 100)
    }

    // MARK: - Highlights Section

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "stats.highlight.title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            // 爆點 Banner：超越 X% 用戶（≥ 85% 才顯示）
            if let percentile = realPercentile, percentile >= 85 {
                percentileBanner(percentile: percentile)
            }

            // 水平滑動卡片
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // 最愛物流商
                    if let fav = favoriteCarrier {
                        favoriteCarrierCard(carrier: fav.carrier)
                    }

                    // 收貨高峰
                    if let peak = peakMonth, peak.count > 1 {
                        peakMonthCard(month: peak.month, count: peak.count)
                    }

                    // 追蹤天數
                    if let days = trackingDays, days > 0 {
                        trackingDaysCard(days: days)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    /// 爆點卡片：你已超越 XX% 的使用者！
    @State private var displayedPercentile: Int = 0
    @State private var hasAnimatedPercentile = false

    private func percentileBanner(percentile: Int) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(String(localized: "stats.highlight.bannerPrefix"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize()

                Text("\(displayedPercentile)")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(themeManager.currentColor)
                    .contentTransition(.numericText(countsDown: false))
                    .frame(width: 68, alignment: .center)

                Text(String(localized: "stats.highlight.bannerSuffix"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(themeManager.currentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(themeManager.currentColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: themeManager.currentColor.opacity(0.5), radius: 12, x: 0, y: 0)
        .shadow(color: themeManager.currentColor.opacity(0.2), radius: 30, x: 0, y: 4)
        .onAppear {
            guard !hasAnimatedPercentile else { return }
            hasAnimatedPercentile = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 1.2)) {
                    displayedPercentile = percentile
                }
            }
        }
        .onChange(of: percentile) { _, newValue in
            withAnimation(.easeOut(duration: 0.6)) {
                displayedPercentile = newValue
            }
        }
    }

    /// 最愛物流商卡片（品牌色背景 + 上方深色漸層）
    private func favoriteCarrierCard(carrier: Carrier) -> some View {
        let bgColor = carrier.brandColor == .white ? Color.gray : carrier.brandColor

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))

                Text(String(localized: "stats.highlight.favoriteCarrier"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .zIndex(1)

            Spacer()

            HStack {
                Spacer()
                CarrierLogoView(carrier: carrier, size: 44)
            }
        }
        .frame(width: 150, height: 75)
        .padding(16)
        .background(
            ZStack {
                bgColor.opacity(0.35)

                // 上方深色漸層，讓標題看得清
                LinearGradient(
                    colors: [Color.black.opacity(0.3), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 收貨高峰卡片
    private func peakMonthCard(month: Date, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentColor)

                Text(String(localized: "stats.highlight.peakMonth"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(month.formatted(.dateTime.year().month(.wide)))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(String(localized: "stats.highlight.peakMonthCount.\(count)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 150, height: 75)
        .adaptiveStatsCardStyle()
    }

    /// 追蹤天數卡片
    private func trackingDaysCard(days: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentColor)

                Text(String(localized: "stats.highlight.trackingDays"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(days)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(String(localized: "stats.highlight.dayUnit"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 150, height: 75)
        .adaptiveStatsCardStyle()
    }

    // MARK: - Carrier Ranking Section

    private var carrierRankingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "stats.personal.topCarriers"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Spacer()

                NavigationLink {
                    AllCarriersStatsView()
                } label: {
                    HStack(spacing: 4) {
                        Text(String(localized: "stats.personal.viewAll"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(carrierRanking.enumerated()), id: \.element.carrier) { index, item in
                    Button {
                        selectedCarrier = item.carrier
                    } label: {
                        carrierRow(rank: index + 1, carrier: item.carrier, count: item.count)
                    }
                    .buttonStyle(.plain)

                    if index < carrierRanking.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.06))
                            .padding(.leading, 60)
                    }
                }
            }
            .adaptiveCardStyle()
        }
        .sheet(item: $selectedCarrier) { carrier in
            CarrierPackagesSheet(carrier: carrier, allPackages: allPackages)
        }
    }

    private func carrierRow(rank: Int, carrier: Carrier, count: Int) -> some View {
        let maxCount = carrierRanking.first?.count ?? 1
        let ratio = CGFloat(count) / CGFloat(maxCount)

        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            CarrierLogoView(carrier: carrier, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                Text(carrier.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(themeManager.currentColor)
                        .frame(width: geo.size.width * ratio, height: 6)
                }
                .frame(height: 6)
            }

            Spacer()

            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Monthly Trend Section

    private var monthlyTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "stats.personal.monthlyTrend"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(monthlyTrend, id: \.month) { item in
                    monthBar(item: item)
                }
            }
            .frame(height: 180)
            .adaptiveCardStyle()
        }
        .sheet(item: $selectedMonth) { month in
            MonthPackagesSheet(month: month, allPackages: allPackages)
        }
    }

    private func monthBar(item: (month: Date, count: Int)) -> some View {
        let isCurrentMonth = Calendar.current.isDate(item.month, equalTo: Date(), toGranularity: .month)
        let barRatio = maxMonthlyCount > 0 ? CGFloat(item.count) / CGFloat(maxMonthlyCount) : 0

        return Button {
            if item.count > 0 {
                selectedMonth = item.month
            }
        } label: {
            VStack(spacing: 6) {
                if item.count > 0 {
                    Text("\(item.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }

                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrentMonth ? themeManager.currentColor : themeManager.currentColor.opacity(0.4))
                    .frame(height: max(barRatio * 120, item.count > 0 ? 8 : 2))
                    .frame(maxWidth: .infinity)

                Text(item.month.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(item.count == 0)
    }

    // MARK: - Spending Analytics Section (Pro)

    private var spendingAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "stats.spending.title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            // 1. 本月消費 Highlight
            SpendingHighlightCard(
                currentMonthSpending: currentMonthSpending,
                lastMonthSpending: lastMonthSpending
            )
            .proStatsOverlay()

            // 2. 每月消費趨勢
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "stats.spending.trend.title"))
                    .font(.headline)
                    .foregroundStyle(.white)

                MonthlySpendingTrendView(
                    trend: monthlySpendingTrend,
                    selectedMonth: $selectedSpendingMonth
                )
            }
            .proStatsOverlay()
            .sheet(item: $selectedSpendingMonth) { month in
                MonthPackagesSheet(month: month, allPackages: allPackages)
            }

            // 3. 購物平台分佈
            if !platformSpendingRanking.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "stats.spending.platform.title"))
                        .font(.headline)
                        .foregroundStyle(.white)

                    PlatformSpendingChartView(
                        data: platformSpendingRanking,
                        selectedPlatform: $selectedPlatform
                    )
                }
                .proStatsOverlay()
                .sheet(item: $selectedPlatform) { platform in
                    PlatformPackagesSheet(platform: platform, allPackages: allPackages)
                }
            }

            // 4. 物流商消費排行
            if !carrierSpendingRanking.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(String(localized: "stats.spending.carrier.title"))
                            .font(.headline)
                            .foregroundStyle(.white)

                        Spacer()

                        NavigationLink {
                            AllCarrierSpendingView(
                                ranking: allCarrierSpendingRanking,
                                allPackages: allPackages
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Text(String(localized: "stats.personal.viewAll"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                        }
                    }

                    carrierSpendingRankingView
                }
                .proStatsOverlay()
                .sheet(item: $selectedSpendingCarrier) { carrier in
                    CarrierPackagesSheet(carrier: carrier, allPackages: allPackages)
                }
            }

            // 5. 配送速度比較
            if !deliverySpeedByCarrier.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(String(localized: "stats.delivery.speed.title"))
                            .font(.headline)
                            .foregroundStyle(.white)

                        Spacer()

                        NavigationLink {
                            AllDeliverySpeedView(data: allDeliverySpeedByCarrier)
                        } label: {
                            HStack(spacing: 4) {
                                Text(String(localized: "stats.personal.viewAll"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                        }
                    }

                    DeliverySpeedView(data: deliverySpeedByCarrier)
                }
                .proStatsOverlay()
            }
        }
    }

    // MARK: - Carrier Spending Ranking View

    private var carrierSpendingRankingView: some View {
        let maxAmount = carrierSpendingRanking.first?.amount ?? 1

        return VStack(spacing: 0) {
            ForEach(Array(carrierSpendingRanking.enumerated()), id: \.element.carrier) { index, item in
                Button {
                    selectedSpendingCarrier = item.carrier
                } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        CarrierLogoView(carrier: item.carrier, size: 36)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.carrier.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(themeManager.currentColor)
                                    .frame(width: geo.size.width * CGFloat(item.amount / maxAmount), height: 6)
                            }
                            .frame(height: 6)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text(formatCurrency(item.amount))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if index < carrierSpendingRanking.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                        .padding(.leading, 60)
                }
            }
        }
        .adaptiveCardStyle()
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        PersonalStatsView()
    }
    .preferredColorScheme(.dark)
}
