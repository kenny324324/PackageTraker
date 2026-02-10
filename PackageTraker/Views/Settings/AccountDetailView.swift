//
//  AccountDetailView.swift
//  PackageTraker
//
//  個人資訊詳情頁
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// 個人資訊頁面（從設定帳號區塊點入）
struct AccountDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authService = FirebaseAuthService.shared

    @State private var showSignOutAlert = false
    @State private var showEditSheet = false

    // 快取資料，避免登出轉場時消失
    @State private var cachedDisplayName: String = ""
    @State private var cachedCreationDate: Date?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 24) {
                    // 大頭像
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(Color(.systemGray3))
                        .padding(.top, 16)

                    // 名稱
                    Text(cachedDisplayName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    // 資訊卡片
                    VStack(spacing: 0) {
                        infoRow(
                            title: String(localized: "account.nickname"),
                            value: cachedDisplayName
                        )

                        Divider()
                            .background(Color.white.opacity(0.1))

                        infoRow(
                            title: String(localized: "account.registrationDate"),
                            value: formattedCreationDate
                        )
                    }
                    .background(Color.secondaryCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    Spacer()
                }
                .padding(.horizontal)

                // 登出按鈕（底部固定）
                Button {
                    showSignOutAlert = true
                } label: {
                    if #available(iOS 26, *) {
                        Text(String(localized: "settings.signOut"))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white)
                            .frame(height: 54)
                            .frame(maxWidth: .infinity)
                            .glassEffect(.regular.tint(.red), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.red.opacity(0.08))
                                )

                            Text(String(localized: "settings.signOut"))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.white)
                        }
                        .frame(height: 54)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .adaptiveBackground()
            .navigationTitle(String(localized: "account.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "account.close")) {
                        dismiss()
                    }
                    .foregroundStyle(Color.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.edit")) {
                        showEditSheet = true
                    }
                    .foregroundStyle(Color.white)
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditProfileSheet(displayName: $cachedDisplayName, onSave: saveNickname)
            }
            .alert(String(localized: "settings.signOut.confirmTitle"), isPresented: $showSignOutAlert) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "settings.signOut"), role: .destructive) {
                    signOut()
                }
            } message: {
                Text(String(localized: "settings.signOut.confirmMessage"))
            }
            .tint(Color.white)
            .onAppear {
                loadUserProfile()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Info Row

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Computed

    private var formattedCreationDate: String {
        guard let date = cachedCreationDate else {
            return String(localized: "account.unknown")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Actions

    /// 載入用戶資料
    private func loadUserProfile() {
        guard let userId = authService.currentUser?.uid else { return }

        // 設定建立日期
        if cachedCreationDate == nil {
            cachedCreationDate = authService.currentUser?.metadata.creationDate
        }

        // 從 Firestore 載入暱稱
        let db = Firestore.firestore()
        Task {
            do {
                let doc = try await db.collection("users").document(userId).getDocument()

                if let nickname = doc.data()?["nickname"] as? String, !nickname.isEmpty {
                    await MainActor.run {
                        cachedDisplayName = nickname
                    }
                } else {
                    // 沒有暱稱，使用 email 前綴作為預設值
                    await MainActor.run {
                        if let email = authService.currentUser?.email {
                            cachedDisplayName = email.components(separatedBy: "@").first ?? email
                        } else {
                            cachedDisplayName = String(localized: "account.unknown")
                        }
                    }
                }
            } catch {
                print("[AccountDetail] Failed to load profile: \(error)")
                // 載入失敗時使用預設值
                await MainActor.run {
                    if let email = authService.currentUser?.email {
                        cachedDisplayName = email.components(separatedBy: "@").first ?? email
                    } else {
                        cachedDisplayName = String(localized: "account.unknown")
                    }
                }
            }
        }
    }

    /// 儲存暱稱到 Firestore
    func saveNickname(_ nickname: String) {
        guard let userId = authService.currentUser?.uid else { return }

        let db = Firestore.firestore()
        Task {
            do {
                try await db.collection("users").document(userId).setData([
                    "nickname": nickname,
                    "lastActive": FieldValue.serverTimestamp()
                ], merge: true)
                print("[AccountDetail] Nickname saved: \(nickname)")
            } catch {
                print("[AccountDetail] Failed to save nickname: \(error)")
            }
        }
    }

    private func signOut() {
        // 先關閉 sheet
        dismiss()

        // 清除 FCM Token
        Task {
            await FirebasePushService.shared.clearToken()
        }

        do {
            try authService.signOut()
        } catch {
            print("Sign out failed: \(error)")
        }
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var displayName: String
    let onSave: (String) -> Void

    @State private var editedName: String = ""
    @State private var showImagePicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 頭像編輯
                Button {
                    showImagePicker = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 100))
                            .foregroundStyle(Color(.systemGray3))

                        ZStack {
                            Circle()
                                .fill(Color.appAccent)
                                .frame(width: 32, height: 32)

                            Image(systemName: "camera.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.top, 16)

                // 暱稱編輯
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "account.nickname"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField(String(localized: "account.nicknamePlaceholder"), text: $editedName)
                        .font(.body)
                        .adaptiveInputStyle()
                }
                .padding(.horizontal)

                Spacer()
            }
            .adaptiveBackground()
            .navigationTitle(String(localized: "account.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(Color.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.save")) {
                        displayName = editedName
                        onSave(editedName)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)
                    .disabled(editedName.isEmpty)
                }
            }
            .onAppear {
                editedName = displayName
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Preview

#Preview {
    AccountDetailView()
}
