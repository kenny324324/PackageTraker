//
//  PaywallView.swift
//  PackageTraker
//
//  Subscription paywall UI
//

import SwiftUI
import StoreKit

// MARK: - Equal Size PreferenceKeys

private struct CardWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Paywall 觸發來源（用於將對應功能排到比較表最上方）
enum PaywallTrigger: String {
    case packages       // 包裹數量
    case ai             // AI 截圖辨識
    case widget         // 桌面小工具
    case spending       // 消費分析
    case homeStats      // 首頁統計
    case themes         // 主題顏色
    case notification   // 個別通知設定
    case savedLocations // 常用取貨地點
    case general        // 預設（無特定來源）
}

/// 付費牆
struct PaywallView: View {
    /// 僅顯示終身方案（用於訂閱制用戶次數用完時升級）
    var lifetimeOnly: Bool = false
    /// 觸發來源（該功能會排到比較表最上面）
    var trigger: PaywallTrigger = .general

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var promoManager = LaunchPromoManager.shared

    @State private var selectedProduct: Product?
    @State private var showError = false
    @State private var showRestoreSuccess = false
    @State private var isRestoring = false
    @State private var isTrialEligible = true
    @State private var safariURL: IdentifiableURL?
    @State private var cardWidth: CGFloat = 0
    @State private var cardHeight: CGFloat = 0
    @State private var highlightTriggerFeature = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color.appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        // Header
                        headerSection
                            .padding(.top, 20)

