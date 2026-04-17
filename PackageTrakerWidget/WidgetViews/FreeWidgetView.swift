//
//  FreeWidgetView.swift
//  PackageTrakerWidget
//
//  Free tier widget (small only): two configurable stat cards.
//  Default: pendingPickup + deliveredLast30Days. Pro stats show lock overlay for free users.
//

import SwiftUI
import WidgetKit

struct FreeWidgetView: View {
    let entry: PackageTimelineEntry
    let topStat: FreeWidgetStatType
    let bottomStat: FreeWidgetStatType

    private let widgetPadding: CGFloat = 8

    var body: some View {
        VStack(spacing: widgetPadding) {
            statCard(for: topStat)
            statCard(for: bottomStat)
        }
        .padding(widgetPadding)
    }

    // MARK: - Stat Card

    @ViewBuilder
    private func statCard(for stat: FreeWidgetStatType) -> some View {
        if stat.isPro && !entry.isPro {
            lockedCard(for: stat)
        } else {
            let display = displayValue(for: stat)
            sectionCard(
                icon: stat.iconName,
                iconColor: iconColor(for: stat),
                title: titleFor(stat),
                displayText: display.text,
                textColor: display.color
            )
        }
    }

    // MARK: - Locked Card (Pro)

    private func lockedCard(for stat: FreeWidgetStatType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 標題列（左上）
            HStack(spacing: 4) {
                Image(systemName: stat.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(titleFor(stat))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // 🔒 PRO（右下）
            HStack(spacing: 4) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("PRO")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Normal Card

    private func sectionCard(
        icon: String,
        iconColor: Color,
        title: String,
        displayText: String,
        textColor: Color
    ) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                Text(displayText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: geo.size.width * 0.75, alignment: .trailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 2)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(iconColor)

                        Text(title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Data Helpers

    private struct DisplayResult {
        let text: String
        let color: Color
    }

    private func displayValue(for stat: FreeWidgetStatType) -> DisplayResult {
        guard let stats = entry.stats else {
            // Fallback: 用 entry 的 pending/delivered 資料
            switch stat {
            case .pendingPickup:
                return DisplayResult(text: "\(entry.pendingPackages.count)", color: .primary)
            case .deliveredLast30Days:
                return DisplayResult(text: "\(entry.recentDelivered.count)", color: .primary)
            default:
                return DisplayResult(text: "--", color: .secondary)
            }
        }

        switch stat {
        case .pendingPickup:
            return DisplayResult(text: "\(stats.pendingPickup)", color: .primary)
        case .deliveredLast30Days:
            return DisplayResult(text: "\(stats.deliveredLast30Days)", color: .primary)
        case .thisMonthSpending:
            return DisplayResult(text: formatCurrency(stats.thisMonthSpending), color: .primary)
        case .pendingAmount:
            return DisplayResult(text: formatCurrency(stats.pendingAmount), color: .primary)
        case .last30DaysSpending:
            return DisplayResult(text: formatCurrency(stats.last30DaysSpending), color: .primary)
        case .thisMonthDelivered:
            return DisplayResult(text: "\(stats.thisMonthDelivered)", color: .primary)
        case .inTransit:
            return DisplayResult(text: "\(stats.inTransit)", color: .primary)
        case .avgDeliveryDays:
            if stats.avgDeliveryDays < 0 {
                return DisplayResult(text: "--", color: .secondary)
            }
            if stats.avgDeliveryDays == stats.avgDeliveryDays.rounded() {
                return DisplayResult(
                    text: "\(Int(stats.avgDeliveryDays))" + String(localized: "widget.stat.unit.days"),
                    color: .primary
                )
            }
            return DisplayResult(
                text: String(format: "%.1f", stats.avgDeliveryDays) + String(localized: "widget.stat.unit.days"),
                color: .primary
            )
        case .spendingDelta:
            let diff = stats.spendingDeltaCurrent - stats.spendingDeltaPrevious
            if stats.spendingDeltaCurrent == 0 && stats.spendingDeltaPrevious == 0 {
                return DisplayResult(text: "$0", color: .primary)
            }
            let formatted = formatCurrency(abs(diff))
            if diff > 0 {
                return DisplayResult(text: "\u{2191}" + formatted, color: .red)
            } else if diff < 0 {
                return DisplayResult(text: "\u{2193}" + formatted, color: .green)
            }
            return DisplayResult(text: formatted, color: .primary)
        case .codPendingAmount:
            return DisplayResult(text: formatCurrency(stats.codPendingAmount), color: .primary)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    private func titleFor(_ stat: FreeWidgetStatType) -> String {
        switch stat {
        case .pendingPickup:        return String(localized: "widget.stat.pendingPickup")
        case .deliveredLast30Days:  return String(localized: "widget.stat.deliveredLast30Days")
        case .thisMonthSpending:    return String(localized: "widget.stat.thisMonthSpending")
        case .pendingAmount:        return String(localized: "widget.stat.pendingAmount")
        case .last30DaysSpending:   return String(localized: "widget.stat.last30DaysSpending")
        case .thisMonthDelivered:   return String(localized: "widget.stat.thisMonthDelivered")
        case .inTransit:            return String(localized: "widget.stat.inTransit")
        case .avgDeliveryDays:      return String(localized: "widget.stat.avgDeliveryDays")
        case .spendingDelta:        return String(localized: "widget.stat.spendingDelta")
        case .codPendingAmount:     return String(localized: "widget.stat.codPendingAmount")
        }
    }

    private func iconColor(for stat: FreeWidgetStatType) -> Color {
        switch stat {
        case .pendingPickup:        return .orange
        case .deliveredLast30Days:  return .green
        case .thisMonthSpending:    return .blue
        case .pendingAmount:        return .yellow
        case .last30DaysSpending:   return .cyan
        case .thisMonthDelivered:   return .mint
        case .inTransit:            return .indigo
        case .avgDeliveryDays:      return .purple
        case .spendingDelta:        return .red
        case .codPendingAmount:     return .orange
        }
    }
}
