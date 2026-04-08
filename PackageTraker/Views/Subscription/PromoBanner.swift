//
//  PromoBanner.swift
//  PackageTraker
//
//  限時優惠 banner（顯示在包裹列表頂部）
//

import SwiftUI

struct PromoBanner: View {
    @ObservedObject private var promoManager = LaunchPromoManager.shared
    var onTap: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "promo.banner.title"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)

                    Text(String(format: NSLocalizedString("promo.banner.countdown", comment: ""), promoManager.countdownText))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.7))
                }

                Spacer(minLength: 4)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.5))
                        .padding(4)
                }
            }
            .padding(12)
            .background(
                LinearGradient(
                    colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }
}
