//
//  LockScreenWidgetViews.swift
//  PackageTrakerWidget
//
//  Lock Screen widgets:
//  - Circular: pending count (static)
//  - Rectangular Package: selected package info (configurable)
//  - Rectangular Stats: single stat value (configurable)
//

import SwiftUI
import WidgetKit

// MARK: - Circular: 待取件數量

struct LockScreenCircularView: View {
    let entry: PackageTimelineEntry

    var body: some View {
        Gauge(value: gaugeValue, in: 0...gaugeMax) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 12))
        } currentValueLabel: {
            Text("\(entry.pendingPackages.count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var gaugeValue: Double {
        Double(entry.pendingPackages.count)
    }

    private var gaugeMax: Double {
        max(Double(entry.pendingPackages.count), 5)
    }
}

// MARK: - Circular Quick Add: App Icon 快速新增

struct LockScreenQuickAddView: View {
    var body: some View {
        Image(systemName: "shippingbox.fill")
            .font(.system(size: 38))
            .widgetAccentable()
            .widgetURL(URL(string: "packagetraker://addPackage")!)
    }
}

// MARK: - Rectangular Package: 選擇的包裹資訊

struct LockScreenRectangularView: View {
    let entry: PackageTimelineEntry

    private var pkg: WidgetPackageItem? {
        entry.selectedPackage
    }

    var body: some View {
        if let pkg {
            VStack(alignment: .leading, spacing: 0) {
                // 第一行：Logo + 物流商（左） + 狀態膠囊（右）
                HStack(spacing: 4) {
                    if let logoName = pkg.carrierLogoName {
                        Image(logoName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(pkg.carrierName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(pkg.statusName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(.primary.opacity(0.15))
                        )
                }

                Spacer(minLength: 0)

                // 第二行：品名（大字、靠左）
                Text(pkg.displayName)
                    .font(.system(size: 23, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 10))
                    Text(String(localized: "widget.lockscreen.noPackages"))
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(String(localized: "widget.lockscreen.addHint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Rectangular Stats: 單一統計值

struct LockScreenStatsRectangularView: View {
    let entry: PackageTimelineEntry

    private var stat: FreeWidgetStatType {
        entry.selectedStat
    }

    var body: some View {
        if stat.isPro && !entry.isPro {
            // Pro 鎖定
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: stat.iconName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(titleFor(stat))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                    Text("PRO")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // 標題列（左上）
                HStack(spacing: 4) {
                    Image(systemName: stat.iconName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(titleFor(stat))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                // 數值（靠左）
                let display = displayValue(for: stat)
                Text(display.text)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(display.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Helpers

    private struct DisplayResult {
        let text: String
        let color: Color
    }

    private func displayValue(for stat: FreeWidgetStatType) -> DisplayResult {
        guard let stats = entry.stats else {
            return DisplayResult(text: "--", color: .secondary)
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
            if stats.avgDeliveryDays < 0 { return DisplayResult(text: "--", color: .secondary) }
            if stats.avgDeliveryDays == stats.avgDeliveryDays.rounded() {
                return DisplayResult(text: "\(Int(stats.avgDeliveryDays))" + String(localized: "widget.stat.unit.days"), color: .primary)
            }
            return DisplayResult(text: String(format: "%.1f", stats.avgDeliveryDays) + String(localized: "widget.stat.unit.days"), color: .primary)
        case .spendingDelta:
            let diff = stats.spendingDeltaCurrent - stats.spendingDeltaPrevious
            if stats.spendingDeltaCurrent == 0 && stats.spendingDeltaPrevious == 0 {
                return DisplayResult(text: "$0", color: .primary)
            }
            let formatted = formatCurrency(abs(diff))
            if diff > 0 { return DisplayResult(text: "\u{2191}" + formatted, color: .primary) }
            if diff < 0 { return DisplayResult(text: "\u{2193}" + formatted, color: .primary) }
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
}
