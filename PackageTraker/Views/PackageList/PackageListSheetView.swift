import SwiftUI

/// 包裹列表 Sheet（用於統計卡片點擊後顯示）
/// 顯示風格與歷史記錄頁面一致
struct PackageListSheetView: View {
    let title: String
    let packages: [Package]

    @State private var selectedPackage: Package?

    /// 依通路分組
    private var groupedByCarrier: [Carrier: [Package]] {
        Dictionary(grouping: packages) { $0.carrier }
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
                    ContentUnavailableView {
                        Label(String(localized: "sheet.empty"), systemImage: "shippingbox")
                    }
                } else {
                    packageList
                }
            }
            .adaptiveBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
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
                            // 通路標題
                            HStack(spacing: 6) {
                                CarrierLogoView(carrier: carrier, size: 24)

                                Text(carrier.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }

                            // 卡片式列表
                            VStack(spacing: 0) {
                                ForEach(Array(carrierPackages.enumerated()), id: \.element.id) { index, package in
                                    packageRow(package: package)

                                    if index < carrierPackages.count - 1 {
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

    private func packageRow(package: Package) -> some View {
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
}
