import SwiftUI

/// 每月消費趨勢 Bar Chart
struct MonthlySpendingTrendView: View {
    let trend: [(month: Date, amount: Double)]
    @Binding var selectedMonth: Date?

    @ObservedObject private var themeManager = ThemeManager.shared

    private var maxAmount: Double {
        trend.map(\.amount).max() ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(trend, id: \.month) { item in
                spendingBar(item: item)
            }
        }
        .frame(height: 180)
        .adaptiveCardStyle()
    }

    private func spendingBar(item: (month: Date, amount: Double)) -> some View {
        let isCurrentMonth = Calendar.current.isDate(item.month, equalTo: Date(), toGranularity: .month)
        let barRatio = maxAmount > 0 ? CGFloat(item.amount) / CGFloat(maxAmount) : 0

        return Button {
            if item.amount > 0 {
                selectedMonth = item.month
            }
        } label: {
            VStack(spacing: 6) {
                if item.amount > 0 {
                    Text(shortCurrency(item.amount))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrentMonth ? themeManager.currentColor : themeManager.currentColor.opacity(0.4))
                    .frame(height: max(barRatio * 120, item.amount > 0 ? 8 : 2))
                    .frame(maxWidth: .infinity)

                Text(item.month.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(item.amount == 0)
    }

    private func shortCurrency(_ value: Double) -> String {
        if value >= 10000 {
            return String(format: "$%.0fk", value / 1000)
        } else if value >= 1000 {
            return String(format: "$%.1fk", value / 1000)
        } else {
            return String(format: "$%.0f", value)
        }
    }
}
