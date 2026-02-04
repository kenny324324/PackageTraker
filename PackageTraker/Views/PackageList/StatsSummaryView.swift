import SwiftUI

/// 頂部統計摘要視圖
struct StatsSummaryView: View {
    let pendingCount: Int
    let deliveredThisMonth: Int

    var body: some View {
        HStack(spacing: 12) {
            // 待取件
            StatCard(
                icon: "shippingbox.fill",
                iconColor: .orange,
                value: pendingCount,
                label: String(localized: "home.pending")
            )

            // 近 30 天已取
            StatCard(
                icon: "checkmark.rectangle.stack.fill",
                iconColor: .green,
                value: deliveredThisMonth,
                label: String(localized: "home.delivered30")
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 單一統計卡片
struct StatCard: View {
    let icon: String
    let iconColor: Color
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：圖示 + 標籤
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(iconColor)
                
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            // 第二行：數值（滾動動畫）
            RollingNumberView.statsStyle(value: value)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .adaptiveStatsCardStyle()
    }
}

// MARK: - Previews

#Preview {
    VStack {
        StatsSummaryView(pendingCount: 10, deliveredThisMonth: 20)
    }
    .padding()
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
