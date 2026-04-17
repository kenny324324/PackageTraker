//
//  ReferralService.swift
//  PackageTraker
//
//  邀請碼系統：管理推薦碼生成、套用、試用期
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// 邀請碼錯誤
enum ReferralError: LocalizedError {
    case codeNotFound
    case selfReferral
    case alreadyReferred
    case mutualReferral
    case networkError(Error)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .codeNotFound:
            return String(localized: "referral.error.codeNotFound")
        case .selfReferral:
            return String(localized: "referral.error.selfReferral")
        case .alreadyReferred:
            return String(localized: "referral.error.alreadyReferred")
        case .mutualReferral:
            return String(localized: "referral.error.mutualReferral")
        case .networkError(let error):
            return error.localizedDescription
        case .notAuthenticated:
            return String(localized: "referral.error.notAuthenticated")
        }
    }
}

/// 被推薦人記錄
struct ReferralRecord: Identifiable {
    let id: String // referee uid
    let displayName: String
    let status: ReferralStatus
    let createdAt: Date

    enum ReferralStatus: String {
        case invited = "invited"
        case completed = "completed"

        var label: String {
            switch self {
            case .invited: return String(localized: "referral.status.invited")
            case .completed: return String(localized: "referral.status.completed")
            }
        }
    }
}

/// 邀請碼管理器
@MainActor
class ReferralService: ObservableObject {

    // MARK: - Singleton

    static let shared = ReferralService()

    // MARK: - Published State

    @Published private(set) var referralCode: String?
    /// 所有輸入邀請碼的人數
    @Published private(set) var referralCount: Int = 0
    /// 成功邀請人數（新增包裹後）
    @Published private(set) var referralSuccessCount: Int = 0
    @Published private(set) var referralTrialEndDate: Date?
    /// 已綁定推薦人但尚未完成（等待新增第一筆包裹）
    @Published private(set) var pendingReferredBy: String?
    /// 是否已經使用過邀請碼（不論 pending 或已完成）
    @Published private(set) var hasBeenReferred = false
    /// 被推薦人列表
    @Published private(set) var referralRecords: [ReferralRecord] = []

    // MARK: - Computed

    /// 是否正在使用邀請試用期
    var isOnReferralTrial: Bool {
        guard let endDate = referralTrialEndDate else { return false }
        return endDate > Date()
    }

