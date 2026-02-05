//
//  EmailLinkingSheet.swift
//  PackageTraker
//
//  Email 連結登入 Sheet
//

import SwiftUI
import SwiftData

/// Email 連結 Sheet
struct EmailLinkingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authManager: GmailAuthManager

    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // 圖示
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .symbolEffect(.pulse, options: .repeating)

                // 標題與說明
                VStack(spacing: 12) {
                    Text(String(localized: "email.linkTitle"))
                        .font(.title2.bold())

                    Text(String(localized: "email.linkDescription"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // 權限說明
                VStack(alignment: .leading, spacing: 16) {
                    permissionRow(
                        icon: "eye",
                        title: String(localized: "email.permissionReadOnly"),
                        description: String(localized: "email.permissionReadOnlyDesc")
                    )

                    permissionRow(
                        icon: "lock.shield",
                        title: String(localized: "email.permissionSecure"),
                        description: String(localized: "email.permissionSecureDesc")
                    )

                    permissionRow(
                        icon: "trash.slash",
                        title: String(localized: "email.permissionRevoke"),
                        description: String(localized: "email.permissionRevokeDesc")
                    )
                }
                .padding(.horizontal, 24)

                Spacer()

                // 登入按鈕
                VStack(spacing: 16) {
                    Button {
                        Task {
                            await signInWithGoogle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            // Google 圖示
                            Image(systemName: "g.circle.fill")
                                .font(.title2)

                            Text(String(localized: "email.signInWithGoogle"))
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(authManager.isLoading)
                    .opacity(authManager.isLoading ? 0.6 : 1)

                    // 載入指示器
                    if authManager.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(String(localized: "email.signingIn"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 隱私說明
                    Text(String(localized: "email.consentMessage"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle(String(localized: "email.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .alert("登入未完成", isPresented: $showError) {
                Button("確定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onChange(of: authManager.isSignedIn) { _, isSignedIn in
                if isSignedIn {
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Components

    private func permissionRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func signInWithGoogle() async {
        do {
            try await authManager.signIn()
        } catch let error as GmailError {
            if case .signInCancelled = error {
                // 使用者取消，不顯示錯誤
                return
            }
            errorMessage = error.localizedDescription
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Email Management Sheet (for managing linked accounts)

struct EmailManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var authManager: GmailAuthManager

    let account: LinkedEmailAccount?

    @State private var showUnlinkConfirmation = false
    @State private var isSyncing = false
    @State private var syncResult: String?

    var body: some View {
        NavigationStack {
            List {
                // 帳號資訊
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 50, height: 50)

                            Image(systemName: "envelope.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(authManager.userEmail ?? "未知")
                                .font(.headline)

                            if let account = account {
                                Text("已連結 \(account.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // 同步狀態
                if let account = account {
                    Section("同步狀態") {
                        HStack {
                            Text("最後同步")
                            Spacer()
                            if let syncTime = account.relativeSyncTime {
                                Text(syncTime)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("從未同步")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let summary = account.lastSyncSummary {
                            HStack {
                                Text("同步結果")
                                Spacer()
                                Text(summary)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Toggle("自動同步", isOn: Binding(
                            get: { account.autoSyncEnabled },
                            set: { account.autoSyncEnabled = $0 }
                        ))
                    }
                }

                // 操作
                Section {
                    Button {
                        Task {
                            await manualSync()
                        }
                    } label: {
                        HStack {
                            Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isSyncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSyncing)

                    if let result = syncResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 解除連結
                Section {
                    Button(role: .destructive) {
                        showUnlinkConfirmation = true
                    } label: {
                        Label("解除連結", systemImage: "link.badge.minus")
                    }
                }
            }
            .navigationTitle("Email 設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "確定要解除連結嗎？",
                isPresented: $showUnlinkConfirmation,
                titleVisibility: .visible
            ) {
                Button("解除連結", role: .destructive) {
                    unlinkAccount()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("解除連結後，將不再從此郵件帳號同步物流資訊。")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func manualSync() async {
        isSyncing = true
        syncResult = nil

        // 這裡會在整合到 PackageListView 後實作完整的同步邏輯
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        isSyncing = false
        syncResult = "同步完成"

        account?.updateSyncStatus(summary: "手動同步完成")
    }

    private func unlinkAccount() {
        // 登出 Gmail
        authManager.signOut()

        // 刪除 SwiftData 記錄
        if let account = account {
            modelContext.delete(account)
        }

        dismiss()
    }
}

// MARK: - Previews

#Preview("連結 Sheet") {
    EmailLinkingSheet(authManager: GmailAuthManager.shared)
}
