//
//  ProNudgeBanner.swift
//  PackageTraker
//
//  可複用的 Pro 升級引導 Banner
//

import SwiftUI

struct ProNudgeBanner: View {
    let message: String
    var icon: String = "exclamationmark.triangle"
    var style: BannerStyle = .warning
    var dismissible: Bool = true
    var onUpgrade: () -> Void
    var onDismiss: (() -> Void)? = nil

    enum BannerStyle {
        case warning    // 橘色（包裹快滿）
        case critical   // 紅色（包裹已滿）
        case info       // 紫色（功能推廣）
    }

    private var backgroundColor: Color {
        switch style {
        case .warning:  return Color.orange
        case .critical: return Color.red
        case .info:     return Color(red: 0.5, green: 0.3, blue: 0.9)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer(minLength: 4)

            Button {
                onUpgrade()
            } label: {
                Text(String(localized: "proNudge.upgrade"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(backgroundColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white, in: Capsule())
            }

            if dismissible {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(12)
        .background(backgroundColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
    }
}
