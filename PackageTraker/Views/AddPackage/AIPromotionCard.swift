//
//  AIPromotionCard.swift
//  PackageTraker
//
//  AI screenshot recognition promotion card for AddPackageView
//

import SwiftUI
import PhotosUI

/// AI 辨識推廣卡片
struct AIPromotionCard: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    let onSelectImage: () -> Void
    let onShowPaywall: () -> Void

    var body: some View {
        Button {
            if subscriptionManager.hasAIAccess {
                onSelectImage()
            } else {
                onShowPaywall()
            }
        } label: {
            HStack(spacing: 14) {
                // AI 圖示
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(String(localized: "ai.card.title"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)

                        if !subscriptionManager.hasAIAccess {
                            Text("PRO")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    LinearGradient(
                                        colors: [.yellow, .orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
                    }

                    Text(String(localized: "ai.card.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color.purple.opacity(0.15), Color.blue.opacity(0.10)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        AIPromotionCard(
            onSelectImage: {},
            onShowPaywall: {}
        )
    }
    .padding()
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
