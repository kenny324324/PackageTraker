#if DEBUG
import SwiftUI
import FirebaseAuth

// MARK: - Cloud Function HTTP Client
//
// DEBUG-only admin function 透過 URLSession 直接呼叫 callable Cloud Function 的
// HTTPS endpoint，**不走 FirebaseFunctions SDK 也不取 Bearer token**。
//
// 為什麼不取 token：iOS 26 + Firebase Auth SDK 的 `getIDToken { ... }` callback 在
// 某些 device state 下永不 fire（其他 Firebase 服務透過內部不同 path 不受影響）。
//
// 改怎麼驗 admin：client 同步取 `Auth.auth().currentUser.uid` 放進 body，server 端
// 比對 admin uid allowlist。DEBUG-only tooling，這層信任可接受。

private enum CloudFunctionError: LocalizedError {
    case notSignedIn
    case invalidResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "未登入"
        case .invalidResponse: return "回應格式錯誤"
        case .http(let code, let msg): return "HTTP \(code): \(msg)"
        }
    }
}

func callCloudFunction(_ name: String, params: [String: Any] = [:]) async throws -> [String: Any] {
    guard let adminUid = Auth.auth().currentUser?.uid else {
        throw CloudFunctionError.notSignedIn
    }

    // admin uid 統一用 `adminUid` 欄位（避免和 getUserDetail 的 target uid 撞名）
    var body = params
    body["adminUid"] = adminUid

    let url = URL(string: "https://asia-east1-packagetraker-e80b0.cloudfunctions.net/\(name)")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["data": body])
    request.timeoutInterval = 30

    // 用 callback-based dataTask + Continuation，避開 URLSession.data(for:) async wrapper
    // （iOS 26 + Swift Concurrency 環境下也有 hang 問題）
    let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data, let response {
                continuation.resume(returning: (data, response))
            } else {
                continuation.resume(throwing: CloudFunctionError.invalidResponse)
            }
        }
        task.resume()
    }

    guard let httpResp = response as? HTTPURLResponse else {
        throw CloudFunctionError.invalidResponse
    }

    let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

    if httpResp.statusCode >= 400 {
        let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown"
        throw CloudFunctionError.http(httpResp.statusCode, msg)
    }

    guard let result = json["result"] as? [String: Any] else {
        throw CloudFunctionError.invalidResponse
    }
    return result
}

// MARK: - Helpers

private func parseStringIntDict(_ raw: Any?) -> [String: Int] {
    guard let dict = raw as? [String: Any] else { return [:] }
    var result: [String: Int] = [:]
    for (k, v) in dict {
        if let i = v as? Int {
            result[k] = i
        } else if let n = v as? NSNumber {
            result[k] = n.intValue
        }
    }
    return result
}

// MARK: - Data Models

private struct AdminSummary {
    let totalUsers: Int
    let subscribedUsers: Int
    let monthly: Int
    let yearly: Int
    let lifetime: Int
    let appVersionDistribution: [String: Int]
    let iosVersionDistribution: [String: Int]
}

private struct AdminUser: Identifiable {
    let id: String // uid
    let email: String
    let subscriptionTier: String?
    let subscriptionProductID: String?
    let packageCount: Int
    let lastActive: Date?
    let createdAt: Date?
    let language: String?
    let appVersion: String?
    let iosVersion: String?

    var isPro: Bool { subscriptionTier == "pro" }

    var subscriptionLabel: String {
        guard isPro, let productID = subscriptionProductID else { return "Free" }
        if productID.contains("lifetime") { return "終身" }
        if productID.contains("yearly") { return "年訂閱" }
        if productID.contains("monthly") { return "月訂閱" }
        return "Pro"
    }
}

private enum UserFilter: String, CaseIterable {
    case all = "全部"
    case pro = "Pro"
    case free = "Free"
    case hasPackages = "有包裹"
    case noPackages = "無包裹"
}

private enum SortOrder: String, CaseIterable {
    case packageCount = "包裹數"
    case lastActive = "最後活躍"
    case createdAt = "建立時間"
}

