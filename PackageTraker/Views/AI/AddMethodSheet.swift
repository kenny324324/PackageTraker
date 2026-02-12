//
//  AddMethodSheet.swift
//  PackageTraker
//
//  新增方式選擇頁（AI 掃描 / 手動輸入）
//

import SwiftUI
import SwiftData
import PhotosUI
import FluidGradient

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
        max(210, min(300, contentHeight + 92))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // AI 掃描按鈕
                PhotosPicker(selection: $aiPhotoItem, matching: .images) {
                    ZStack {
                        FluidGradient(
                            blobs: [
                                Color(red: 0.5, green: 0.2, blue: 0.8),
                                Color(red: 0.2, green: 0.4, blue: 0.9),
                                Color(red: 0.9, green: 0.3, blue: 0.7)
                            ],
                            highlights: [
                                .white.opacity(0.25),
                                Color(red: 0.7, green: 0.55, blue: 1.0),
                                Color(red: 0.55, green: 0.75, blue: 1.0)
                            ],
                            speed: 1.0,
                            blur: 0.8
                        )
                        .overlay(Color.black.opacity(0.14))

                        HStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder")
                                .font(.title3)
                                .foregroundStyle(.white)

                            Text(String(localized: "addMethod.aiScan.title"))
                                .font(.headline)
                                .foregroundStyle(.white)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .frame(height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                // 手動輸入按鈕
                Button {
                    showManualAdd = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.title3)
                        Text(String(localized: "addMethod.manualInput"))
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondaryCardBackground)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 6)
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

// MARK: - Preview

#Preview {
    AddMethodSheet()
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
