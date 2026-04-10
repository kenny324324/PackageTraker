import SwiftUI
import SwiftData

/// 取貨地點欄位 + 常用地點選取
struct PickupLocationPicker: View {
    @Binding var text: String
    @Query(sort: \SavedPickupLocation.createdAt, order: .reverse) private var savedLocations: [SavedPickupLocation]

    @State private var showLocationSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "add.pickupLocation"))
                .font(.headline)

            HStack(spacing: 8) {
                TextField(String(localized: "add.pickupLocationPlaceholder"), text: $text)
                    .textFieldStyle(.plain)

                if !savedLocations.isEmpty {
                    Button {
                        showLocationSheet = true
                    } label: {
                        Text(String(localized: "add.selectLocation.short"))
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .adaptiveInputStyle()
        }
        .sheet(isPresented: $showLocationSheet) {
            locationPickerSheet
        }
    }

    /// 組合顯示文字：「物流商名 地點名」
    private func displayText(for location: SavedPickupLocation) -> String {
        "\(location.carrier.displayName) \(location.name)"
    }

    // MARK: - Location Picker Sheet

    private var locationPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(savedLocations) { location in
                    Button {
                        text = displayText(for: location)
                        showLocationSheet = false
                    } label: {
                        HStack(spacing: 12) {
                            CarrierLogoView(carrier: location.carrier, size: 28)

                            Text(location.name)
                                .foregroundStyle(.white)

                            Spacer()

                            if text == displayText(for: location) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(String(localized: "add.selectLocation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        showLocationSheet = false
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            if #available(iOS 26, *) {
                Color.clear
            } else {
                Color.cardBackground
            }
        }
    }
}
