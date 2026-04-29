//
//  MilestonePromoBanner.swift
//  PackageTraker
//
//  1000 用戶里程碑慶祝 banner（顯示在包裹列表頂部，與 PromoBanner 互斥）
//

import SwiftUI

struct MilestonePromoBanner: View {
    @ObservedObject private var promoManager = MilestonePromoManager.shared
    var onTap: () -> Void
    var onDismiss: () -> Void

    private var isFinal: Bool { promoManager.isFinalCountdown }

    private var bannerColors: [Color] {
        if isFinal {
            // 最後 3 天：紅紫漸層
            return [Color(hex: "FF3B5C"), Color(hex: "8B2EFF")]
        }
        // 紫金漸層
        return [Color(hex: "8B2EFF"), Color(hex: "FFB800")]
    }

    private var titleText: String {
        if isFinal {
            return String(format: NSLocalizedString("milestone.promo.banner.final", comment: ""), promoManager.remainingDays)
        }
        return String(localized: "milestone.promo.banner")
    }

    private var subtitleText: String {
        String(format: NSLocalizedString("milestone.promo.remaining_days", comment: ""), promoManager.remainingDays)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isFinal ? "alarm.fill" : "party.popper.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(subtitleText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer(minLength: 4)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(4)
                }
            }
            .padding(12)
            .background(
                LinearGradient(
                    colors: bannerColors,
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }
}
