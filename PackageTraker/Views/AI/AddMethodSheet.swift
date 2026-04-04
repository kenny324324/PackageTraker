//
//  AddMethodSheet.swift
//  PackageTraker
//
//  新增方式選擇頁（AI 掃描 / 手動輸入）
//

import SwiftUI
import SwiftData

/// 新增包裹方式選擇 Sheet
struct AddMethodSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onManualAdd: () -> Void
    var onAIScan: () -> Void
    var onShowPaywall: (Bool) -> Void  // lifetimeOnly
    var onShowAITrialUpsell: () -> Void  // AI 試用用完

    @State private var contentHeight: CGFloat = 0
    @State private var remainingScans: Int = AIVisionService.shared.remainingScans

    /// AI 免費試用：最多 3 次（終身額度）
    private static let aiTrialLimit = 3
    private var aiTrialUsedCount: Int { UserDefaults.standard.integer(forKey: "aiTrialUsedCount") }
    private var aiTrialRemaining: Int { max(0, Self.aiTrialLimit - aiTrialUsedCount) }

    private var adaptiveSheetHeight: CGFloat {
        max(184, min(248, contentHeight + 80))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // AI 掃描按鈕
                aiScanButton

                // AI 剩餘次數顯示
                if FeatureFlags.subscriptionEnabled {
                    if SubscriptionManager.shared.hasAIAccess && !SubscriptionManager.shared.isLifetime {
                        // 訂閱制用戶：顯示每日剩餘
                        Text(String(localized: "ai.remainingScans.\(remainingScans)"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if !SubscriptionManager.shared.hasAIAccess && aiTrialRemaining > 0 {
                        // 免費用戶試用中：顯示試用剩餘
                        Text(String(localized: "aiTrial.remaining.\(aiTrialRemaining).\(Self.aiTrialLimit)"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // 手動輸入按鈕
                Button {
                    onManualAdd()
                } label: {
                    Text(String(localized: "addMethod.manualInput"))
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                .accessibilityLabel(String(localized: "addMethod.manualInput"))
            }
            .padding(.horizontal)
            .padding(.top, 2)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: AddMethodContentHeightPreferenceKey.self, value: proxy.size.height)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle(String(localized: "addMethod.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(adaptiveSheetHeight)])
        .presentationDragIndicator(.hidden)
        .presentationBackground {
            if #available(iOS 26, *) {
                Color.clear
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .onPreferenceChange(AddMethodContentHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // 使用本地快取的剩餘次數（不呼叫 Cloud Function，避免 TestFlight 閃退）
            // 伺服器同步在每次 AI 掃描成功後自動執行，快取值已足夠準確
            remainingScans = AIVisionService.shared.remainingScans
        }
    }

    /// 未訂閱（試用剩餘 > 0）→ 正常掃描；試用用完 → AITrialUpsellView；
    /// 訂閱制次數用完 → 彈 Paywall（升級終身）；其餘 → 正常掃描
    @ViewBuilder
    private var aiScanButton: some View {
        if FeatureFlags.subscriptionEnabled && !SubscriptionManager.shared.hasAIAccess {
            if aiTrialRemaining > 0 {
                // 免費用戶但還有試用額度 → 正常進入 AI 流程
                Button { onAIScan() } label: { aiScanLabel }
                    .buttonStyle(.plain)
            } else {
                // 免費用戶且試用用完 → 彈 AITrialUpsellView
                Button {
                    onShowAITrialUpsell()
                } label: { aiScanLabel }
                    .buttonStyle(.plain)
            }
        } else if FeatureFlags.subscriptionEnabled && !SubscriptionManager.shared.isLifetime && remainingScans <= 0 {
            // 訂閱制但今日次數已用完 → 直接彈升級終身方案
            Button {
                onShowPaywall(true)
            } label: { aiScanLabel }
                .buttonStyle(.plain)
        } else {
            Button { onAIScan() } label: { aiScanLabel }
                .buttonStyle(.plain)
        }
    }

    private var aiScanLabel: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.24, green: 0.56, blue: 1.00), location: 0.00),
                    .init(color: Color(red: 0.62, green: 0.36, blue: 0.95), location: 0.36),
                    .init(color: Color(red: 0.98, green: 0.23, blue: 0.38), location: 0.72),
                    .init(color: Color(red: 1.00, green: 0.53, blue: 0.18), location: 1.00),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .padding(-10)
            .saturation(0.80)
            .contrast(1.16)
            .brightness(0.10)

            Color.black.opacity(0.26)

            HStack(spacing: 10) {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                Text(String(localized: "addMethod.aiScan.title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .frame(height: 56)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.9)
        )
        .modifier(AILiquidGlassCapsuleModifier())
        .modifier(AIScanButtonShadowModifier())
    }

}

private struct AddMethodContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AILiquidGlassCapsuleModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.clear.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct AIScanButtonShadowModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .shadow(color: Color(red: 0.19, green: 0.62, blue: 1.00).opacity(0.44), radius: 16, x: -8, y: 0)
                .shadow(color: Color(red: 0.54, green: 0.42, blue: 1.00).opacity(0.30), radius: 15, x: 0, y: 0)
                .shadow(color: Color(red: 1.00, green: 0.54, blue: 0.26).opacity(0.34), radius: 15, x: 8, y: 0)
        } else {
            content
        }
    }
}

// MARK: - Preview

#Preview {
    AddMethodSheet(onManualAdd: {}, onAIScan: {}, onShowPaywall: { _ in }, onShowAITrialUpsell: {})
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
