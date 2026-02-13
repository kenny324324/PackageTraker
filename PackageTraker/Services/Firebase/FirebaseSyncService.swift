//
//  FirebaseSyncService.swift
//  PackageTraker
//
//  Firestore 雙向同步服務：上傳本地資料 + 即時下載雲端變更
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import SwiftData

@MainActor
final class FirebaseSyncService: ObservableObject {
    static let shared = FirebaseSyncService()

    private let db = Firestore.firestore()
    @Published var isSyncing = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0

    // MARK: - Listener State

    private var packagesListener: ListenerRegistration?
    private var isListening = false
    private weak var activeModelContext: ModelContext?

    // MARK: - Loop Prevention

    /// 記錄本機最近上傳的 packageId → 時間，防止 listener 回寫造成迴圈
    private var recentLocalWrites: [String: Date] = [:]
    private let localWriteEchoWindow: TimeInterval = 5.0

    private init() {}

    // MARK: - User ID

    private var userId: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - 單一包裹同步（fire-and-forget）

    func syncPackage(_ package: Package) {
        guard let userId else { return }

        // 標記本地寫入（防迴圈）
        markLocalWrite(package.id.uuidString)

        // 擷取資料（在 @MainActor 上安全讀取 SwiftData）
        let packageData = packageToFirestoreData(package)
        let packageDocId = package.id.uuidString
        let eventsData = package.events.map { event in
            (id: event.id.uuidString, data: eventToFirestoreData(event))
        }

        let currentEventIds = Set(eventsData.map { $0.id })

        Task {
            do {
                let packageRef = db.collection("users").document(userId)
                    .collection("packages").document(packageDocId)

                // 查詢 Firestore 現有 events，刪除不再存在的舊文件（修復歷史重複問題）
                let existingEvents = try await packageRef.collection("events").getDocuments()
                let staleIds = existingEvents.documents
                    .map { $0.documentID }
                    .filter { !currentEventIds.contains($0) }

                let batch = db.batch()
                batch.setData(packageData, forDocument: packageRef, merge: true)

                for event in eventsData {
                    let eventRef = packageRef.collection("events").document(event.id)
                    batch.setData(event.data, forDocument: eventRef)
                }

                // 刪除過時的 event 文件
                for staleId in staleIds {
                    let staleRef = packageRef.collection("events").document(staleId)
                    batch.deleteDocument(staleRef)
                }

                try await batch.commit()
                if !staleIds.isEmpty {
                    print("[Sync] 🧹 Cleaned up \(staleIds.count) stale event docs")
                }
                print("[Sync] ✅ Package synced: \(packageData["trackingNumber"] ?? "")")
            } catch {
                print("[Sync] ❌ Failed to sync package: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 軟刪除雲端包裹（標記 isDeleted，不真正刪除）

    func deletePackage(_ packageId: UUID) {
        guard let userId else { return }

        // 標記本地寫入（防迴圈）
        markLocalWrite(packageId.uuidString)

        let docId = packageId.uuidString

        Task {
            do {
                let packageRef = db.collection("users").document(userId)
                    .collection("packages").document(docId)

                try await packageRef.setData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp()
                ], merge: true)

                print("[Sync] ✅ Package soft-deleted: \(docId)")
            } catch {
                print("[Sync] ❌ Failed to soft-delete package: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 批次同步（首次登入用）

    func syncAllPackages(_ packages: [Package]) async {
        guard let userId else { return }
        guard !packages.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        print("[Sync] Starting bulk sync of \(packages.count) packages...")

        for package in packages {
            let packageData = packageToFirestoreData(package)
            let packageDocId = package.id.uuidString
            let eventsData = package.events.map { event in
                (id: event.id.uuidString, data: eventToFirestoreData(event))
            }

            do {
                let batch = db.batch()
                let packageRef = db.collection("users").document(userId)
                    .collection("packages").document(packageDocId)

                batch.setData(packageData, forDocument: packageRef, merge: true)

                for event in eventsData {
                    let eventRef = packageRef.collection("events").document(event.id)
                    batch.setData(event.data, forDocument: eventRef)
                }

                try await batch.commit()
            } catch {
                print("[Sync] ❌ Failed to sync \(packageData["trackingNumber"] ?? ""): \(error.localizedDescription)")
            }
        }

        print("[Sync] ✅ Bulk sync completed")
    }

    // MARK: - 一次性事件去重清理

    /// 清理本地 SwiftData 中重複的 events，並同步清理 Firestore
    /// 只執行一次（透過 UserDefaults flag 控制）
    func deduplicateEventsIfNeeded(in modelContext: ModelContext) async {
        let key = "hasDeduplicatedEvents_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let descriptor = FetchDescriptor<Package>()
        guard let allPackages = try? modelContext.fetch(descriptor) else { return }

        var totalCleaned = 0

        for package in allPackages {
            let originalCount = package.events.count
            var seen = Set<String>()
            var uniqueEvents: [TrackingEvent] = []

            // 按時間降序去重，保留最新的
            let sorted = package.events.sorted { $0.timestamp > $1.timestamp }
            for event in sorted {
                let dedupeKey = "\(Int(event.timestamp.timeIntervalSince1970))|\(event.eventDescription)"
                if seen.insert(dedupeKey).inserted {
                    // 重新計算確定性 ID
                    event.id = TrackingEvent.deterministicId(
                        trackingNumber: package.trackingNumber,
                        timestamp: event.timestamp,
                        description: event.eventDescription
                    )
                    uniqueEvents.append(event)
                } else {
                    event.package = nil
                }
            }

            if uniqueEvents.count < originalCount {
                package.events = uniqueEvents
                totalCleaned += (originalCount - uniqueEvents.count)

                // 同步清理 Firestore
                syncPackage(package)
            }
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: key)

        if totalCleaned > 0 {
            print("[Sync] 🧹 Deduplicated \(totalCleaned) duplicate events across all packages")
        }
    }

    // MARK: - 補傳遺漏的包裹

    /// 比對本地 vs Firestore，上傳缺少的包裹（每次冷啟動背景執行）
    func uploadMissingPackages(from modelContext: ModelContext) async {
        guard let userId else { return }

        // 取得所有本地包裹
        let descriptor = FetchDescriptor<Package>()
        guard let allPackages = try? modelContext.fetch(descriptor),
              !allPackages.isEmpty else { return }

        do {
            // 取得 Firestore 已有的包裹 ID（只讀 ID，不下載完整文件）
            let snapshot = try await db.collection("users").document(userId)
                .collection("packages").getDocuments()
            let remoteIds = Set(snapshot.documents.map { $0.documentID })

            // 找出本地有但 Firestore 沒有的
            let missing = allPackages.filter { !remoteIds.contains($0.id.uuidString) }

            if !missing.isEmpty {
                print("[Sync] Uploading \(missing.count) missing packages to Firestore...")
                await syncAllPackages(missing)
            }
        } catch {
            print("[Sync] ❌ Failed to check missing packages: \(error.localizedDescription)")
        }
    }

    // MARK: - 下載所有包裹（初始同步用）

    func downloadAllPackages(into modelContext: ModelContext) async -> Int {
        guard let userId else { return 0 }

        isDownloading = true
        downloadProgress = 0
        defer {
            isDownloading = false
            downloadProgress = 1.0
        }

        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("packages")
                .getDocuments()

            let total = snapshot.documents.count
            guard total > 0 else { return 0 }

            // 取得本地已有的包裹 ID
            let allLocalDescriptor = FetchDescriptor<Package>()
            let localPackages = (try? modelContext.fetch(allLocalDescriptor)) ?? []
            let localById = Dictionary(uniqueKeysWithValues: localPackages.map { ($0.id.uuidString, $0) })

            var count = 0

            for (index, doc) in snapshot.documents.enumerated() {
                let data = doc.data()
                let docId = doc.documentID

                // 跳過已軟刪除的
                if data["isDeleted"] as? Bool == true {
                    // 如果本地還存在，刪除它
                    if let localPkg = localById[docId] {
                        modelContext.delete(localPkg)
                        count += 1
                    }
                    downloadProgress = Double(index + 1) / Double(total)
                    continue
                }

                if let existing = localById[docId] {
                    // 本地已有 → 比較時間戳，remote 較新才更新
                    let remoteUpdated = (data["lastUpdated"] as? Timestamp)?.dateValue() ?? Date.distantPast
                    if remoteUpdated > existing.lastUpdated {
                        updateLocalPackage(existing, with: data)
                        await fetchAndApplyEvents(for: existing, packageDocId: docId)
                        count += 1
                    }
                } else {
                    // 本地不存在 → 新建
                    if let uuid = UUID(uuidString: docId) {
                        let newPackage = createLocalPackage(id: uuid, from: data, in: modelContext)
                        if let pkg = newPackage {
                            await fetchAndApplyEvents(for: pkg, packageDocId: docId)
                        }
                        count += 1
                    }
                }

                downloadProgress = Double(index + 1) / Double(total)
            }

            try? modelContext.save()
            print("[Sync] ✅ Download complete: \(count) packages synced")
            return count
        } catch {
            print("[Sync] ❌ Download failed: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - 用戶偏好設定同步

    /// 從 Firestore 下載用戶偏好設定到 UserDefaults
    func downloadUserPreferences() async {
        guard let userId else { return }

        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            guard let data = doc.data() else { return }

            // 訂閱層級 + 產品 ID（monthly/yearly/lifetime）
            if let tier = data["subscriptionTier"] as? String,
               let subTier = SubscriptionTier(rawValue: tier) {
                UserDefaults.standard.set(tier, forKey: "subscriptionTier")
                let productID = data["subscriptionProductID"] as? String
                if let productID {
                    UserDefaults.standard.set(productID, forKey: "subscriptionProductID")
                }
                await SubscriptionManager.shared.applyFirestoreTier(subTier, productID: productID)
            }

            // 通知設定：per-device，不跨裝置同步（各裝置獨立管理）

            // 使用者偏好（主題、刷新間隔、隱藏已送達）
            if let prefs = data["preferences"] as? [String: Any] {
                if let theme = prefs["selectedTheme"] as? String {
                    UserDefaults.standard.set(theme, forKey: "selectedTheme")
                }
                if let interval = prefs["refreshInterval"] as? String {
                    UserDefaults.standard.set(interval, forKey: "refreshInterval")
                }
                if let hide = prefs["hideDeliveredPackages"] as? Bool {
                    UserDefaults.standard.set(hide, forKey: "hideDeliveredPackages")
                }
            }

            print("[Sync] ✅ User preferences downloaded")
        } catch {
            print("[Sync] ❌ Failed to download preferences: \(error.localizedDescription)")
        }
    }

    /// 上傳偏好設定到 Firestore（fire-and-forget）
    func syncUserPreferences(theme: String? = nil, refreshInterval: String? = nil, hideDeliveredPackages: Bool? = nil) {
        guard let userId else { return }

        var prefs: [String: Any] = [:]
        if let theme { prefs["selectedTheme"] = theme }
        if let interval = refreshInterval { prefs["refreshInterval"] = interval }
        if let hide = hideDeliveredPackages { prefs["hideDeliveredPackages"] = hide }

        guard !prefs.isEmpty else { return }

        Task {
            try? await db.collection("users").document(userId).setData([
                "preferences": prefs
            ], merge: true)
        }
    }

    // MARK: - 即時監聽器

    func startListening(modelContext: ModelContext) {
        guard let userId else { return }
        guard !isListening else { return }

        activeModelContext = modelContext
        isListening = true

        let packagesRef = db.collection("users").document(userId)
            .collection("packages")

        packagesListener = packagesRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot else {
                if let error { print("[Sync] Listener error: \(error.localizedDescription)") }
                return
            }

            Task { @MainActor in
                self.handleSnapshot(snapshot)
            }
        }

        print("[Sync] 🎧 Listener started for user \(userId)")
    }

    func stopListening() {
        packagesListener?.remove()
        packagesListener = nil
        isListening = false
        activeModelContext = nil
        recentLocalWrites.removeAll()
        print("[Sync] 🎧 Listener stopped")
    }

    // MARK: - Snapshot 處理

    private func handleSnapshot(_ snapshot: QuerySnapshot) {
        guard let modelContext = activeModelContext else { return }

        for change in snapshot.documentChanges {
            let docId = change.document.documentID
            let data = change.document.data()

            // 迴圈防止：跳過自己剛上傳的
            if isRecentLocalWrite(docId) {
                continue
            }

            switch change.type {
            case .added, .modified:
                applyRemoteChange(docId: docId, data: data, to: modelContext)
            case .removed:
                removeLocalPackage(docId: docId, from: modelContext)
            }
        }

        try? modelContext.save()
    }

    private func applyRemoteChange(docId: String, data: [String: Any], to modelContext: ModelContext) {
        guard let packageId = UUID(uuidString: docId) else { return }

        // 處理軟刪除
        if data["isDeleted"] as? Bool == true {
            removeLocalPackage(docId: docId, from: modelContext)
            return
        }

        // 查找本地包裹
        let descriptor = FetchDescriptor<Package>(
            predicate: #Predicate<Package> { pkg in pkg.id == packageId }
        )
        let existingPackage = try? modelContext.fetch(descriptor).first

        if let existing = existingPackage {
            // 衝突處理：比較時間戳
            let remoteUpdated = (data["lastUpdated"] as? Timestamp)?.dateValue() ?? Date.distantPast
            let localUpdated = existing.lastUpdated

            let remoteStatus = data["status"] as? String ?? ""
            let statusProgressed = isStatusProgression(from: existing.statusRawValue, to: remoteStatus)

            if remoteUpdated > localUpdated || statusProgressed {
                updateLocalPackage(existing, with: data)
                // 狀態進階時也拉取最新 events
                if statusProgressed {
                    Task {
                        await fetchAndApplyEvents(for: existing, packageDocId: docId)
                        try? modelContext.save()
                    }
                }
            }
        } else {
            // 其他裝置新增的包裹 → 本地新建
            let newPackage = createLocalPackage(id: packageId, from: data, in: modelContext)
            if let pkg = newPackage {
                Task {
                    await fetchAndApplyEvents(for: pkg, packageDocId: docId)
                    try? modelContext.save()
                }
            }
        }
    }

    // MARK: - Firestore → SwiftData 轉換

    @discardableResult
    private func createLocalPackage(id: UUID, from data: [String: Any], in modelContext: ModelContext) -> Package? {
        guard let trackingNumber = data["trackingNumber"] as? String,
              let carrierRaw = data["carrier"] as? String else { return nil }

        let carrier = Carrier(rawValue: carrierRaw) ?? .other
        let status = TrackingStatus(rawValue: data["status"] as? String ?? "pending") ?? .pending
        let lastUpdated = (data["lastUpdated"] as? Timestamp)?.dateValue() ?? Date()
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()

        let package = Package(
            id: id,
            trackingNumber: trackingNumber,
            carrier: carrier,
            customName: data["customName"] as? String,
            pickupCode: data["pickupCode"] as? String,
            pickupLocation: data["pickupLocation"] as? String,
            status: status,
            lastUpdated: lastUpdated,
            createdAt: createdAt,
            isArchived: data["isArchived"] as? Bool ?? false,
            latestDescription: data["latestDescription"] as? String,
            storeName: data["storeName"] as? String,
            serviceType: data["serviceType"] as? String,
            pickupDeadline: data["pickupDeadline"] as? String,
            paymentMethod: (data["paymentMethod"] as? String).flatMap { PaymentMethod(rawValue: $0) },
            amount: data["amount"] as? Double,
            purchasePlatform: data["purchasePlatform"] as? String,
            notes: data["notes"] as? String,
            userPickupLocation: data["userPickupLocation"] as? String
        )
        package.trackTwRelationId = data["trackTwRelationId"] as? String

        modelContext.insert(package)
        return package
    }

    private func updateLocalPackage(_ package: Package, with data: [String: Any]) {
        if let v = data["status"] as? String { package.statusRawValue = v }
        if let v = data["lastUpdated"] as? Timestamp { package.lastUpdated = v.dateValue() }
        if let v = data["isArchived"] as? Bool { package.isArchived = v }
        if let v = data["latestDescription"] as? String { package.latestDescription = v }
        if let v = data["customName"] as? String { package.customName = v }
        if let v = data["pickupCode"] as? String { package.pickupCode = v }
        if let v = data["pickupLocation"] as? String { package.pickupLocation = v }
        if let v = data["userPickupLocation"] as? String { package.userPickupLocation = v }
        if let v = data["storeName"] as? String { package.storeName = v }
        if let v = data["serviceType"] as? String { package.serviceType = v }
        if let v = data["pickupDeadline"] as? String { package.pickupDeadline = v }
        if let v = data["paymentMethod"] as? String { package.paymentMethodRawValue = v }
        if let v = data["amount"] as? Double { package.amount = v }
        if let v = data["purchasePlatform"] as? String { package.purchasePlatform = v }
        if let v = data["notes"] as? String { package.notes = v }
        if let v = data["trackTwRelationId"] as? String { package.trackTwRelationId = v }
    }

    private func removeLocalPackage(docId: String, from modelContext: ModelContext) {
        guard let packageId = UUID(uuidString: docId) else { return }
        let descriptor = FetchDescriptor<Package>(
            predicate: #Predicate<Package> { pkg in pkg.id == packageId }
        )
        if let package = try? modelContext.fetch(descriptor).first {
            modelContext.delete(package)
        }
    }

    // MARK: - Events Subcollection 下載

    private func fetchAndApplyEvents(for package: Package, packageDocId: String) async {
        guard let userId else { return }

        do {
            let eventsSnapshot = try await db.collection("users").document(userId)
                .collection("packages").document(packageDocId)
                .collection("events")
                .order(by: "timestamp", descending: true)
                .getDocuments()

            // 清除現有 events → 重新寫入（含去重）
            for event in package.events {
                event.package = nil
            }
            package.events.removeAll()

            var seenKeys = Set<String>()
            for doc in eventsSnapshot.documents {
                let data = doc.data()
                guard let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                      let statusRaw = data["status"] as? String,
                      let description = data["description"] as? String else { continue }

                // 依 timestamp + description 去重（防止歷史重複文件）
                let dedupeKey = "\(Int(timestamp.timeIntervalSince1970))|\(description)"
                guard !seenKeys.contains(dedupeKey) else { continue }
                seenKeys.insert(dedupeKey)

                let eventId = UUID(uuidString: doc.documentID) ?? UUID()
                let event = TrackingEvent(
                    id: eventId,
                    timestamp: timestamp,
                    status: TrackingStatus(rawValue: statusRaw) ?? .pending,
                    description: description,
                    location: data["location"] as? String
                )
                event.package = package
                package.events.append(event)
            }
        } catch {
            print("[Sync] ❌ Failed to fetch events for \(packageDocId): \(error.localizedDescription)")
        }
    }

    // MARK: - 迴圈防止

    private func markLocalWrite(_ packageId: String) {
        recentLocalWrites[packageId] = Date()
        // 清理過期項目
        let cutoff = Date().addingTimeInterval(-10)
        recentLocalWrites = recentLocalWrites.filter { $0.value > cutoff }
    }

    private func isRecentLocalWrite(_ packageId: String) -> Bool {
        guard let writeTime = recentLocalWrites[packageId] else { return false }
        return Date().timeIntervalSince(writeTime) < localWriteEchoWindow
    }

    // MARK: - 狀態進階判斷

    private func isStatusProgression(from localStatus: String, to remoteStatus: String) -> Bool {
        let priority: [String: Int] = [
            "pending": 0, "shipped": 1, "inTransit": 2,
            "arrivedAtStore": 3, "delivered": 4, "returned": 4
        ]
        guard let localP = priority[localStatus], let remoteP = priority[remoteStatus] else {
            return false
        }
        return remoteP > localP
    }

    // MARK: - Data Conversion (Upload)

    private func packageToFirestoreData(_ package: Package) -> [String: Any] {
        var data: [String: Any] = [
            "trackingNumber": package.trackingNumber,
            "carrier": package.carrierRawValue,
            "status": package.statusRawValue,
            "lastUpdated": Timestamp(date: package.lastUpdated),
            "createdAt": Timestamp(date: package.createdAt),
            "isArchived": package.isArchived
        ]

        if let v = package.trackTwRelationId { data["trackTwRelationId"] = v }
        if let v = package.customName { data["customName"] = v }
        if let v = package.pickupCode { data["pickupCode"] = v }
        if let v = package.pickupLocation { data["pickupLocation"] = v }
        if let v = package.userPickupLocation { data["userPickupLocation"] = v }
        if let v = package.storeName { data["storeName"] = v }
        if let v = package.latestDescription { data["latestDescription"] = v }
        if let v = package.serviceType { data["serviceType"] = v }
        if let v = package.pickupDeadline { data["pickupDeadline"] = v }
        if let v = package.paymentMethodRawValue { data["paymentMethod"] = v }
        if let v = package.amount { data["amount"] = v }
        if let v = package.purchasePlatform { data["purchasePlatform"] = v }
        if let v = package.notes { data["notes"] = v }

        return data
    }

    private func eventToFirestoreData(_ event: TrackingEvent) -> [String: Any] {
        var data: [String: Any] = [
            "timestamp": Timestamp(date: event.timestamp),
            "status": event.statusRawValue,
            "description": event.eventDescription
        ]
        if let v = event.location { data["location"] = v }
        return data
    }
}
