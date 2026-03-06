//
//  SmallWidgetView.swift
//  PackageTrakerWidget
//
//  Small widget: shows 1 package with carrier logo, status badge, and latest event
//

import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: PackageTimelineEntry

    var body: some View {
        Group {
            if let package = entry.packages.first {
                packageContent(package)
            } else {
                emptyContent
            }
        }
        .padding(12)
    }

    // MARK: - Package Content

    private func packageContent(_ package: WidgetPackageItem) -> some View {
        Link(destination: package.deepLinkURL) {
            VStack(spacing: 0) {
                // 頂部：通路 Logo (左) + 狀態膠囊 (右)
                HStack(alignment: .top) {
                    // 通路 Logo（圓形）
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

                    Spacer()

                    // 狀態膠囊：0.1 背景色 + 該顏色文字
                    Text(package.statusName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusColor(package.statusColor))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statusColor(package.statusColor).opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 4)

                // 中間：商品名稱（最多兩行，靠左）
                Text(package.displayName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                // 底部：當前狀態描述區塊
                if let desc = package.latestDescription {
                    Text(desc)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
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
                .font(.system(size: 13, design: .rounded))
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
