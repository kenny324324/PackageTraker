import SwiftUI
import SwiftData

/// 歷史記錄頁面
struct HistoryView: View {
    @Query(filter: #Predicate<Package> { $0.isArchived || $0.statusRawValue == "delivered" })
    private var packages: [Package]
    
    @State private var selectedPackage: Package?
    
    /// 按訂單成立時間排序（由新到舊）
    private var sortedPackages: [Package] {
        packages.sorted { pkg1, pkg2 in
            let time1 = pkg1.orderCreatedTimestamp ?? pkg1.createdAt
            let time2 = pkg2.orderCreatedTimestamp ?? pkg2.createdAt
            return time1 > time2
        }
    }

    /// 依通路分組（保持訂單成立時間排序）
    private var groupedByCarrier: [Carrier: [Package]] {
        Dictionary(grouping: sortedPackages) { $0.carrier }
    }

    /// 排序後的通路列表（依包裹數量排序）
    private var sortedCarriers: [Carrier] {
        groupedByCarrier.keys.sorted { carrier1, carrier2 in
            (groupedByCarrier[carrier1]?.count ?? 0) > (groupedByCarrier[carrier2]?.count ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if packages.isEmpty {
                    emptyView
                } else {
                    packageList
                }
            }
            .adaptiveBackground()
            .navigationTitle(String(localized: "history.title"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .sheet(item: $selectedPackage) { package in
                PackageDetailView(package: package)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var packageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(sortedCarriers, id: \.self) { carrier in
                    if let carrierPackages = groupedByCarrier[carrier] {
                        VStack(alignment: .leading, spacing: 12) {
                            // 通路標題（含 logo）
                            carrierHeader(carrier: carrier, packages: carrierPackages)

                            // 卡片式列表（最多顯示 3 筆）
                            VStack(spacing: 0) {
                                let displayPackages = Array(carrierPackages.prefix(3))
                                ForEach(Array(displayPackages.enumerated()), id: \.element.id) { index, package in
                                    historyRow(package: package)
                                    
                                    // 分隔線（最後一項不加）
                                    if index < displayPackages.count - 1 {
                                        Divider()
                                            .padding(.leading, 68)
                                    }
                                }
                            }
                            .background(Color.secondaryCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func historyRow(package: Package) -> some View {
        Button {
            selectedPackage = package
        } label: {
            HStack(spacing: 12) {
                CarrierLogoView(carrier: package.carrier, size: 44)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.customName ?? package.carrier.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(package.trackingNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    StatusIconBadge(status: package.status)
                    
                    Text(package.formattedOrderCreatedTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func carrierHeader(carrier: Carrier, packages: [Package]) -> some View {
        if packages.count > 3 {
            // 超過 3 筆，顯示可點擊的標題帶箭頭
            NavigationLink(destination: CarrierHistoryView(carrier: carrier, packages: packages)) {
                HStack(spacing: 6) {
                    CarrierLogoView(carrier: carrier, size: 24)

                    Text(carrier.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } else {
            // 不足 3 筆，顯示普通標題
            HStack(spacing: 6) {
                CarrierLogoView(carrier: carrier, size: 24)

                Text(carrier.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(String(localized: "history.empty"), systemImage: "archivebox")
        } description: {
            Text(String(localized: "history.emptyDesc"))
        }
    }
}

// MARK: - Previews

#Preview {
    HistoryView()
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
