//
//  SoftPaywallSheet.swift
//  PackageTraker
//
//  一次性輕量 Paywall Sheet（條件觸發，只彈一次）
//

import SwiftUI
import SwiftData

struct SoftPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Query private var allPackages: [Package]
    var onViewPlans: () -> Void

    private let maxFreePackages = 5

    private var activePackageCount: Int {
        allPackages.filter { !$0.isArchived }.count
    }

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

                // Unlock description
                Text(String(localized: "softPaywall.unlockDescription"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Package Quota Progress
                packageQuotaBar

                Spacer(minLength: 0)

                // CTA
                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            onViewPlans()
                        }
                    } label: {
                        Text(String(localized: "softPaywall.viewPlans"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .adaptiveSheetCTAStyle(gradientColors: [.yellow, .orange])
                    }

                    Button {
                        UserDefaults.standard.set(true, forKey: "hasSeenSoftPaywall")
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
            .navigationTitle(String(localized: "softPaywall.title"))
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
    }

    // MARK: - Package Quota Progress Bar

    private var packageQuotaBar: some View {
        let progress = min(CGFloat(activePackageCount) / CGFloat(maxFreePackages), 1.0)
        let isFull = activePackageCount >= maxFreePackages
        let progressColor: Color = isFull ? .red : .orange

        return VStack(spacing: 6) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(progressColor)

                Text(String(localized: "softPaywall.quota.title"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)

                Spacer()

                Text("\(activePackageCount)/\(maxFreePackages)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(progressColor)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(progressColor)
                        .frame(width: progress * geometry.size.width, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text(isFull
                     ? String(localized: "softPaywall.quota.full")
                     : String(format: NSLocalizedString("softPaywall.quota.remaining", comment: ""), maxFreePackages - activePackageCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
