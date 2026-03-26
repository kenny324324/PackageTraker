//
//  AppStatsService.swift
//  PackageTraker
//
//  從 Firestore /stats/app 讀取 App 整體統計數據
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class AppStatsService: ObservableObject {
    static let shared = AppStatsService()
    private init() {}

    @Published var totalUsers: Int = 0
    @Published var totalPackages: Int = 0
    @Published var totalDelivered: Int = 0
    @Published var isLoaded: Bool = false

    // 增量（與上次快取相比的差異）
    @Published var diffUsers: Int = 0
    @Published var diffPackages: Int = 0
    @Published var diffDelivered: Int = 0

    // UserDefaults 快取 key
    private let cacheKeyUsers = "appStats.totalUsers"
    private let cacheKeyPackages = "appStats.totalPackages"
    private let cacheKeyDelivered = "appStats.totalDelivered"

    /// 從 Firestore 讀取統計數據，失敗時使用快取
    func fetchStats() async {
        // 先載入快取（避免空白閃爍）
        loadCache()
        let previousUsers = totalUsers
        let previousPackages = totalPackages
        let previousDelivered = totalDelivered

        do {
            print("[AppStats] Fetching /stats/app...")
            let doc = try await Firestore.firestore()
                .collection("stats").document("app").getDocument()

            guard let data = doc.data() else {
                print("[AppStats] Document not found or empty")
                if totalUsers > 0 || totalPackages > 0 {
                    isLoaded = true
                }
                return
            }

            totalUsers = data["totalUsers"] as? Int ?? 0
            totalPackages = data["totalPackages"] as? Int ?? 0
            totalDelivered = data["totalDelivered"] as? Int ?? 0
            isLoaded = true

            // 計算增量（只顯示正增長）
            if previousUsers > 0 || previousPackages > 0 {
                diffUsers = max(0, totalUsers - previousUsers)
                diffPackages = max(0, totalPackages - previousPackages)
                diffDelivered = max(0, totalDelivered - previousDelivered)
            }

            print("[AppStats] ✅ Loaded: \(totalUsers) users, \(totalPackages) packages, \(totalDelivered) delivered")

            // 更新快取
            saveCache()
        } catch {
            print("[AppStats] ❌ Failed: \(error.localizedDescription)")
            // 離線或失敗時使用快取值
            if totalUsers > 0 || totalPackages > 0 {
                isLoaded = true
            }
        }
    }

    private func loadCache() {
        let defaults = UserDefaults.standard
        totalUsers = defaults.integer(forKey: cacheKeyUsers)
        totalPackages = defaults.integer(forKey: cacheKeyPackages)
        totalDelivered = defaults.integer(forKey: cacheKeyDelivered)
    }

    private func saveCache() {
        let defaults = UserDefaults.standard
        defaults.set(totalUsers, forKey: cacheKeyUsers)
        defaults.set(totalPackages, forKey: cacheKeyPackages)
        defaults.set(totalDelivered, forKey: cacheKeyDelivered)
    }
}
