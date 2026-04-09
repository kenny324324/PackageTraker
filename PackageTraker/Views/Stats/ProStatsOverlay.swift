import SwiftUI

/// Pro 專屬內容遮罩 — 模糊 + 鎖頭 + PRO 徽章
struct ProStatsOverlay: ViewModifier {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false

    private var isLocked: Bool {
        FeatureFlags.subscriptionEnabled && !subscriptionManager.isPro
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: isLocked ? 6 : 0)
            .allowsHitTesting(!isLocked)
            .overlay {
                if isLocked {
                    lockedOverlay
                }
            }
            .fullScreenCover(isPresented: $showPaywall) {
                PaywallView(trigger: .spending)
            }
    }

    private var lockedOverlay: some View {
        Color.black.opacity(0.15)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay {
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(.yellow.opacity(0.9))

                    Text(String(localized: "stats.pro.unlock"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showPaywall = true
            }
    }
}

extension View {
    func proStatsOverlay() -> some View {
        modifier(ProStatsOverlay())
    }
}
