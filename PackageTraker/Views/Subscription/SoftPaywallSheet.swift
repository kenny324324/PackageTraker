//
//  SoftPaywallSheet.swift
//  PackageTraker
//
//  一次性輕量 Paywall Sheet（條件觸發，只彈一次）
//

import SwiftUI

struct SoftPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onViewPlans: () -> Void

    /// 與付費牆功能對比表一致
    private let features: [(icon: String, text: LocalizedStringResource)] = [
        ("shippingbox.fill", "paywall.comparison.packages"),
        ("sparkles", "paywall.comparison.ai"),
        ("chart.pie.fill", "paywall.comparison.spending"),
        ("bell.badge.fill", "paywall.comparison.notification"),
    ]

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Header
            VStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.yellow, Color.orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text(String(localized: "softPaywall.title"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(String(localized: "softPaywall.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Feature List
            VStack(alignment: .leading, spacing: 14) {
                ForEach(features, id: \.icon) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(.yellow)
                            .frame(width: 28)

                        Text(String(localized: feature.text))
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // CTA
            Button {
                dismiss()
                // Delay to allow sheet dismiss animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onViewPlans()
                }
            } label: {
                Text(String(localized: "softPaywall.viewPlans"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .padding(.horizontal, 24)

            Button {
                UserDefaults.standard.set(true, forKey: "hasSeenSoftPaywall")
                dismiss()
            } label: {
                Text(String(localized: "softPaywall.later"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)
        }
        .adaptiveGradientBackground()
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}
