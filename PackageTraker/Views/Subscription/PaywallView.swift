//
//  PaywallView.swift
//  PackageTraker
//
//  Subscription paywall UI
//

import SwiftUI
import StoreKit

/// 付費牆
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @State private var selectedProduct: Product?
    @State private var showError = false
    @State private var showRestoreSuccess = false
    @State private var isRestoring = false

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

                        // 訂閱方案選擇
                        planSelectionSection
                    }
                    .padding(.bottom, 200) // Space for bottom button area
                }

                // 固定在底部的訂閱按鈕
                VStack(spacing: 0) {
                    Spacer()
                    
                    // 底部區域背景
                    VStack(spacing: 0) {
                        // Terms text
                        Text(String(localized: "paywall.termsNote"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 16)
                        
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
                    }
                    .padding(20)
                    .background(
                        Group {
                            if #available(iOS 26, *) {
                                Rectangle()
                                    .fill(.clear)
                                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
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
                            .foregroundStyle(.white.opacity(0.8))
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
            .onAppear {
                // 預設選 Lifetime
                if selectedProduct == nil {
                    selectedProduct = subscriptionManager.lifetimeProduct
                        ?? subscriptionManager.yearlyProduct
                        ?? subscriptionManager.monthlyProduct
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
                if let lifetime = subscriptionManager.lifetimeProduct {
                    lifetimePlanCard(product: lifetime)
                }

                // Yearly
                if let yearly = subscriptionManager.yearlyProduct {
                    standardPlanCard(product: yearly, badge: String(localized: "paywall.badge.bestValue"), subtitle: String(localized: "paywall.trial"))
                }

                // Monthly
                if let monthly = subscriptionManager.monthlyProduct {
                    standardPlanCard(product: monthly, badge: nil, subtitle: String(localized: "paywall.cancelAnytime"))
                }
            }
            .padding(.horizontal, 20)
        }
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
            }
            .frame(width: 140)
            .padding(14)
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
            .shadow(color: .orange.opacity(isSelected ? 0.4 : 0), radius: 10, x: 0, y: 5)
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

                    Text("/ \(title.lowercased())")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
            .frame(width: 140)
            .padding(14)
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

                Divider().background(Color.white.opacity(0.1))

                // Feature Rows
                comparisonRow(
                    icon: "shippingbox.fill",
                    feature: String(localized: "paywall.comparison.packages"),
                    freeValue: String(localized: "paywall.comparison.packages.free"),
                    proValue: String(localized: "paywall.comparison.packages.pro")
                )

                Divider().background(Color.white.opacity(0.1))

                comparisonRow(
                    icon: "paintpalette.fill",
                    feature: String(localized: "paywall.comparison.themes"),
                    freeValue: String(localized: "paywall.comparison.themes.free"),
                    proValue: String(localized: "paywall.comparison.themes.pro")
                )

                Divider().background(Color.white.opacity(0.1))

                comparisonRow(
                    icon: "sparkles",
                    feature: String(localized: "paywall.comparison.ai"),
                    freeValue: String(localized: "paywall.comparison.ai.free"),
                    proValue: String(localized: "paywall.comparison.ai.pro"),
                    isCheckmark: true
                )

                Divider().background(Color.white.opacity(0.1))

                comparisonRow(
                    icon: "apps.iphone",
                    feature: String(localized: "paywall.comparison.widget"),
                    freeValue: String(localized: "paywall.comparison.widget.free"),
                    proValue: String(localized: "paywall.comparison.widget.pro")
                )
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private func comparisonRow(icon: String, feature: String, freeValue: String, proValue: String, isCheckmark: Bool = false) -> some View {
        HStack(spacing: 0) {
            // Feature name with icon
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.yellow)
                    .frame(width: 20)

                Text(feature)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
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
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        Button {
            if let product = selectedProduct {
                Task {
                    let success = await subscriptionManager.purchase(product)
                    if success { dismiss() }
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
        if product.id == SubscriptionProductID.lifetime.rawValue {
            return String(localized: "paywall.button.lifetime")
        } else if product.id == SubscriptionProductID.yearly.rawValue {
            return String(localized: "paywall.button.trial")
        } else {
            return String(localized: "paywall.button.subscribe")
        }
    }
}

// Helper for Hex Colors
// (Moved to Extensions/Color+Theme.swift)

#Preview {
    PaywallView()
}
