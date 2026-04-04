//
//  AICarrierSelectView.swift
//  PackageTraker
//
//  使用者選擇物流商 → 選照片 → 進入 AI 掃描
//

import SwiftUI
import SwiftData
import PhotosUI

// MARK: - ViewModel（封裝 PHPicker/用量檢查相關邏輯）

@Observable
final class AICarrierSelectViewModel {
    var selectedCarrier: Carrier?
    var selectedImage: UIImage?
    var showScanning = false
    var showPaywall = false
    var showCarrierAlert = false
    var searchText = ""

    /// 檢查用量 → 呈現 PHPicker
    func checkUsageAndPresentPicker() {
        // 免費用戶走試用額度判斷
        if !SubscriptionManager.shared.hasAIAccess {
            let used = UserDefaults.standard.integer(forKey: "aiTrialUsedCount")
            if used >= 3 {
                showPaywall = true
            } else {
                presentPicker()
            }
            return
        }

        // 訂閱制用戶走每日額度判斷
        if !SubscriptionManager.shared.isLifetime {
            if AIVisionService.shared.remainingScans <= 0 {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let usage = await AIVisionService.shared.fetchUsageFromServer()
                    let remaining = max(0, usage.limit - usage.used)
                    if remaining <= 0 {
                        self.showPaywall = true
                    } else {
                        self.presentPicker()
                    }
                }
                return
            }
        }
        presentPicker()
    }

    /// 用 UIKit present PHPickerViewController
    func presentPicker() {
        guard let topVC = Self.topViewController() else { return }
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        let delegate = ImagePickerDelegate { [weak self] image in
            guard let self, let image else { return }
            print("🟢 [AI] ImagePickerDelegate 拿到圖片 \(image.size)")
            self.selectedImage = image
            self.showScanning = true
            print("🟢 [AI] showScanning = \(self.showScanning)")
        }
        objc_setAssociatedObject(picker, &ImagePickerDelegate.associatedKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        picker.delegate = delegate
        topVC.present(picker, animated: true)
    }

    static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}

// MARK: - PHPicker Delegate（callback-based，不用 continuation）

private final class ImagePickerDelegate: NSObject, PHPickerViewControllerDelegate {
    static var associatedKey: UInt8 = 0
    let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        if let provider = results.first?.itemProvider,
           provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
                DispatchQueue.main.async {
                    picker.dismiss(animated: true) {
                        self?.completion(image as? UIImage)
                    }
                }
            }
        } else {
            picker.dismiss(animated: true) { [weak self] in
                self?.completion(nil)
            }
        }
    }
}

// MARK: - AICarrierSelectView

/// AI 掃描流程第一步：選擇物流商
struct AICarrierSelectView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var vm = AICarrierSelectViewModel()

    private var trackableCarriers: [Carrier] {
        Carrier.allCases.filter { $0.trackTwUUID != nil }
    }

    private var filteredCarriers: [Carrier] {
        let keyword = vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return trackableCarriers }
        return trackableCarriers.filter { carrier in
            carrier.displayName.localizedCaseInsensitiveContains(keyword)
                || carrier.rawValue.localizedCaseInsensitiveContains(keyword)
                || carrier.abbreviation.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        @Bindable var vm = vm
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
            .searchable(text: $vm.searchText, prompt: String(localized: "carrier.searchPlaceholder"))
            .adaptiveBackground()
            .navigationTitle(String(localized: "ai.carrierSelect.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if vm.selectedCarrier == nil {
                            vm.showCarrierAlert = true
                        } else {
                            vm.checkUsageAndPresentPicker()
                        }
                    } label: {
                        Text(String(localized: "ai.carrierSelect.next"))
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .tint(Color.appAccent)
                }
            }
            .alert(String(localized: "ai.carrierSelect.alert.title"), isPresented: $vm.showCarrierAlert) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "ai.carrierSelect.alert.message"))
            }
            .navigationDestination(isPresented: $vm.showScanning) {
                if let carrier = vm.selectedCarrier, let image = vm.selectedImage {
                    AIScanningView(
                        carrier: carrier,
                        image: image,
                        onDismiss: { dismiss() },
                        onCancel: { vm.showScanning = false }
                    )
                }
            }
        }
        .fullScreenCover(isPresented: $vm.showPaywall) {
            PaywallView(lifetimeOnly: true)
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
    }

    // MARK: - Carrier Row

    private func carrierRow(_ carrier: Carrier) -> some View {
        Button {
            vm.selectedCarrier = carrier
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CarrierLogoView(carrier: carrier, size: 32)
                    Text(carrier.displayName)
                        .foregroundStyle(.white)
                    Spacer()
                    if carrier == vm.selectedCarrier {
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
    AICarrierSelectView()
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
