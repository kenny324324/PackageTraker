//
//  AITrialUpsellView.swift
//  PackageTraker
//
//  AI 免費試用次數用完後的升級引導頁
//

import SwiftUI

struct AITrialUpsellView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            // Title
            Text(String(localized: "aiTrial.exhausted.title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            // Subtitle
            Text(String(localized: "aiTrial.exhausted.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // CTA Button
            Button {
                showPaywall = true
            } label: {
                Text(String(localized: "aiTrial.exhausted.viewPlans"))
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

            // Dismiss
            Button {
                dismiss()
            } label: {
                Text(String(localized: "aiTrial.exhausted.later"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)
        }
        .adaptiveGradientBackground()
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(trigger: .ai)
        }
        .preferredColorScheme(.dark)
    }
}
