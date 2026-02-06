#if DEBUG
import SwiftUI
import SwiftData

/// 開發者選項（僅 DEBUG 模式）
struct DeveloperOptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var apiStatus: String = ""
    @State private var isTestingAPI = false

    private let debugService = DebugNotificationService.shared

    var body: some View {
        List {
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
            } header: {
                Text("系統資訊")
            }
        }
        .navigationTitle("開發者選項")
        .navigationBarTitleDisplayMode(.inline)
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

#Preview {
    NavigationStack {
        DeveloperOptionsView()
    }
    .modelContainer(for: Package.self, inMemory: true)
}
#endif
