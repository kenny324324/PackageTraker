#if DEBUG
import SwiftUI

// MARK: - Data Models

private struct NotificationLog: Identifiable {
    let id: String
    let userId: String
    let type: String
    let title: String
    let body: String
    let targetDeviceCount: Int
    let failedDeviceIds: [String]
    let success: Bool
    let errorDetails: String?
    let trackingNumber: String?
    let reminderPackageCount: Int?
    let createdAt: Date?

    var typeLabel: String {
        switch type {
        case "statusChange": return "狀態變更"
        case "dailyReminder": return "每日提醒"
        default: return type
        }
    }

    var typeColor: Color {
        switch type {
        case "statusChange": return .blue
        case "dailyReminder": return .orange
        default: return .gray
        }
    }

    var shortUserId: String {
        if userId.count > 8 {
            return String(userId.prefix(8)) + "..."
        }
        return userId
    }
}

private enum LogTypeFilter: String, CaseIterable {
    case all = "全部"
    case statusChange = "狀態變更"
    case dailyReminder = "每日提醒"
}

private enum ResultFilter: String, CaseIterable {
    case all = "全部"
    case success = "成功"
    case failed = "失敗"
}

// MARK: - NotificationLogsView

struct NotificationLogsView: View {
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var allLogs: [NotificationLog] = []
    @State private var typeFilter: LogTypeFilter = .all
    @State private var resultFilter: ResultFilter = .all
    @State private var queryLimit = 100

    private var logs: [NotificationLog] {
        allLogs.filter { log in
            let typeMatch: Bool = switch typeFilter {
            case .all: true
            case .statusChange: log.type == "statusChange"
            case .dailyReminder: log.type == "dailyReminder"
            }
            let resultMatch: Bool = switch resultFilter {
            case .all: true
            case .success: log.success
            case .failed: !log.success
            }
            return typeMatch && resultMatch
        }
    }

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var body: some View {
        List {
            filterSection
            logsSection
        }
        .overlay {
            if isLoading && allLogs.isEmpty {
                ProgressView("載入中⋯")
            }
        }
        .refreshable {
            await fetchLogs()
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
            await fetchLogs()
        }
        .navigationTitle("通知記錄")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        Section {
            Picker("類型", selection: $typeFilter) {
                Text("全部").tag(LogTypeFilter.all)
                Text("狀態變更").tag(LogTypeFilter.statusChange)
                Text("每日提醒").tag(LogTypeFilter.dailyReminder)
            }

            Picker("結果", selection: $resultFilter) {
                Text("全部").tag(ResultFilter.all)
                Text("成功").tag(ResultFilter.success)
                Text("失敗").tag(ResultFilter.failed)
            }
        } header: {
            Text("篩選")
        }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        Section {
            if logs.isEmpty && !isLoading {
                Text("沒有通知記錄")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(logs) { log in
                    logRow(log)
                }

                if allLogs.count >= queryLimit {
                    Button {
                        queryLimit += 100
                        Task { await fetchLogs() }
                    } label: {
                        HStack {
                            Spacer()
                            Text("載入更多")
                                .foregroundStyle(Color.appAccent)
                            Spacer()
                        }
                    }
                }
            }
        } header: {
            Text(verbatim: "通知記錄 (\(logs.count))")
        }
    }

    // MARK: - Log Row

    @ViewBuilder
    private func logRow(_ log: NotificationLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 第一行：type badge + 時間 + 成功/失敗
            HStack {
                Text(log.typeLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(log.typeColor.opacity(0.2))
                    .foregroundStyle(log.typeColor)
                    .clipShape(Capsule())

                Spacer()

                if let date = log.createdAt {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Circle()
                    .fill(log.success ? .green : .red)
                    .frame(width: 8, height: 8)
            }

            // 第二行：標題
            Text(log.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            // 第三行：內文
            Text(log.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // 第四行：metadata
            HStack(spacing: 12) {
                Label(log.shortUserId, systemImage: "person.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Label("\(log.targetDeviceCount)", systemImage: "iphone")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if !log.failedDeviceIds.isEmpty {
                    Label("\(log.failedDeviceIds.count) 失敗", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                if let trackingNumber = log.trackingNumber, !trackingNumber.isEmpty {
                    Text(trackingNumber)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else if let count = log.reminderPackageCount {
                    Text(verbatim: "\(count) 件待取")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // 錯誤詳情
            if let error = log.errorDetails {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Fetch

    private func fetchLogs() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await callCloudFunction("getNotificationLogs", params: ["limit": queryLimit])

            guard let logsData = data["logs"] as? [[String: Any]] else {
                errorMessage = "回傳格式錯誤"
                return
            }

            allLogs = logsData.map { dict in
                let metadata = dict["metadata"] as? [String: Any] ?? [:]
                return NotificationLog(
                    id: dict["id"] as? String ?? UUID().uuidString,
                    userId: dict["userId"] as? String ?? "",
                    type: dict["type"] as? String ?? "",
                    title: dict["title"] as? String ?? "",
                    body: dict["body"] as? String ?? "",
                    targetDeviceCount: dict["targetDeviceCount"] as? Int ?? 0,
                    failedDeviceIds: dict["failedDeviceIds"] as? [String] ?? [],
                    success: dict["success"] as? Bool ?? false,
                    errorDetails: dict["errorDetails"] as? String,
                    trackingNumber: metadata["trackingNumber"] as? String,
                    reminderPackageCount: metadata["reminderPackageCount"] as? Int,
                    createdAt: parseISO(dict["createdAt"] as? String)
                )
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
