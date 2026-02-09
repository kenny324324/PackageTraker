//
//  FirebaseSyncService.swift
//  PackageTraker
//
//  Firestore 上傳同步服務：將本地 SwiftData 包裹資料同步到雲端
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

    private init() {}

    // MARK: - User ID

    private var userId: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - 單一包裹同步（fire-and-forget）

    func syncPackage(_ package: Package) {
        guard let userId else { return }

        // 擷取資料（在 @MainActor 上安全讀取 SwiftData）
        let packageData = packageToFirestoreData(package)
        let packageDocId = package.id.uuidString
        let eventsData = package.events.map { event in
            (id: event.id.uuidString, data: eventToFirestoreData(event))
        }

        Task {
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
                print("[Sync] ✅ Package synced: \(packageData["trackingNumber"] ?? "")")
            } catch {
                print("[Sync] ❌ Failed to sync package: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 軟刪除雲端包裹（標記 isDeleted，不真正刪除）

    func deletePackage(_ packageId: UUID) {
        guard let userId else { return }

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

    // MARK: - Data Conversion

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