    /// 試用剩餘天數（nil 表示不在試用中）
    var daysRemaining: Int? {
        guard isOnReferralTrial, let endDate = referralTrialEndDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: endDate)
        return max(0, components.day ?? 0)
    }

    // MARK: - Constants

    /// 安全字元集（排除 0/O/1/I/L/S/5 避免混淆）
    private static let codeCharacters = Array("ABCDEFGHJKMNPQRTUVWXYZ2346789")
    private static let codeLength = 8
    private static let trialDays = 7

    // MARK: - Init

    private init() {
        // 從 UserDefaults 快取讀取（冷啟動立即可用）
        referralCode = UserDefaults.standard.string(forKey: "referralCode")
        referralCount = UserDefaults.standard.integer(forKey: "referralCount")
        referralSuccessCount = UserDefaults.standard.integer(forKey: "referralSuccessCount")
        pendingReferredBy = UserDefaults.standard.string(forKey: "pendingReferredBy")
        hasBeenReferred = UserDefaults.standard.bool(forKey: "hasBeenReferred")
        if let interval = UserDefaults.standard.object(forKey: "referralTrialEndDate") as? Double {
            referralTrialEndDate = Date(timeIntervalSince1970: interval)
        }
    }

    // MARK: - Public Methods

    /// 從 Firestore 載入邀請碼資料（app 啟動時呼叫）
    func loadReferralData() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()

        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            guard let data = doc.data() else { return }

            if let code = data["referralCode"] as? String {
                referralCode = code
                UserDefaults.standard.set(code, forKey: "referralCode")
            }

            if let count = data["referralCount"] as? Int {
                referralCount = count
                UserDefaults.standard.set(count, forKey: "referralCount")
            }

            if let successCount = data["referralSuccessCount"] as? Int {
                referralSuccessCount = successCount
                UserDefaults.standard.set(successCount, forKey: "referralSuccessCount")
            }

            if let timestamp = data["referralTrialEndDate"] as? Timestamp {
                let date = timestamp.dateValue()
                referralTrialEndDate = date
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "referralTrialEndDate")
            }

            // 有 referredBy → 已使用過邀請碼
            if let referredBy = data["referredBy"] as? String, !referredBy.isEmpty {
                hasBeenReferred = true
                UserDefaults.standard.set(true, forKey: "hasBeenReferred")

                if data["referralTrialEndDate"] == nil {
                    pendingReferredBy = referredBy
                    UserDefaults.standard.set(referredBy, forKey: "pendingReferredBy")
                } else {
                    pendingReferredBy = nil
                    UserDefaults.standard.removeObject(forKey: "pendingReferredBy")
                }
            } else {
                hasBeenReferred = false
                UserDefaults.standard.set(false, forKey: "hasBeenReferred")
                pendingReferredBy = nil
                UserDefaults.standard.removeObject(forKey: "pendingReferredBy")
            }

            // 載入被推薦人列表
            if let code = referralCode {
                await loadReferralRecords(code: code)
            }

            print("[Referral] Loaded data: code=\(referralCode ?? "nil"), count=\(referralCount), success=\(referralSuccessCount), pending=\(pendingReferredBy ?? "nil")")
        } catch {
            print("[Referral] Failed to load data: \(error.localizedDescription)")
        }
    }

    /// 載入被推薦人列表
    func loadReferralRecords(code: String) async {
        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection("referralCodes").document(code)
                .collection("referees").order(by: "createdAt", descending: true).getDocuments()

            referralRecords = snapshot.documents.compactMap { doc in
                let data = doc.data()
                let statusRaw = data["status"] as? String ?? "invited"
                let name = data["displayName"] as? String ?? ""
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                return ReferralRecord(
                    id: doc.documentID,
                    displayName: name,
                    status: ReferralRecord.ReferralStatus(rawValue: statusRaw) ?? .invited,
                    createdAt: createdAt
                )
            }
        } catch {
            print("[Referral] Failed to load referral records: \(error.localizedDescription)")
        }
    }

    /// 確保使用者有邀請碼（沒有則生成）
    @discardableResult
    func ensureReferralCode() async -> String? {
        if let code = referralCode { return code }

        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let db = Firestore.firestore()

        // 從 Firestore 讀取
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            if let existing = doc.data()?["referralCode"] as? String {
                referralCode = existing
                UserDefaults.standard.set(existing, forKey: "referralCode")
                return existing
            }
        } catch {
            print("[Referral] Failed to check existing code: \(error.localizedDescription)")
        }

        // 生成新碼（最多重試 3 次）
        for attempt in 1...3 {
            let candidate = generateCode()
            do {
                let codeRef = db.collection("referralCodes").document(candidate)
                let userRef = db.collection("users").document(uid)

                try await db.runTransaction { transaction, errorPointer in
                    let codeDoc: DocumentSnapshot
                    do {
                        codeDoc = try transaction.getDocument(codeRef)
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }

                    if codeDoc.exists {
                        errorPointer?.pointee = NSError(domain: "ReferralService", code: 409, userInfo: [NSLocalizedDescriptionKey: "Code collision"])
                        return nil
                    }

                    transaction.setData([
                        "ownerUid": uid,
                        "createdAt": FieldValue.serverTimestamp()
                    ], forDocument: codeRef)

                    transaction.updateData([
                        "referralCode": candidate,
                        "referralCount": 0,
                        "referralSuccessCount": 0,
                        "referralBonusDays": 0
                    ], forDocument: userRef)

                    return nil
                }

                referralCode = candidate
                UserDefaults.standard.set(candidate, forKey: "referralCode")
                print("[Referral] Generated code: \(candidate) (attempt \(attempt))")
                return candidate
            } catch {
                print("[Referral] Code generation attempt \(attempt) failed: \(error.localizedDescription)")
                continue
            }
        }

        print("[Referral] Failed to generate code after 3 attempts")
        return nil
    }

    /// 綁定邀請碼（記錄推薦關係 + referralCount +1）
    func applyReferralCode(_ code: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ReferralError.notAuthenticated
        }

        let db = Firestore.firestore()
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. 查詢碼是否存在
        let codeDoc = try await db.collection("referralCodes").document(normalizedCode).getDocument()
        guard let codeData = codeDoc.data(),
              let ownerUid = codeData["ownerUid"] as? String else {
            throw ReferralError.codeNotFound
        }

        // 2. 不能自我推薦
        if ownerUid == uid {
            throw ReferralError.selfReferral
        }

        // 3. 檢查是否已被推薦過
        let userDoc = try await db.collection("users").document(uid).getDocument()
        if let referredBy = userDoc.data()?["referredBy"] as? String, !referredBy.isEmpty {
            throw ReferralError.alreadyReferred
        }

        // 4. 防止互相推薦
        let ownerDoc = try await db.collection("users").document(ownerUid).getDocument()
        if let ownerReferredBy = ownerDoc.data()?["referredBy"] as? String, ownerReferredBy == uid {
            throw ReferralError.mutualReferral
        }

        // 5. 取得當前用戶名稱用於顯示（從 Firestore 讀 nickname）
        let userData = userDoc.data() ?? [:]
        let nickname = userData["nickname"] as? String ?? ""
        let email = Auth.auth().currentUser?.email ?? ""
        let displayName = nickname.isEmpty ? (email.isEmpty ? "User" : email) : nickname

        // 6. 取得推薦人目前的 referralCount
        let ownerData = ownerDoc.data() ?? [:]
        let currentCount = ownerData["referralCount"] as? Int ?? 0

        // 7. Batch write
        let batch = db.batch()

        // 被推薦人自己的 user doc
        let userRef = db.collection("users").document(uid)
        batch.updateData(["referredBy": ownerUid], forDocument: userRef)

        // 推薦人的 referralCount +1
        let ownerRef = db.collection("users").document(ownerUid)
        batch.updateData(["referralCount": currentCount + 1], forDocument: ownerRef)

        // 寫入 referees 子集合
        let refereeRef = db.collection("referralCodes").document(normalizedCode)
            .collection("referees").document(uid)
        batch.setData([
            "displayName": displayName,
            "status": "invited",
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: refereeRef)

        try await batch.commit()

        // 8. 更新本地狀態
        pendingReferredBy = ownerUid
        hasBeenReferred = true
        UserDefaults.standard.set(ownerUid, forKey: "pendingReferredBy")
        UserDefaults.standard.set(true, forKey: "hasBeenReferred")

        print("[Referral] Bound code \(normalizedCode) → referrer \(ownerUid), referralCount now \(currentCount + 1)")

        // 9. 如果已有包裹，直接完成邀請
        let packagesSnapshot = try await db.collection("users").document(uid)
            .collection("packages").limit(to: 1).getDocuments()
        if !packagesSnapshot.isEmpty {
            print("[Referral] User already has packages, completing referral immediately")
            await completeReferralIfNeeded()
        }
    }

    /// 成功新增包裹後呼叫：若有待完成的推薦，發放雙方 7 天 Pro 試用
    func completeReferralIfNeeded() async {
        guard let ownerUid = pendingReferredBy,
              let uid = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        let now = Date()
        let trialEnd = Calendar.current.date(byAdding: .day, value: Self.trialDays, to: now)!

        do {
            let ownerDoc = try await db.collection("users").document(ownerUid).getDocument()
            let ownerData = ownerDoc.data() ?? [:]
            let ownerCurrentEnd: Date
            if let ownerTimestamp = ownerData["referralTrialEndDate"] as? Timestamp {
                ownerCurrentEnd = ownerTimestamp.dateValue()
            } else {
                ownerCurrentEnd = now
            }
            let ownerBaseDate = max(ownerCurrentEnd, now)
            let ownerNewEnd = Calendar.current.date(byAdding: .day, value: Self.trialDays, to: ownerBaseDate)!
            let ownerCurrentBonus = ownerData["referralBonusDays"] as? Int ?? 0
            let ownerCurrentSuccess = ownerData["referralSuccessCount"] as? Int ?? 0

            // 找出推薦人的邀請碼（用來更新 referees 子集合狀態）
            let ownerCode = ownerData["referralCode"] as? String

            let batch = db.batch()

            // 被推薦人：發放 trial
            let userRef = db.collection("users").document(uid)
            batch.updateData([
                "referralTrialEndDate": Timestamp(date: trialEnd)
            ], forDocument: userRef)

            // 推薦人：+7 天 + successCount+1
            let ownerRef = db.collection("users").document(ownerUid)
            batch.updateData([
                "referralSuccessCount": ownerCurrentSuccess + 1,
                "referralBonusDays": ownerCurrentBonus + Self.trialDays,
                "referralTrialEndDate": Timestamp(date: ownerNewEnd)
            ], forDocument: ownerRef)

            // 更新 referees 子集合狀態為 completed
            if let ownerCode {
                let refereeRef = db.collection("referralCodes").document(ownerCode)
                    .collection("referees").document(uid)
                batch.updateData(["status": "completed"], forDocument: refereeRef)
            }

            try await batch.commit()

            // 更新本地狀態
            referralTrialEndDate = trialEnd
            UserDefaults.standard.set(trialEnd.timeIntervalSince1970, forKey: "referralTrialEndDate")
            pendingReferredBy = nil
            UserDefaults.standard.removeObject(forKey: "pendingReferredBy")

            // 同步 Widget 訂閱狀態（試用期視為 Pro）
            WidgetDataService.shared.updateSubscriptionTier(.pro)

            print("[Referral] ✅ Referral completed! Both get trial. Referee until \(trialEnd), referrer until \(ownerNewEnd)")
        } catch {
            print("[Referral] ❌ Failed to complete referral: \(error.localizedDescription)")
        }
    }

    /// 登出時清除本地快取
    func clearCache() {
        referralCode = nil
        referralCount = 0
        referralSuccessCount = 0
        referralTrialEndDate = nil
        pendingReferredBy = nil
        hasBeenReferred = false
        referralRecords = []
        UserDefaults.standard.removeObject(forKey: "referralCode")
        UserDefaults.standard.removeObject(forKey: "referralCount")
        UserDefaults.standard.removeObject(forKey: "referralSuccessCount")
        UserDefaults.standard.removeObject(forKey: "referralTrialEndDate")
        UserDefaults.standard.removeObject(forKey: "pendingReferredBy")
        UserDefaults.standard.removeObject(forKey: "hasBeenReferred")
        print("[Referral] Cache cleared on sign-out")
    }

    // MARK: - Private

    /// 生成隨機邀請碼
    private func generateCode() -> String {
        var result = ""
        for _ in 0..<Self.codeLength {
            let index = Int.random(in: 0..<Self.codeCharacters.count)
            result.append(Self.codeCharacters[index])
        }
        return result
    }
}
