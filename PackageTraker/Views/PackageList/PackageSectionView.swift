import SwiftUI

/// 排序方式
enum PackageSortOption: String, CaseIterable {
    case addedDate
    case orderDate
    case pendingFirst
    
    var displayName: String {
        switch self {
        case .addedDate: return String(localized: "sort.addedDate")
        case .orderDate: return String(localized: "sort.orderDate")
        case .pendingFirst: return String(localized: "sort.pendingFirst")
        }
    }
}

/// 包裹分組區塊視圖（水平滾動）
struct PackageSectionView: View {
    let title: String
    let packages: [Package]
    var namespace: Namespace.ID?
    var onPackageTap: ((Package) -> Void)? = nil
    var onPackageEdit: ((Package) -> Void)? = nil
    var onPackageDelete: ((Package) -> Void)? = nil
    
    @State private var sortOption: PackageSortOption = .addedDate

    // 卡片寬度：中間值，約 250pt
    private var cardWidth: CGFloat {
        250
    }
    
    /// 根據排序方式排序/篩選後的包裹
    private var sortedPackages: [Package] {
        switch sortOption {
        case .addedDate:
            return packages.sorted { $0.createdAt > $1.createdAt }
        case .orderDate:
            return packages.sorted { 
                ($0.orderCreatedTimestamp ?? $0.createdAt) > ($1.orderCreatedTimestamp ?? $1.createdAt)
            }
        case .pendingFirst:
            // 只顯示待取貨（已到店）的包裹，按加入時間排序
            return packages
                .filter { $0.status == .arrivedAtStore }
                .sorted { $0.createdAt > $1.createdAt }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 標題列（保持 padding）
            HStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                Text("(\(packages.count))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()
                
                // 排序選擇
                Menu {
                    ForEach(PackageSortOption.allCases, id: \.self) { option in
                        Button {
                            sortOption = option
                        } label: {
                            if sortOption == option {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } label: {
                    Text(sortOption.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)

            // 包裹卡片 - 水平滾動（內容頭尾有 padding，可滑到邊緣）
            if sortedPackages.isEmpty {
                emptyView
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(sortedPackages) { package in
                            PackageCardView(
                                package: package,
                                namespace: namespace,
                                onTap: { onPackageTap?(package) },
                                onEdit: { onPackageEdit?(package) },
                                onDelete: { onPackageDelete?(package) }
                            )
                            .frame(width: cardWidth)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12) // 為 liquid glass 按壓效果和光暈預留空間
                }
            }
        }
    }

    private var emptyView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(String(localized: "section.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 32)
            Spacer()
        }
        .adaptiveSecondaryCardStyle()
    }
}

// MARK: - Previews

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            PackageSectionView(
                title: "媽媽驛站",
                packages: [
                    Package(
                        trackingNumber: "SF1234567890",
                        carrier: .sfExpress,
                        pickupCode: "6-5-29-14",
                        pickupLocation: "媽媽驛站",
                        status: .arrivedAtStore
                    ),
                    Package(
                        trackingNumber: "TW268979373141Z",
                        carrier: .sevenEleven,
                        pickupCode: "2-4-2-17",
                        pickupLocation: "媽媽驛站",
                        status: .arrivedAtStore
                    ),
                    Package(
                        trackingNumber: "HCT123456789",
                        carrier: .hct,
                        pickupCode: "3-8-15-22",
                        pickupLocation: "媽媽驛站",
                        status: .arrivedAtStore
                    )
                ]
            )

            PackageSectionView(
                title: "其他驛站",
                packages: [
                    Package(
                        trackingNumber: "YT1234567890",
                        carrier: .cainiao,
                        pickupCode: "3-7-29-29",
                        pickupLocation: "其他驛站",
                        status: .arrivedAtStore
                    )
                ]
            )
        }
        .padding()
    }
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