                        // 功能比較表
                        featureComparisonSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, -12)

                        // 訂閱方案選擇
                        planSelectionSection
                    }
                    .padding(.bottom, 220) // Space for bottom button area
                }

                // 底部漸層遮罩（z-index 在 ScrollView 上方、底部容器下方）
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [Color.appBackground.opacity(0), Color.appBackground],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                    Color.appBackground
                        .frame(height: 80)
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .allowsHitTesting(false)

                // 固定在底部的訂閱按鈕
                VStack(spacing: 0) {
                    Spacer()

                    // 底部區域背景
                    VStack(spacing: 0) {
                        if lifetimeOnly {
                            // 升級終身方案提示
                            Text(String(localized: "paywall.unlockUnlimitedAI"))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.yellow)
                                .padding(.bottom, 16)
                        } else {
                            // Terms text
                            Text(String(localized: "paywall.termsNote"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 16)
                        }
                        
                        subscribeButton
                        
                        // Restore Purchase Button
                        Button {
                            isRestoring = true
                            Task {
                                await subscriptionManager.restorePurchases()
                                isRestoring = false
                                if subscriptionManager.isPro {
                                    showRestoreSuccess = true
                                }
                            }
                        } label: {
                            if isRestoring {
                                ProgressView()
                                    .tint(.secondary)
                                    .scaleEffect(0.8)
                            } else {
                                Text(String(localized: "paywall.restore"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .disabled(isRestoring)
                        .padding(.top, 16)

                        // Terms & Privacy links
                        HStack(spacing: 4) {
                            Button(String(localized: "paywall.terms")) {
                                if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                                    safariURL = IdentifiableURL(url: url)
                                }
                            }
                            Text("·").foregroundStyle(.white.opacity(0.3))
                            Button(String(localized: "paywall.privacy")) {
                                if let url = URL(string: "https://ripe-cereal-4f9.notion.site/Privacy-Policy-302341fcbfde81d589a2e4ba6713b911") {
                                    safariURL = IdentifiableURL(url: url)
                                }
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 8)
                    }
                    .padding(20)
                    .modifier(PaywallBottomAreaModifier())
                }
            }
            .navigationTitle(String(localized: "paywall.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .alert(String(localized: "paywall.error"), isPresented: $showError) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                if let msg = subscriptionManager.errorMessage {
                    Text(msg)
                }
            }
            .alert(String(localized: "paywall.restoreSuccess"), isPresented: $showRestoreSuccess) {
                Button(String(localized: "common.ok"), role: .cancel) {
                    if subscriptionManager.isPro {
                        dismiss()
                    }
                }
            }
            .sheet(item: $safariURL) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
            .onAppear {
                // 預設選 Lifetime
                if selectedProduct == nil {
                    selectedProduct = subscriptionManager.bestLifetimeProduct
                        ?? subscriptionManager.yearlyProduct
                        ?? subscriptionManager.monthlyProduct
                }
                AnalyticsService.logPaywallShown(trigger: trigger.rawValue)

                // 觸發來源強調：震動 + 動畫
                if trigger != .general {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        highlightTriggerFeature = true
                    }
                }
            }
            .task {
                // 檢查年費方案的試用資格
                if let yearly = subscriptionManager.yearlyProduct,
                   let subscription = yearly.subscription {
                    isTrialEligible = await subscription.isEligibleForIntroOffer
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Premium Icon
            ZStack {
                // Glow effect
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .blur(radius: 20)

                // Icon
                Image("SplashIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .shadow(color: .orange.opacity(0.3), radius: 5, x: 0, y: 2)
            }

            VStack(spacing: 8) {
                Text(String(localized: "paywall.headline"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                Text(String(localized: "paywall.subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Plan Selection Section

    private var planSelectionSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Lifetime (Special Design)
                if promoManager.isPromoActive,
                   let promoProduct = subscriptionManager.lifetimeLaunchProduct {
                    promoLifetimePlanCard(
                        promoProduct: promoProduct,
                        originalProduct: subscriptionManager.lifetimeProduct
                    )
                } else if let lifetime = subscriptionManager.lifetimeProduct {
                    lifetimePlanCard(product: lifetime)
                }

                if !lifetimeOnly {
                    // Yearly
                    if let yearly = subscriptionManager.yearlyProduct {
                        standardPlanCard(
                            product: yearly,
                            badge: String(localized: "paywall.badge.bestValue"),
                            subtitle: isTrialEligible
                                ? String(localized: "paywall.trial")
                                : String(localized: "paywall.cancelAnytime")
                        )
                    }

                    // Monthly
                    if let monthly = subscriptionManager.monthlyProduct {
                        standardPlanCard(product: monthly, badge: nil, subtitle: String(localized: "paywall.cancelAnytime"))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .onPreferenceChange(CardWidthKey.self) { cardWidth = $0 }
        .onPreferenceChange(CardHeightKey.self) { cardHeight = $0 }
    }
    
    // MARK: - Lifetime Card
    
    private func lifetimePlanCard(product: Product) -> some View {
        let isSelected = selectedProduct?.id == product.id

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedProduct = product
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Header with radio button
                HStack(alignment: .top) {
                    Text(String(localized: "paywall.plan.lifetime"))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.black)

                    Spacer()

                    // Radio button
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color.black : Color.black.opacity(0.3), lineWidth: 2)
                            .frame(width: 20, height: 20)

                        if isSelected {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 12, height: 12)
                        }
                    }
                }

                // One-time badge
                Text(String(localized: "paywall.plan.oneTime"))
                    .font(.system(size: 10))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(.black)

                // Description
                Text(String(localized: "paywall.plan.lifetimeDesc"))
                    .font(.system(size: 11))
                    .foregroundStyle(.black.opacity(0.7))
                    .lineLimit(2)

                // Price
                Text(product.displayPrice)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(14)
            .background(GeometryReader { geo in
                Color.clear
                    .preference(key: CardWidthKey.self, value: geo.size.width)
                    .preference(key: CardHeightKey.self, value: geo.size.height)
            })
            .frame(minWidth: 180,
                   idealWidth: cardWidth > 0 ? cardWidth : nil,
                   maxWidth: cardWidth > 0 ? cardWidth : nil,
                   minHeight: cardHeight > 0 ? cardHeight : nil,
                   alignment: .top)
            .background(
                LinearGradient(
                    colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .clear, radius: 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Promo Lifetime Card

    private func promoLifetimePlanCard(promoProduct: Product, originalProduct: Product?) -> some View {
        let isSelected = selectedProduct?.id == promoProduct.id

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedProduct = promoProduct
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Header with badge + radio
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        // 限時優惠 badge
                        Text(String(localized: "promo.badge"))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())

                        Text(String(localized: "paywall.plan.lifetime"))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.black)
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color.black : Color.black.opacity(0.3), lineWidth: 2)
                            .frame(width: 20, height: 20)

                        if isSelected {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 12, height: 12)
                        }
                    }
                }

                // One-time badge
                Text(String(localized: "paywall.plan.oneTime"))
                    .font(.system(size: 10))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(.black)

                // Price: original strikethrough + promo price
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let original = originalProduct {
                        Text(original.displayPrice)
                            .font(.subheadline)
                            .strikethrough()
                            .foregroundStyle(.black.opacity(0.5))
                    }
                    Text(promoProduct.displayPrice)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                // Countdown
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10))
                    Text(promoManager.countdownText)
                        .font(.system(size: 11, design: .monospaced))
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.black.opacity(0.7))
            }
            .padding(14)
            .background(GeometryReader { geo in
                Color.clear
                    .preference(key: CardWidthKey.self, value: geo.size.width)
                    .preference(key: CardHeightKey.self, value: geo.size.height)
            })
            .frame(minWidth: 180,
                   idealWidth: cardWidth > 0 ? cardWidth : nil,
                   maxWidth: cardWidth > 0 ? cardWidth : nil,
                   minHeight: cardHeight > 0 ? cardHeight : nil,
                   alignment: .top)
            .background(
                LinearGradient(
                    colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Standard Plan Card
    
    private func standardPlanCard(product: Product, badge: String?, subtitle: String) -> some View {
        let isSelected = selectedProduct?.id == product.id
        let title = product.id == SubscriptionProductID.yearly.rawValue
            ? String(localized: "paywall.plan.yearly")
            : String(localized: "paywall.plan.monthly")

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedProduct = product
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Header with radio button
                HStack(alignment: .top) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Spacer()

                    // Radio
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color.yellow : Color.gray.opacity(0.3), lineWidth: 2)
                            .frame(width: 20, height: 20)

                        if isSelected {
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 12, height: 12)
                        }
                    }
                }

                // Badge or placeholder (to maintain consistent height)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10))
                        .fontWeight(.bold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                } else {
                    // Transparent placeholder
                    Text(" ")
                        .font(.system(size: 10))
                        .fontWeight(.bold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .opacity(0)
                }

                // Description
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Price with period on the right
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(product.displayPrice)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("/ \(title.lowercased())")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .layoutPriority(-1)

                    Spacer()
                }
            }
            .padding(14)
            .background(GeometryReader { geo in
                Color.clear
                    .preference(key: CardWidthKey.self, value: geo.size.width)
                    .preference(key: CardHeightKey.self, value: geo.size.height)
            })
            .frame(minWidth: 180,
                   idealWidth: cardWidth > 0 ? cardWidth : nil,
                   maxWidth: cardWidth > 0 ? cardWidth : nil,
                   minHeight: cardHeight > 0 ? cardHeight : nil,
                   alignment: .top)
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature Comparison Section

    /// 功能比較項目定義
    private struct FeatureRow: Identifiable {
        let id: PaywallTrigger
        let icon: String
        let feature: String
        let freeValue: String
        let proValue: String
        let isCheckmark: Bool
    }

    /// 預設排序的功能比較項目
    private var defaultFeatures: [FeatureRow] {
        [
            FeatureRow(id: .packages, icon: "shippingbox.fill",
                       feature: String(localized: "paywall.comparison.packages"),
                       freeValue: String(localized: "paywall.comparison.packages.free"),
                       proValue: String(localized: "paywall.comparison.packages.pro"),
                       isCheckmark: false),
            FeatureRow(id: .ai, icon: "sparkles",
                       feature: String(localized: "paywall.comparison.ai"),
                       freeValue: String(localized: "paywall.comparison.ai.free"),
                       proValue: String(localized: "paywall.comparison.ai.pro"),
                       isCheckmark: true),
            FeatureRow(id: .widget, icon: "apps.iphone",
                       feature: String(localized: "paywall.comparison.widget"),
                       freeValue: String(localized: "paywall.comparison.widget.free"),
                       proValue: String(localized: "paywall.comparison.widget.pro"),
                       isCheckmark: false),
            FeatureRow(id: .spending, icon: "chart.pie.fill",
                       feature: String(localized: "paywall.comparison.spending"),
                       freeValue: String(localized: "paywall.comparison.spending.free"),
                       proValue: String(localized: "paywall.comparison.spending.pro"),
                       isCheckmark: true),
            FeatureRow(id: .homeStats, icon: "chart.bar.fill",
                       feature: String(localized: "paywall.comparison.homeStats"),
                       freeValue: String(localized: "paywall.comparison.homeStats.free"),
                       proValue: String(localized: "paywall.comparison.homeStats.pro"),
                       isCheckmark: true),
            FeatureRow(id: .themes, icon: "paintpalette.fill",
                       feature: String(localized: "paywall.comparison.themes"),
                       freeValue: String(localized: "paywall.comparison.themes.free"),
                       proValue: String(localized: "paywall.comparison.themes.pro"),
                       isCheckmark: false),
            FeatureRow(id: .notification, icon: "bell.badge.fill",
                       feature: String(localized: "paywall.comparison.notification"),
                       freeValue: String(localized: "paywall.comparison.notification.free"),
                       proValue: String(localized: "paywall.comparison.notification.pro"),
                       isCheckmark: true),
            FeatureRow(id: .savedLocations, icon: "mappin.and.ellipse",
                       feature: String(localized: "paywall.comparison.savedLocations"),
                       freeValue: String(localized: "paywall.comparison.savedLocations.free"),
                       proValue: String(localized: "paywall.comparison.savedLocations.pro"),
                       isCheckmark: false),
        ]
    }

    /// 依觸發來源排序的功能列表（觸發的排第一，其餘維持原順序）
    private var orderedFeatures: [FeatureRow] {
        guard trigger != .general else { return defaultFeatures }
        var features = defaultFeatures
        if let index = features.firstIndex(where: { $0.id == trigger }) {
            let item = features.remove(at: index)
            features.insert(item, at: 0)
        }
        return features
    }

    private var featureComparisonSection: some View {
        VStack(spacing: 0) {
            // Title
            Text(String(localized: "paywall.comparison.title"))
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            // Comparison Table
            VStack(spacing: 0) {
                // Header Row
                HStack(spacing: 0) {
                    Text("")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)

                    Text(String(localized: "paywall.comparison.free"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 80)

                    Text(String(localized: "paywall.comparison.pro"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.yellow)
                        .frame(width: 80)
                }
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.03))

                // Feature Rows
                ForEach(orderedFeatures) { feature in
                    Divider().background(Color.white.opacity(0.1))

                    let isTriggered = trigger != .general && feature.id == trigger
                    comparisonRow(
                        icon: feature.icon,
                        feature: feature.feature,
                        freeValue: feature.freeValue,
                        proValue: feature.proValue,
                        isCheckmark: feature.isCheckmark,
                        isHighlighted: isTriggered
                    )
                }
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private func comparisonRow(icon: String, feature: String, freeValue: String, proValue: String, isCheckmark: Bool = false, isHighlighted: Bool = false) -> some View {
        HStack(spacing: 0) {
            // Feature name with icon
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow)
                    .frame(width: 20)

                Text(feature)
                    .font(.subheadline)
                    .fontWeight(isHighlighted ? .bold : .medium)
                    .foregroundStyle(isHighlighted ? .yellow : .white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)

            // Free value
            Text(freeValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80)

            // Pro value
            if isCheckmark {
                Text(proValue)
                    .font(.body)
                    .foregroundStyle(.yellow)
                    .frame(width: 80)
            } else {
                Text(proValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.yellow)
                    .frame(width: 80)
            }
        }
        .padding(.vertical, 16)
        .background(isHighlighted && highlightTriggerFeature ? Color.yellow.opacity(0.08) : Color.clear)
        .animation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true), value: highlightTriggerFeature)
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        Button {
            if let product = selectedProduct {
                Task {
                    let success = await subscriptionManager.purchase(product)
                    if success {
                        AnalyticsService.logSubscriptionPurchased(productId: product.id)
                        dismiss()
                    }
                    if subscriptionManager.errorMessage != nil { showError = true }
                }
            } else {
                subscriptionManager.mockPurchase()
                dismiss()
            }
        } label: {
            ZStack {
                if subscriptionManager.isPurchasing {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text(actionButtonTitle)
                        .fontWeight(.bold)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.yellow, .orange],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.black)
            .clipShape(Capsule())
        }
        .disabled(subscriptionManager.isPurchasing)
    }
    
    private var actionButtonTitle: String {
        guard let product = selectedProduct else { return String(localized: "paywall.button.subscribe") }
        if SubscriptionProductID.allLifetimeIDs.contains(product.id) {
            return String(localized: "paywall.button.lifetime")
        } else if product.id == SubscriptionProductID.yearly.rawValue {
            return isTrialEligible
                ? String(localized: "paywall.button.trial")
                : String(localized: "paywall.button.subscribe")
        } else {
            return String(localized: "paywall.button.subscribe")
        }
    }
}

/// iOS 26 懸浮玻璃式，iOS 18 貼邊毛玻璃式
private struct PaywallBottomAreaModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .background(
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        } else {
            content
                .background(.ultraThinMaterial)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

// Helper for Hex Colors
// (Moved to Extensions/Color+Theme.swift)

#Preview {
    PaywallView()
}
