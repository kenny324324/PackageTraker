import SwiftUI
import SwiftData

/// 常用取貨地點管理頁面
struct SavedLocationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPickupLocation.createdAt, order: .reverse) private var locations: [SavedPickupLocation]
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var promoManager = LaunchPromoManager.shared

    @State private var showAddSheet = false
    @State private var showPaywall = false
    @State private var editingLocation: SavedPickupLocation?

    /// 免費用戶最多 3 個常用地點
    private static let freeLimit = 3

    /// 超商門市（用於分組判斷）
    private static let storeCarriers: Set<Carrier> = [.shopee, .sevenEleven, .familyMart, .hiLife, .okMart]

    private var canAddMore: Bool {
        subscriptionManager.isPro || locations.count < Self.freeLimit
    }

    /// 取得分組用的 key（超商各自分組，其餘都歸「其他」）
    private func groupKey(for location: SavedPickupLocation) -> Carrier {
        Self.storeCarriers.contains(location.carrier) ? location.carrier : .other
    }

    /// 依門市分組
    private var groupedByCarrier: [Carrier: [SavedPickupLocation]] {
        Dictionary(grouping: locations) { groupKey(for: $0) }
    }

    /// 固定順序（與新增頁面一致）
    private static let carrierOrder: [Carrier] = [.shopee, .sevenEleven, .familyMart, .hiLife, .okMart, .other]

    /// 排序後的門市列表（依固定順序，只顯示有資料的）
    private var sortedCarriers: [Carrier] {
        Self.carrierOrder.filter { groupedByCarrier[$0] != nil }
    }

    var body: some View {
        ScrollView {
            if locations.isEmpty {
                emptyStateView
                    .padding()
            } else {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sortedCarriers, id: \.self) { carrier in
                        if let carrierLocations = groupedByCarrier[carrier] {
                            VStack(alignment: .leading, spacing: 12) {
                                // 門市標題
                                HStack(spacing: 6) {
                                    CarrierLogoView(carrier: carrier, size: 24)

                                    Text(carrier.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                }

                                // 卡片式列表
                                VStack(spacing: 0) {
                                    ForEach(Array(carrierLocations.enumerated()), id: \.element.id) { index, location in
                                        locationRow(location)

                                        if index < carrierLocations.count - 1 {
                                            Divider()
                                                .padding(.leading, 16)
                                        }
                                    }
                                }
                                .background(Color.secondaryCardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }

                    // 免費用戶達上限：限時優惠 banner 或升級提示
                    if !subscriptionManager.isPro && locations.count >= Self.freeLimit {
                        if promoManager.isPromoActive {
                            PromoBanner(
                                onTap: { showPaywall = true },
                                onDismiss: { }
                            )
                        } else {
                            Button {
                                showPaywall = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(Color.appAccent)

                                    Text(String(localized: "savedLocations.unlockMore"))
                                        .foregroundStyle(Color.appAccent)

                                    Spacer()
                                }
                                .padding(16)
                                .background(Color.secondaryCardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
        }
        .adaptiveBackground()
        .navigationTitle(String(localized: "savedLocations.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if canAddMore {
                        showAddSheet = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditLocationSheet(
                mode: .add,
                isDuplicate: { isDuplicate(name: $0, carrier: $1) },
                onSave: { addLocation(name: $0, carrier: $1) }
            )
        }
        .sheet(item: $editingLocation) { location in
            AddEditLocationSheet(
                mode: .edit(name: location.name, carrier: location.carrier),
                isDuplicate: { isDuplicate(name: $0, carrier: $1, excludingId: location.id) },
                onSave: { saveEdit(location: location, name: $0, carrier: $1) }
            )
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(trigger: .savedLocations)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 60)

            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(String(localized: "savedLocations.empty"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(String(localized: "savedLocations.addHint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Location Row

    private func locationRow(_ location: SavedPickupLocation) -> some View {
        HStack(spacing: 12) {
            // 非超商門市：顯示實際物流商 icon
            if !Self.storeCarriers.contains(location.carrier) && location.carrier != .other {
                CarrierLogoView(carrier: location.carrier, size: 28)
            }

            Text(location.name)
                .foregroundStyle(.white)

            Spacer()

            Button {
                editingLocation = location
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                editingLocation = location
            } label: {
                Label(String(localized: "savedLocations.edit"), systemImage: "pencil")
            }

            Button(role: .destructive) {
                deleteLocation(location)
            } label: {
                Label(String(localized: "common.delete"), systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func isDuplicate(name: String, carrier: Carrier, excludingId: UUID? = nil) -> Bool {
        let groupKey: Carrier = Self.storeCarriers.contains(carrier) ? carrier : .other
        return locations.contains { loc in
            let locGroupKey: Carrier = Self.storeCarriers.contains(loc.carrier) ? loc.carrier : .other
            return loc.name == name && locGroupKey == groupKey && loc.id != (excludingId ?? UUID())
        }
    }

    private func addLocation(name: String, carrier: Carrier) {
        guard !isDuplicate(name: name, carrier: carrier) else { return }
        let location = SavedPickupLocation(name: name, carrier: carrier)
        modelContext.insert(location)
        try? modelContext.save()
        FirebaseSyncService.shared.syncSavedLocation(location)
    }

    private func saveEdit(location: SavedPickupLocation, name: String, carrier: Carrier) {
        location.name = name
        location.carrier = carrier
        try? modelContext.save()
        FirebaseSyncService.shared.syncSavedLocation(location)
    }

    private func deleteLocation(_ location: SavedPickupLocation) {
        let locationId = location.id
        modelContext.delete(location)
        try? modelContext.save()
        FirebaseSyncService.shared.deleteSavedLocation(locationId)
    }
}

// MARK: - Add/Edit Location Sheet

struct AddEditLocationSheet: View {
    enum Mode {
        case add
        case edit(name: String, carrier: Carrier)
    }

    let mode: Mode
    var isDuplicate: (String, Carrier) -> Bool = { _, _ in false }
    let onSave: (String, Carrier) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var locationName: String
    @State private var selectedCarrier: Carrier
    @State private var isOtherSelected: Bool
    @State private var showDuplicateAlert = false

    /// 超商門市選項
    private static let storeCarriers: [Carrier] = [
        .shopee, .sevenEleven, .familyMart, .hiLife, .okMart
    ]

    /// 其他物流商 icon 選項
    private static let otherCarriers: [Carrier] = [
        .other, .tcat, .hct, .ecan, .postTW, .pchome, .momo, .kerry,
        .taiwanExpress, .dhl, .fedex, .ups, .sfExpress, .customs
    ]

    init(mode: Mode, isDuplicate: @escaping (String, Carrier) -> Bool = { _, _ in false }, onSave: @escaping (String, Carrier) -> Void) {
        self.mode = mode
        self.isDuplicate = isDuplicate
        self.onSave = onSave
        let storeSet = Set(Self.storeCarriers)
        switch mode {
        case .add:
            _locationName = State(initialValue: "")
            _selectedCarrier = State(initialValue: .sevenEleven)
            _isOtherSelected = State(initialValue: false)
        case .edit(let name, let carrier):
            _locationName = State(initialValue: name)
            _selectedCarrier = State(initialValue: carrier)
            _isOtherSelected = State(initialValue: !storeSet.contains(carrier))
        }
    }

    private var isAdd: Bool {
        if case .add = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                // 地點名稱
                Section {
                    TextField(String(localized: "savedLocations.namePlaceholder"), text: $locationName)
                } header: {
                    Text(String(localized: "savedLocations.locationName"))
                }

                // 門市選擇
                Section {
                    ForEach(Self.storeCarriers) { carrier in
                        Button {
                            selectedCarrier = carrier
                            isOtherSelected = false
                        } label: {
                            HStack(spacing: 12) {
                                CarrierLogoView(carrier: carrier, size: 28)

                                Text(carrier.displayName)
                                    .foregroundStyle(.white)

                                Spacer()

                                if !isOtherSelected && selectedCarrier == carrier {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                    }

                    // 其他選項
                    Button {
                        isOtherSelected = true
                        selectedCarrier = .other
                    } label: {
                        HStack(spacing: 12) {
                            CarrierLogoView(carrier: .other, size: 28)

                            Text(Carrier.other.displayName)
                                .foregroundStyle(.white)

                            Spacer()

                            if isOtherSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                    }

                    // 選了「其他」時展開 icon 選擇
                    if isOtherSelected {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Self.otherCarriers) { carrier in
                                    Button {
                                        selectedCarrier = carrier
                                    } label: {
                                        CarrierLogoView(carrier: carrier, size: 36)
                                            .overlay {
                                                if selectedCarrier == carrier {
                                                    RoundedRectangle(cornerRadius: 9)
                                                        .stroke(Color.appAccent, lineWidth: 2.5)
                                                        .frame(width: 40, height: 40)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                } header: {
                    Text(String(localized: "savedLocations.store"))
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(isAdd ? String(localized: "savedLocations.add") : String(localized: "savedLocations.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.confirm")) {
                        let trimmed = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        if isDuplicate(trimmed, selectedCarrier) {
                            showDuplicateAlert = true
                        } else {
                            onSave(trimmed, selectedCarrier)
                            dismiss()
                        }
                    }
                    .tint(Color.appAccent)
                    .foregroundStyle(.white)
                    .disabled(locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert(String(localized: "savedLocations.duplicateTitle"), isPresented: $showDuplicateAlert) {
            Button(String(localized: "common.confirm"), role: .cancel) { }
        } message: {
            Text(String(localized: "savedLocations.duplicateMessage"))
        }
        .presentationDetents([.medium, .large])
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
