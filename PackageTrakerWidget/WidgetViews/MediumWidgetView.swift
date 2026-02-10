//
//  MediumWidgetView.swift
//  PackageTrakerWidget
//
//  Medium widget: shows 2-3 packages in a list
//

import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: PackageTimelineEntry

    var body: some View {
        if entry.packages.isEmpty {
            emptyContent
        } else if !entry.isPro && FeatureFlags.subscriptionEnabled {
            proUpgradeContent
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
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(String(localized: "widget.title"))
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(entry.packages.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            // 包裹列表（最多 3 個）
            ForEach(Array(entry.packages.prefix(3).enumerated()), id: \.element.id) { index, package in
                if index > 0 {
                    Divider()
                        .padding(.vertical, 2)
                }
                Link(destination: package.deepLinkURL) {
                    packageRow(package)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func packageRow(_ package: WidgetPackageItem) -> some View {
        HStack(spacing: 10) {
            // 狀態指示點
            Circle()
                .fill(statusColor(package.statusColor))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(package.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(package.carrierName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(package.statusName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(statusColor(package.statusColor))
        }
    }

    // MARK: - Empty Content

    private var emptyContent: some View {
        HStack {
            Image(systemName: "shippingbox")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "widget.empty"))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(String(localized: "widget.emptyHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Pro Upgrade

    private var proUpgradeContent: some View {
        VStack(spacing: 8) {
            // 還是顯示第一個包裹
            if let package = entry.packages.first {
                Link(destination: package.deepLinkURL) {
                    packageRow(package)
                }
            }

            Divider()

            HStack {
                Image(systemName: "crown.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)

                Text(String(localized: "widget.upgradePro"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
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

// MARK: - Feature Flags (Widget side)

/// Widget 側的 FeatureFlags（與主 App 保持一致）
enum FeatureFlags {
    static let subscriptionEnabled = true
}
