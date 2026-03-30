import SwiftUI
import SwiftData

/// 全部物流商統計排名頁面
struct AllCarriersStatsView: View {
    @Query private var allPackages: [Package]
    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var selectedCarrier: Carrier?

    /// 全部物流商排名（含 0 筆），依數量降序、同數量依名稱排序
    private var allCarrierRanking: [(carrier: Carrier, count: Int)] {
        let grouped = Dictionary(grouping: allPackages) { $0.carrier }
        return Carrier.allCases.map { carrier in
            (carrier: carrier, count: grouped[carrier]?.count ?? 0)
        }
        .sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.carrier.displayName < $1.carrier.displayName
        }
    }

    private var maxCount: Int {
        allCarrierRanking.first?.count ?? 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(allCarrierRanking.enumerated()), id: \.element.carrier) { index, item in
                    Button {
                        if item.count > 0 {
                            selectedCarrier = item.carrier
                        }
                    } label: {
                        carrierRow(rank: index + 1, carrier: item.carrier, count: item.count)
                    }
                    .buttonStyle(.plain)
                    .disabled(item.count == 0)

                    if index < allCarrierRanking.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.06))
                            .padding(.leading, 60)
                    }
                }
            }
            .adaptiveCardStyle()
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle(String(localized: "stats.allCarriers.title"))
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveGradientBackground()
        .sheet(item: $selectedCarrier) { carrier in
            CarrierPackagesSheet(carrier: carrier, allPackages: allPackages)
        }
    }

    // MARK: - Carrier Row

    private func carrierRow(rank: Int, carrier: Carrier, count: Int) -> some View {
        let ratio = maxCount > 0 ? CGFloat(count) / CGFloat(max(maxCount, 1)) : 0

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
                    .foregroundStyle(count > 0 ? .white : .secondary)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(count > 0 ? themeManager.currentColor : Color.white.opacity(0.1))
                        .frame(width: count > 0 ? geo.size.width * ratio : geo.size.width * 0.02, height: 6)
                }
                .frame(height: 6)
            }

            Spacer()

            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(count > 0 ? .white : .secondary)

                if count > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Carrier Packages Sheet

/// 物流商包裹列表 Sheet（支援點進包裹詳情）
struct CarrierPackagesSheet: View {
    let carrier: Carrier
    let allPackages: [Package]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPackage: Package?

    private var carrierPackages: [Package] {
        allPackages
            .filter { $0.carrier == carrier }
            .sorted {
                let t1 = $0.orderCreatedTimestamp ?? $0.createdAt
                let t2 = $1.orderCreatedTimestamp ?? $1.createdAt
                return t1 > t2
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(carrierPackages) { package in
                        CompactPackageCard(package: package) {
                            selectedPackage = package
                        }
                    }
                }
                .padding()
            }
            .adaptiveBackground()
            .navigationTitle(carrier.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.done")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .sheet(item: $selectedPackage) { package in
                PackageDetailView(package: package)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Month Packages Sheet

/// 某月份包裹列表 Sheet
struct MonthPackagesSheet: View {
    let month: Date
    let allPackages: [Package]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPackage: Package?

    private var monthPackages: [Package] {
        let calendar = Calendar.current
        return allPackages
            .filter { calendar.isDate($0.createdAt, equalTo: month, toGranularity: .month) }
            .sorted {
                let t1 = $0.orderCreatedTimestamp ?? $0.createdAt
                let t2 = $1.orderCreatedTimestamp ?? $1.createdAt
                return t1 > t2
            }
    }

    private var sheetTitle: String {
        month.formatted(.dateTime.year().month(.wide))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(monthPackages) { package in
                        CompactPackageCard(package: package) {
                            selectedPackage = package
                        }
                    }
                }
                .padding()
            }
            .adaptiveBackground()
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.done")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .sheet(item: $selectedPackage) { package in
                PackageDetailView(package: package)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Date + Identifiable

extension Date: @retroactive Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}

// MARK: - String + Identifiable

extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        AllCarriersStatsView()
    }
    .preferredColorScheme(.dark)
    .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
