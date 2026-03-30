import SwiftUI

/// 某購物平台的包裹列表 Sheet
struct PlatformPackagesSheet: View {
    let platform: String
    let allPackages: [Package]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPackage: Package?

    private var platformPackages: [Package] {
        allPackages
            .filter { ($0.purchasePlatform ?? "") == platform }
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
                    ForEach(platformPackages) { package in
                        CompactPackageCard(package: package) {
                            selectedPackage = package
                        }
                    }
                }
                .padding()
            }
            .adaptiveBackground()
            .navigationTitle(platform)
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
