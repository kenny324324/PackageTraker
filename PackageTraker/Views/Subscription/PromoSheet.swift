//
//  PromoSheet.swift
//  PackageTraker
//
//  限時優惠 / 1000 用戶慶祝 Sheet（依 variant 切換配色與文案）
//

import SwiftUI
import StoreKit

/// Promo Sheet 樣式
enum PromoSheetVariant {
    case launch     // 新用戶 24hr 半價（990）
    case milestone  // 1000 用戶慶祝（1290）
}

struct PromoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var launchPromo = LaunchPromoManager.shared
    @ObservedObject private var milestonePromo = MilestonePromoManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    var variant: PromoSheetVariant = .launch
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
                                colors: iconGlowColors,
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
                        .shadow(color: iconShadow, radius: 5, x: 0, y: 2)
                }

                // Description
                Text(descriptionText)
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

                            if let promo = promoProduct {
                                Text(promo.displayPrice)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(priceTint)
                            }
                        }
                    }

                    // Countdown
                    HStack(spacing: 6) {
                        Image(systemName: countdownIcon)
                            .font(.system(size: 12))
                        Text(countdownText)
                            .font(.system(size: 13, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(countdownTint)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer(minLength: 0)

                // CTA
                VStack(spacing: 12) {
                    Button {
                        AnalyticsService.logPromoSheetCTAClicked(variant: analyticsVariant)
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            onViewPlans()
                        }
                    } label: {
                        Text(ctaText)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .adaptiveSheetCTAStyle(gradientColors: ctaGradient)
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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationBackground {
            if #available(iOS 26, *) {
                Color.clear
            } else {
                Color.cardBackground
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            AnalyticsService.logPromoSheetShown(variant: analyticsVariant)
        }
    }

    // MARK: - Variant-specific config

    private var promoProduct: Product? {
        switch variant {
        case .launch: return subscriptionManager.lifetimeLaunchProduct
        case .milestone: return subscriptionManager.lifetimeMilestoneProduct
        }
    }

    private var iconGlowColors: [Color] {
        // 統一使用金色光暈（兩個變體共用）
        [Color.yellow.opacity(0.3), Color.orange.opacity(0.1)]
    }

    private var iconShadow: Color {
        .orange.opacity(0.3)
    }

    private var descriptionText: String {
        switch variant {
        case .launch:
            return String(localized: "promo.sheet.description")
        case .milestone:
            return String(localized: "milestone.promo.sheet.description")
        }
    }

    private var navigationTitle: String {
        switch variant {
        case .launch: return String(localized: "promo.sheet.title")
        case .milestone: return String(localized: "milestone.promo.sheet.title")
        }
    }

    private var ctaText: String {
        switch variant {
        case .launch: return String(localized: "promo.sheet.cta")
        case .milestone: return String(localized: "milestone.promo.sheet.cta")
        }
    }

    private var ctaGradient: [Color] {
        switch variant {
        case .launch: return [.yellow, .orange]
        case .milestone:
            // 紫金漸層
            return [Color(hex: "C089FF"), Color(hex: "FFD27A")]
        }
    }

    private var priceTint: Color {
        switch variant {
        case .launch: return .yellow
        case .milestone: return Color(hex: "FFB800")
        }
    }

    private var countdownIcon: String {
        switch variant {
        case .launch: return "clock.fill"
        case .milestone:
            return milestonePromo.isFinalCountdown ? "alarm.fill" : "calendar"
        }
    }

    private var countdownTint: Color {
        switch variant {
        case .launch: return .orange
        case .milestone:
            return milestonePromo.isFinalCountdown ? Color(hex: "FF3B5C") : Color(hex: "C089FF")
        }
    }

    private var countdownText: String {
        switch variant {
        case .launch:
            return String(format: NSLocalizedString("promo.banner.countdown", comment: ""), launchPromo.countdownText)
        case .milestone:
            if milestonePromo.isFinalCountdown {
                return String(format: NSLocalizedString("milestone.promo.final_countdown", comment: ""), milestonePromo.remainingDays)
            }
            return String(format: NSLocalizedString("milestone.promo.remaining_days", comment: ""), milestonePromo.remainingDays)
        }
    }

    private var analyticsVariant: String {
        switch variant {
        case .launch: return "launch"
        case .milestone: return "milestone"
        }
    }
}
