//
//  SubscriptionManager.swift
//  PackageTraker
//
//  StoreKit 2 subscription management service
//

import Foundation
import Combine
import StoreKit
import FirebaseAuth
import FirebaseFirestore

/// Type alias to disambiguate StoreKit.Transaction from Firestore.Transaction
private typealias StoreTransaction = StoreKit.Transaction

/// 訂閱管理器 — StoreKit 2
@MainActor
class SubscriptionManager: ObservableObject {

    // MARK: - Singleton

    static let shared = SubscriptionManager()

    // MARK: - Published State

    /// 當前訂閱層級
    @Published private(set) var currentTier: SubscriptionTier = .free

    /// 當前訂閱產品 ID（用於顯示 Monthly/Yearly）
    @Published private(set) var currentProductID: String?

    /// StoreKit 產品（月費 / 年費）
    @Published private(set) var products: [Product] = []

    /// 購買中
    @Published private(set) var isPurchasing = false

    /// 錯誤訊息
    @Published var errorMessage: String?

    // MARK: - Computed

    var isPro: Bool { currentTier == .pro }
    var maxPackageCount: Int { isPro ? .max : 5 }
    var hasAIAccess: Bool { isPro }
    var hasAllThemes: Bool { isPro }

    /// 訂閱名稱（顯示用）
    var subscriptionName: String {
        if !isPro {
            return String(localized: "settings.subscription.free")
        }

        if let productID = currentProductID {
            if productID == SubscriptionProductID.monthly.rawValue {
                return "Pro Monthly"
            } else if productID == SubscriptionProductID.yearly.rawValue {
                return "Pro Yearly"
            } else if productID == SubscriptionProductID.lifetime.rawValue {
                return "Pro Lifetime"
            }
        }

        // 舊用戶或未知產品，顯示通用 Pro
        return String(localized: "settings.subscription.pro")
    }

    /// 月費產品
    var monthlyProduct: Product? {
        products.first { $0.id == SubscriptionProductID.monthly.rawValue }
    }

    /// 年費產品
    var yearlyProduct: Product? {
        products.first { $0.id == SubscriptionProductID.yearly.rawValue }
    }

    /// 買斷產品
    var lifetimeProduct: Product? {
        products.first { $0.id == SubscriptionProductID.lifetime.rawValue }
    }

    // MARK: - Private

    private var transactionListener: Task<Void, Never>?

    // MARK: - Init

    private init() {
        // 讀取本地快取
        if let cached = UserDefaults.standard.string(forKey: "subscriptionTier"),
           let tier = SubscriptionTier(rawValue: cached) {
            currentTier = tier
        }

        // 讀取產品 ID 快取
        currentProductID = UserDefaults.standard.string(forKey: "subscriptionProductID")

        // 啟動交易監聽
        transactionListener = listenForTransactions()

        // 載入產品 + 驗證權益
        Task {
            await loadProducts()
            await checkEntitlements()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Public Methods

    /// 載入 StoreKit 產品
    func loadProducts() async {
        do {
            let ids = SubscriptionProductID.allCases.map(\.rawValue)
            print("[Subscription] Requesting products: \(ids)")
            let storeProducts = try await Product.products(for: Set(ids))
            // 月費排前面
            products = storeProducts.sorted { $0.price < $1.price }
            print("[Subscription] ✅ Loaded \(products.count) products:")
            for product in products {
                print("  - \(product.id): \(product.displayPrice)")
            }
        } catch {
            print("[Subscription] ❌ Failed to load products: \(error.localizedDescription)")
        }
    }

    /// 購買產品
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateTier(from: transaction)
                await transaction.finish()
                print("[Subscription] Purchase successful: \(transaction.productID)")
                return true

            case .userCancelled:
                return false

            case .pending:
                return false

            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 恢復購買
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 驗證當前權益
    func checkEntitlements() async {
        var hasPro = false
        var productID: String?

        for await result in StoreTransaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if SubscriptionProductID.allCases.map(\.rawValue).contains(transaction.productID) {
                    hasPro = true
                    productID = transaction.productID
                }
            }
        }

        let newTier: SubscriptionTier = hasPro ? .pro : .free
        if currentTier != newTier || currentProductID != productID {
            currentTier = newTier
            currentProductID = productID
            persistTier(newTier)
            persistProductID(productID)
            syncToFirestore(newTier)
        }
    }

    /// 從 Firestore 下載的層級（作為 StoreKit 驗證前的初始值）
    func applyFirestoreTier(_ tier: SubscriptionTier) {
        if currentTier != tier {
            currentTier = tier
            persistTier(tier)
        }
    }

    // MARK: - Debug Methods

    #if DEBUG
    /// 開發測試用：直接設定訂閱層級（跳過 StoreKit）
    func debugSetTier(_ tier: SubscriptionTier, productID: String? = nil) {
        currentTier = tier
        currentProductID = productID
        persistTier(tier)
        persistProductID(productID)
        syncToFirestore(tier)
        print("[Subscription] Debug set tier: \(tier.rawValue), productID: \(productID ?? "nil")")
    }
    #endif

    /// 模擬購買成功（在 StoreKit 產品尚未設定時使用）
    func mockPurchase(productID: String = SubscriptionProductID.yearly.rawValue) {
        currentTier = .pro
        currentProductID = productID
        persistTier(.pro)
        persistProductID(productID)
        syncToFirestore(.pro)
        print("[Subscription] Mock purchase succeeded: \(productID)")
    }

    // MARK: - Private Methods

    /// 監聽交易更新（續訂、過期、撤銷）
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in StoreTransaction.updates {
                if case .verified(let transaction) = result {
                    await self?.updateTier(from: transaction)
                    await transaction.finish()
                }
            }
        }
    }

    /// 驗證交易
    private func checkVerified(_ result: VerificationResult<StoreTransaction>) throws -> StoreTransaction {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }

    /// 根據交易更新層級
    private func updateTier(from transaction: StoreTransaction) async {
        let productIds = SubscriptionProductID.allCases.map(\.rawValue)

        if productIds.contains(transaction.productID) {
            if transaction.revocationDate != nil {
                // 已撤銷
                setTier(.free, productID: nil)
            } else if transaction.expirationDate != nil,
                      transaction.expirationDate! < Date() {
                // 已過期
                setTier(.free, productID: nil)
            } else {
                setTier(.pro, productID: transaction.productID)
            }
        }
    }

    private func setTier(_ tier: SubscriptionTier, productID: String?) {
        guard currentTier != tier || currentProductID != productID else { return }
        currentTier = tier
        currentProductID = productID
        persistTier(tier)
        persistProductID(productID)
        syncToFirestore(tier)
    }

    /// 本地快取
    private func persistTier(_ tier: SubscriptionTier) {
        UserDefaults.standard.set(tier.rawValue, forKey: "subscriptionTier")
    }

    /// 本地快取產品 ID
    private func persistProductID(_ productID: String?) {
        if let productID {
            UserDefaults.standard.set(productID, forKey: "subscriptionProductID")
        } else {
            UserDefaults.standard.removeObject(forKey: "subscriptionProductID")
        }
    }

    /// 同步到 Firestore（fire-and-forget）
    private func syncToFirestore(_ tier: SubscriptionTier) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        Task {
            do {
                try await db.collection("users").document(uid).setData([
                    "subscriptionTier": tier.rawValue
                ], merge: true)
                print("[Subscription] Synced tier to Firestore: \(tier.rawValue)")
            } catch {
                print("[Subscription] Failed to sync tier: \(error.localizedDescription)")
            }
        }
    }
}
