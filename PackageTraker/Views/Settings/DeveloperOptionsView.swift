#if DEBUG
import SwiftUI
import SwiftData

/// 開發者選項（僅 DEBUG 模式）
struct DeveloperOptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var apiStatus: String = ""
    @State private var isTestingAPI = false
    @State private var showSoftPaywall = false
    @State private var showPromoSheet = false
    @State private var showWhatsNew = false
    @State private var whatsNewData: WhatsNewData?
    @State private var isFetchingWhatsNew = false

    private let debugService = DebugNotificationService.shared

    var body: some View {
        List {
            // MARK: - Admin
            Section {
                NavigationLink {
                    AdminStatsView()
                } label: {
                    Label("資料庫統計", systemImage: "chart.bar.doc.horizontal")
                }

                NavigationLink {
                    NotificationLogsView()
                } label: {
                    Label("通知記錄", systemImage: "bell.and.waves.left.and.right")
                }

                NavigationLink {
                    AdminVersionsView()
                } label: {
                    Label("版本分佈", systemImage: "iphone.gen3")
                }
            } header: {
                Text("Admin")
            } footer: {
                Text("查看所有使用者與訂閱統計、通知發送記錄。需要網路連線，載入可能較慢。")
            }

            // MARK: - 通知測試
            Section {
                Button {
                    debugService.sendTestArrivalNotification()
                } label: {
                    Label("發送到貨通知", systemImage: "bell.badge.fill")
                }

                Button {
                    debugService.sendTestPickupReminder(count: 3)
                } label: {
                    Label("發送取貨提醒", systemImage: "clock.badge.exclamationmark.fill")
                }

                Button {
                    debugService.simulateStatusChange(
                        packageName: "蝦皮測試包裹",
                        location: "全家-景安門市"
                    )
                } label: {
                    Label("模擬狀態變化通知", systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text("通知測試")
            } footer: {
                Text("立即發送本地通知，用於測試通知功能是否正常。請確保已開啟通知權限。")
            }

            // MARK: - Mock 資料
            Section {
                Button {
                    seedScreenshotData()
                } label: {
                    Label("一鍵產生截圖資料", systemImage: "photo.stack.fill")
                }

                // 選擇狀態新增測試包裹
                Menu {
                    Button {
                        addMockPackage(status: .pending)
                    } label: {
                        Label("待出貨", systemImage: "clock")
                    }

                    Button {
                        addMockPackage(status: .shipped)
                    } label: {
                        Label("已出貨", systemImage: "shippingbox")
                    }

                    Button {
                        addMockPackage(status: .inTransit)
                    } label: {
                        Label("運送中", systemImage: "truck.box")
                    }

                    Button {
                        addMockPackage(status: .arrivedAtStore)
                    } label: {
                        Label("已到貨（待取件）", systemImage: "building.2")
                    }

                    Button {
                        addMockPackage(status: .delivered)
                    } label: {
                        Label("已取貨", systemImage: "checkmark.circle")
                    }
                } label: {
                    Label("新增測試包裹", systemImage: "plus.rectangle.fill")
                }

                Button(role: .destructive) {
                    clearMockData()
                } label: {
                    Label("清除測試資料", systemImage: "trash.fill")
                }
            } header: {
                Text("Mock 資料")
            } footer: {
                Text("選擇狀態後自動生成物流商、名稱等資訊")
            }

            // MARK: - API 除錯
            Section {
                HStack {
                    Text("Track.TW Token")
                    Spacer()
                    Text(TrackTwTokenStorage.shared.getToken() != nil ? "已設定" : "未設定")
                        .foregroundStyle(TrackTwTokenStorage.shared.getToken() != nil ? .green : .red)
                }

                Button {
                    Task { await testAPIConnection() }
                } label: {
                    HStack {
                        Label("測試 API 連線", systemImage: "antenna.radiowaves.left.and.right")
                        if isTestingAPI {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isTestingAPI)

                if !apiStatus.isEmpty {
                    Text(apiStatus)
                        .font(.caption)
                        .foregroundStyle(apiStatus.contains("✅") ? .green : .red)
                }
            } header: {
                Text("API 除錯")
            }

            // MARK: - 訂閱測試
            Section {
                HStack {
                    Text("訂閱狀態")
                    Spacer()
                    Text(subscriptionManager.isPro ? "Pro" : "免費")
                        .foregroundStyle(subscriptionManager.isPro ? .yellow : .secondary)
                        .fontWeight(.semibold)
                }

                Button {
                    subscriptionManager.debugSetTier(.pro)
                } label: {
                    Label("切換至 Pro", systemImage: "crown.fill")
                }
                .disabled(subscriptionManager.isPro)

                Button {
                    subscriptionManager.debugSetTier(.free)
                } label: {
                    Label("切換至免費", systemImage: "arrow.uturn.backward")
                }
                .disabled(!subscriptionManager.isPro)
            } header: {
                Text("訂閱測試")
            } footer: {
                Text("直接切換訂閱狀態，跳過 StoreKit 驗證。用於測試 Pro 功能與 UI 變化。")
            }

            // MARK: - AI 掃描
            Section {
                HStack {
                    Text("今日已用次數")
                    Spacer()
                    let used = 20 - AIVisionService.shared.remainingScans
                    Text("\(used) / 20")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("方案")
                    Spacer()
                    Text(SubscriptionManager.shared.isLifetime ? "終身（無限）" : "訂閱（20/天）")
                        .foregroundStyle(SubscriptionManager.shared.isLifetime ? .green : .secondary)
                }

                Button {
                    UserDefaults.standard.removeObject(forKey: "ai.dailyUsage.count")
                    UserDefaults.standard.removeObject(forKey: "ai.dailyUsage.date")
                    print("[Debug] AI 掃描次數已重置")
                } label: {
                    Label("重置掃描次數", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("AI 掃描")
            } footer: {
                Text("重置本地每日掃描次數快取。終身方案不受次數限制。")
            }

            // MARK: - 轉換率測試
            Section {
                HStack {
                    Text("AI 試用已用")
                    Spacer()
                    Text("\(UserDefaults.standard.integer(forKey: "aiTrialUsedCount")) / 3")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("累計新增包裹")
                    Spacer()
                    Text("\(UserDefaults.standard.integer(forKey: "totalPackagesAdded"))")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("軟 Paywall")
                    Spacer()
                    Text(UserDefaults.standard.bool(forKey: "hasSeenSoftPaywall") ? "已顯示" : "未顯示")
                        .foregroundStyle(UserDefaults.standard.bool(forKey: "hasSeenSoftPaywall") ? .red : .green)
                }

                Button {
                    showSoftPaywall = true
                } label: {
                    Label("顯示軟 Paywall", systemImage: "crown.fill")
                        .foregroundStyle(.yellow)
                }

                Button {
                    UserDefaults.standard.set(0, forKey: "aiTrialUsedCount")
                    UserDefaults.standard.set(false, forKey: "hasSeenSoftPaywall")
                    UserDefaults.standard.set(0, forKey: "totalPackagesAdded")
                    UserDefaults.standard.set(Date(), forKey: "appFirstLaunchDate")
                    print("[Debug] 轉換率測試狀態已全部重置")
                } label: {
                    Label("重置所有轉換率狀態", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("轉換率測試")
            } footer: {
                Text("重置 AI 試用次數、軟 Paywall 顯示狀態、累計新增包裹數、首次安裝日期。")
            }

            // MARK: - What's New 測試
            Section {
                HStack {
                    Text("已讀版本")
                    Spacer()
                    Text(WhatsNewService.shared.lastSeenVersion ?? "無")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        isFetchingWhatsNew = true
                        // 先從 Remote Config 讀取，忽略版本與已讀檢查
                        if let data = await WhatsNewService.shared.fetchWhatsNewData() {
                            whatsNewData = data
                        } else {
                            // fallback 假資料
                            whatsNewData = WhatsNewData(
                                targetVersion: AppConfiguration.appVersion,
                                emoji: "✨",
                                features: ["新功能 A 示範", "新功能 B 示範", "Bug 修復與效能優化"]
                            )
                        }
                        isFetchingWhatsNew = false
                        showWhatsNew = true
                    }
                } label: {
                    HStack {
                        Label("顯示 What's New", systemImage: "sparkles")
                            .foregroundStyle(.blue)
                        if isFetchingWhatsNew {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isFetchingWhatsNew)

                Button {
                    WhatsNewService.shared.resetSeen()
                    print("[Debug] What's New 已讀狀態已重置")
                } label: {
                    Label("重置已讀狀態", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("What's New 測試")
            } footer: {
                Text("從 Remote Config 讀取 whats_new 參數並預覽。重置已讀後下次冷啟動會重新顯示。")
            }

            // MARK: - 限時優惠測試
            Section {
                HStack {
                    Text("優惠狀態")
                    Spacer()
                    Text(LaunchPromoManager.shared.isPromoActive ? "進行中" :
                         LaunchPromoManager.shared.isPromoExpired ? "已過期" : "未啟動")
                        .foregroundStyle(LaunchPromoManager.shared.isPromoActive ? .green : .red)
                }

                if let start = LaunchPromoManager.shared.promoStartDate {
                    HStack {
                        Text("起始時間")
                        Spacer()
                        Text(start, style: .date)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("剩餘時間")
                    Spacer()
                    Text(LaunchPromoManager.shared.countdownText)
                        .foregroundStyle(.yellow)
                        .monospacedDigit()
                }

                Button {
                    showPromoSheet = true
                } label: {
                    Label("顯示優惠 Sheet", systemImage: "tag.fill")
                        .foregroundStyle(.yellow)
                }

                Button {
                    LaunchPromoManager.shared.debugResetPromo()
                } label: {
                    Label("重置優惠計時器", systemImage: "arrow.counterclockwise")
                }

                Button {
                    let almostExpired = Date().addingTimeInterval(-47 * 3600)
                    LaunchPromoManager.shared.debugSetPromoStart(almostExpired)
                } label: {
                    Label("模擬剩餘 1 小時", systemImage: "clock.badge.exclamationmark")
                }

                Button {
                    LaunchPromoManager.shared.debugExpirePromo()
                } label: {
                    Label("模擬已過期", systemImage: "clock.badge.xmark")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("限時優惠測試")
            } footer: {
                Text("重置或模擬限時優惠的各種狀態。影響 PaywallView 和 PackageListView 的顯示。")
            }

            // MARK: - 動畫預覽
            Section {
                NavigationLink {
                    OrbAnimationPreviewView()
                } label: {
                    Label("光球動畫預覽", systemImage: "sparkles")
                }
            } header: {
                Text("動畫預覽")
            } footer: {
                Text("預覽 AI 掃描光球動畫效果，可切換不同階段。不消耗 API 額度。")
            }

            // MARK: - 系統資訊
            Section {
                HStack {
                    Text("Build 配置")
                    Spacer()
                    Text("DEBUG")
                        .foregroundStyle(.orange)
                }

                HStack {
                    Text("App 版本")
                    Spacer()
                    Text(AppConfiguration.fullVersionString)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("iOS 版本")
                    Spacer()
                    Text(UIDevice.current.systemVersion)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("FCM Token")
                    Spacer()
                    if let token = FirebasePushService.shared.fcmToken {
                        Text(token)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("無")
                            .foregroundStyle(.red)
                    }
                }

                Button {
                    if let token = FirebasePushService.shared.fcmToken {
                        UIPasteboard.general.string = token
                    }
                } label: {
                    Label("複製 FCM Token", systemImage: "doc.on.doc")
                }
                .disabled(FirebasePushService.shared.fcmToken == nil)
            } header: {
                Text("系統資訊")
            }
        }
        .navigationTitle("開發者選項")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSoftPaywall) {
            SoftPaywallSheet {
                // Dev preview
            }
        }
        .sheet(isPresented: $showPromoSheet) {
            PromoSheet {
                // Dev preview
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            if let data = whatsNewData {
                WhatsNewSheet(data: data, markAsRead: false)
            }
        }
    }

    // MARK: - Actions

    private func addMockPackage(status: TrackingStatus) {
        // 隨機選擇物流商和名稱
        let carriers: [(Carrier, String)] = [
            (.tcat, "momo 測試訂單"),
            (.sevenEleven, "蝦皮測試包裹"),
            (.familyMart, "PChome 測試"),
            (.hct, "Yahoo 測試訂單"),
            (.postTW, "博客來測試"),
            (.sfExpress, "淘寶測試包裹")
        ]
        let mock = carriers.randomElement()!

        // 根據狀態決定取貨地點
        let pickupLocation: String? = status == .arrivedAtStore || status == .delivered
            ? (mock.0 == .sevenEleven ? "7-11 景安門市" : "全家 中和店")
            : nil

        let package = Package(
            trackingNumber: "MOCK\(Int.random(in: 100000...999999))",
            carrier: mock.0,
            customName: mock.1,
            pickupCode: "\(Int.random(in: 1...9))-\(Int.random(in: 1...9))-\(Int.random(in: 10...99))-\(Int.random(in: 10...99))",
            pickupLocation: pickupLocation,
            status: status
        )
        modelContext.insert(package)

        do {
            try modelContext.save()
            print("[Debug] 已新增測試包裹: \(package.trackingNumber) (\(status.displayName))")
        } catch {
            print("[Debug] 新增測試包裹失敗: \(error)")
        }
    }

    private func clearMockData() {
        let descriptor = FetchDescriptor<Package>(
            predicate: #Predicate<Package> { package in
                package.trackingNumber.starts(with: "MOCK") ||
                package.trackingNumber.starts(with: "SHOT") ||
                package.trackingNumber.starts(with: "TEST")
            }
        )

        do {
            let mockPackages = try modelContext.fetch(descriptor)
            let count = mockPackages.count

            for package in mockPackages {
                modelContext.delete(package)
            }

            try modelContext.save()
            print("[Debug] 已清除 \(count) 個測試包裹")
        } catch {
            print("[Debug] 清除測試包裹失敗: \(error)")
        }
    }

    /// 一鍵產生可用於 App Store 截圖的假資料（含時間軸）
    private func seedScreenshotData() {
        clearMockData()

        let now = Date()

        // 1) 已到店（含完整時間軸）
        let packageA = Package(
            trackingNumber: "SHOT711000001",
            carrier: .sevenEleven,
            customName: "蝦皮藍牙耳機",
            pickupCode: "6-5-29-14",
            pickupLocation: "7-11 景安門市",
            status: .arrivedAtStore,
            lastUpdated: now.addingTimeInterval(-15 * 60),
            latestDescription: "包裹已到店，請於期限內取件",
            storeName: "7-11 景安門市",
            pickupDeadline: "03/12 23:59"
        )

        let timelineA: [TrackingEvent] = [
            TrackingEvent(
                timestamp: now.addingTimeInterval(-15 * 60),
                status: .arrivedAtStore,
                description: "[景安門市] 包裹已到店，可前往取件",
                location: "新北市中和區"
            ),
            TrackingEvent(
                timestamp: now.addingTimeInterval(-2 * 60 * 60),
                status: .inTransit,
                description: "包裹配送中，前往取件門市",
                location: "新北市中和區"
            ),
            TrackingEvent(
                timestamp: now.addingTimeInterval(-6 * 60 * 60),
                status: .shipped,
                description: "賣家已寄件，等待物流收件",
                location: "台北市"
            ),
            TrackingEvent(
                timestamp: now.addingTimeInterval(-18 * 60 * 60),
                status: .pending,
                description: "訂單已成立",
                location: nil
            ),
        ]
        timelineA.forEach { $0.package = packageA }
        packageA.events = timelineA

        // 2) 已到店
        let packageB = Package(
            trackingNumber: "SHOTFM000002",
            carrier: .familyMart,
            customName: "momo 行動電源",
            pickupCode: "35415",
            pickupLocation: "全家 中和店",
            status: .arrivedAtStore,
            lastUpdated: now.addingTimeInterval(-40 * 60),
            latestDescription: "已到店 全家-中和店",
            storeName: "全家 中和店",
            pickupDeadline: "03/13 23:59"
        )

        // 3) 配送中
        let packageC = Package(
            trackingNumber: "SHOTTCAT00003",
            carrier: .tcat,
            customName: "PChome 機械鍵盤",
            pickupLocation: "宅配到府",
            status: .inTransit,
            lastUpdated: now.addingTimeInterval(-90 * 60),
            latestDescription: "包裹已從台北轉運中心發出"
        )

        // 4) 已出貨
        let packageD = Package(
            trackingNumber: "SHOTHCT000004",
            carrier: .hct,
            customName: "博客來新書",
            pickupLocation: "宅配到府",
            status: .shipped,
            lastUpdated: now.addingTimeInterval(-3 * 60 * 60),
            latestDescription: "貨件已收件，準備配送"
        )

        // 5) 待出貨
        let packageE = Package(
            trackingNumber: "SHOTMOMO00005",
            carrier: .momo,
            customName: "momo 折疊桌",
            status: .pending,
            lastUpdated: now.addingTimeInterval(-5 * 60 * 60),
            latestDescription: "訂單處理中"
        )

        // 6) 國際配送中
        let packageF = Package(
            trackingNumber: "SHOTDHL000006",
            carrier: .dhl,
            customName: "Amazon 轉接器",
            pickupLocation: "宅配到府",
            status: .inTransit,
            lastUpdated: now.addingTimeInterval(-7 * 60 * 60),
            latestDescription: "Shipment in transit - Hong Kong"
        )

        // 7) 歷史：已取貨（可拍歷史頁）
        let historyA = Package(
            trackingNumber: "SHOTDONE00007",
            carrier: .sevenEleven,
            customName: "蝦皮手機殼",
            status: .delivered,
            lastUpdated: now.addingTimeInterval(-2 * 24 * 60 * 60),
            isArchived: true,
            latestDescription: "買家取件成功"
        )

        // 8) 歷史：已取貨
        let historyB = Package(
            trackingNumber: "SHOTDONE00008",
            carrier: .fedex,
            customName: "Apple Watch 錶帶",
            status: .delivered,
            lastUpdated: now.addingTimeInterval(-8 * 24 * 60 * 60),
            isArchived: true,
            latestDescription: "Delivered"
        )

        let allPackages = [packageA, packageB, packageC, packageD, packageE, packageF, historyA, historyB]
        allPackages.forEach { modelContext.insert($0) }

        do {
            try modelContext.save()
            print("[Debug] 已建立 \(allPackages.count) 筆截圖資料")
        } catch {
            print("[Debug] 建立截圖資料失敗: \(error)")
        }
    }

    private func testAPIConnection() async {
        isTestingAPI = true
        apiStatus = ""

        do {
            let profile = try await TrackTwAPIClient.shared.getUserProfile()
            apiStatus = "✅ 連線成功: \(profile.name)"
        } catch {
            apiStatus = "❌ 連線失敗: \(error.localizedDescription)"
        }

        isTestingAPI = false
    }
}

// MARK: - 光球動畫預覽頁

/// 獨立預覽 OrganicOrbAnimation，可切換階段，不消耗 API
struct OrbAnimationPreviewView: View {
    @State private var stage: AIScanningView.ScanStage = .aiRecognition

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                OrganicOrbAnimation(stage: stage)
                    .frame(height: 280)

                Spacer()
                    .frame(height: 40)

                // 階段標示
                Text(stageName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: stage)

                Spacer()

                // 階段切換按鈕
                HStack(spacing: 12) {
                    stageButton("AI 辨識", stage: .aiRecognition, color: .purple)
                    stageButton("API 驗證", stage: .apiVerification, color: .blue)
                    stageButton("完成", stage: .complete, color: .green)
                    stageButton("失敗", stage: .failed, color: .red)
                }
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("光球動畫")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private var stageName: String {
        switch stage {
        case .aiRecognition: return "AI 辨識中"
        case .apiVerification: return "API 驗證中"
        case .complete: return "完成"
        case .failed: return "失敗"
        }
    }

    private func stageButton(_ title: String, stage: AIScanningView.ScanStage, color: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.stage = stage
            }
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(self.stage == stage ? .white : .white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(self.stage == stage ? color.opacity(0.5) : .white.opacity(0.1))
                )
        }
    }
}

#Preview {
    NavigationStack {
        DeveloperOptionsView()
    }
    .modelContainer(for: Package.self, inMemory: true)
}

#Preview("Orb Preview") {
    NavigationStack {
        OrbAnimationPreviewView()
    }
}
#endif
