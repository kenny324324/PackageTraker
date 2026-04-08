//
//  PromoSheet.swift
//  PackageTraker
//
//  限時優惠 Sheet（優惠進行中每次啟動彈出）
//

import SwiftUI
import StoreKit

struct PromoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var promoManager = LaunchPromoManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    var onViewPlans: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 90, height: 90)
                        .blur(radius: 20)

                    Image("SplashIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .shadow(color: .orange.opacity(0.3), radius: 5, x: 0, y: 2)
                }

                // Description
                Text(String(localized: "promo.sheet.description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Price + Countdown
                VStack(spacing: 12) {
                    // Price comparison
                    if let original = subscriptionManager.lifetimeProduct {
                        HStack(spacing: 8) {
                            Text(original.displayPrice)
                                .font(.title3)
                                .strikethrough()
                                .foregroundStyle(.secondary)

                            if let promo = subscriptionManager.lifetimeLaunchProduct {
                                Text(promo.displayPrice)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }

                    // Countdown
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                        Text(String(format: NSLocalizedString("promo.banner.countdown", comment: ""), promoManager.countdownText))
                            .font(.system(size: 13, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.orange)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer(minLength: 0)

                // CTA
                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            onViewPlans()
                        }
                    } label: {
                        Text(String(localized: "promo.sheet.cta"))
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

                    Button {
                        dismiss()
                    } label: {
                        Text(String(localized: "softPaywall.later"))
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .navigationTitle(String(localized: "promo.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
    }
}
