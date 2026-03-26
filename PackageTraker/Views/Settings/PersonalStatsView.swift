import SwiftUI
import SwiftData

/// 個人統計儀表板
struct PersonalStatsView: View {
    @Query private var allPackages: [Package]

    // MARK: - Computed Properties

    private var activeCount: Int {
        allPackages.filter { !$0.isArchived }.count
    }

    private var carrierRanking: [(carrier: Carrier, count: Int)] {
        let grouped = Dictionary(grouping: allPackages) { $0.carrier }
        return grouped
            .map { (carrier: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    private var monthlyTrend: [(month: Date, count: Int)] {
        let calendar = Calendar.current
        let now = Date()

        // 建立最近 6 個月的起始日
        var months: [Date] = []
        for i in (0..<6).reversed() {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                let components = calendar.dateComponents([.year, .month], from: date)
                if let monthStart = calendar.date(from: components) {
                    months.append(monthStart)
                }
            }
        }

        // 統計每月包裹數
        let grouped = Dictionary(grouping: allPackages) { package -> Date in
            let components = calendar.dateComponents([.year, .month], from: package.createdAt)
            return calendar.date(from: components) ?? package.createdAt
        }

        return months.map { month in
            (month: month, count: grouped[month]?.count ?? 0)
        }
    }

    private var maxMonthlyCount: Int {
        monthlyTrend.map(\.count).max() ?? 1
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            if allPackages.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 24) {
                    overviewSection
                    carrierRankingSection
                    monthlyTrendSection
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(String(localized: "stats.personal.title"))
        .adaptiveGradientBackground()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(String(localized: "stats.personal.empty"), systemImage: "chart.bar.fill")
        }
        .foregroundStyle(.secondary)
        .padding(.top, 100)
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        HStack(spacing: 12) {
            StatCard(
                icon: "shippingbox.fill",
                iconColor: .blue,
                value: allPackages.count,
                label: String(localized: "stats.personal.totalPackages")
            )

            StatCard(
                icon: "clock.fill",
                iconColor: .orange,
                value: activeCount,
                label: String(localized: "stats.personal.activePackages")
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Carrier Ranking Section

    private var carrierRankingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "stats.personal.topCarriers"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                ForEach(Array(carrierRanking.enumerated()), id: \.element.carrier) { index, item in
                    carrierRow(rank: index + 1, carrier: item.carrier, count: item.count)

                    if index < carrierRanking.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.06))
                            .padding(.leading, 60)
                    }
                }
            }
            .adaptiveCardStyle()
        }
    }

    private func carrierRow(rank: Int, carrier: Carrier, count: Int) -> some View {
        let maxCount = carrierRanking.first?.count ?? 1
        let ratio = CGFloat(count) / CGFloat(maxCount)

        return HStack(spacing: 12) {
            // 排名
            Text("\(rank)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            // Logo
            CarrierLogoView(carrier: carrier, size: 36)

            // 名稱 + 比例條
            VStack(alignment: .leading, spacing: 6) {
                Text(carrier.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(carrier.brandColor == .white ? Color.appAccent : carrier.brandColor)
                        .frame(width: geo.size.width * ratio, height: 6)
                }
                .frame(height: 6)
            }

            Spacer()

            // 數量
            Text("\(count)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
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
    }

    private func monthBar(item: (month: Date, count: Int)) -> some View {
        let isCurrentMonth = Calendar.current.isDate(item.month, equalTo: Date(), toGranularity: .month)
        let barRatio = maxMonthlyCount > 0 ? CGFloat(item.count) / CGFloat(maxMonthlyCount) : 0

        return VStack(spacing: 6) {
            // 數量標籤
            if item.count > 0 {
                Text("\(item.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // 長條
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrentMonth ? Color.appAccent : Color.appAccent.opacity(0.4))
                .frame(height: max(barRatio * 120, item.count > 0 ? 8 : 2))
                .frame(maxWidth: .infinity)

            // 月份
            Text(item.month.formatted(.dateTime.month(.abbreviated)))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        PersonalStatsView()
    }
    .preferredColorScheme(.dark)
}
