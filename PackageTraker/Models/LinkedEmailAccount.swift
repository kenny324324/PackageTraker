//
//  LinkedEmailAccount.swift
//  PackageTraker
//
//  已連結的 Email 帳號 (SwiftData Model)
//

import Foundation
import SwiftData

/// 已連結的 Email 帳號
@Model
final class LinkedEmailAccount {
    /// 唯一識別碼
    var id: UUID

    /// Email 地址
    var email: String

    /// 服務提供者 (gmail, outlook, etc.)
    var provider: String

    /// 建立時間
    var createdAt: Date

    /// 最後同步時間
    var lastSyncAt: Date?

    /// 最後同步結果摘要
    var lastSyncSummary: String?

    /// 是否啟用自動同步
    var autoSyncEnabled: Bool

    /// 同步過的郵件 ID 列表（用於去重）
    var syncedMessageIds: [String]

    // MARK: - Initialization

    init(
        email: String,
        provider: String = "gmail",
        autoSyncEnabled: Bool = true
    ) {
        self.id = UUID()
        self.email = email
        self.provider = provider
        self.createdAt = Date()
        self.lastSyncAt = nil
        self.lastSyncSummary = nil
        self.autoSyncEnabled = autoSyncEnabled
        self.syncedMessageIds = []
    }

    // MARK: - Computed Properties

    /// 顯示名稱
    var displayName: String {
        return email
    }

    /// 服務提供者圖示名稱
    var providerIconName: String {
        switch provider.lowercased() {
        case "gmail":
            return "envelope.fill"
        case "outlook":
            return "envelope.badge.fill"
        default:
            return "envelope"
        }
    }

    /// 相對同步時間描述
    var relativeSyncTime: String? {
        guard let lastSyncAt = lastSyncAt else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "zh_TW")
        return formatter.localizedString(for: lastSyncAt, relativeTo: Date())
    }

    /// 是否需要重新同步（超過 15 分鐘）
    var needsSync: Bool {
        guard let lastSyncAt = lastSyncAt else { return true }
        return Date().timeIntervalSince(lastSyncAt) > 15 * 60
    }

    // MARK: - Methods

    /// 更新同步狀態
    func updateSyncStatus(summary: String?) {
        self.lastSyncAt = Date()
        self.lastSyncSummary = summary
    }

    /// 記錄已同步的郵件 ID
    func markMessageAsSynced(_ messageId: String) {
        if !syncedMessageIds.contains(messageId) {
            syncedMessageIds.append(messageId)

            // 只保留最近 1000 筆記錄
            if syncedMessageIds.count > 1000 {
                syncedMessageIds = Array(syncedMessageIds.suffix(1000))
            }
        }
    }

    /// 檢查郵件是否已同步過
    func isMessageSynced(_ messageId: String) -> Bool {
        return syncedMessageIds.contains(messageId)
    }

    /// 清除同步記錄
    func clearSyncHistory() {
        syncedMessageIds = []
        lastSyncAt = nil
        lastSyncSummary = nil
    }
}
