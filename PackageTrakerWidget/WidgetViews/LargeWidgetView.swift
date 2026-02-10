//
//  LargeWidgetView.swift
//  PackageTrakerWidget
//
//  Large widget: shows 4-5 packages with latest event details
//

import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: PackageTimelineEntry

    var body: some View {
        if entry.packages.isEmpty {
            emptyContent
        } else {
            packageList
        }
    }

    // MARK: - Package List

    private var packageList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 標題列
            HStack {
                Image(systemName: "shippingbox.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Text(String(localized: "widget.title"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(localized: "widget.count\(entry.packages.count)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            // 包裹列表（最多 5 個）
            ForEach(Array(entry.packages.prefix(5).enumerated()), id: \.element.id) { index, package in
                if index > 0 {
                    Divider()
                        .padding(.vertical, 4)
                }
                Link(destination: package.deepLinkURL) {
                    packageDetailRow(package)
                }
            }

            Spacer(minLength: 0)

            // 免費用戶 Pro 提示
            if !entry.isPro && FeatureFlags.subscriptionEnabled {
                Divider()
                    .padding(.vertical, 4)
                proUpgradeHint
            }
        }
    }

    private func packageDetailRow(_ package: WidgetPackageItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // 狀態指示圓點
            Circle()
                .fill(statusColor(package.statusColor))
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                // 包裹名稱 + 物流商
                HStack {
                    Text(package.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Spacer()

                    Text(package.statusName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(package.statusColor))
                        .clipShape(Capsule())
                }

                // 物流商
                Text(package.carrierName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // 最新動態
                if let desc = package.latestDescription {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // 取貨地點
                if let location = package.pickupLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption2)
                        Text(location)
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Empty Content

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(String(localized: "widget.empty"))
                .font(.subheadline)
                .fontWeight(.medium)

            Text(String(localized: "widget.emptyHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pro Upgrade Hint

    private var proUpgradeHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)

            Text(String(localized: "widget.upgradePro"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func statusColor(_ color: WidgetStatusColor) -> Color {
        switch color {
        case .green: return .green
        case .blue: return .blue
        case .orange: return .orange
        case .red: return .red
        case .gray: return .gray
        case .purple: return .purple
        }
    }
}
