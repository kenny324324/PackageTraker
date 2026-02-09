import SwiftUI
import SwiftData

/// 新增包裹 — 第二步：填寫包裹額外資訊
struct PackageInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var existingPackages: [Package]

    let trackingNumber: String
    let carrier: Carrier
    let trackingResult: TrackingResult
    let relationId: String
    let onComplete: () -> Void
    let popToRoot: () -> Void

    @State private var customName = ""
    @State private var selectedPaymentMethod: PaymentMethod?
    @State private var amountText = ""
    @State private var selectedPlatform = ""
    @State private var notes = ""
    @State private var userPickupLocation = ""
    @State private var showPlatformPicker = false

    @State private var showErrorAlert = false
    @State private var errorTitle = ""
    @State private var errorMessage = ""
    @State private var showUpdateConfirmation = false
    @State private var duplicatePackage: Package?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                customNameSection
                platformSection
                pickupLocationSection

                Divider()
                    .background(Color.secondaryCardBackground)

                paymentMethodSection
                amountSection

                Divider()
                    .background(Color.secondaryCardBackground)

                notesSection
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            hideKeyboard()
        }
        .adaptiveBackground()
        .navigationTitle(String(localized: "add.packageInfo"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    popToRoot()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(String(localized: "add.title"))
                    }
                }
                .foregroundStyle(.white)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "add.button")) {
                    addPackage()
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
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
        .sheet(isPresented: $showPlatformPicker) {
            PlatformPickerSheet(selectedPlatform: $selectedPlatform)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Views

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

    private func findDuplicatePackage() -> Package? {
        existingPackages.first { pkg in
            pkg.trackingNumber == trackingNumber && pkg.carrier == carrier
        }
    }

    private var hasAdditionalInfo: Bool {
        !customName.isEmpty ||
        selectedPaymentMethod != nil ||
        !amountText.isEmpty ||
        !selectedPlatform.isEmpty ||
        !notes.isEmpty ||
        !userPickupLocation.isEmpty
    }

    // MARK: - Actions

    private func addPackage() {
        if let existing = findDuplicatePackage() {
            duplicatePackage = existing

            if hasAdditionalInfo {
                showUpdateConfirmation = true
            } else {
                errorTitle = String(localized: "error.duplicateTitle")
                errorMessage = String(localized: "error.duplicateMessage")
                showErrorAlert = true
            }
            return
        }

        let package = Package(
            trackingNumber: trackingNumber,
            carrier: carrier,
            customName: customName.isEmpty ? nil : customName,
            pickupCode: nil,
            pickupLocation: trackingResult.events.first?.location ?? carrier.defaultPickupLocation,
            status: trackingResult.currentStatus,
            latestDescription: trackingResult.events.first?.description,
            paymentMethod: selectedPaymentMethod,
            amount: Double(amountText),
            purchasePlatform: selectedPlatform.isEmpty ? nil : selectedPlatform,
            notes: notes.isEmpty ? nil : notes,
            userPickupLocation: userPickupLocation.isEmpty ? nil : userPickupLocation
        )
        package.trackTwRelationId = relationId

        if let storeName = trackingResult.storeName { package.storeName = storeName }
        if let serviceType = trackingResult.serviceType { package.serviceType = serviceType }
        if let pickupDeadline = trackingResult.pickupDeadline { package.pickupDeadline = pickupDeadline }

        for eventDTO in trackingResult.events {
            let event = TrackingEvent(
                timestamp: eventDTO.timestamp,
                status: eventDTO.status,
                description: eventDTO.description,
                location: eventDTO.location
            )
            event.package = package
            package.events.append(event)
        }

        modelContext.insert(package)
        try? modelContext.save()

        // 同步到 Firestore
        FirebaseSyncService.shared.syncPackage(package)

        onComplete()
    }

    private func updateExistingPackage() {
        guard let package = duplicatePackage else { return }

        if !customName.isEmpty { package.customName = customName }
        if let method = selectedPaymentMethod { package.paymentMethodRawValue = method.rawValue }
        if let amount = Double(amountText) { package.amount = amount }
        if !selectedPlatform.isEmpty { package.purchasePlatform = selectedPlatform }
        if !notes.isEmpty { package.notes = notes }
        if !userPickupLocation.isEmpty { package.userPickupLocation = userPickupLocation }

        try? modelContext.save()

        // 同步到 Firestore
        FirebaseSyncService.shared.syncPackage(package)

        onComplete()
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
