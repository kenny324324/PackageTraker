//
//  InviteFriendsSection.swift
//  PackageTraker
//
//  Settings 頁面的「邀請好友」區塊
//

import SwiftUI

/// 邀請好友卡片（Settings 頁面用）
struct InviteFriendsSection: View {
    @ObservedObject private var referralService = ReferralService.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @State private var codeCopied = false
    @State private var inputCode = ""
    @State private var isApplying = false
    @State private var showInputAlert = false
    @State private var showResult = false
    @State private var resultTitle = ""
    @State private var resultMessage = ""
    @State private var showReferralList = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 標題
            HStack {
                Image("ReferralGift")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                Text(String(localized: "referral.inviteFriends"))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Spacer()

                // 已成功邀請人數（可點擊查看列表）
                Button {
                    showReferralList = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text(String(format: String(localized: "referral.successCount"), referralService.referralSuccessCount))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // 說明文字
            Text(String(localized: "referral.description"))
                .font(.caption)
                .foregroundStyle(.secondary)

            // 邀請碼顯示
            if let code = referralService.referralCode {
                HStack {
                    Text(code)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .tracking(2)

                    Spacer()

                    // 分享 Menu
                    Menu {
                        Button {
                            UIPasteboard.general.string = code
                            codeCopied = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                codeCopied = false
                            }
                        } label: {
                            Label(String(localized: "referral.copyCode"), systemImage: "doc.on.doc")
                        }

                        Button {
                            shareInvite(code: code)
                        } label: {
                            Label(String(localized: "referral.shareInvite"), systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Text(codeCopied ? String(localized: "referral.codeCopied") : String(localized: "referral.share"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                    }
                }
                .padding(12)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            } else {
                // 載入中
                HStack {
                    ProgressView()
                        .tint(.secondary)
                    Text(String(localized: "common.loading"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 輸入好友邀請碼（已使用過則隱藏）
            if !referralService.hasBeenReferred {
                Button {
                    inputCode = ""
                    showInputAlert = true
                } label: {
                    Text(String(localized: "referral.enterCode"))
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            // 試用中 badge
            if subscriptionManager.isReferralTrial, let days = referralService.daysRemaining {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                    Text(String(format: String(localized: "referral.trialBadge"), days))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.appAccent.opacity(0.3))
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color.secondaryCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task {
            await referralService.loadReferralData()
            await referralService.ensureReferralCode()
        }
        .alert(String(localized: "referral.enterCode"), isPresented: $showInputAlert) {
            TextField(String(localized: "referral.enterCode.placeholder"), text: $inputCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button(String(localized: "referral.apply")) {
                applyCode()
            }
            Button(String(localized: "common.cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "referral.enterCode.message"))
        }
        .alert(resultTitle, isPresented: $showResult) {
            Button(String(localized: "common.ok")) { }
        } message: {
            Text(resultMessage)
        }
        .sheet(isPresented: $showReferralList) {
            ReferralListSheet()
                .presentationDetents([.medium])
                .presentationBackground {
                    if #available(iOS 26, *) {
                        Color.clear
                    } else {
                        Color.cardBackground
                    }
                }
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Apply Code

    private func applyCode() {
        let code = inputCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }

        isApplying = true
        Task {
            do {
                try await referralService.applyReferralCode(code)
                resultTitle = String(localized: "referral.alert.bound")
                resultMessage = String(localized: "referral.codeBound")
                inputCode = ""
            } catch let error as ReferralError {
                switch error {
                case .codeNotFound:
                    resultTitle = String(localized: "referral.alert.notFound")
                default:
                    resultTitle = String(localized: "referral.notice")
                }
                resultMessage = error.localizedDescription
            } catch {
                resultTitle = String(localized: "referral.notice")
                resultMessage = error.localizedDescription
            }
            isApplying = false
            showResult = true
        }
    }

    // MARK: - Share

    private func shareInvite(code: String) {
        let message = String(localized: "referral.shareMessage.\(code)")
        let deepLink = "packagetraker://invite/\(code)"
        let items: [Any] = ["\(message)\n\n\(deepLink)"]

        guard let topVC = topViewController() else { return }
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        topVC.present(activityVC, animated: true)
    }

    private func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}

// MARK: - Referral List Sheet

struct ReferralListSheet: View {
    @ObservedObject private var referralService = ReferralService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if referralService.referralRecords.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "referral.list.empty"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(referralService.referralRecords) { record in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.displayName.isEmpty ? String(localized: "referral.list.anonymous") : record.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(.white)

                                    Text(record.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(record.status.label)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(record.status == .completed ? .green : .orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        (record.status == .completed ? Color.green : Color.orange).opacity(0.15)
                                    )
                                    .clipShape(Capsule())
                            }
                        }

                        Section {
                        } footer: {
                            Text(String(localized: "referral.list.hint"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 4)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .background(Color.clear)
            .navigationTitle(String(localized: "referral.list.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}