private struct AdminUserDetail {
    let uid: String
    let email: String?
    let appleId: String?
    let subscriptionTier: String?
    let subscriptionProductID: String?
    let language: String?
    let fcmToken: String?
    let lastActive: Date?
    let createdAt: Date?
    let notificationSettings: [String: Any]?
    let packages: [AdminUserPackage]
    let rawFields: [String: Any]?

    var isPro: Bool { subscriptionTier == "pro" }

    var subscriptionLabel: String {
        guard isPro, let productID = subscriptionProductID else { return "Free" }
        if productID.contains("lifetime") { return "終身" }
        if productID.contains("yearly") { return "年訂閱" }
        if productID.contains("monthly") { return "月訂閱" }
        return "Pro"
    }
}

private struct AdminUserPackage: Identifiable {
    let id: String
    let trackingNumber: String
    let carrier: String
    let status: String
    let customName: String?
    let pickupCode: String?
    let pickupLocation: String?
    let storeName: String?
    let latestDescription: String?
    let isArchived: Bool
    let isDeleted: Bool
    let amount: Double?
    let purchasePlatform: String?
    let lastUpdated: Date?
    let createdAt: Date?
    let events: [AdminPackageEvent]

    var carrierEnum: Carrier? { Carrier(rawValue: carrier) }
    var statusEnum: TrackingStatus? { TrackingStatus(rawValue: status) }

    var displayName: String {
        customName ?? carrierEnum?.displayName ?? carrier
    }

    var formattedDate: String {
        guard let lastUpdated else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: lastUpdated)
    }
}

private struct AdminPackageEvent: Identifiable, TimelineEventData {
    let id: String
    let timestamp: Date
    let status: TrackingStatus
    let eventDescription: String
    let location: String?

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: timestamp)
    }
}

// MARK: - AdminStatsView

struct AdminStatsView: View {
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var summary: AdminSummary?
    @State private var users: [AdminUser] = []
    @State private var nextCursor: String?
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .packageCount
    @State private var userFilter: UserFilter = .all
    @State private var selectedUser: AdminUser?

