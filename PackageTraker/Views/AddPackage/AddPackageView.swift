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
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingOCR = false
    @State private var ocrResult: OCRResult?
    @State private var showOCRResultSheet = false
    @State private var showOCRError = false
    @State private var ocrErrorMessage = ""

    // AI 辨識相關狀態
    @State private var aiPhotoItem: PhotosPickerItem?
    @State private var isProcessingAI = false
    @State private var aiResult: AIVisionResult?
    @State private var showAIResultSheet = false
    @State private var showAIError = false
    @State private var aiErrorMessage = ""

    // 訂閱相關
    @State private var showPaywall = false

    // AI 辨識結果中的額外欄位（傳遞到 PackageInfoView）
    @State private var aiPickupLocation: String?
    @State private var aiPickupCode: String?
    @State private var aiPackageName: String?

    private let ocrService = TrackingNumberOCRService.shared
    private let aiService = AIVisionService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    trackingNumberSection

                    if FeatureFlags.aiVisionEnabled {
                        aiPromotionSection
                    }

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
                        popToRoot: { showQueryPage = false },
                        prefillName: aiPackageName,
                        prefillPickupLocation: aiPickupLocation,
                        prefillPickupCode: aiPickupCode
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
            .sheet(isPresented: $showAIResultSheet) {
                if let result = aiResult {
                    AIVisionResultSheet(result: result) { selection in
                        handleAISelection(selection)
                    }
                    .presentationDetents([.large])
                }
            }
            .alert(String(localized: "ai.error.title"), isPresented: $showAIError) {
                Button(String(localized: "common.confirm"), role: .cancel) { }
            } message: {
                Text(aiErrorMessage)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                if let newItem {
                    Task {
                        await processSelectedImage(newItem)
                    }
                }
            }
            .onChange(of: aiPhotoItem) { _, newItem in
                if let newItem {
                    Task {
                        await processAIImage(newItem)
                    }
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

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
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

    // MARK: - AI Promotion

    @ViewBuilder
    private var aiPromotionSection: some View {
        if SubscriptionManager.shared.hasAIAccess {
            // Pro 用戶：直接開啟圖片選擇器
            PhotosPicker(
                selection: $aiPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                aiPromotionCardLabel
            }
            .buttonStyle(.plain)
            .disabled(isProcessingAI)
        } else {
            // 免費用戶：顯示付費牆
            Button { showPaywall = true } label: {
                aiPromotionCardLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var aiPromotionCardLabel: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(String(localized: "ai.card.title"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    if !SubscriptionManager.shared.hasAIAccess {
                        Text("PRO")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                    }
                }

                Text(String(localized: "ai.card.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isProcessingAI {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.15), Color.blue.opacity(0.10)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - AI Processing

    private func processAIImage(_ item: PhotosPickerItem) async {
        isProcessingAI = true

        defer {
            aiPhotoItem = nil
            isProcessingAI = false
        }

        do {
            guard let imageData = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: imageData) else {
                await MainActor.run {
                    aiErrorMessage = String(localized: "error.imageLoadFailed")
                    showAIError = true
                }
                return
            }

            let result = try await aiService.analyzePackageImage(uiImage)

            await MainActor.run {
                aiResult = result
                showAIResultSheet = true
            }
        } catch {
            await MainActor.run {
                aiErrorMessage = error.localizedDescription
                showAIError = true
            }
        }
    }

    private func handleAISelection(_ selection: AIVisionSelection) {
        trackingNumber = selection.trackingNumber

        if let carrier = selection.carrier,
           Carrier.supportedCarriers.contains(carrier) {
            selectedCarrier = carrier
            selectedCategory = carrier.category
        }

        aiPickupLocation = selection.pickupLocation
        aiPickupCode = selection.pickupCode
        aiPackageName = selection.packageName
    }

    // MARK: - OCR

    private func processSelectedImage(_ item: PhotosPickerItem) async {
        isProcessingOCR = true

        defer {
            selectedPhotoItem = nil
            isProcessingOCR = false
        }

        do {
            guard let imageData = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: imageData) else {
                await MainActor.run {
                    ocrErrorMessage = String(localized: "error.imageLoadFailed")
                    showOCRError = true
                }
                return
            }

            let result = try await ocrService.recognizeTrackingNumbers(from: uiImage)

            await MainActor.run {
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
            }
        } catch {
            await MainActor.run {
                ocrErrorMessage = error.localizedDescription
                showOCRError = true
            }
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

// MARK: - Previews

#Preview {
    AddPackageView()
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
