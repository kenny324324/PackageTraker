import SwiftUI
import SwiftData
import PhotosUI

// MARK: - ViewModel（封裝 OCR/PHPicker 相關邏輯）
@Observable
final class AddPackageViewModel {
    var trackingNumber = ""
    var selectedCarrier: Carrier?
    var selectedCategory: CarrierCategory = .convenienceStore

    // 導航狀態（放在 class 內避免 view 重建時遺失）
    var showQueryPage = false

    // OCR 相關狀態
    var isProcessingOCR = false
    var ocrResult: OCRResult?
    var showOCRResultSheet = false
    var showOCRError = false
    var ocrErrorMessage = ""

    private let ocrService = TrackingNumberOCRService.shared

    /// 呈現 PHPicker → 選完照片後自動跑 OCR
    func presentPickerAndRunOCR() {
        guard let topVC = Self.topViewController() else { return }
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        let delegate = OCRPickerDelegate { [weak self] image in
            guard let self, let image else { return }
            print("🟢 [OCR] ImagePickerDelegate 拿到圖片 \(image.size)")
            Task { @MainActor [weak self] in
                await self?.runOCR(on: image)
            }
        }
        objc_setAssociatedObject(picker, &OCRPickerDelegate.associatedKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        picker.delegate = delegate
        topVC.present(picker, animated: true)
    }

    @MainActor
    func runOCR(on image: UIImage) async {
        isProcessingOCR = true
        defer { isProcessingOCR = false }

        do {
            let result = try await ocrService.recognizeTrackingNumbers(from: image)
            print("🟢 [OCR] OCR 完成, candidates: \(result.trackingNumberCandidates.count)")
            ocrResult = result

            if result.trackingNumberCandidates.count == 1,
               let candidate = result.trackingNumberCandidates.first,
               candidate.confidence >= 0.9 {
                handleOCRSelection(OCRSelection(
                    trackingNumber: candidate.trackingNumber,
                    suggestedCarrier: candidate.suggestedCarrier
                ))
            } else {
                showOCRResultSheet = true
            }
        } catch {
            print("🔴 [OCR] OCR 錯誤: \(error)")
            ocrErrorMessage = error.localizedDescription
            showOCRError = true
        }
    }

    func handleOCRSelection(_ selection: OCRSelection) {
        trackingNumber = selection.trackingNumber

        if let suggestedCarrier = selection.suggestedCarrier,
           Carrier.supportedCarriers.contains(suggestedCarrier) {
            selectedCarrier = suggestedCarrier
            selectedCategory = suggestedCarrier.category
        }
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

// MARK: - PHPicker Delegate for OCR

private final class OCRPickerDelegate: NSObject, PHPickerViewControllerDelegate {
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

// MARK: - AddPackageView

/// 新增包裹 — 第一步：輸入單號 + 選擇物流商
struct AddPackageView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var existingPackages: [Package]

    @State private var vm = AddPackageViewModel()

    @State private var showDuplicateAlert = false
    @State private var showPaywall = false

    var body: some View {
        @Bindable var vm = vm
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    trackingNumberSection
                    carrierSelectionSection
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                hideKeyboard()
            }
            .adaptiveBackground()
            .navigationTitle(String(localized: "add.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "add.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "add.continue")) {
                        // 檢查包裹數量限制
                        let activeCount = existingPackages.filter { !$0.isArchived }.count
                        if FeatureFlags.subscriptionEnabled && activeCount >= SubscriptionManager.shared.maxPackageCount {
                            showPaywall = true
                            return
                        }

                        let normalized = vm.trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        if existingPackages.contains(where: { $0.trackingNumber == normalized }) {
                            showDuplicateAlert = true
                        } else {
                            vm.showQueryPage = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .disabled(vm.trackingNumber.isEmpty || vm.selectedCarrier == nil)
                }
            }
            .navigationDestination(isPresented: $vm.showQueryPage) {
                if let carrier = vm.selectedCarrier {
                    PackageQueryView(
                        trackingNumber: vm.trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                        carrier: carrier,
                        onComplete: { dismiss() },
                        popToRoot: { vm.showQueryPage = false }
                    )
                }
            }
            .alert(String(localized: "error.duplicateTitle"), isPresented: $showDuplicateAlert) {
                Button(String(localized: "common.confirm"), role: .cancel) { }
            } message: {
                Text(String(localized: "error.duplicateMessage"))
            }
            .alert(String(localized: "error.ocrFailed"), isPresented: $vm.showOCRError) {
                Button(String(localized: "common.confirm"), role: .cancel) { }
            } message: {
                Text(vm.ocrErrorMessage)
            }
            .fullScreenCover(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $vm.showOCRResultSheet) {
                if let result = vm.ocrResult {
                    OCRResultSheet(result: result) { selection in
                        vm.handleOCRSelection(selection)
                        vm.showOCRResultSheet = false
                    }
                    .presentationDetents([.medium, .large])
                    .preferredColorScheme(.dark)
                }
            }
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
    }

    // MARK: - Views

    private var trackingNumberSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "add.trackingNumber"))
                    .font(.headline)

                Spacer()

                Button {
                    vm.presentPickerAndRunOCR()
                } label: {
                    HStack(spacing: 4) {
                        if vm.isProcessingOCR {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "doc.text.viewfinder")
                        }
                        Text(String(localized: "add.ocrButton"))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                }
                .disabled(vm.isProcessingOCR)
            }

            HStack {
                TextField(String(localized: "add.trackingNumberPlaceholder"), text: $vm.trackingNumber)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)

                if vm.trackingNumber.isEmpty, UIPasteboard.general.hasStrings {
                    Button {
                        if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            vm.trackingNumber = text
                        }
                    } label: {
                        Label(String(localized: "common.paste"), systemImage: "doc.on.clipboard")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .adaptiveInputStyle()

            Text(String(localized: "add.supportedCarriers"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var availableCategories: [CarrierCategory] {
        CarrierCategory.allCases.filter { !Carrier.carriers(for: $0).isEmpty }
    }

    private var carrierSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "add.selectCarrier"))
                    .font(.headline)

                Spacer()

                Menu {
                    ForEach(availableCategories) { category in
                        Button {
                            vm.selectedCategory = category
                            vm.selectedCarrier = nil
                        } label: {
                            if category == vm.selectedCategory {
                                Label(category.displayName, systemImage: "checkmark")
                            } else {
                                Text(category.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(vm.selectedCategory.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .adaptiveCapsuleButtonStyle()
                }
            }

            VStack(spacing: 8) {
                let carriers = Carrier.carriers(for: vm.selectedCategory)
                ForEach(carriers, id: \.self) { carrier in
                    carrierButton(carrier)
                }
            }
        }
    }

    private func carrierButton(_ carrier: Carrier) -> some View {
        let isSelected = vm.selectedCarrier == carrier

        return Button(action: { vm.selectedCarrier = carrier }) {
            HStack(spacing: 12) {
                CarrierLogoView(carrier: carrier, size: 40)

                Text(carrier.displayName)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appAccent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.appAccent.opacity(0.1) : Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.appAccent : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Previews

#Preview {
    AddPackageView()
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
