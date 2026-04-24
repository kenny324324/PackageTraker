//
//  AccountDetailView.swift
//  PackageTraker
//
//  個人資訊詳情頁
//

import SwiftUI
import PhotosUI
import StoreKit
import FirebaseAuth
import FirebaseFirestore

/// 個人資訊頁面（從設定帳號區塊點入）
struct AccountDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authService = FirebaseAuthService.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @State private var showSignOutAlert = false
    @State private var showEditSheet = false
    @State private var showPaywall = false
    @State private var isRestoring = false

    // 快取資料，使用 AppStorage 持久化避免閃爍
    @AppStorage("cachedDisplayName") private var cachedDisplayName: String = ""
    @AppStorage("cachedPhotoURL") private var cachedPhotoURL: String = ""
    @State private var cachedCreationDate: Date?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 24) {
                    // 大頭像
                    AvatarView(urlString: cachedPhotoURL, size: 100)
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

                    // 訂閱管理區塊
                    if FeatureFlags.subscriptionEnabled {
                        subscriptionSection
                    }

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
                        Text(String(localized: "settings.signOut"))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white)
                            .frame(height: 54)
                            .frame(maxWidth: .infinity)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
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
                EditProfileSheet(
                    displayName: $cachedDisplayName,
                    photoURL: $cachedPhotoURL,
                    onSave: saveNickname
                )
            }
            .fullScreenCover(isPresented: $showPaywall) {
                PaywallView()
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

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "account.subscription.title"))
                .font(.headline)
                .foregroundStyle(.white)

            VStack(spacing: 0) {
                // 當前方案
                HStack(spacing: 12) {
                    Image(systemName: subscriptionManager.isPro ? "crown.fill" : "shippingbox.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(subscriptionManager.isPro ? .yellow : .secondary)
                        .frame(width: 28)

                    Text(String(localized: "account.subscription.currentPlan"))
                        .foregroundStyle(.white)

                    Spacer()

                    HStack(spacing: 6) {
                        if !subscriptionManager.isPro {
                            Text(String(localized: "settings.subscription.free"))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }

                        if subscriptionManager.isPro {
                            Text("PRO")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    LinearGradient(
                                        colors: [.yellow, .orange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(16)

                Divider()
                    .background(Color.white.opacity(0.1))

                // 升級 / 管理訂閱
                if subscriptionManager.isPro {
                    // 已訂閱：管理訂閱（跳轉 Apple 訂閱管理頁面）
                    Button {
                        openSubscriptionManagement()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gear")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .frame(width: 28)

                            Text(String(localized: "account.subscription.manage"))
                                .foregroundStyle(.white)

                            Spacer()

                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    // 免費用戶：升級按鈕
                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.yellow)
                                .frame(width: 28)

                            Text(String(localized: "account.subscription.upgrade"))
                                .foregroundStyle(.white)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

            }
            .background(Color.secondaryCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // 恢復購買（小灰字，放在卡片外）
            Button {
                restorePurchases()
            } label: {
                HStack(spacing: 4) {
                    if isRestoring {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(String(localized: "account.subscription.restore"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isRestoring)
            .frame(maxWidth: .infinity, alignment: .center)
        }
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

        // 從 Firestore 載入暱稱（背景更新，不影響已快取的名稱）
        let db = Firestore.firestore()
        Task {
            do {
                let doc = try await db.collection("users").document(userId).getDocument()

                if let photoURL = doc.data()?["photoURL"] as? String {
                    await MainActor.run {
                        cachedPhotoURL = photoURL
                    }
                }

                if let nickname = doc.data()?["nickname"] as? String, !nickname.isEmpty {
                    await MainActor.run {
                        cachedDisplayName = nickname
                    }
                } else if cachedDisplayName.isEmpty {
                    // Firestore 沒有暱稱且本地也沒快取，才用 email 前綴
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
                if cachedDisplayName.isEmpty {
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

    /// 開啟 Apple 訂閱管理頁面
    private func openSubscriptionManagement() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }

    /// 恢復購買
    private func restorePurchases() {
        isRestoring = true
        Task {
            await subscriptionManager.restorePurchases()
            isRestoring = false
        }
    }

    private func signOut() {
        // 清除快取的顯示名稱與頭像
        cachedDisplayName = ""
        cachedPhotoURL = ""
        AvatarCache.shared.clear()

        // 清除 FCM Token
        Task {
            await FirebasePushService.shared.clearToken()
        }

        do {
            try authService.signOut()
        } catch {
            print("Sign out failed: \(error)")
        }

        // 最後再關閉 sheet（確保 onChange 先觸發）
        dismiss()
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var displayName: String
    @Binding var photoURL: String
    let onSave: (String) -> Void

    @State private var editedName: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var isUploading = false
    @State private var uploadError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 頭像編輯
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    ZStack(alignment: .bottomTrailing) {
                        avatarPreview
                            .frame(width: 100, height: 100)

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
                .disabled(isUploading)
                .padding(.top, 16)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task { await loadPickedImage(newItem) }
                }

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
                    .disabled(isUploading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isUploading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(String(localized: "common.save"))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.white)
                        }
                    }
                    .disabled(editedName.isEmpty || isUploading)
                }
            }
            .onAppear {
                editedName = displayName
            }
            .alert(
                String(localized: "avatar.uploadFailed"),
                isPresented: Binding(
                    get: { uploadError != nil },
                    set: { if !$0 { uploadError = nil } }
                ),
                presenting: uploadError
            ) { _ in
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { error in
                Text(error)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let pickedImage {
            Image(uiImage: pickedImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            AvatarView(urlString: photoURL, size: 100)
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                pickedImage = image
            }
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func save() async {
        if let pickedImage {
            isUploading = true
            do {
                let url = try await AvatarStorageService.shared.uploadAvatar(pickedImage)
                photoURL = url
            } catch {
                uploadError = error.localizedDescription
                isUploading = false
                return
            }
            isUploading = false
        }

        displayName = editedName
        onSave(editedName)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    AccountDetailView()
}
