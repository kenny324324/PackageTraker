//
//  AICarrierSelectView.swift
//  PackageTraker
//
//  使用者選擇物流商 → 選照片 → 進入 AI 掃描
//

import SwiftUI
import SwiftData
import PhotosUI

/// AI 掃描流程第一步：選擇物流商
struct AICarrierSelectView: View {
    let onDismiss: () -> Void  // 關閉整個 AI 流程（回首頁）

    @State private var selectedCarrier: Carrier?
    @State private var searchText = ""
    @State private var selectedImage: UIImage?
    @State private var showScanning = false
    @State private var showPaywall = false
    @State private var showCarrierAlert = false

    private var trackableCarriers: [Carrier] {
        Carrier.allCases.filter { $0.trackTwUUID != nil }
    }

    private var filteredCarriers: [Carrier] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return trackableCarriers }
        return trackableCarriers.filter { carrier in
            carrier.displayName.localizedCaseInsensitiveContains(keyword)
                || carrier.rawValue.localizedCaseInsensitiveContains(keyword)
                || carrier.abbreviation.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCarriers, id: \.rawValue) { carrier in
                    carrierRow(carrier)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $searchText, prompt: String(localized: "carrier.searchPlaceholder"))
            .adaptiveBackground()
            .navigationTitle(String(localized: "ai.carrierSelect.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        onDismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if selectedCarrier == nil {
                            showCarrierAlert = true
                        } else {
                            presentPhotoPicker()
                        }
                    } label: {
                        Text(String(localized: "ai.carrierSelect.next"))
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .tint(Color.appAccent)
                }
            }
            .alert(String(localized: "ai.carrierSelect.alert.title"), isPresented: $showCarrierAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "ai.carrierSelect.alert.message"))
            }
            .navigationDestination(isPresented: $showScanning) {
                if let carrier = selectedCarrier, let image = selectedImage {
                    AIScanningView(
                        carrier: carrier,
                        image: image,
                        onDismiss: onDismiss,
                        onCancel: { showScanning = false }
                    )
                }
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(lifetimeOnly: true)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Carrier Row

    private func carrierRow(_ carrier: Carrier) -> some View {
        Button {
            selectedCarrier = carrier
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CarrierLogoView(carrier: carrier, size: 32)
                    Text(carrier.displayName)
                        .foregroundStyle(.white)
                    Spacer()
                    if carrier == selectedCarrier {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.appAccent)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                Divider()
                    .padding(.leading, 56)
            }
        }
    }

    // MARK: - Present Photo Picker (UIKit)

    /// 直接用 UIKit present PHPickerViewController，不走 SwiftUI sheet
    private func presentPhotoPicker() {
        // 終身方案不限次數，其他方案先檢查本地快取的用量
        if !SubscriptionManager.shared.isLifetime {
            if AIVisionService.shared.remainingScans <= 0 {
                // 本地已歸零，需要 server 確認（在選完照片後再做也行，但先擋一次）
                Task {
                    let usage = await AIVisionService.shared.fetchUsageFromServer()
                    let remaining = max(0, usage.limit - usage.used)
                    if remaining <= 0 {
                        showPaywall = true
                        return
                    }
                    await MainActor.run { showPHPicker() }
                }
                return
            }
        }
        showPHPicker()
    }

    @MainActor
    private func showPHPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        // 找到最上層的 presented VC
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        let delegate = PHPickerDelegateHandler { [weak picker] image in
            picker?.dismiss(animated: true)
            if let image {
                self.selectedImage = image
                self.showScanning = true
            }
        }
        // 存到 picker 的 associated object 避免被 ARC 回收
        objc_setAssociatedObject(picker, &PHPickerDelegateHandler.associatedKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        picker.delegate = delegate
        topVC.present(picker, animated: true)
    }
}

// MARK: - PHPicker Delegate Handler

private final class PHPickerDelegateHandler: NSObject, PHPickerViewControllerDelegate {
    static var associatedKey: UInt8 = 0

    let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            completion(nil)
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
            DispatchQueue.main.async {
                self?.completion(image as? UIImage)
            }
        }
    }
}

// MARK: - Aurora Glow Background

/// 邊緣極光光暈 — 紫/藍/青色緩慢飄移，營造 AI 氛圍
private struct AuroraGlowBackground: View {
    @State private var phase: CGFloat = 0
    @State private var breathe: CGFloat = 1.0

    private let colors: [Color] = [
        Color(red: 0.4, green: 0.2, blue: 0.9),
        Color(red: 0.2, green: 0.3, blue: 1.0),
        Color(red: 0.1, green: 0.5, blue: 0.9),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 頂部極光（3 個橢圓）
                ForEach(0..<3, id: \.self) { i in
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    colors[i].opacity(0.35),
                                    colors[i].opacity(0.08),
                                    .clear,
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 160
                            )
                        )
                        .frame(
                            width: 300 + CGFloat(i) * 40,
                            height: 120 + CGFloat(i) * 20
                        )
                        .scaleEffect(breathe)
                        .offset(
                            x: sin(phase + Double(i) * 2.1) * 60,
                            y: -geo.size.height / 2 + 60 + CGFloat(i) * 20
                        )
                        .blur(radius: 50)
                        .opacity(0.22)
                }

                // 底部極光（2 個橢圓，較淡）
                ForEach(0..<2, id: \.self) { i in
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    colors[(i + 1) % 3].opacity(0.3),
                                    colors[(i + 2) % 3].opacity(0.06),
                                    .clear,
                                ],
                                center: .center,
                                startRadius: 15,
                                endRadius: 140
                            )
                        )
                        .frame(
                            width: 250 + CGFloat(i) * 30,
                            height: 100 + CGFloat(i) * 15
                        )
                        .scaleEffect(breathe)
                        .offset(
                            x: cos(phase + Double(i) * 1.8) * 50,
                            y: geo.size.height / 2 - 50 - CGFloat(i) * 15
                        )
                        .blur(radius: 45)
                        .opacity(0.13)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                breathe = 1.06
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AICarrierSelectView(onDismiss: {})
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
