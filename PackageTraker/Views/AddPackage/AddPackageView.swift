import SwiftUI
import SwiftData
import PhotosUI

/// 新增包裹頁面
struct AddPackageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // 查詢已存在的包裹（用於檢查重複）
    @Query private var existingPackages: [Package]

    @State private var trackingNumber = ""
    @State private var customName = ""
    @State private var selectedCarrier: Carrier?
    @State private var isLoading = false
    @State private var showErrorAlert = false
    @State private var errorTitle = ""
    @State private var errorMessage = ""
    
    // 更新確認對話框
    @State private var showUpdateConfirmation = false
    @State private var duplicatePackage: Package?
    
    // 包裹額外資訊
    @State private var selectedPaymentMethod: PaymentMethod?
    @State private var amountText = ""
    @State private var selectedPlatform = ""
    @State private var notes = ""
    @State private var userPickupLocation = ""
    @State private var showPlatformPicker = false
    
    // OCR 相關狀態
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingOCR = false
    @State private var ocrResult: OCRResult?
    @State private var showOCRResultSheet = false

    private let trackingManager = TrackingManager()
    private let ocrService = TrackingNumberOCRService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 單號輸入
                    trackingNumberSection

                    // 手動選擇物流商
                    carrierSelectionSection
                    
                    Divider()
                        .background(Color.secondaryCardBackground)

                    // 自訂名稱（可選）
                    customNameSection
                    
                    // 購買平台
                    platformSection
                    
                    // 取貨地點
                    pickupLocationSection
                    
                    Divider()
                        .background(Color.secondaryCardBackground)
                    
                    // 付款方式
                    paymentMethodSection
                    
                    // 金額
                    amountSection
                    
                    Divider()
                        .background(Color.secondaryCardBackground)
                    
                    // 備註
                    notesSection
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
                    if isLoading {
                        ProgressView()
                    } else {
                        Button(String(localized: "add.button")) {
                            Task { await addPackage() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.appAccent)
                        .disabled(trackingNumber.isEmpty || selectedCarrier == nil)
                    }
                }
            }
            .alert(errorTitle, isPresented: $showErrorAlert) {
                Button(String(localized: "common.confirm"), role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog(String(localized: "error.updateTitle"), isPresented: $showUpdateConfirmation, titleVisibility: .visible) {
                Button(String(localized: "common.update")) {
                    updateExistingPackage()
                }
                Button(String(localized: "common.cancel"), role: .cancel) { }
            } message: {
                Text(String(localized: "error.updateMessage"))
            }
            .sheet(isPresented: $showOCRResultSheet) {
                if let result = ocrResult {
                    OCRResultSheet(result: result) { selection in
                        handleOCRSelection(selection)
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $showPlatformPicker) {
                PlatformPickerSheet(selectedPlatform: $selectedPlatform)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                if let newItem {
                    Task {
                        await processSelectedImage(newItem)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Views

    private var trackingNumberSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "add.trackingNumber"))
                    .font(.headline)
                
                Spacer()
                
                // 截圖辨識按鈕
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

    private var carrierSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "add.selectCarrier"))
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(Carrier.supportedCarriers, id: \.self) { carrier in
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
                    .font(.subheadline)
                    .fontWeight(.medium)
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
                    .stroke(isSelected ? Color.appAccent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var customNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "add.productName"))
                .font(.headline)

            TextField(String(localized: "add.productNamePlaceholder"), text: $customName)
                .textFieldStyle(.plain)
                .adaptiveInputStyle()
        }
    }
    
    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "add.platform"))
                .font(.headline)
            
            Button {
                showPlatformPicker = true
            } label: {
                HStack {
                    Text(selectedPlatform.isEmpty ? String(localized: "add.platformPlaceholder") : selectedPlatform)
                        .foregroundStyle(selectedPlatform.isEmpty ? .secondary : .primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .adaptiveInputStyle()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
    
    private var pickupLocationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "add.pickupLocation"))
                .font(.headline)

            TextField(String(localized: "add.pickupLocationPlaceholder"), text: $userPickupLocation)
                .textFieldStyle(.plain)
                .adaptiveInputStyle()
        }
    }
    
    private var paymentMethodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "add.paymentMethod"))
                .font(.headline)
            
            Menu {
                Button(String(localized: "common.clear")) {
                    selectedPaymentMethod = nil
                }
                ForEach(PaymentMethod.allCases) { method in
                    Button {
                        selectedPaymentMethod = method
                    } label: {
                        Label(method.displayName, systemImage: method.iconName)
                    }
                }
            } label: {
                HStack {
                    if let method = selectedPaymentMethod {
                        Image(systemName: method.iconName)
                            .foregroundStyle(.secondary)
                        Text(method.displayName)
                            .foregroundStyle(.primary)
                    } else {
                        Text(String(localized: "add.selectPaymentMethod"))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .adaptiveInputStyle()
            }
            .foregroundStyle(.white)
        }
    }
    
    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "add.amount"))
                .font(.headline)
            
            HStack {
                Text("$")
                    .foregroundStyle(.secondary)
                
                TextField(String(localized: "add.amountPlaceholder"), text: $amountText)
                    .textFieldStyle(.plain)
                    .keyboardType(.numberPad)
                
                Spacer()
            }
            .adaptiveInputStyle()
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "add.notes"))
                .font(.headline)
            
            TextField(String(localized: "add.notesPlaceholder"), text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .adaptiveInputStyle()
        }
    }

    // MARK: - Duplicate Check

    private func findDuplicatePackage(trackingNumber: String, carrier: Carrier) -> Package? {
        existingPackages.first { pkg in
            pkg.trackingNumber == trackingNumber && pkg.carrier == carrier
        }
    }
    
    /// 檢查用戶是否有輸入任何額外資訊
    private var hasAdditionalInfo: Bool {
        !customName.isEmpty ||
        selectedPaymentMethod != nil ||
        !amountText.isEmpty ||
        !selectedPlatform.isEmpty ||
        !notes.isEmpty ||
        !userPickupLocation.isEmpty
    }

    // MARK: - Actions

    private func addPackage() async {
        guard let carrier = selectedCarrier else { return }

        let cleanedNumber = trackingNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // 檢查是否已新增過
        if let existing = findDuplicatePackage(trackingNumber: cleanedNumber, carrier: carrier) {
            duplicatePackage = existing
            
            if hasAdditionalInfo {
                // 有新資訊，詢問是否更新
                showUpdateConfirmation = true
            } else {
                // 沒有新資訊，顯示錯誤
                errorTitle = String(localized: "error.duplicateTitle")
                errorMessage = String(localized: "error.duplicateMessage")
                showErrorAlert = true
            }
            return
        }

        isLoading = true

        do {
            // 先嘗試追蹤，若失敗則不允許新增
            let result = try await trackingManager.track(number: cleanedNumber, carrier: carrier)

            // 追蹤成功，建立新包裹
            let package = Package(
                trackingNumber: cleanedNumber,
                carrier: carrier,
                customName: customName.isEmpty ? nil : customName,
                pickupCode: nil,
                pickupLocation: result.events.first?.location ?? carrier.defaultPickupLocation,
                status: result.currentStatus,
                latestDescription: result.events.first?.description,
                paymentMethod: selectedPaymentMethod,
                amount: Double(amountText),
                purchasePlatform: selectedPlatform.isEmpty ? nil : selectedPlatform,
                notes: notes.isEmpty ? nil : notes,
                userPickupLocation: userPickupLocation.isEmpty ? nil : userPickupLocation
            )

            // 加入追蹤事件
            for eventDTO in result.events {
                let event = TrackingEvent(
                    timestamp: eventDTO.timestamp,
                    status: eventDTO.status,
                    description: eventDTO.description,
                    location: eventDTO.location
                )
                event.package = package
                package.events.append(event)
            }

            // 儲存到 SwiftData
            modelContext.insert(package)

            try modelContext.save()

            await MainActor.run {
                isLoading = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorTitle = String(localized: "error.queryFailed")
                errorMessage = mapErrorMessage(error)
                showErrorAlert = true
            }
        }
    }
    
    /// 更新已存在的包裹資訊
    private func updateExistingPackage() {
        guard let package = duplicatePackage else { return }
        
        // 更新用戶輸入的額外資訊
        if !customName.isEmpty {
            package.customName = customName
        }
        if let method = selectedPaymentMethod {
            package.paymentMethodRawValue = method.rawValue
        }
        if let amount = Double(amountText) {
            package.amount = amount
        }
        if !selectedPlatform.isEmpty {
            package.purchasePlatform = selectedPlatform
        }
        if !notes.isEmpty {
            package.notes = notes
        }
        if !userPickupLocation.isEmpty {
            package.userPickupLocation = userPickupLocation
        }
        
        try? modelContext.save()
        dismiss()
    }

    private func mapErrorMessage(_ error: Error) -> String {
        if let trackingError = error as? TrackingError {
            switch trackingError {
            case .trackingNumberNotFound:
                return "查無此單號，請確認單號是否正確"
            case .unsupportedCarrier:
                return "不支援此物流商"
            case .networkError:
                return "網路連線失敗，請稍後再試"
            case .parsingError:
                return "資料解析失敗，請稍後再試"
            case .invalidResponse:
                return "伺服器回應錯誤，請稍後再試"
            case .rateLimited:
                return "查詢過於頻繁，請稍後再試"
            case .invalidTrackingNumber:
                return "單號格式不正確，請檢查是否輸入正確"
            }
        }
        return "追蹤失敗：\(error.localizedDescription)"
    }
    
    // MARK: - OCR Processing
    
    /// 處理選取的圖片並進行 OCR 辨識
    private func processSelectedImage(_ item: PhotosPickerItem) async {
        isProcessingOCR = true
        
        defer {
            // 重置 PhotosPicker 選取狀態
            selectedPhotoItem = nil
            isProcessingOCR = false
        }
        
        do {
            // 載入圖片資料
            guard let imageData = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: imageData) else {
                await MainActor.run {
                    errorTitle = String(localized: "error.imageLoadFailed")
                    errorMessage = String(localized: "error.imageLoadFailed")
                    showErrorAlert = true
                }
                return
            }
            
            // 執行 OCR
            let result = try await ocrService.recognizeTrackingNumbers(from: uiImage)
            
            await MainActor.run {
                ocrResult = result
                
                // 如果只有一個高信心度的結果，直接填入
                if result.trackingNumberCandidates.count == 1,
                   let candidate = result.trackingNumberCandidates.first,
                   candidate.confidence >= 0.9 {
                    handleOCRSelection(OCRSelection(
                        trackingNumber: candidate.trackingNumber,
                        suggestedCarrier: candidate.suggestedCarrier
                    ))
                } else {
                    // 否則顯示結果讓使用者選擇
                    showOCRResultSheet = true
                }
            }
        } catch {
            await MainActor.run {
                errorTitle = String(localized: "error.ocrFailed")
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
    
    /// 處理 OCR 選取結果
    private func handleOCRSelection(_ selection: OCRSelection) {
        // 填入單號
        trackingNumber = selection.trackingNumber
        
        // 如果有建議的物流商，且在支援清單中，自動選取
        if let suggestedCarrier = selection.suggestedCarrier,
           Carrier.supportedCarriers.contains(suggestedCarrier) {
            selectedCarrier = suggestedCarrier
        }
    }
    
    /// 隱藏鍵盤
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Previews

#Preview {
    AddPackageView()
        .modelContainer(for: [Package.self, TrackingEvent.self], inMemory: true)
}
