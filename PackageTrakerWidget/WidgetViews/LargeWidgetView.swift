//
//  LargeWidgetView.swift
//  PackageTrakerWidget
//
//  Large widget: shows up to 4 packages in list style
//

import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
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
        VStack(spacing: 0) {
            ForEach(Array(entry.packages.prefix(3).enumerated()), id: \.offset) { index, package in
                if index > 0 {
                    Divider()
                        .padding(.vertical, 6)
                }
                Link(destination: package.deepLinkURL) {
                    packageRow(package)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func packageRow(_ package: WidgetPackageItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Logo + Name + Status capsule
            HStack(alignment: .center, spacing: 8) {
                if let logoName = package.carrierLogoName {
                    Image(logoName)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                } else {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.1))
                        .clipShape(Circle())
                }

                Text(package.displayName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Spacer()

                Text(package.statusName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor(package.statusColor))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor(package.statusColor).opacity(0.1))
                    .clipShape(Capsule())
            }

            // Row 2: Latest description in gray rounded rect
            if let desc = package.latestDescription, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
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
