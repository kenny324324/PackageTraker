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
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    featureComparisonSection
                    productCardsSection
                    purchaseButton
                    footerSection
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .adaptiveBackground()
            .navigationTitle(String(localized: "paywall.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
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
                // 預設選年費
                if selectedProduct == nil {
                    selectedProduct = subscriptionManager.yearlyProduct ?? subscriptionManager.monthlyProduct
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(String(localized: "paywall.headline"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text(String(localized: "paywall.subheadline"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }

    // MARK: - Feature Comparison

    private var featureComparisonSection: some View {
        VStack(spacing: 0) {
            // 標題列
            HStack {
                Text(String(localized: "paywall.features"))
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(String(localized: "paywall.free"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50)
                Text(String(localized: "paywall.pro"))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.yellow)
                    .frame(width: 50)
            }
            .padding(16)

            Divider().background(Color.white.opacity(0.1))

            featureRow(String(localized: "paywall.feature.packages"), free: "5", pro: "∞")
            Divider().background(Color.white.opacity(0.1))
            featureRow(String(localized: "paywall.feature.themes"), free: "1", pro: "8")
            Divider().background(Color.white.opacity(0.1))
            featureRow(String(localized: "paywall.feature.ocr"), freeCheck: true, proCheck: true)
            Divider().background(Color.white.opacity(0.1))
            featureRow(String(localized: "paywall.feature.ai"), freeCheck: false, proCheck: true)
            Divider().background(Color.white.opacity(0.1))
            featureRow(String(localized: "paywall.feature.widget"), freeCheck: false, proCheck: true)
            Divider().background(Color.white.opacity(0.1))
            featureRow(String(localized: "paywall.feature.push"), freeCheck: true, proCheck: true)
        }
        .background(Color.secondaryCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func featureRow(_ title: String, free: String? = nil, pro: String? = nil, freeCheck: Bool? = nil, proCheck: Bool? = nil) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white)

            Spacer()

            if let free = free {
                Text(free)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 50)
            } else if let check = freeCheck {
                Image(systemName: check ? "checkmark" : "xmark")
                    .font(.caption)
                    .foregroundStyle(check ? .green : .secondary.opacity(0.5))
                    .frame(width: 50)
            }

            if let pro = pro {
                Text(pro)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.yellow)
                    .frame(width: 50)
            } else if let check = proCheck {
                Image(systemName: check ? "checkmark" : "xmark")
                    .font(.caption)
                    .foregroundStyle(check ? .green : .secondary.opacity(0.5))
                    .frame(width: 50)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Product Cards

    private var productCardsSection: some View {
        VStack(spacing: 12) {
            if let yearly = subscriptionManager.yearlyProduct {
                productCard(yearly, badge: String(localized: "paywall.bestValue"))
            }
            if let monthly = subscriptionManager.monthlyProduct {
                productCard(monthly, badge: nil)
            }

            if subscriptionManager.products.isEmpty {
                Text(String(localized: "paywall.loadingProducts"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            }
        }
    }

    private func productCard(_ product: Product, badge: String?) -> some View {
        let isSelected = selectedProduct?.id == product.id

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedProduct = product
            }
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.id == SubscriptionProductID.yearly.rawValue
                             ? String(localized: "paywall.yearly")
                             : String(localized: "paywall.monthly"))
                            .font(.headline)
                            .foregroundStyle(.white)

                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.yellow)
                                .clipShape(Capsule())
                        }
                    }

                    Text(product.displayPrice + periodSuffix(product))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .yellow : .secondary)
            }
            .padding(16)
            .background(isSelected ? Color.yellow.opacity(0.08) : Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.yellow.opacity(0.5) : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func periodSuffix(_ product: Product) -> String {
        if product.id == SubscriptionProductID.yearly.rawValue {
            return " / " + String(localized: "paywall.year")
        }
        return " / " + String(localized: "paywall.month")
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        VStack(spacing: 12) {
            Button {
                if let product = selectedProduct {
                    // 有 StoreKit 產品：正式購買流程
                    Task {
                        let success = await subscriptionManager.purchase(product)
                        if success { dismiss() }
                        if subscriptionManager.errorMessage != nil { showError = true }
                    }
                } else {
                    // 沒有 StoreKit 產品：mock 購買
                    subscriptionManager.mockPurchase()
                    dismiss()
                }
            } label: {
                HStack {
                    if subscriptionManager.isPurchasing {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(String(localized: "paywall.subscribe"))
                        .fontWeight(.bold)
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
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(subscriptionManager.isPurchasing)

            // 恢復購買
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
                        .scaleEffect(0.8)
                } else {
                    Text(String(localized: "paywall.restore"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isRestoring)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            Text(String(localized: "paywall.termsNote"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button {
                    if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(String(localized: "paywall.terms"))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }

                Button {
                    if let url = URL(string: "https://ripe-cereal-4f9.notion.site/Privacy-Policy-302341fcbfde81d589a2e4ba6713b911") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(String(localized: "paywall.privacy"))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
}
