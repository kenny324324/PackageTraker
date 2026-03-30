#if DEBUG
import SwiftUI
import FirebaseFunctions

// MARK: - Data Models

private struct AdminSummary {
    let totalUsers: Int
    let subscribedUsers: Int
    let monthly: Int
    let yearly: Int
    let lifetime: Int
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

    var isPro: Bool { subscriptionTier == "pro" }

    var subscriptionLabel: String {
        guard isPro, let productID = subscriptionProductID else { return "Free" }
        if productID.contains("lifetime") { return "終身" }
        if productID.contains("yearly") { return "年訂閱" }
        if productID.contains("monthly") { return "月訂閱" }
        return "Pro"
    }
}

private enum SortOrder: String, CaseIterable {
    case packageCount = "包裹數"
    case lastActive = "最後活躍"
    case createdAt = "建立時間"
}

// MARK: - AdminStatsView

struct AdminStatsView: View {
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var summary: AdminSummary?
    @State private var users: [AdminUser] = []
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .packageCount

    private let functions = Functions.functions(region: "asia-east1")
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var filteredUsers: [AdminUser] {
        let filtered = searchText.isEmpty
            ? users
            : users.filter { $0.email.localizedCaseInsensitiveContains(searchText) }

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
            if let summary {
                summarySection(summary)
            }

            usersSection
        }
        .searchable(text: $searchText, prompt: "搜尋 email")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        .navigationTitle("資料庫統計")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary Section

    @ViewBuilder
    private func summarySection(_ summary: AdminSummary) -> some View {
        Section {
            statsRow("總用戶數", value: "\(summary.totalUsers)", icon: "person.2.fill")
            statsRow("訂閱用戶", value: "\(summary.subscribedUsers)", icon: "star.fill", color: .yellow)

            if summary.subscribedUsers > 0 {
                Divider()
                statsRow("月訂閱", value: "\(summary.monthly)", icon: "calendar")
                statsRow("年訂閱", value: "\(summary.yearly)", icon: "calendar.badge.clock")
                statsRow("終身", value: "\(summary.lifetime)", icon: "infinity", color: .purple)
            }
        } header: {
            Text("總覽")
        }
    }

    private func statsRow(_ title: String, value: String, icon: String, color: Color = .secondary) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(color)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Users Section

    private var usersSection: some View {
        Section {
            ForEach(filteredUsers) { user in
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
        } header: {
            Text("所有用戶 (\(filteredUsers.count))")
        }
    }

    // MARK: - Fetch

    private func fetchStats() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let callable = functions.httpsCallable("getAdminStats")
            callable.timeoutInterval = 120
            let result = try await callable.call()

            guard let data = result.data as? [String: Any] else {
                errorMessage = "回傳格式錯誤"
                return
            }

            // Parse summary
            if let summaryData = data["summary"] as? [String: Any] {
                summary = AdminSummary(
                    totalUsers: summaryData["totalUsers"] as? Int ?? 0,
                    subscribedUsers: summaryData["subscribedUsers"] as? Int ?? 0,
                    monthly: summaryData["monthly"] as? Int ?? 0,
                    yearly: summaryData["yearly"] as? Int ?? 0,
                    lifetime: summaryData["lifetime"] as? Int ?? 0
                )
            }

            // Parse users
            if let usersData = data["users"] as? [[String: Any]] {
                users = usersData.map { dict in
                    AdminUser(
                        id: dict["uid"] as? String ?? "",
                        email: dict["email"] as? String ?? "(no email)",
                        subscriptionTier: dict["subscriptionTier"] as? String,
                        subscriptionProductID: dict["subscriptionProductID"] as? String,
                        packageCount: dict["packageCount"] as? Int ?? 0,
                        lastActive: parseISO(dict["lastActive"] as? String),
                        createdAt: parseISO(dict["createdAt"] as? String),
                        language: dict["language"] as? String
                    )
                }
            }
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
