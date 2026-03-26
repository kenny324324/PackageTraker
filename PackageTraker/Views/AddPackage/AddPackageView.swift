import SwiftUI
import SwiftData
import PhotosUI

/// 新增包裹 — 第一步：輸入單號 + 選擇物流商
struct AddPackageView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var existingPackages: [Package]

    @State private var trackingNumber = ""
    @State private var selectedCarrier: Carrier?
    @State private var selectedCategory: CarrierCategory = .convenienceStore
    @State private var showQueryPage = false
    @State private var showDuplicateAlert = false

    // OCR 相關狀態
    @State private var isProcessingOCR = false
    @State private var ocrResult: OCRResult?
    @State private var showOCRResultSheet = false
    @State private var showOCRError = false
    @State private var ocrErrorMessage = ""

    // 訂閱相關
    @State private var showPaywall = false

    private let ocrService = TrackingNumberOCRService.shared

    var body: some View {
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

                        let normalized = trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        if existingPackages.contains(where: { $0.trackingNumber == normalized }) {
                            showDuplicateAlert = true
                        } else {
                            showQueryPage = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .disabled(trackingNumber.isEmpty || selectedCarrier == nil)
                }
            }
            .navigationDestination(isPresented: $showQueryPage) {
                if let carrier = selectedCarrier {
                    PackageQueryView(
                        trackingNumber: trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                        carrier: carrier,
                        onComplete: { dismiss() },
                        popToRoot: { showQueryPage = false }
                    )
                }
            }
            .alert(String(localized: "error.duplicateTitle"), isPresented: $showDuplicateAlert) {
                Button(String(localized: "common.confirm"), role: .cancel) { }
            } message: {
                Text(String(localized: "error.duplicateMessage"))
            }
            .alert(String(localized: "error.ocrFailed"), isPresented: $showOCRError) {
                Button(String(localized: "common.confirm"), role: .cancel) { }
            } message: {
                Text(ocrErrorMessage)
            }
            .sheet(isPresented: $showOCRResultSheet) {
                if let result = ocrResult {
                    OCRResultSheet(result: result) { selection in
                        handleOCRSelection(selection)
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .fullScreenCover(isPresented: $showPaywall) {
                PaywallView()
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
                    presentOCRPhotoPicker()
                } label: {
                    HStack(spacing: 4) {
                        if isProcessingOCR {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "doc.text.viewfinder")
                        }
                        Text(String(localized: "add.ocrButton"))
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.appAccent)
                }
                .disabled(isProcessingOCR)
            }

            TextField(String(localized: "add.trackingNumberPlaceholder"), text: $trackingNumber)
                .textFieldStyle(.plain)
                .font(.system(size: 18, design: .monospaced))
                .adaptiveInputStyle()
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)

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
                            selectedCategory = category
                            selectedCarrier = nil
                        } label: {
                            if category == selectedCategory {
                                Label(category.displayName, systemImage: "checkmark")
                            } else {
                                Text(category.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedCategory.displayName)
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
                let carriers = Carrier.carriers(for: selectedCategory)
                ForEach(carriers, id: \.self) { carrier in
                    carrierButton(carrier)
                }
            }
        }
    }

    private func carrierButton(_ carrier: Carrier) -> some View {
        let isSelected = selectedCarrier == carrier

        return Button(action: { selectedCarrier = carrier }) {
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

    // MARK: - OCR

    /// 直接用 UIKit present PHPickerViewController，避免 SwiftUI PhotosPicker 在 fullScreenCover 中被意外關閉
    private func presentOCRPhotoPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        let delegate = OCRPhotoPickerDelegate { [ocrService] image in
            guard let image else { return }
            Task { @MainActor in
                await processPickedImage(image, ocrService: ocrService)
            }
        }
        objc_setAssociatedObject(picker, &OCRPhotoPickerDelegate.associatedKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        picker.delegate = delegate
        topVC.present(picker, animated: true)
    }

    @MainActor
    private func processPickedImage(_ uiImage: UIImage, ocrService: TrackingNumberOCRService) async {
        isProcessingOCR = true
        defer { isProcessingOCR = false }

        do {
            let result = try await ocrService.recognizeTrackingNumbers(from: uiImage)
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
            ocrErrorMessage = error.localizedDescription
            showOCRError = true
        }
    }

    private func handleOCRSelection(_ selection: OCRSelection) {
        trackingNumber = selection.trackingNumber

        if let suggestedCarrier = selection.suggestedCarrier,
           Carrier.supportedCarriers.contains(suggestedCarrier) {
            selectedCarrier = suggestedCarrier
            selectedCategory = suggestedCarrier.category
        }
    }

    // MARK: - Helpers

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - OCR Photo Picker Delegate

private final class OCRPhotoPickerDelegate: NSObject, PHPickerViewControllerDelegate {
    static var associatedKey: UInt8 = 0

    let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
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

// MARK: - Previews

#Preview {
    AddPackageView()
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
