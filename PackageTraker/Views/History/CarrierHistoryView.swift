import SwiftUI

/// 單一通路的完整歷史記錄頁面
struct CarrierHistoryView: View {
    let carrier: Carrier
    let packages: [Package]
    
    @State private var selectedPackage: Package?
    
    /// 按訂單成立時間排序（由新到舊）
    private var sortedPackages: [Package] {
        packages.sorted { pkg1, pkg2 in
            let time1 = pkg1.orderCreatedTimestamp ?? pkg1.createdAt
            let time2 = pkg2.orderCreatedTimestamp ?? pkg2.createdAt
            return time1 > time2
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(sortedPackages) { package in
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
        .preferredColorScheme(.dark)
        .sheet(item: $selectedPackage) { package in
            PackageDetailView(package: package)
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        CarrierHistoryView(
            carrier: .sevenEleven,
            packages: [
                Package(
                    trackingNumber: "TW123456789",
                    carrier: .sevenEleven,
                    customName: "蝦皮手機殼",
                    status: .delivered
                ),
                Package(
                    trackingNumber: "TW987654321",
                    carrier: .sevenEleven,
                    customName: "momo 藍牙耳機",
                    status: .delivered
                ),
                Package(
                    trackingNumber: "TW111222333",
                    carrier: .sevenEleven,
                    status: .delivered
                )
            ]
        )
    }
}
