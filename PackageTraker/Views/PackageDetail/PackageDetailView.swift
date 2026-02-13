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

    @State private var showDeleteConfirmation = false
    @State private var isRefreshing = false
    @State private var showEditSheet = false

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
                Button(String(localized: "detail.edit")) {
                    showEditSheet = true
                }
                .foregroundStyle(.white)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditPackageSheet(package: package)
        }
        .safeAreaInset(edge: .bottom) {
            bottomToolbar
        }
        .preferredColorScheme(.dark)
        .task {
            // 進入詳細頁時，只在資料過期時才刷新
            await refreshIfNeeded()
        }
        .confirmationDialog(String(localized: "detail.deleteConfirm"), isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(String(localized: "common.delete"), role: .destructive) {
                deletePackage()
            }
            Button(String(localized: "common.cancel"), role: .cancel) { }
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
            // 複製單號按鈕（靠左）
            Button(action: copyTrackingNumber) {
                Image(systemName: "doc.on.doc")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
            }
            .adaptiveToolbarButtonStyle()

            Spacer()

            // 刪除按鈕（靠右，帶文字）
            Button {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.title3)
                    Text(String(localized: "common.delete"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .adaptiveCapsuleButtonStyle(tint: .red)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
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
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
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

/// 時間軸事件行
struct TimelineEventRow: View {
    let event: TrackingEvent
    let isFirst: Bool
    let isLast: Bool

    // 波紋動畫狀態（多層波紋）
    @State private var ripple1 = false
    @State private var ripple2 = false
    @State private var ripple3 = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 時間軸線 + 圓點
            VStack(spacing: 0) {
                // 上方連接線
                if !isFirst {
                    Rectangle()
                        .fill(Color.secondaryCardBackground)
                        .frame(width: 2, height: 4)
                }

                // 圓點（含波紋動畫）
                ZStack {
                    // 多層波紋效果（僅當前狀態）
                    if isFirst {
                        // 第一層波紋
                        Circle()
                            .fill(event.status.color.opacity(ripple1 ? 0 : 0.3))
                            .frame(width: 12, height: 12)
                            .scaleEffect(ripple1 ? 2.5 : 1)

                        // 第二層波紋（延遲）
                        Circle()
                            .fill(event.status.color.opacity(ripple2 ? 0 : 0.3))
                            .frame(width: 12, height: 12)
                            .scaleEffect(ripple2 ? 2.5 : 1)

                        // 第三層波紋（更多延遲）
                        Circle()
                            .fill(event.status.color.opacity(ripple3 ? 0 : 0.3))
                            .frame(width: 12, height: 12)
                            .scaleEffect(ripple3 ? 2.5 : 1)
                    }

                    // 主圓點
                    Circle()
                        .fill(isFirst ? event.status.color : Color.secondaryCardBackground)
                        .frame(width: 12, height: 12)
                }
                .frame(width: 24, height: 24)

                // 下方連接線
                if !isLast {
                    Rectangle()
                        .fill(Color.secondaryCardBackground)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 20)
            .padding(.top, 2) // 對齊文字中心

            // 事件內容
            VStack(alignment: .leading, spacing: 4) {
                Text(event.eventDescription)
                    .font(.subheadline)
                    .foregroundStyle(isFirst ? .primary : .secondary)

                HStack {
                    Text(event.formattedTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if let location = event.location {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 16)

            Spacer()
        }
        .onAppear {
            // 啟動多層波紋動畫（交錯啟動）
            if isFirst {
                // 第一層波紋
                withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                    ripple1 = true
                }
                // 第二層波紋（延遲 0.6 秒）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                        ripple2 = true
                    }
                }
                // 第三層波紋（延遲 1.2 秒）
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                        ripple3 = true
                    }
                }
            }
        }
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