    private static let pageSize = 50

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var filteredUsers: [AdminUser] {
        var filtered = users

        switch userFilter {
        case .all: break
        case .pro: filtered = filtered.filter { $0.isPro }
        case .free: filtered = filtered.filter { !$0.isPro }
        case .hasPackages: filtered = filtered.filter { $0.packageCount > 0 }
        case .noPackages: filtered = filtered.filter { $0.packageCount == 0 }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { $0.email.localizedCaseInsensitiveContains(searchText) }
        }

        switch sortOrder {
        case .packageCount:
            return filtered.sorted { $0.packageCount > $1.packageCount }
        case .lastActive:
            return filtered.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
        case .createdAt:
            return filtered.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
    }

    var body: some View {
        List {
            usersSection
        }
        .searchable(text: $searchText, prompt: "搜尋 email")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(UserFilter.allCases, id: \.self) { filter in
                        Button {
                            userFilter = filter
                        } label: {
                            if userFilter == filter {
                                Label(filter.rawValue, systemImage: "checkmark")
                            } else {
                                Text(filter.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: userFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }

                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            if sortOrder == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .overlay {
            if isLoading && users.isEmpty {
                ProgressView("載入中⋯")
            }
        }
        .refreshable {
            await fetchStats()
        }
        .alert("錯誤", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("確定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await fetchStats()
        }
        .navigationTitle("使用者列表")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedUser) { user in
            AdminUserDetailSheet(user: user)
        }
    }

    // MARK: - Users Section

    private var usersSection: some View {
        Section {
            ForEach(filteredUsers) { user in
                Button {
                    selectedUser = user
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(user.email)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)

                            Spacer()

                            Text(user.subscriptionLabel)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(user.isPro ? Color.yellow.opacity(0.2) : Color.gray.opacity(0.2))
                                .foregroundStyle(user.isPro ? .yellow : .secondary)
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 12) {
                            Label("\(user.packageCount)", systemImage: "shippingbox.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let lang = user.language {
                                Text(lang)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if let lastActive = user.lastActive {
                                Text(lastActive, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .foregroundStyle(.primary)
            }

            if nextCursor != nil {
                Button {
                    Task { await loadMore() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoadingMore {
                            ProgressView()
                        } else {
                            Text("載入更多")
                                .foregroundStyle(Color.appAccent)
                        }
                        Spacer()
                    }
                }
                .disabled(isLoadingMore)
            }
        } header: {
            if let total = summary?.totalUsers {
                Text("用戶 (\(filteredUsers.count) / \(users.count) 已載入，共 \(total))")
            } else {
                Text("用戶 (\(filteredUsers.count))")
            }
        }
    }

    // MARK: - Fetch

    private func fetchStats() async {
        isLoading = true
        defer { isLoading = false }

        users = []
        nextCursor = nil

        await fetchPage(cursor: nil)
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await fetchPage(cursor: cursor)
    }

    private func fetchPage(cursor: String?) async {
        do {
            var params: [String: Any] = ["limit": Self.pageSize]
            if let cursor { params["cursor"] = cursor }
            let data = try await callCloudFunction("getAdminStats", params: params)

            if let summaryData = data["summary"] as? [String: Any] {
                summary = AdminSummary(
                    totalUsers: summaryData["totalUsers"] as? Int ?? 0,
                    subscribedUsers: summaryData["subscribedUsers"] as? Int ?? 0,
                    monthly: summaryData["monthly"] as? Int ?? 0,
                    yearly: summaryData["yearly"] as? Int ?? 0,
                    lifetime: summaryData["lifetime"] as? Int ?? 0,
                    appVersionDistribution: parseStringIntDict(summaryData["appVersionDistribution"]),
                    iosVersionDistribution: parseStringIntDict(summaryData["iosVersionDistribution"])
                )
            }

            if let usersData = data["users"] as? [[String: Any]] {
                let newUsers = usersData.map { dict in
                    AdminUser(
                        id: dict["uid"] as? String ?? "",
                        email: dict["email"] as? String ?? "(no email)",
                        subscriptionTier: dict["subscriptionTier"] as? String,
                        subscriptionProductID: dict["subscriptionProductID"] as? String,
                        packageCount: dict["packageCount"] as? Int ?? 0,
                        lastActive: parseISO(dict["lastActive"] as? String),
                        createdAt: parseISO(dict["createdAt"] as? String),
                        language: dict["language"] as? String,
                        appVersion: dict["appVersion"] as? String,
                        iosVersion: dict["iosVersion"] as? String
                    )
                }
                users.append(contentsOf: newUsers)
            }

            nextCursor = data["nextCursor"] as? String
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseISO(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFormatter.date(from: string)
    }
}

// MARK: - AdminAnalyticsView

struct AdminAnalyticsView: View {
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var summary: AdminSummary?

    var body: some View {
        List {
            if let summary {
                overallSection(summary)
                subscriptionSection(summary)
            }
        }
        .overlay {
            if isLoading && summary == nil {
                ProgressView("載入中⋯")
            }
        }
        .refreshable {
            await fetchSummary()
        }
        .alert("錯誤", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("確定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await fetchSummary()
        }
        .navigationTitle("統計分析")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    @ViewBuilder
    private func overallSection(_ summary: AdminSummary) -> some View {
        Section {
            row("總用戶數", value: "\(summary.totalUsers)", icon: "person.2.fill")
            row("訂閱用戶", value: "\(summary.subscribedUsers)", icon: "star.fill", color: .yellow)

            if summary.totalUsers > 0 {
                let rate = Double(summary.subscribedUsers) / Double(summary.totalUsers) * 100
                row("訂閱率", value: String(format: "%.2f%%", rate), icon: "percent")
            }
        } header: {
            Text("總覽")
        }
    }

    @ViewBuilder
    private func subscriptionSection(_ summary: AdminSummary) -> some View {
        Section {
            row("月訂閱", value: "\(summary.monthly)", icon: "calendar")
            row("年訂閱", value: "\(summary.yearly)", icon: "calendar.badge.clock")
            row("終身", value: "\(summary.lifetime)", icon: "infinity", color: .purple)
        } header: {
            Text("訂閱方案分佈")
        }
    }

    private func row(_ title: String, value: String, icon: String, color: Color = .secondary) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(color)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Fetch

    private func fetchSummary() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // 只需要 summary，limit=1 拿最少資料
            let data = try await callCloudFunction("getAdminStats", params: ["limit": 1])

            guard let summaryData = data["summary"] as? [String: Any] else {
                errorMessage = "回傳格式錯誤"
                return
            }

            summary = AdminSummary(
                totalUsers: summaryData["totalUsers"] as? Int ?? 0,
                subscribedUsers: summaryData["subscribedUsers"] as? Int ?? 0,
                monthly: summaryData["monthly"] as? Int ?? 0,
                yearly: summaryData["yearly"] as? Int ?? 0,
                lifetime: summaryData["lifetime"] as? Int ?? 0,
                appVersionDistribution: parseStringIntDict(summaryData["appVersionDistribution"]),
                iosVersionDistribution: parseStringIntDict(summaryData["iosVersionDistribution"])
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - AdminUserDetailSheet

private struct AdminUserDetailSheet: View {
    let user: AdminUser

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var detail: AdminUserDetail?
    @State private var showRawFields = false
    @State private var selectedPackage: AdminUserPackage?
    @State private var showUserInfo = false
    @State private var showNotification = false
    @State private var hideDeleted = false

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "zh-Hant_TW")
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                if let detail {
                    userInfoSection(detail)
                    notificationSection(detail)
                    packagesSection(detail.packages)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("載入中⋯")
                }
                if let errorMessage, !isLoading {
                    ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle(user.email)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            showRawFields = true
                        } label: {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                        .disabled(detail == nil)

                        Button {
                            hideDeleted.toggle()
                        } label: {
                            Image(systemName: hideDeleted ? "trash.slash.fill" : "trash.slash")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                await fetchDetail()
            }
            .sheet(isPresented: $showRawFields) {
                if let rawFields = detail?.rawFields {
                    RawFieldsSheet(title: user.email, fields: rawFields)
                }
            }
            .sheet(item: $selectedPackage) { pkg in
                AdminPackageDetailSheet(package: pkg)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - User Info

    @ViewBuilder
    private func userInfoSection(_ detail: AdminUserDetail) -> some View {
        Section {
            DisclosureGroup(isExpanded: $showUserInfo) {
                infoRow("UID", value: detail.uid)

                if let email = detail.email {
                    infoRow("Email", value: email)
                }

                if let appleId = detail.appleId {
                    infoRow("Apple ID", value: appleId)
                }

                infoRow("訂閱", value: detail.subscriptionLabel)

                if let lang = detail.language {
                    infoRow("語言", value: lang)
                }

                if let createdAt = detail.createdAt {
                    infoRow("註冊時間", value: dateFormatter.string(from: createdAt))
                }

                if let lastActive = detail.lastActive {
                    infoRow("最後活躍", value: dateFormatter.string(from: lastActive))
                }

                if let token = detail.fcmToken {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FCM Token")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(token)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
            } label: {
                Text("用戶資料")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
    }

    // MARK: - Notification Settings

    @ViewBuilder
    private func notificationSection(_ detail: AdminUserDetail) -> some View {
        if let settings = detail.notificationSettings {
            Section {
                DisclosureGroup(isExpanded: $showNotification) {
                    notifRow("通知開關", key: "enabled", settings: settings)
                    notifRow("到貨通知", key: "arrivalNotification", settings: settings)
                    notifRow("出貨通知", key: "shippedNotification", settings: settings)
                    notifRow("取貨提醒", key: "pickupReminder", settings: settings)
                } label: {
                    Text("通知設定")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
    }

    private func notifRow(_ title: String, key: String, settings: [String: Any]) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            if let enabled = settings[key] as? Bool {
                Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(enabled ? .green : .red)
            } else {
                Text("--")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Packages

    @ViewBuilder
    private func packagesSection(_ packages: [AdminUserPackage]) -> some View {
        let active = packages.filter { !$0.isArchived && !$0.isDeleted }
        let archived = packages.filter { $0.isArchived && !$0.isDeleted }
        let deleted = packages.filter { $0.isDeleted }

        if !active.isEmpty {
            Section {
                ForEach(active) { pkg in
                    packageRow(pkg)
                }
            } header: {
                Text("進行中 (\(active.count))")
            }
        }

        if !archived.isEmpty {
            Section {
                ForEach(archived) { pkg in
                    packageRow(pkg)
                }
            } header: {
                Text("已封存 (\(archived.count))")
            }
        }

        if !hideDeleted, !deleted.isEmpty {
            Section {
                ForEach(deleted) { pkg in
                    packageRow(pkg, showDeleted: true)
                }
            } header: {
                Text("已刪除 (\(deleted.count))")
            }
        }

        if packages.isEmpty {
            Section {
                Text("沒有包裹")
                    .foregroundStyle(.secondary)
            } header: {
                Text("包裹")
            }
        }
    }

    private func packageRow(_ pkg: AdminUserPackage, showDeleted: Bool = false) -> some View {
        Button {
            selectedPackage = pkg
        } label: {
            HStack(spacing: 12) {
                if let carrier = pkg.carrierEnum {
                    CarrierLogoView(carrier: carrier, size: 44)
                        .opacity(showDeleted ? 0.4 : 1)
                } else {
                    Image(systemName: "shippingbox.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(pkg.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(showDeleted ? .secondary : .primary)
                            .lineLimit(1)

                        if showDeleted {
                            Text("已刪除")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(0.15))
                                .foregroundStyle(.red)
                                .clipShape(Capsule())
                        }
                    }

                    Text(pkg.trackingNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let status = pkg.statusEnum {
                        StatusIconBadge(status: status)
                    }

                    Text(pkg.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    // MARK: - Fetch

    private func fetchDetail() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await callCloudFunction("getUserDetail", params: ["uid": user.id])

            guard let userData = data["user"] as? [String: Any],
                  let packagesData = data["packages"] as? [[String: Any]],
                  let rawFields = data["rawFields"] as? [String: Any] else {
                errorMessage = "回傳格式錯誤"
                return
            }

            let packages = packagesData.map { dict in
                let eventsData = dict["events"] as? [[String: Any]] ?? []
                let events = eventsData.compactMap { eDict -> AdminPackageEvent? in
                    guard let timestamp = parseISO(eDict["timestamp"] as? String) else { return nil }
                    return AdminPackageEvent(
                        id: eDict["id"] as? String ?? UUID().uuidString,
                        timestamp: timestamp,
                        status: TrackingStatus(rawValue: eDict["status"] as? String ?? "") ?? .pending,
                        eventDescription: eDict["description"] as? String ?? "",
                        location: eDict["location"] as? String
                    )
                }

                return AdminUserPackage(
                    id: dict["id"] as? String ?? UUID().uuidString,
                    trackingNumber: dict["trackingNumber"] as? String ?? "",
                    carrier: dict["carrier"] as? String ?? "",
                    status: dict["status"] as? String ?? "",
                    customName: dict["customName"] as? String,
                    pickupCode: dict["pickupCode"] as? String,
                    pickupLocation: dict["pickupLocation"] as? String,
                    storeName: dict["storeName"] as? String,
                    latestDescription: dict["latestDescription"] as? String,
                    isArchived: dict["isArchived"] as? Bool ?? false,
                    isDeleted: dict["isDeleted"] as? Bool ?? false,
                    amount: dict["amount"] as? Double,
                    purchasePlatform: dict["purchasePlatform"] as? String,
                    lastUpdated: parseISO(dict["lastUpdated"] as? String),
                    createdAt: parseISO(dict["createdAt"] as? String),
                    events: events
                )
            }

            detail = AdminUserDetail(
                uid: userData["uid"] as? String ?? user.id,
                email: userData["email"] as? String,
                appleId: userData["appleId"] as? String,
                subscriptionTier: userData["subscriptionTier"] as? String,
                subscriptionProductID: userData["subscriptionProductID"] as? String,
                language: userData["language"] as? String,
                fcmToken: userData["fcmToken"] as? String,
                lastActive: parseISO(userData["lastActive"] as? String),
                createdAt: parseISO(userData["createdAt"] as? String),
                notificationSettings: userData["notificationSettings"] as? [String: Any],
                packages: packages,
                rawFields: rawFields
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseISO(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFormatter.date(from: string)
    }
}

// MARK: - AdminPackageDetailSheet

private struct AdminPackageDetailSheet: View {
    let package: AdminUserPackage

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    packageInfoSection
                    timelineSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(package.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Package Info

    private var packageInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let carrier = package.carrierEnum {
                    CarrierLogoView(carrier: carrier, size: 48)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(package.displayName)
                        .font(.headline)

                    Text(package.trackingNumber)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                if let status = package.statusEnum {
                    StatusIconBadge(status: status)
                }
            }

            // 額外資訊
            let infoItems: [(String, String)] = [
                ("取貨碼", package.pickupCode),
                ("取貨地點", package.pickupLocation ?? package.storeName),
                ("金額", package.amount.map { "$\(Int($0))" }),
                ("平台", package.purchasePlatform),
                ("最新狀態", package.latestDescription),
            ].compactMap { title, value in
                guard let v = value, !v.isEmpty else { return nil }
                return (title, v)
            }

            if !infoItems.isEmpty {
                VStack(spacing: 8) {
                    ForEach(infoItems, id: \.0) { title, value in
                        HStack {
                            Text(title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(value)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(12)
                .adaptiveCardStyle()
            }
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("物流歷程")
                .font(.headline)

            if package.events.isEmpty {
                Text("尚無物流事件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .adaptiveCardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(package.events.enumerated()), id: \.element.id) { index, event in
                        TimelineEventRow(
                            event: event,
                            isFirst: index == 0,
                            isLast: index == package.events.count - 1
                        )
                    }
                }
                .adaptiveCardStyle()
            }
        }
    }
}

// MARK: - RawFieldsSheet

private struct RawFieldsSheet: View {
    let title: String
    let fields: [String: Any]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedKeys, id: \.self) { key in
                    rawFieldRow(key: key, value: fields[key])
                }
            }
            .navigationTitle("Firestore 原始資料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sortedKeys: [String] {
        fields.keys.sorted()
    }

    @ViewBuilder
    private func rawFieldRow(key: String, value: Any?) -> some View {
        if let dict = value as? [String: Any] {
            // 巢狀 map → 展開 DisclosureGroup
            DisclosureGroup {
                ForEach(dict.keys.sorted(), id: \.self) { subKey in
                    leafRow(key: subKey, value: formatNestedValue(dict[subKey]))
                }
            } label: {
                Text(key)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        } else {
            leafRow(key: key, value: formatValue(value))
        }
    }

    private func leafRow(key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
    }

    private func formatNestedValue(_ value: Any?) -> String {
        guard let value else { return "null" }
        if let dict = value as? [String: Any] {
            let entries = dict.keys.sorted().map { k in
                "\(k): \(formatValue(dict[k]))"
            }
            return "{ \(entries.joined(separator: ", ")) }"
        }
        return formatValue(value)
    }

    private func formatValue(_ value: Any?) -> String {
        guard let value else { return "null" }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let string = value as? String {
            return string
        }
        if let array = value as? [Any] {
            return "[\(array.count) items]"
        }
        return String(describing: value)
    }
}

// MARK: - AdminVersionsView

struct AdminVersionsView: View {
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var summary: AdminSummary?
    @State private var users: [AdminUser] = []
    @State private var nextCursor: String?
    @State private var appVersionFilter: String = "全部"
    @State private var iosVersionFilter: String = "全部"

    private static let pageSize = 50

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// App 版本選項（從 summary 拿，所有使用者都納入）
    private var uniqueAppVersions: [String] {
        guard let summary else { return ["全部"] }
        let versions = summary.appVersionDistribution.keys
            .filter { $0 != "未知" }
            .sorted()
            .reversed()
        return ["全部"] + versions
    }

    private var uniqueIOSVersions: [String] {
        guard let summary else { return ["全部"] }
        let versions = summary.iosVersionDistribution.keys
            .filter { $0 != "未知" }
            .sorted()
            .reversed()
        return ["全部"] + versions
    }

    private var filteredUsers: [AdminUser] {
        users.filter { user in
            let appMatch = appVersionFilter == "全部" || user.appVersion == appVersionFilter
            let iosMatch = iosVersionFilter == "全部" || user.iosVersion == iosVersionFilter
            return appMatch && iosMatch
        }
    }

    var body: some View {
        List {
            distributionSection
            userListSection
        }
        .overlay {
            if isLoading && users.isEmpty {
                ProgressView("載入中⋯")
            }
        }
        .refreshable {
            await fetchUsers()
        }
        .alert("錯誤", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("確定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(uniqueAppVersions, id: \.self) { version in
                        Button {
                            appVersionFilter = version
                        } label: {
                            if appVersionFilter == version {
                                Label(version, systemImage: "checkmark")
                            } else {
                                Text(version)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "app.badge")
                }

                Menu {
                    ForEach(uniqueIOSVersions, id: \.self) { version in
                        Button {
                            iosVersionFilter = version
                        } label: {
                            if iosVersionFilter == version {
                                Label(version, systemImage: "checkmark")
                            } else {
                                Text(version)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "iphone.gen3")
                }
            }
        }
        .task {
            await fetchUsers()
        }
        .navigationTitle("版本分佈")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Distribution Section

    private var distributionSection: some View {
        Section {
            // App 版本分佈（從 summary 拿，全用戶）
            let appGroups = (summary?.appVersionDistribution ?? [:])
                .sorted { $0.key > $1.key }
            ForEach(appGroups, id: \.key) { version, count in
                HStack {
                    Label(version, systemImage: "app.badge")
                        .font(.subheadline)
                    Spacer()
                    Text("\(count)")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }

            Divider()

            // iOS 版本分佈
            let iosGroups = (summary?.iosVersionDistribution ?? [:])
                .sorted { $0.key > $1.key }
            ForEach(iosGroups, id: \.key) { version, count in
                HStack {
                    Label("iOS \(version)", systemImage: "iphone.gen3")
                        .font(.subheadline)
                    Spacer()
                    Text("\(count)")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        } header: {
            if let total = summary?.totalUsers {
                Text("版本分佈（共 \(total) 位用戶）")
            } else {
                Text("版本分佈")
            }
        }
    }

    // MARK: - User List

    private var userListSection: some View {
        Section {
            if filteredUsers.isEmpty && !isLoading {
                Text("沒有符合的用戶")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredUsers) { user in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.email)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                Text(user.appVersion ?? "未知")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("iOS \(user.iosVersion ?? "未知")")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        if let lastActive = user.lastActive {
                            Text(lastActive, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if nextCursor != nil {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Text("載入更多")
                                    .foregroundStyle(Color.appAccent)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isLoadingMore)
                }
            }
        } header: {
            Text("用戶 (\(filteredUsers.count) / \(users.count) 已載入)")
        }
    }

    // MARK: - Fetch

    private func fetchUsers() async {
        isLoading = true
        defer { isLoading = false }

        users = []
        nextCursor = nil

        await fetchPage(cursor: nil)
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await fetchPage(cursor: cursor)
    }

    private func fetchPage(cursor: String?) async {
        do {
            var params: [String: Any] = ["limit": Self.pageSize]
            if let cursor { params["cursor"] = cursor }
            let data = try await callCloudFunction("getAdminStats", params: params)

            if let summaryData = data["summary"] as? [String: Any] {
                summary = AdminSummary(
                    totalUsers: summaryData["totalUsers"] as? Int ?? 0,
                    subscribedUsers: summaryData["subscribedUsers"] as? Int ?? 0,
                    monthly: summaryData["monthly"] as? Int ?? 0,
                    yearly: summaryData["yearly"] as? Int ?? 0,
                    lifetime: summaryData["lifetime"] as? Int ?? 0,
                    appVersionDistribution: parseStringIntDict(summaryData["appVersionDistribution"]),
                    iosVersionDistribution: parseStringIntDict(summaryData["iosVersionDistribution"])
                )
            }

            if let usersData = data["users"] as? [[String: Any]] {
                let newUsers = usersData.map { dict in
                    AdminUser(
                        id: dict["uid"] as? String ?? "",
                        email: dict["email"] as? String ?? "(no email)",
                        subscriptionTier: dict["subscriptionTier"] as? String,
                        subscriptionProductID: dict["subscriptionProductID"] as? String,
                        packageCount: dict["packageCount"] as? Int ?? 0,
                        lastActive: parseISO(dict["lastActive"] as? String),
                        createdAt: parseISO(dict["createdAt"] as? String),
                        language: dict["language"] as? String,
                        appVersion: dict["appVersion"] as? String,
                        iosVersion: dict["iosVersion"] as? String
                    )
                }
                users.append(contentsOf: newUsers)
            }

            nextCursor = data["nextCursor"] as? String
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseISO(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFormatter.date(from: string)
    }
}

#endif
