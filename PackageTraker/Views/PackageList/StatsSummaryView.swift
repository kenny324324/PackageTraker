import SwiftUI

/// 頂部統計摘要視圖
struct StatsSummaryView: View {
    let stat1: (type: StatType, value: StatValue)
    let stat2: (type: StatType, value: StatValue)
    var onStat1Tap: (() -> Void)? = nil
    var onStat2Tap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            StatCard(
                icon: stat1.type.icon,
                iconColor: stat1.type.iconColor,
                displayValue: stat1.value,
                label: stat1.type.localizedLabel,
                onTap: onStat1Tap
            )

            StatCard(
                icon: stat2.type.icon,
                iconColor: stat2.type.iconColor,
                displayValue: stat2.value,
                label: stat2.type.localizedLabel,
                onTap: onStat2Tap
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 單一統計卡片
struct StatCard: View {
    let icon: String
    let iconColor: Color
    let displayValue: StatValue
    let label: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
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

                // 第二行：數值
                if displayValue.isInteger {
                    RollingNumberView.statsStyle(value: displayValue.integerValue)
                } else {
                    Text(displayValue.displayString)
                        .font(.system(size: 28, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(displayValue.deltaColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .adaptiveStatsCardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview {
    VStack {
        StatsSummaryView(
            stat1: (.pendingPickup, .integer(10)),
            stat2: (.deliveredLast30Days, .integer(20))
        )

        StatsSummaryView(
            stat1: (.thisMonthSpending, .currency(12345)),
            stat2: (.avgDeliveryDays, .days(3.2))
        )

        StatsSummaryView(
            stat1: (.codPendingAmount, .currency(500)),
            stat2: (.spendingDelta, .delta(current: 5000, previous: 3000))
        )
    }
    .padding()
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
