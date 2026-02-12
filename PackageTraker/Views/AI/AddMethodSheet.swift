//
//  AddMethodSheet.swift
//  PackageTraker
//
//  新增方式選擇頁（AI 掃描 / 手動輸入）
//

import SwiftUI
import SwiftData
import PhotosUI

/// 新增包裹方式選擇 Sheet
struct AddMethodSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var aiPhotoItem: PhotosPickerItem?
    @State private var showAIScanningView = false
    @State private var selectedImage: UIImage?
    @State private var showManualAdd = false
    @State private var showPaywall = false
    @State private var contentHeight: CGFloat = 0

    private var adaptiveSheetHeight: CGFloat {
        max(184, min(248, contentHeight + 80))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                // AI 掃描按鈕
                PhotosPicker(selection: $aiPhotoItem, matching: .images) {
                    ZStack {
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.24, green: 0.56, blue: 1.00), location: 0.00), // blue
                                .init(color: Color(red: 0.62, green: 0.36, blue: 0.95), location: 0.36), // purple
                                .init(color: Color(red: 0.98, green: 0.23, blue: 0.38), location: 0.72), // red
                                .init(color: Color(red: 1.00, green: 0.53, blue: 0.18), location: 1.00) // orange
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
                    .shadow(color: Color(red: 0.19, green: 0.62, blue: 1.00).opacity(0.44), radius: 16, x: -8, y: 0)
                    .shadow(color: Color(red: 0.54, green: 0.42, blue: 1.00).opacity(0.30), radius: 15, x: 0, y: 0)
                    .shadow(color: Color(red: 1.00, green: 0.54, blue: 0.26).opacity(0.34), radius: 15, x: 8, y: 0)
                }
                .buttonStyle(.plain)

                // 手動輸入按鈕
                Button {
                    showManualAdd = true
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
        .presentationBackground(.clear)
        .onPreferenceChange(AddMethodContentHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
        }
        .onChange(of: aiPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await loadImage(from: newItem)
            }
        }
        .fullScreenCover(isPresented: $showAIScanningView, onDismiss: {
            selectedImage = nil
        }) {
            if let image = selectedImage {
                AIScanningView(image: image, onDismiss: {
                    showAIScanningView = false
                    dismiss()
                }, onCancel: {
                    showAIScanningView = false
                })
            }
        }
        .fullScreenCover(isPresented: $showManualAdd) {
            AddPackageView()
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
        .preferredColorScheme(.dark)
    }

    private func loadImage(from item: PhotosPickerItem) async {
        defer { aiPhotoItem = nil }

        // 訂閱檢查
        if FeatureFlags.subscriptionEnabled && !SubscriptionManager.shared.hasAIAccess {
            showPaywall = true
            return
        }

        guard let imageData = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: imageData) else {
            return
        }

        selectedImage = image
        showAIScanningView = true
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

// MARK: - Preview

#Preview {
    AddMethodSheet()
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
