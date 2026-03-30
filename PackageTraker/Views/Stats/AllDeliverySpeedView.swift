import SwiftUI

/// 全部物流商配送速度頁面
struct AllDeliverySpeedView: View {
    let data: [(carrier: Carrier, avgDays: Double)]

    @ObservedObject private var themeManager = ThemeManager.shared

    private var maxDays: Double {
        data.map(\.avgDays).max() ?? 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(data.enumerated()), id: \.element.carrier) { index, item in
                    speedRow(rank: index + 1, carrier: item.carrier, avgDays: item.avgDays)

                    if index < data.count - 1 {
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
        .navigationTitle(String(localized: "stats.delivery.speed.title"))
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveGradientBackground()
    }

    private func speedRow(rank: Int, carrier: Carrier, avgDays: Double) -> some View {
        let ratio = maxDays > 0 ? CGFloat(avgDays) / CGFloat(maxDays) : 0

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
                        .fill(speedColor(days: avgDays))
                        .frame(width: max(geo.size.width * ratio, 4), height: 6)
                }
                .frame(height: 6)
            }

            Spacer()

            Text(String(localized: "stats.delivery.speed.days.\(String(format: "%.1f", avgDays))"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 10)
    }

    private func speedColor(days: Double) -> Color {
        if days <= 2 { return .green }
        if days <= 5 { return .yellow }
        return .orange
    }
}
