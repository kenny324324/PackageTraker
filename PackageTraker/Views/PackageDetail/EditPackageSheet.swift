import SwiftUI

/// 編輯包裹資訊 Sheet
struct EditPackageSheet: View {
    @Bindable var package: Package
    @Environment(\.dismiss) private var dismiss
    
    @State private var customName: String = ""
    @State private var selectedPlatform: String = ""
    @State private var selectedPaymentMethod: PaymentMethod?
    @State private var amountText: String = ""
    @State private var notes: String = ""
    @State private var userPickupLocation: String = ""
    @State private var showPlatformPicker = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 包裹資訊（不可編輯）
                    packageInfoSection
                    
                    Divider()
                        .background(Color.secondaryCardBackground)
                    
                    // 品名
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
            .navigationTitle(String(localized: "edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showPlatformPicker) {
                PlatformPickerSheet(selectedPlatform: $selectedPlatform)
                    .presentationDetents([.medium, .large])
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadCurrentValues()
        }
    }
    
    // MARK: - Views
    
    private var packageInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "edit.packageInfo"))
                .font(.headline)
            
            HStack(spacing: 12) {
                CarrierLogoView(carrier: package.carrier, size: 44)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.carrier.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(package.trackingNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
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
    
    // MARK: - Actions
    
    private func loadCurrentValues() {
        customName = package.customName ?? ""
        selectedPlatform = package.purchasePlatform ?? ""
        selectedPaymentMethod = package.paymentMethod
        if let amount = package.amount {
            amountText = String(Int(amount))
        } else {
            amountText = ""
        }
        notes = package.notes ?? ""
        userPickupLocation = package.userPickupLocation ?? ""
    }
    
    private func saveChanges() {
        package.customName = customName.isEmpty ? nil : customName
        package.purchasePlatform = selectedPlatform.isEmpty ? nil : selectedPlatform
        package.paymentMethod = selectedPaymentMethod
        package.amount = Double(amountText)
        package.notes = notes.isEmpty ? nil : notes
        package.userPickupLocation = userPickupLocation.isEmpty ? nil : userPickupLocation
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Preview

#Preview {
    EditPackageSheet(package: Package(
        trackingNumber: "TW123456789H",
        carrier: .shopee,
        customName: "藍牙耳機"
    ))
}
