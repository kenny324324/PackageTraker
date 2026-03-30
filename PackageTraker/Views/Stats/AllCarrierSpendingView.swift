import SwiftUI
import SwiftData

/// 全部物流商消費排行頁面
struct AllCarrierSpendingView: View {
    let ranking: [(carrier: Carrier, amount: Double)]
    let allPackages: [Package]

    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var selectedCarrier: Carrier?

    private var maxAmount: Double {
        ranking.first?.amount ?? 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(ranking.enumerated()), id: \.element.carrier) { index, item in
                    Button {
                        if item.amount > 0 {
                            selectedCarrier = item.carrier
                        }
                    } label: {
                        spendingRow(rank: index + 1, carrier: item.carrier, amount: item.amount)
                    }
                    .buttonStyle(.plain)
                    .disabled(item.amount == 0)

                    if index < ranking.count - 1 {
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
        .navigationTitle(String(localized: "stats.spending.carrier.title"))
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveGradientBackground()
        .sheet(item: $selectedCarrier) { carrier in
            CarrierPackagesSheet(carrier: carrier, allPackages: allPackages)
        }
    }

    private func spendingRow(rank: Int, carrier: Carrier, amount: Double) -> some View {
        let ratio = maxAmount > 0 ? CGFloat(amount) / CGFloat(max(maxAmount, 1)) : 0

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
                    .foregroundStyle(amount > 0 ? .white : .secondary)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(amount > 0 ? themeManager.currentColor : Color.white.opacity(0.1))
                        .frame(width: amount > 0 ? geo.size.width * ratio : geo.size.width * 0.02, height: 6)
                }
                .frame(height: 6)
            }

            Spacer()

            HStack(spacing: 4) {
                Text(formatCurrency(amount))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(amount > 0 ? .white : .secondary)

                if amount > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}
