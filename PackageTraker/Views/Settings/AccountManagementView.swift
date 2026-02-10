//
//  AccountManagementView.swift
//  PackageTraker
//
//  帳號管理頁面（刪除帳號）
//

import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseFirestore

/// 帳號管理頁面
struct AccountManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var linkedAccounts: [LinkedEmailAccount]

    @ObservedObject private var authService = FirebaseAuthService.shared

    @State private var showDeleteConfirmation = false
    @State private var showDeleteSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 標題
            Text(String(localized: "accountManagement.title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            // 刪除帳號按鈕
            Button {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red)

                    Text(String(localized: "accountManagement.deleteAccount"))
                        .foregroundStyle(.red)
                        .fontWeight(.medium)

                    Spacer()
                }
                .padding(16)
                .background(Color.secondaryCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)

            // 說明文字
            Text(String(localized: "accountManagement.deleteDescription"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .adaptiveBackground()
        .navigationTitle(String(localized: "settings.accountManagement"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            String(localized: "accountManagement.deleteConfirmTitle"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "accountManagement.deleteAccount"), role: .destructive) {
                deleteAccount()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "accountManagement.deleteConfirmMessage"))
        }
        .alert(String(localized: "accountManagement.deleteSuccess"), isPresented: $showDeleteSuccess) {
            Button(String(localized: "common.ok"), role: .cancel) {
                dismiss()
            }
        }
    }

    // MARK: - Actions

    private func deleteAccount() {
        do {
            // 1. 刪除所有包裹（cascade 會自動刪除 TrackingEvent）
            let packageDescriptor = FetchDescriptor<Package>()
            let allPackages = try modelContext.fetch(packageDescriptor)

            let packageIds = allPackages.map { $0.id }

            for package in allPackages {
                modelContext.delete(package)
            }

            // 2. 刪除所有 LinkedEmailAccount
            for account in linkedAccounts {
                modelContext.delete(account)
            }

            try modelContext.save()

            // 3. 從 Firestore 刪除所有包裹
            for id in packageIds {
                FirebaseSyncService.shared.deletePackage(id)
            }

            // 4. 重置初次同步標記
            if let uid = authService.currentUser?.uid {
                UserDefaults.standard.removeObject(forKey: "hasPerformedInitialSync_\(uid)")
            }

            // 5. 取消所有通知
            NotificationService.shared.cancelAllNotifications()

            // 6. 清除快取的顯示名稱
            UserDefaults.standard.removeObject(forKey: "cachedDisplayName")

            // 7. 清除 FCM Token
            Task {
                await FirebasePushService.shared.clearToken()
            }

            // 8. 顯示成功
            showDeleteSuccess = true

            // 9. 登出（延遲讓 alert 先顯示）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                try? authService.signOut()
            }

        } catch {
            print("[AccountManagement] Delete account failed: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AccountManagementView()
    }
    .modelContainer(for: [Package.self, TrackingEvent.self, LinkedEmailAccount.self], inMemory: true)
}
