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
        Group {
            if entry.packages.isEmpty {
                emptyContent
            } else {
                packageList
            }
        }
        .padding(12)
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
        HStack(alignment: .top, spacing: 10) {
            // 狀態指示點
            Circle()
                .fill(statusColor(package.statusColor))
                .frame(width: 8, height: 8)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(package.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(package.carrierName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let desc = package.latestDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

