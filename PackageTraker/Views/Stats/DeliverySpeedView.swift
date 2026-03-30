import SwiftUI

/// 各物流商平均配送天數比較
struct DeliverySpeedView: View {
    let data: [(carrier: Carrier, avgDays: Double)]

    @ObservedObject private var themeManager = ThemeManager.shared

    private var maxDays: Double {
        data.map(\.avgDays).max() ?? 1
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.carrier) { index, item in
                speedRow(carrier: item.carrier, avgDays: item.avgDays)

                if index < data.count - 1 {
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                        .padding(.leading, 60)
                }
            }
        }
        .adaptiveCardStyle()
    }

    private func speedRow(carrier: Carrier, avgDays: Double) -> some View {
        let ratio = maxDays > 0 ? CGFloat(avgDays) / CGFloat(maxDays) : 0

        return HStack(spacing: 12) {
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

    /// 配送速度顏色：快 → 綠、中 → 黃、慢 → 橘
    private func speedColor(days: Double) -> Color {
        if days <= 2 { return .green }
        if days <= 5 { return .yellow }
        return .orange
    }
}
