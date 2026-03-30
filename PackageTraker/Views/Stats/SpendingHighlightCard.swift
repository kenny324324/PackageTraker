import SwiftUI

/// 本月消費 Highlight 卡片
struct SpendingHighlightCard: View {
    let currentMonthSpending: Double
    let lastMonthSpending: Double

    @ObservedObject private var themeManager = ThemeManager.shared

    private var delta: Double {
        currentMonthSpending - lastMonthSpending
    }

    private var formattedAmount: String {
        formatCurrency(currentMonthSpending)
    }

    private var deltaText: String {
        if currentMonthSpending == 0 && lastMonthSpending == 0 {
            return String(localized: "stats.spending.noData")
        }
        if delta > 0 {
            return String(localized: "stats.spending.deltaUp.\(formatCurrency(delta))")
        } else if delta < 0 {
            return String(localized: "stats.spending.deltaDown.\(formatCurrency(abs(delta)))")
        } else {
            return String(localized: "stats.spending.deltaFlat")
        }
    }

    private var deltaColor: Color {
        if delta > 0 { return .red.opacity(0.9) }
        if delta < 0 { return .green.opacity(0.9) }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "stats.spending.highlight.title"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(formattedAmount)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if currentMonthSpending > 0 || lastMonthSpending > 0 {
                Text(deltaText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(deltaColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveStatsCardStyle()
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}
