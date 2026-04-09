import SwiftUI
import SwiftData
import WidgetKit

/// 包裹詳情頁（時間軸）
struct PackageDetailView: View {
    let package: Package
    var namespace: Namespace.ID? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PackageRefreshService.self) private var refreshService

    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showDeleteConfirmation = false
    @State private var showCompleteConfirmation = false
    @State private var isRefreshing = false
    @State private var showEditSheet = false
    @State private var showPaywall = false

    /// 追蹤事件（按時間降序排列，去重）
    private var events: [TrackingEvent] {
        var seen = Set<String>()
        return package.events
            .sorted { $0.timestamp > $1.timestamp }
            .filter { event in
                let key = "\(Int(event.timestamp.timeIntervalSince1970))|\(event.eventDescription)"
                return seen.insert(key).inserted
            }
    }

    /// 是否從 hero 動畫進入（有 namespace 表示從首頁進入）
    private var isHeroNavigation: Bool {
        namespace != nil
    }

    var body: some View {
        // 從 sheet 進入時需要 NavigationStack，從 hero 進入時不需要
        if isHeroNavigation {
            contentView
        } else {
            NavigationStack {
                contentView
            }
        }
    }

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 頂部：包裹資訊卡片
                packageInfoCard

                // 訂單資訊卡片（若有）
                if hasOrderInfo {
                    orderInfoCard
                }

                // 時間軸
                timelineSection
            }
            .padding()
            .padding(.bottom, 80) // 為底部 toolbar 留空間
        }
        .refreshable {
            await refreshPackage()
        }
        .adaptiveBackground()
        .navigationTitle(String(localized: "detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: isHeroNavigation ? "chevron.left" : "xmark")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !package.status.isCompleted {
                    markCompleteButton
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditPackageSheet(package: package)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(trigger: .notification)
        }
        .safeAreaInset(edge: .bottom) {
            bottomToolbar
        }
        .preferredColorScheme(.dark)
        .task {
            // 進入詳細頁時，只在資料過期時才刷新
            await refreshIfNeeded()
        }
        .overlay {
            Color.clear
                .alert(String(localized: "detail.deleteConfirm"), isPresented: $showDeleteConfirmation) {
                    Button(String(localized: "common.delete"), role: .destructive) {
                        deletePackage()
                    }
                    Button(String(localized: "common.cancel"), role: .cancel) { }
                }
                .tint(.white)
        }
        .overlay {
            Color.clear
                .alert(String(localized: "detail.markCompleteConfirm"), isPresented: $showCompleteConfirmation) {
                    Button(String(localized: "detail.markComplete")) {
                        markAsDelivered()
                    }
                    Button(String(localized: "common.cancel"), role: .cancel) { }
                } message: {
                    Text(String(localized: "detail.markCompleteMessage"))
                }
                .tint(.white)
        }
    }

    // MARK: - Views

    private var packageInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 物流商與狀態
            HStack {
                CarrierLogoView(carrier: package.carrier, size: 56)

                VStack(alignment: .leading, spacing: 4) {
                    // 標題：物流商名稱 + 門市名稱（如有）
                    Text(carrierDisplayTitle)
                        .font(.headline)

                    // 副標題：單號
                    Text(package.trackingNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusIconBadge(status: package.status)
            }

            Divider()
                .background(Color.secondaryCardBackground)

            // 取件碼（大字體）
            if let pickupCode = package.pickupCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "detail.pickupCode"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pickupCode)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                }
            }

            // 取貨地點
            if let location = package.pickupLocation {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.secondary)
                    Text(localizedPickupLocation(location))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // 服務類型 + 取件期限（7-11、全家）
            if hasExtraInfo {
                HStack(spacing: 16) {
                    // 服務類型
                    if let serviceType = package.serviceType, !serviceType.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "creditcard")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(serviceType)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 取件期限
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("\(String(localized: "detail.deadline")) \(formattedDeadlineDisplay)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .adaptiveCardStyle()
    }

    /// 是否有額外資訊
    private var hasExtraInfo: Bool {
        package.serviceType != nil || package.pickupDeadline != nil
    }

    /// 是否有訂單資訊
    private var hasOrderInfo: Bool {
        package.customName != nil ||
        package.purchasePlatform != nil ||
        package.paymentMethod != nil ||
        package.amount != nil ||
        package.notes != nil
    }

    /// 訂單資訊卡片
    private var orderInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "detail.orderInfo"))
                .font(.headline)

            VStack(spacing: 12) {
                // 品名
                if let name = package.customName, !name.isEmpty {
                    orderInfoRow(icon: "shippingbox.fill", title: String(localized: "add.productName"), value: name)
                }

                // 購買平台
                if let platform = package.purchasePlatform, !platform.isEmpty {
                    orderInfoRow(icon: "cart.fill", title: String(localized: "add.platform"), value: platform)
                }

                // 付款方式
                if let method = package.paymentMethod {
                    orderInfoRow(icon: method.iconName, title: String(localized: "add.paymentMethod"), value: method.displayName)
                }

                // 金額
                if let amount = package.formattedAmount {
                    orderInfoRow(icon: "dollarsign.circle.fill", title: String(localized: "add.amount"), value: amount)
                }

                // 備註
                if let notes = package.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "note.text")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            Text(String(localized: "add.notes"))
                                .foregroundStyle(.secondary)
                        }

                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.leading, 28)
                    }
                }
            }
        }
        .adaptiveCardStyle()
    }

    private func orderInfoRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
    }

    /// 格式化的取件期限顯示
    private var formattedDeadlineDisplay: String {
        guard let deadline = package.pickupDeadline, !deadline.isEmpty else {
            return "-"
        }
        return formatDeadline(deadline)
    }

    /// 物流商顯示標題（含門市名稱）
    private var carrierDisplayTitle: String {
        if let storeName = package.storeName, !storeName.isEmpty {
            // 7-11: "7-ELEVEN 福美店"
            // 全家: 門市名稱已包含「全家」，直接顯示
            if package.carrier == .sevenEleven {
                return "\(package.carrier.displayName) \(storeName)店"
            } else if package.carrier == .familyMart {
                return storeName
            }
        }
        return package.carrier.displayName
    }

    /// 格式化取件期限（2026-02-06 -> 02/06）
    private func formatDeadline(_ deadline: String) -> String {
        // 嘗試解析日期
        let formatters = ["yyyy-MM-dd", "yyyy/MM/dd"]
        for format in formatters {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = format
            if let date = inputFormatter.date(from: deadline) {
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "MM/dd"
                return outputFormatter.string(from: date)
            }
        }
        return deadline
    }

    /// 本地化取貨地點顯示
    /// 如果取貨地點等於物流商的預設名稱，返回本地化的名稱
    private func localizedPickupLocation(_ location: String) -> String {
        // 檢查是否等於當前包裹物流商的預設取貨地點
        // 這樣可以正確處理不同語言環境
        for carrier in Carrier.allCases {
            if location == carrier.displayName || location == carrier.defaultPickupLocation {
                return carrier.displayName
            }
        }
        return location
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "detail.timeline"))
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    TimelineEventRow(
                        event: event,
                        isFirst: index == 0,
                        isLast: index == events.count - 1
                    )
                }
            }
            .adaptiveCardStyle()
        }
    }

    private var bottomToolbar: some View {
        HStack {
            // 編輯按鈕
            editButton

            // 通知設定按鈕（Pro，已完成的包裹不顯示）
            if !package.status.isCompleted {
                notificationMenuButton
            }

            // 複製單號按鈕
            Button(action: copyTrackingNumber) {
                Image(systemName: "doc.on.doc")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
            }
            .adaptiveToolbarButtonStyle()

            Spacer()

            // 刪除按鈕（靠右）
            deleteButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var markCompleteButton: some View {
        if #available(iOS 26, *) {
            Button {
                showCompleteConfirmation = true
            } label: {
                Text(String(localized: "detail.markComplete"))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.glassProminent)
            .tint(.green)
        } else {
            Button {
                showCompleteConfirmation = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(String(localized: "detail.markComplete"))
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green, in: Capsule())
            }
        }
    }

    private var editButton: some View {
        Button {
            showEditSheet = true
        } label: {
            Image(systemName: "pencil")
                .font(.title3)
                .foregroundStyle(.black)
                .frame(width: 50, height: 50)
        }
        .adaptiveToolbarButtonStyle(tint: .white)
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
        }
        .adaptiveToolbarButtonStyle(tint: .red)
    }

    /// 通知鈴鐺 icon（根據 3 個開關狀態）
    private var bellIconName: String {
        let allOn = package.notifyShipped && package.notifyInTransit && package.notifyArrived
        let allOff = !package.notifyShipped && !package.notifyInTransit && !package.notifyArrived
        if allOff { return "bell.slash.fill" }
        if allOn { return "bell.fill" }
        return "bell.badge"
    }

    /// 是否所有通知都關閉
    private var allNotificationsOff: Bool {
        !package.notifyShipped && !package.notifyInTransit && !package.notifyArrived
    }

    /// Pro 功能是否啟用
    private var isPro: Bool {
        !FeatureFlags.subscriptionEnabled || subscriptionManager.isPro
    }

    /// 通知設定 Menu 按鈕
    private var notificationMenuButton: some View {
        Menu {
            // 全部開/關（所有用戶可用）
            Button {
                let newValue = allNotificationsOff
                package.notifyShipped = newValue
                package.notifyInTransit = newValue
                package.notifyArrived = newValue
                saveAndSync()
            } label: {
                Label(
                    allNotificationsOff
                        ? String(localized: "detail.notify.enableAll")
                        : String(localized: "detail.notify.disableAll"),
                    systemImage: allNotificationsOff ? "bell.fill" : "bell.slash.fill"
                )
            }

            Divider()

            // 階段選項（Pro 專屬）
            Button {
                if isPro {
                    package.notifyShipped.toggle()
                    saveAndSync()
                } else {
                    showPaywall = true
                }
            } label: {
                Label(
                    String(localized: "detail.notify.shipped") + (isPro ? "" : " (PRO)"),
                    systemImage: package.notifyShipped ? "checkmark.circle.fill" : "circle"
                )
            }
            Button {
                if isPro {
                    package.notifyInTransit.toggle()
                    saveAndSync()
                } else {
                    showPaywall = true
                }
            } label: {
                Label(
                    String(localized: "detail.notify.inTransit") + (isPro ? "" : " (PRO)"),
                    systemImage: package.notifyInTransit ? "checkmark.circle.fill" : "circle"
                )
            }
            Button {
                if isPro {
                    package.notifyArrived.toggle()
                    saveAndSync()
                } else {
                    showPaywall = true
                }
            } label: {
                Label(
                    String(localized: "detail.notify.arrived") + (isPro ? "" : " (PRO)"),
                    systemImage: package.notifyArrived ? "checkmark.circle.fill" : "circle"
                )
            }
        } label: {
            Image(systemName: bellIconName)
                .font(.title3)
                .foregroundStyle(allNotificationsOff ? Color.secondary : Color.white)
                .frame(width: 50, height: 50)
        }
        .adaptiveToolbarButtonStyle()
    }

    /// 儲存並同步到 Firestore
    private func saveAndSync() {
        try? modelContext.save()
        FirebaseSyncService.shared.syncPackage(package)
    }

    // MARK: - Actions

    private func copyTrackingNumber() {
        UIPasteboard.general.string = package.trackingNumber
    }

    private func openOfficialWebsite() {
        // TODO: 實作跳轉物流官網
    }

    private func deletePackage() {
        let packageId = package.id
        modelContext.delete(package)
        try? modelContext.save()
        // 從 Firestore 刪除
        FirebaseSyncService.shared.deletePackage(packageId)
        // 更新 Widget
        let remainingPackages = (try? modelContext.fetch(FetchDescriptor<Package>())) ?? []
        WidgetDataService.shared.updateWidgetData(packages: remainingPackages)
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }

    private func markAsDelivered() {
        let now = Date()
        let description = String(localized: "detail.markCompleteEvent")

        // 更新狀態
        package.status = .delivered
        package.lastUpdated = now
        package.latestDescription = description

        // 建立手動完成事件
        let event = TrackingEvent(
            id: TrackingEvent.deterministicId(trackingNumber: package.trackingNumber, timestamp: now, description: description),
            timestamp: now,
            status: .delivered,
            description: description
        )
        event.package = package
        package.events.append(event)

        try? modelContext.save()
        FirebaseSyncService.shared.syncPackage(package, includeStatus: true)

        // 更新 Widget
        let allPackages = (try? modelContext.fetch(FetchDescriptor<Package>())) ?? []
        WidgetDataService.shared.updateWidgetData(packages: allPackages)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 只在資料過期時自動刷新（5 分鐘內不重複呼叫 API）
    private func refreshIfNeeded() async {
        guard refreshService.isStale(package, threshold: 300) else {
            return
        }
        await refreshPackage()
    }

    /// 刷新包裹追蹤資料
    private func refreshPackage() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        _ = await refreshService.refreshPackage(package, in: modelContext)
        isRefreshing = false
    }
}

// MARK: - Previews

#Preview("時間軸狀態") {
    let package = Package(
        trackingNumber: "TW268979373141Z",
        carrier: .shopee,
        customName: "科技織紋手機殼",
        pickupLocation: "中和福美店",
        status: .delivered,
        paymentMethod: .cod,
        amount: 1290,
        purchasePlatform: "蝦皮購物"
    )

    // 建立測試事件
    let events = [
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-3600),
            status: .delivered,
            description: "[中和福美 - 智取店] 買家取件成功",
            location: "中和福美店"
        ),
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-86400),
            status: .arrivedAtStore,
            description: "包裹已配達買家取件門市 - [中和福美 - 智取店]",
            location: "中和福美店"
        ),
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-172800),
            status: .inTransit,
            description: "包裹抵達理貨中心，處理中",
            location: nil
        ),
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-259200),
            status: .shipped,
            description: "賣家已寄件成功",
            location: nil
        ),
        TrackingEvent(
            timestamp: Date().addingTimeInterval(-345600),
            status: .pending,
            description: "賣家將於確認訂單後出貨",
            location: nil
        )
    ]

    for event in events {
        event.package = package
        package.events.append(event)
    }

    return PackageDetailView(package: package)
        .environment(PackageRefreshService())
}
