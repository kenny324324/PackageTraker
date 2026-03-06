//
//  FreeWidgetView.swift
//  PackageTrakerWidget
//
//  Free tier widget (small only): pickup reminder with two sections.
//

import SwiftUI
import WidgetKit

struct FreeWidgetView: View {
    let entry: PackageTimelineEntry

    private let widgetPadding: CGFloat = 8

    var body: some View {
        VStack(spacing: widgetPadding) {
            sectionCard(
                icon: "shippingbox.fill",
                iconColor: .brown,
                title: String(localized: "widget.pending"),
                count: entry.pendingPackages.count
            )

            sectionCard(
                icon: "checkmark.circle.fill",
                iconColor: .secondary,
                title: String(localized: "widget.recentDelivered"),
                count: entry.recentDelivered.count
            )
        }
        .padding(widgetPadding)
    }

    // MARK: - Section Card

    private func sectionCard(
        icon: String,
        iconColor: Color,
        title: String,
        count: Int
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Text("\(count)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
    }
}
