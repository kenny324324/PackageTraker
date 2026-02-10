//
//  SmallWidgetView.swift
//  PackageTrakerWidget
//
//  Small widget: shows 1 package with status
//

import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: PackageTimelineEntry

    var body: some View {
        if let package = entry.packages.first {
            packageContent(package)
        } else {
            emptyContent
        }
    }

    // MARK: - Package Content

    private func packageContent(_ package: WidgetPackageItem) -> some View {
        Link(destination: package.deepLinkURL) {
            VStack(alignment: .leading, spacing: 8) {
                // 物流商 + 狀態
                HStack {
                    Image(systemName: "shippingbox.fill")
                        .font(.caption)
                        .foregroundStyle(statusColor(package.statusColor))

                    Text(package.carrierName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()
                }

                // 包裹名稱
                Text(package.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Spacer()

                // 狀態 badge
                Text(package.statusName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(package.statusColor))
                    .clipShape(Capsule())

                // 最新動態
                if let desc = package.latestDescription {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Empty Content

    private var emptyContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(String(localized: "widget.empty"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
