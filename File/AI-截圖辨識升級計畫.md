# PackageTraker AI 截圖辨識升級計畫

## 專案概述

將現有的基礎 OCR 截圖辨識功能升級為 AI 智能辨識,提供更準確、更全面的物流資訊提取能力,並作為訂閱制收費功能。

### 現有功能限制

- 使用 Apple Vision Framework OCR,基於正則表達式匹配物流單號
- 只能識別追蹤號碼,無法提取其他資訊(包裹名稱、取件地址、預估送達時間等)
- 對新格式或複雜截圖效果不佳
- 依賴硬編碼規則,維護成本高

### 升級目標

- 使用 AI 視覺模型智能理解截圖內容
- 提取更多資訊:追蹤號碼、物流商、取件地址、包裹名稱、預估送達時間、取件碼等
- 不依賴規則,適應各種截圖格式
- 建立訂閱制商業模式

---

## 技術方案

### AI API 選型: Google Gemini 2.0 Flash

**選擇理由:**
- **成本最低**: 每次辨識僅 NT$0.07 (vs Claude Sonnet NT$2.40,便宜 34 倍)
- **免費額度**: 每天 100 次免費,無需信用卡
- **官方 API**: Google 官方支援,穩定可靠
- **中文支援**: 繁體、簡體中文識別準確度高
- **速度快**: 回應時間 1-3 秒
- **簡單整合**: Google AI SDK for Swift

**成本分析:**
- Gemini 2.0 Flash 定價: $0.10/M input tokens, $0.40/M output tokens
- 每張圖片消耗: ~258 tokens (圖片) + 500 tokens (prompt) = 758 input + 200 output
- 單次成本: (758 × $0.10 + 200 × $0.40) / 1,000,000 = $0.000156 ≈ NT$0.005
- 訂閱制用戶平均每月 50 次使用 → API 成本 NT$0.25
- 月費 NT$49 → 毛利率 **99.5%**

**免費額度:**
- 5 RPM (requests per minute)
- 250,000 TPM (tokens per minute)
- 100 requests per day
- 無需信用卡,立即可用

**API 實作方式:**
- 使用 Google Generative AI SDK for Swift
- 圖片轉 base64 後透過 Messages API 傳送
- 後端可選: 直接從 iOS 調用(API Key 加密存儲) 或 中繼伺服器(更安全)

---

## 功能整合策略: 共存模式

保留現有基礎 OCR(免費) + 新增 AI 智能辨識(訂閱制)

### UI 設計

在 `AddPackageView` 提供兩種辨識方式:

#### 方案: 獨立推廣卡片 (已選定)

在追蹤號碼輸入框和物流商選擇之間,插入一個醒目的 **AI 功能推廣卡片**:

```
┌────────────────────────────────────────┐
│  追蹤號碼                [截圖辨識]    │  ← 保留原有 OCR
│  ┌──────────────────────────────────┐ │
│  │  TW123456789H__________________  │ │
│  └──────────────────────────────────┘ │
└────────────────────────────────────────┘

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓  ← AI 推廣卡片(新增)
┃  ✨ 試試 AI 智能辨識                  ┃
┃                                        ┃
┃  ✓ 自動識別 6+ 個欄位                ┃
┃  ✓ 3 秒極速分析                      ┃
┃  ✓ 準確度 90%+                       ┃
┃                                        ┃
┃  ┌────────────────────────────────┐  ┃
┃  │    立即體驗 AI 辨識 👑          │  ┃  ← CTA 按鈕
┃  └────────────────────────────────┘  ┃
┃                                        ┃
┃  訂閱會員專享 • NT$49/月              ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

┌────────────────────────────────────────┐
│  選擇物流商              [便利商店 ▼] │
│  ...                                   │
└────────────────────────────────────────┘
```

**基礎 OCR (免費)** - 右上角小按鈕
- 現有功能,無限次使用
- 只識別追蹤號碼和物流商
- 基於規則匹配

**AI 智能辨識 (訂閱制)** - 獨立推廣卡片
- 提取 6+ 個欄位資訊
- 適應各種截圖格式
- 訂閱會員專享
- 非會員顯示付費牆引導訂閱
- **視覺明顯** - 漸變背景、大按鈕、功能列表

### 付費牆設計

非訂閱用戶點擊「AI 智能辨識」時:

```
┌─────────────────────────────────┐
│  🤖 AI 智能辨識                  │
├─────────────────────────────────┤
│  自動識別:                       │
│  ✓ 追蹤號碼                     │
│  ✓ 物流商                       │
│  ✓ 取件地址/門市                │
│  ✓ 包裹名稱                     │
│  ✓ 預估送達時間                 │
│  ✓ 取件碼                       │
│                                  │
│  節省時間,準確度更高!            │
│                                  │
│  【開始訂閱 NT$49/月】           │
│  【查看更多方案】                │
└─────────────────────────────────┘
```

---

## AI 功能設計

### 識別資訊優先級

#### 第一優先級 (Phase 1 MVP)
1. **追蹤號碼** (Tracking Number) - 必須
2. **物流商** (Carrier) - 必須
3. **取件地址** (Pickup Location) - 便利商店門市、物流中心地址

#### 第二優先級 (Phase 2)
4. **包裹名稱** (Package Name) - 商品描述
5. **預估送達時間** (Estimated Delivery) - ISO 8601 格式
6. **取件碼** (Pickup Code) - 例如 6-5-29-14

#### 第三優先級 (未來)
7. 收件人姓名
8. 訂單金額
9. 購買平台(蝦皮、PChome、momo)

### AI Prompt 設計

```swift
let systemPrompt = """
你是台灣物流截圖辨識專家。請從圖片中提取以下資訊,以 JSON 格式回傳:

{
  "trackingNumber": "物流單號(字串)",
  "carrier": "物流商(7-11|全家|黑貓|蝦皮|順豐|郵局等)",
  "pickupLocation": "取貨地點(門市名稱或完整地址)",
  "pickupCode": "取件碼(若有,格式如 6-5-29-14)",
  "packageName": "包裹名稱或商品描述",
  "estimatedDelivery": "預估送達時間(YYYY-MM-DD 格式)",
  "confidence": {
    "trackingNumber": 0.95,
    "carrier": 0.90,
    "pickupLocation": 0.85
  }
}

規則:
1. 若無法辨識某欄位,設為 null
2. confidence 表示辨識信心度(0.0-1.0)
3. carrier 必須對應台灣常見物流商
4. 日期統一用 YYYY-MM-DD 格式
5. 取件碼通常是便利商店的數字代碼
6. 包裹名稱應從商品描述或訂單資訊中提取
"""
```

### 結果展示 UI (AIVisionResultSheet)

```
┌─────────────────────────────────┐
│  🤖 AI 識別結果                  │
├─────────────────────────────────┤
│  ✓ 追蹤號碼: TW123456789H (95%) │
│  ✓ 物流商: 蝦皮店到店 (98%)     │
│  ✓ 取貨地點: 7-11景安門市 (90%) │
│  ✓ 取件碼: 6-5-29-14 (92%)      │
│  ⚠ 包裹名稱: 藍牙耳機 (70%)     │
│  - 預估送達: 未識別              │
├─────────────────────────────────┤
│  【確認並填入】  【重新掃描】    │
└─────────────────────────────────┘
```

**信心度指示:**
- ≥ 90%: 綠色勾選 ✓ (自動填入)
- 70-89%: 黃色警告 ⚠ (建議檢查)
- < 70%: 灰色未識別 - (不填入)

**可編輯:**
- 所有欄位可點擊修改
- 低信心度欄位預設展開編輯狀態

---

## 商業模式: 訂閱制

### 定價方案

#### Tier 1: 免費用戶
- 無限基礎 OCR 截圖辨識
- 無限包裹追蹤
- ❌ 無 AI 智能辨識

#### Tier 2: 月訂閱 (主推)
- **NT$49/月**
- 無限 AI 智能辨識
- 所有基礎功能
- 未來進階功能優先體驗

#### Tier 3: 年訂閱 (優惠)
- **NT$399/年** (相當於 NT$33/月,省 33%)
- 無限 AI 智能辨識
- 所有基礎功能
- 未來進階功能優先體驗

### 商業模式優勢

**為什麼選擇訂閱制?**
1. **穩定收入**: 可預測的月經常性收入(MRR)
2. **用戶粘性**: 訂閱用戶留存率更高
3. **成本可控**: API 成本極低(NT$0.005/次),利潤率 99%+
4. **心理門檻低**: NT$49/月 = 一杯咖啡,易接受
5. **擴展空間**: 未來可加入更多訂閱權益(批量匯入、數據分析等)

**vs 次數包方案:**
- 次數包需要頻繁購買,用戶體驗差
- 訂閱制更符合 App Store 生態
- 蘋果分潤: 首年 30%,次年起 15%

### 利潤分析

**假設場景: 1000 位訂閱用戶**

**收入:**
- 月訂閱: 800 人 × NT$49 = NT$39,200
- 年訂閱: 200 人 × NT$399 / 12 = NT$6,650
- 總月收入: NT$45,850
- 扣除蘋果分潤 (30%): NT$32,095

**成本:**
- 平均每用戶每月 50 次 AI 辨識
- 1000 用戶 × 50 次 × NT$0.005 = NT$250
- 後端伺服器(選): NT$0-500/月
- 總成本: NT$250-750/月

**淨利潤: NT$31,345-31,845/月**
**利潤率: 97-99%**

---

## 技術架構

### 新增服務層

#### 1. AIVisionService.swift

**位置**: `PackageTraker/Services/AIVision/AIVisionService.swift`

**職責:**
- 與 Gemini API 通訊
- 圖片壓縮和 base64 編碼
- API 請求構建和執行
- 回應解析和錯誤處理

**核心方法:**
```swift
final class AIVisionService {
    static let shared = AIVisionService()

    /// 分析物流截圖
    func analyzePackageImage(_ image: UIImage) async throws -> AIVisionResult

    /// 壓縮圖片 (最大 500KB)
    private func compressImage(_ image: UIImage, maxSizeKB: Int) -> Data?

    /// 構建 Gemini API 請求
    private func makeGeminiRequest(imageBase64: String) throws -> URLRequest

    /// 執行 API 調用
    private func execute(_ request: URLRequest) async throws -> Data

    /// 解析回應 JSON
    private func parseResponse(_ data: Data) throws -> AIVisionResult
}
```

#### 2. AIVisionModels.swift

**位置**: `PackageTraker/Services/AIVision/AIVisionModels.swift`

**資料結構:**
```swift
struct AIVisionResult: Codable {
    let trackingNumber: String?
    let carrier: String?
    let pickupLocation: String?
    let pickupCode: String?
    let packageName: String?
    let estimatedDelivery: String?  // ISO 8601
    let confidence: ConfidenceScores

    struct ConfidenceScores: Codable {
        let trackingNumber: Float
        let carrier: Float
        let pickupLocation: Float
    }

    /// 轉換為 App 的 Carrier 枚舉
    var detectedCarrier: Carrier? {
        // 模糊匹配物流商名稱
    }
}

enum AIVisionError: LocalizedError {
    case imageProcessingFailed
    case networkError(Error)
    case apiError(String)
    case parsingError
    case insufficientCredits
    case subscriptionRequired
}
```

#### 3. SubscriptionManager.swift

**位置**: `PackageTraker/Services/Subscription/SubscriptionManager.swift`

**職責:**
- 訂閱狀態管理 (StoreKit 2)
- AI 辨識權限檢查
- 購買流程處理
- Receipt 驗證

**核心方法:**
```swift
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published var hasActiveSubscription: Bool = false
    @Published var subscriptionType: SubscriptionType?

    enum SubscriptionType: String {
        case monthly = "com.packagetraker.premium.monthly"
        case yearly = "com.packagetraker.premium.yearly"
    }

    /// 檢查是否有 AI 辨識權限
    var hasAIAccess: Bool { hasActiveSubscription }

    /// 購買訂閱
    func purchase(_ type: SubscriptionType) async throws

    /// 恢復購買
    func restorePurchases() async throws

    /// 取消訂閱
    func cancelSubscription() async throws

    /// 監聽訂閱狀態變化
    func observeTransactionUpdates()
}
```

### UI 層

#### 1. AddPackageView.swift (修改)

**變更:**
- 新增「AI 功能推廣卡片」在輸入框和物流商選擇之間
- 檢查訂閱狀態
- 顯示付費牆(非訂閱用戶)

**修改位置**:
- 狀態變數: 第 16-23 行後
- 主 body: 第 28-33 行
- 新 computed property: 第 144 行後

```swift
// 新增狀態 (第 16-23 行後)
@State private var showAIVisionPicker = false
@State private var showPaywall = false
@State private var isProcessingAI = false
@State private var aiVisionResult: AIVisionResult?
@State private var showAIResultSheet = false
@StateObject private var subscriptionManager = SubscriptionManager.shared

// 修改主 body (第 28-33 行)
ScrollView {
    VStack(alignment: .leading, spacing: 24) {
        trackingNumberSection          // 現有

        aiFeaturePromotionCard        // 👈 新增卡片

        carrierSelectionSection        // 現有
    }
    .padding()
}

// 新增 computed property (第 144 行後)
private var aiFeaturePromotionCard: some View {
    VStack(alignment: .leading, spacing: 16) {
        // 標題
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.yellow)

            Text("試試 AI 智能辨識")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            if !subscriptionManager.hasAIAccess {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.yellow)
            }
        }

        // 功能列表
        VStack(alignment: .leading, spacing: 8) {
            featureRow(icon: "checkmark.circle.fill", text: "自動識別 6+ 個欄位")
            featureRow(icon: "bolt.fill", text: "3 秒極速分析")
            featureRow(icon: "chart.line.uptrend.xyaxis", text: "準確度 90%+")
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.9))

        // 主要 CTA 按鈕
        Button {
            if subscriptionManager.hasAIAccess {
                showAIVisionPicker = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                Text(subscriptionManager.hasAIAccess ? "立即體驗 AI 辨識" : "立即訂閱解鎖")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white)
            .foregroundStyle(Color.appAccent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        // 底部說明
        HStack(spacing: 4) {
            if !subscriptionManager.hasAIAccess {
                Text("訂閱會員專享")
                Text("•")
                Text("NT$49/月")
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("會員專屬功能")
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.7))
    }
    .padding(20)
    .background(
        LinearGradient(
            colors: [Color.appAccent, Color.appAccent.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
}

// 輔助方法
private func featureRow(icon: String, text: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: icon)
            .font(.caption)
        Text(text)
    }
}
```

**視覺設計重點:**
| 元素 | 設計細節 |
|------|---------|
| **背景** | 漸變色(appAccent → appAccent.opacity(0.8)) |
| **圓角** | 16pt (比一般卡片更圓潤) |
| **陰影** | 黑色 20% 透明度,模糊 10pt |
| **內距** | 20pt (較大的內距,更有空間感) |
| **主按鈕** | 白色背景 + appAccent 文字,形成強烈對比 |
| **尺寸** | 寬度 100%,高度約 180-200pt |

**為什麼這個設計更明顯?**
1. ✅ **視覺層級最高** - 漸變背景 + 陰影效果,自然吸引目光
2. ✅ **位置黃金** - 在輸入框和選擇器之間,用戶必經之路
3. ✅ **尺寸更大** - 占據整個寬度,無法忽視
4. ✅ **內容豐富** - 功能說明 + 價值傳遞 + 行動召喚
5. ✅ **轉換率高** - 大按鈕清楚告訴用戶下一步做什麼

#### 2. AIVisionResultSheet.swift (新檔案)

**位置**: `PackageTraker/Views/AddPackage/AIVisionResultSheet.swift`

**職責:**
- 顯示 AI 識別結果
- 允許編輯各欄位
- 確認並填入到 AddPackageView

```swift
struct AIVisionResultSheet: View {
    let result: AIVisionResult
    let onConfirm: (AIVisionResult) -> Void
    let onCancel: () -> Void

    @State private var editedResult: AIVisionResult

    var body: some View {
        NavigationStack {
            List {
                // 追蹤號碼
                resultRow(
                    label: "追蹤號碼",
                    value: editedResult.trackingNumber,
                    confidence: result.confidence.trackingNumber
                )

                // 物流商
                resultRow(
                    label: "物流商",
                    value: editedResult.carrier,
                    confidence: result.confidence.carrier
                )

                // ... 其他欄位
            }
            .navigationTitle("AI 識別結果")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("確認") {
                        onConfirm(editedResult)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
        }
    }
}
```

#### 3. PaywallSheet.swift (新檔案)

**位置**: `PackageTraker/Views/Subscription/PaywallSheet.swift`

**職責:**
- 展示訂閱方案
- 購買流程引導
- 恢復購買

```swift
struct PaywallSheet: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // 功能介紹
            VStack(spacing: 16) {
                Text("🤖 AI 智能辨識")
                    .font(.largeTitle.bold())

                FeatureRow(icon: "checkmark.circle", text: "自動識別 6+ 個欄位")
                FeatureRow(icon: "bolt.fill", text: "3 秒極速分析")
                FeatureRow(icon: "shield.fill", text: "準確度 90%+")
                FeatureRow(icon: "infinity", text: "無限次使用")
            }

            Spacer()

            // 訂閱方案
            VStack(spacing: 12) {
                SubscriptionOption(
                    title: "年訂閱",
                    price: "NT$399/年",
                    savings: "省 33%",
                    isRecommended: true
                ) {
                    // 購買年訂閱
                }

                SubscriptionOption(
                    title: "月訂閱",
                    price: "NT$49/月",
                    savings: nil,
                    isRecommended: false
                ) {
                    // 購買月訂閱
                }
            }

            Button("恢復購買") {
                Task {
                    try? await subscriptionManager.restorePurchases()
                }
            }
            .font(.footnote)
        }
        .padding()
    }
}
```

#### 4. SubscriptionView.swift (新檔案)

**位置**: `PackageTraker/Views/Settings/SubscriptionView.swift`

**職責:**
- 顯示訂閱狀態
- 管理訂閱(續訂、取消)
- 購買歷史

```swift
struct SubscriptionView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    var body: some View {
        List {
            Section("當前方案") {
                if subscriptionManager.hasActiveSubscription {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("進階會員")
                                .font(.headline)
                            Text(subscriptionManager.subscriptionType?.displayName ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                    }
                } else {
                    Text("未訂閱")
                        .foregroundColor(.secondary)
                }
            }

            Section("會員權益") {
                FeatureRow(icon: "sparkles", text: "無限 AI 智能辨識")
                FeatureRow(icon: "checkmark.circle", text: "未來進階功能優先體驗")
            }

            if subscriptionManager.hasActiveSubscription {
                Section {
                    Button("管理訂閱") {
                        // 打開 App Store 訂閱管理
                    }
                    Button("取消訂閱", role: .destructive) {
                        // 引導到 App Store 取消
                    }
                }
            } else {
                Section {
                    Button("開始訂閱") {
                        // 顯示 PaywallSheet
                    }
                }
            }
        }
        .navigationTitle("訂閱管理")
    }
}
```

### 本地化

新增以下字串到 3 個 `.strings` 檔案:

**zh-Hant.lproj/Localizable.strings:**
```
"ai.button" = "AI 辨識";
"ai.title" = "AI 識別結果";
"ai.confirm" = "確認並填入";
"ai.rescan" = "重新掃描";
"ai.processing" = "AI 分析中...";
"ai.field.trackingNumber" = "追蹤號碼";
"ai.field.carrier" = "物流商";
"ai.field.pickupLocation" = "取件地址";
"ai.field.pickupCode" = "取件碼";
"ai.field.packageName" = "包裹名稱";
"ai.field.estimatedDelivery" = "預估送達";
"ai.error.imageProcessing" = "圖片處理失敗";
"ai.error.network" = "網路錯誤";
"ai.error.parsing" = "辨識結果解析失敗";
"ai.error.subscription" = "此功能需要訂閱會員";
"subscription.title" = "訂閱管理";
"subscription.monthly" = "月訂閱";
"subscription.yearly" = "年訂閱";
"subscription.price.monthly" = "NT$49/月";
"subscription.price.yearly" = "NT$399/年";
"paywall.title" = "AI 智能辨識";
"paywall.feature1" = "自動識別 6+ 個欄位";
"paywall.feature2" = "3 秒極速分析";
"paywall.feature3" = "準確度 90%+";
"paywall.feature4" = "無限次使用";
"paywall.subscribe" = "開始訂閱";
"paywall.restore" = "恢復購買";
```

(需同步翻譯到 `zh-Hans.lproj` 和 `en.lproj`)

---

## 實作階段規劃

### Phase 1: MVP 核心功能 (2-3 週)

**目標**: 驗證 AI 辨識準確度,建立基礎功能,免費提供給所有用戶測試

**交付物:**
1. ✅ AIVisionService 實作 (Gemini 2.0 Flash 整合)
2. ✅ AIVisionModels 資料結構
3. ✅ AIVisionResultSheet UI
4. ✅ AddPackageView 整合 AI 按鈕
5. ✅ 基礎錯誤處理
6. ✅ 本地化字串 (3 語言)

**功能範圍:**
- 識別 3 個核心欄位: 追蹤號碼、物流商、取件地址
- 顯示信心度分數
- 允許手動編輯結果
- **暫不限制使用次數** (收集用戶反饋)

**驗收標準:**
- [ ] 成功識別 7-11、全家、蝦皮截圖 (準確率 ≥ 85%)
- [ ] 圖片壓縮至 500KB 以下
- [ ] API 回應時間 < 5 秒
- [ ] 無崩潰、無記憶體洩漏
- [ ] 支援 iOS 16+

**測試資料:**
- 準備 50+ 張真實物流截圖(各種物流商、格式)
- 手動驗證識別結果準確度
- 記錄錯誤案例用於 Prompt 優化

**關鍵檔案:**
- `PackageTraker/Services/AIVision/AIVisionService.swift`
- `PackageTraker/Services/AIVision/AIVisionModels.swift`
- `PackageTraker/Views/AddPackage/AIVisionResultSheet.swift`
- `PackageTraker/Views/AddPackage/AddPackageView.swift` (修改)
- `PackageTraker/zh-Hant.lproj/Localizable.strings` (新增字串)
- `PackageTraker/zh-Hans.lproj/Localizable.strings` (新增字串)
- `PackageTraker/en.lproj/Localizable.strings` (新增字串)

---

### Phase 2: 完整功能 + 優化 (3-4 週)

**目標**: 擴展識別能力,優化用戶體驗,準備商業化

**新增功能:**
1. ✅ 擴展識別欄位 (6+ 個)
   - 包裹名稱
   - 預估送達時間
   - 取件碼
   - 訂單金額(選)
2. ✅ 圖片編輯功能
   - 裁剪、旋轉、調整亮度
   - 幫助提升識別準確度
3. ✅ 進階錯誤處理
   - 網路超時重試(最多 3 次)
   - API 錯誤友善提示
   - 降級到基礎 OCR
4. ✅ 性能優化
   - 圖片快取(避免重複上傳)
   - 背景處理(不阻塞 UI)
5. ✅ 分析追蹤
   - Firebase Analytics 整合
   - 追蹤識別成功率、使用頻率
   - 識別最常用物流商

**交付物:**
1. 優化 AI Prompt (支援更多欄位)
2. 新增 `ImageEditorView` (裁剪預處理)
3. 改進 `AIVisionResultSheet` (支援更多欄位)
4. 錯誤處理增強
5. Firebase Analytics 整合
6. A/B 測試準備 (不同 Prompt 版本)

**驗收標準:**
- [ ] 識別 6+ 個欄位,準確率 ≥ 80%
- [ ] 用戶可修改所有識別結果
- [ ] 95th percentile 回應時間 < 8 秒
- [ ] 錯誤率 < 3%
- [ ] 50+ 位 Beta 測試用戶反饋

**關鍵檔案:**
- `PackageTraker/Services/AIVision/AIVisionService.swift` (擴展)
- `PackageTraker/Views/AddPackage/ImageEditorView.swift` (新檔案)
- `PackageTraker/Views/AddPackage/AIVisionResultSheet.swift` (擴展)
- `PackageTraker/Services/Analytics/AnalyticsManager.swift` (新檔案)

---

### Phase 3: 訂閱系統整合 (4-5 週)

**目標**: 完成 In-App Purchase 整合,啟動商業化

**新增功能:**
1. ✅ StoreKit 2 整合
   - 月訂閱、年訂閱產品
   - 購買流程
   - Receipt 驗證
   - 恢復購買
2. ✅ 付費牆 (PaywallSheet)
   - 展示訂閱價值
   - 引導購買流程
   - 限時優惠(可選)
3. ✅ 訂閱管理頁面
   - 顯示訂閱狀態
   - 管理/取消訂閱
   - 購買歷史
4. ✅ Settings 整合
   - 新增「訂閱管理」入口
   - 顯示會員標誌
5. ✅ 權限控制
   - 非訂閱用戶顯示付費牆
   - 訂閱用戶無限使用 AI

**交付物:**
1. `SubscriptionManager.swift` (StoreKit 2)
2. `PaywallSheet.swift`
3. `SubscriptionView.swift`
4. Settings 整合
5. App Store Connect 產品配置
6. 隱私政策更新
7. App Store 審核資料準備

**驗收標準:**
- [ ] 購買流程成功率 ≥ 95%
- [ ] Receipt 驗證延遲 < 2 秒
- [ ] 支援訂閱恢復和取消
- [ ] 通過 App Store Review
- [ ] 無訂閱狀態不同步問題
- [ ] 隱私政策符合要求

**App Store Connect 配置:**
- 產品 ID:
  - `com.packagetraker.premium.monthly` - NT$49/月
  - `com.packagetraker.premium.yearly` - NT$399/年
- 訂閱群組: PackageTraker Premium
- 免費試用: 可選(建議 7 天)
- 自動續訂: 啟用

**關鍵檔案:**
- `PackageTraker/Services/Subscription/SubscriptionManager.swift`
- `PackageTraker/Views/Subscription/PaywallSheet.swift`
- `PackageTraker/Views/Settings/SubscriptionView.swift`
- `PackageTraker/Views/Settings/SettingsView.swift` (修改)
- `PackageTraker/Views/AddPackage/AddPackageView.swift` (權限檢查)

---

## API 安全性

### 方案 A: 直接從 iOS 調用 (簡單,Phase 1 推薦)

**優點:**
- 實作簡單,無需後端
- 降低延遲
- 節省伺服器成本

**缺點:**
- API Key 存在 App 中(加密但可被逆向)
- 濫用風險(可透過訂閱驗證降低)

**實作:**
```swift
// API Key 加密存儲
struct Secrets {
    static var geminiAPIKey: String {
        // 從 Keychain 讀取或解密
        return KeychainHelper.getAPIKey() ?? ""
    }
}

// API 調用
let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(Secrets.geminiAPIKey)")!
```

### 方案 B: 中繼後端 API (安全,Phase 3 推薦)

**優點:**
- API Key 完全隱藏
- 可加入額外驗證(訂閱狀態)
- 可監控和限制濫用

**缺點:**
- 需要維護後端伺服器
- 增加延遲
- 伺服器成本

**架構:**
```
[iOS App] → [自建 API Server] → [Gemini API]
           (驗證訂閱狀態)
```

**建議**: Phase 1 使用方案 A,Phase 3 商業化後遷移到方案 B

---

## 驗證計畫

### 功能測試

1. **AI 辨識準確度測試**
   - 準備 100+ 張真實物流截圖
   - 覆蓋所有支援物流商: 7-11, 全家, 蝦皮, 黑貓, 順豐, 郵局等
   - 測試各種截圖品質: 清晰、模糊、部分遮擋、多個資訊
   - 目標準確率: ≥ 85% (Phase 1), ≥ 90% (Phase 2)

2. **使用流程測試**
   - 從相簿選擇圖片 → AI 分析 → 顯示結果 → 編輯 → 確認填入
   - 測試所有分支: 高信心度自動填入、低信心度手動確認、辨識失敗降級
   - 平均完成時間目標: < 10 秒

3. **訂閱流程測試** (Phase 3)
   - 非訂閱用戶: 顯示付費牆 → 選擇方案 → 購買 → 驗證 → 解鎖功能
   - 訂閱用戶: 直接使用 AI 功能
   - 恢復購買流程
   - 取消訂閱流程

### 性能測試

1. **回應時間**
   - API 調用: < 5 秒 (P95)
   - 圖片壓縮: < 1 秒
   - UI 渲染: < 0.5 秒

2. **記憶體使用**
   - 圖片處理峰值: < 100MB
   - 無記憶體洩漏

3. **電池消耗**
   - AI 辨識對電池影響 < 5%

### Beta 測試

**Phase 1 結束後:**
- 邀請 50-100 位用戶內測
- 收集反饋: 準確度、速度、易用性
- 調整 Prompt 和 UI

**Phase 2 結束後:**
- 擴大到 500+ 位用戶
- A/B 測試不同 UI 設計
- 數據分析: 使用頻率、最常見錯誤

**Phase 3 上線前:**
- 最終測試訂閱流程
- App Store 審核準備
- 客服 FAQ 準備

### 模擬器測試

**可用模擬器**: iPhone 17 Pro (iOS 26.2)

**測試命令:**
```bash
# 構建並運行
xcodebuild build -project PackageTraker.xcodeproj -scheme PackageTraker -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# 運行測試
xcodebuild test -project PackageTraker.xcodeproj -scheme PackageTraker -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## 成功指標 (KPI)

### Phase 1 (MVP)
- **AI 辨識使用率**: ≥ 30% 新增包裹使用 AI
- **識別準確率**: ≥ 85% (追蹤號碼 + 物流商)
- **用戶滿意度**: ≥ 4.0/5.0 (App 內評分提示)
- **崩潰率**: < 1%

### Phase 2 (完整功能)
- **AI 辨識使用率**: ≥ 50%
- **識別準確率**: ≥ 90%
- **欄位完整度**: 平均 4+ 個欄位/次
- **Day 7 留存率**: ≥ 60%

### Phase 3 (商業化)
- **訂閱轉換率**: ≥ 3% (使用過 AI 的用戶)
- **ARPU**: ≥ NT$5/月/活躍用戶
- **訂閱留存率**:
  - Month 1: ≥ 70%
  - Month 3: ≥ 50%
  - Month 6: ≥ 40%
- **LTV/CAC**: ≥ 3:1 (如有付費推廣)
- **淨收入**: ≥ NT$50,000/月 (假設 1500 訂閱用戶)

### 持續監控指標

- API 成本 (Gemini)
- API 錯誤率
- 平均辨識時間
- 最常用物流商
- 訂閱流失原因
- 客服問題分類

---

## 風險評估與應對

### 技術風險

| 風險 | 機率 | 影響 | 應對策略 |
|-----|------|------|---------|
| Gemini API 準確度不足 | 中 | 高 | Phase 1 充分測試,準備備案(GPT-4o-mini) |
| API 成本超支 | 低 | 中 | 監控每用戶消耗,設定成本上限 |
| App Store 審核被拒 | 低 | 高 | 提前準備隱私政策,明確標示數據用途 |
| 圖片處理性能問題 | 低 | 中 | 優化壓縮演算法,背景處理 |
| 訂閱系統 bug | 中 | 高 | 充分測試 StoreKit,使用沙盒環境 |

### 商業風險

| 風險 | 機率 | 影響 | 應對策略 |
|-----|------|------|---------|
| 用戶不願付費 | 中 | 高 | Phase 1 免費測試驗證價值,調整定價 |
| 訂閱留存率低 | 中 | 中 | 持續優化功能,增加訂閱價值 |
| 競品推出類似功能 | 低 | 中 | 快速迭代,專注台灣本地化 |
| 使用率低於預期 | 低 | 中 | 優化 UI 入口,教育用戶價值 |

### 應急預案

**如果 Gemini API 不可用:**
- 備案 1: 切換到 GPT-4o-mini
- 備案 2: 降級到基礎 OCR
- 通知用戶服務暫時中斷

**如果訂閱轉換率 < 1%:**
- 調整定價(降低或改為次數包)
- 提供限時優惠
- 重新設計付費牆
- 增加免費試用期

**如果 App Store 審核被拒:**
- 常見原因: 隱私政策不清、訂閱說明不足
- 準備: 詳細的審核說明文件、測試帳號
- 備案: 暫時移除付費功能,先上線免費版

---

## 預算與時間估算

### 開發時間

**總開發時間: 9-12 週 (2-3 個月)**

| 階段 | iOS 開發 | 測試 | 總時數 |
|-----|---------|------|--------|
| Phase 1 (MVP) | 40h | 20h | 60h |
| Phase 2 (完整功能) | 60h | 30h | 90h |
| Phase 3 (訂閱系統) | 80h | 40h | 120h |
| **總計** | **180h** | **90h** | **270h** |

### 成本預算

**開發期間成本:**
- Gemini API (免費額度): NT$0
- 測試設備: NT$0 (使用模擬器)
- 開發工具: NT$0 (Xcode 免費)
- **總計: NT$0**

**運營期間成本 (月):**
- Gemini API: NT$250-2,500 (依用戶量)
- Apple Developer: NT$100/月 (NT$3,000/年 ÷ 12)
- 伺服器(選,Phase 3): NT$0-500/月
- 分析工具(Firebase): NT$0 (免費額度)
- **總計: NT$350-3,100/月**

**收支平衡點:**
- 假設月費 NT$49,Apple 分潤 30%
- 淨收入/用戶: NT$34.3
- 月成本 NT$1,000 → 需要 30 位訂閱用戶
- 月成本 NT$3,000 → 需要 88 位訂閱用戶

---

## 下一步行動

### 立即開始 (本週)

1. [ ] 註冊 Google AI Studio 帳號
2. [ ] 取得 Gemini API Key
3. [ ] 測試 API 調用(使用 Postman 或 curl)
4. [ ] 收集 50+ 張真實物流截圖
5. [ ] 手動測試 Gemini 對這些截圖的辨識效果

### Phase 1 準備 (下週)

1. [ ] 建立 `AIVision/` 資料夾結構
2. [ ] 安裝 Google Generative AI SDK (若有)
3. [ ] 實作 `AIVisionService.swift` 基礎框架
4. [ ] 實作圖片壓縮功能
5. [ ] 測試端到端 API 調用

### 持續追蹤

- 每週檢查開發進度
- 每 2 週收集用戶反饋
- 每月檢視 KPI 達成情況
- 每季評估是否需要調整策略

---

## 附錄: 完整檔案清單

### 新增檔案

#### Services 層
- `PackageTraker/Services/AIVision/AIVisionService.swift`
- `PackageTraker/Services/AIVision/AIVisionModels.swift`
- `PackageTraker/Services/AIVision/AIVisionTokenStorage.swift` (可選)
- `PackageTraker/Services/Subscription/SubscriptionManager.swift`
- `PackageTraker/Services/Subscription/IAPProduct.swift`
- `PackageTraker/Services/Analytics/AnalyticsManager.swift` (Phase 2)

#### Views 層
- `PackageTraker/Views/AddPackage/AIVisionResultSheet.swift`
- `PackageTraker/Views/AddPackage/ImageEditorView.swift` (Phase 2)
- `PackageTraker/Views/Subscription/PaywallSheet.swift`
- `PackageTraker/Views/Subscription/SubscriptionView.swift`
- `PackageTraker/Views/Subscription/SubscriptionOptionView.swift`

#### 本地化
- 更新 `PackageTraker/zh-Hant.lproj/Localizable.strings`
- 更新 `PackageTraker/zh-Hans.lproj/Localizable.strings`
- 更新 `PackageTraker/en.lproj/Localizable.strings`

### 修改檔案

- `PackageTraker/Views/AddPackage/AddPackageView.swift` (新增 AI 按鈕)
- `PackageTraker/Views/Settings/SettingsView.swift` (新增訂閱入口)
- `PackageTraker/FeatureFlags.swift` (新增 aiVisionEnabled)
- `PackageTraker/PackageTrakerApp.swift` (初始化 SubscriptionManager)

---

## 總結

本計畫將在 2-3 個月內完成從基礎 OCR 到 AI 智能辨識的升級,採用成本最低的 **Gemini 2.0 Flash** API,建立 **訂閱制** 商業模式(月費 NT$49),預期利潤率達 **97-99%**。

**核心優勢:**
- ✅ 成本極低 (每次辨識 NT$0.005)
- ✅ 免費額度充足 (每天 100 次)
- ✅ 訂閱制穩定收入
- ✅ 共存模式降低風險
- ✅ 分階段實作可控

**關鍵成功因素:**
1. Phase 1 充分驗證 AI 準確度 (≥ 85%)
2. 優化用戶體驗,降低使用門檻
3. 合理定價 (NT$49/月 = 一杯咖啡)
4. 持續監控和優化

期待這個升級能顯著提升 PackageTraker 的競爭力和商業價值! 🚀

---

**Sources:**
- [Gemini API Pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [AI API Pricing Comparison 2026](https://intuitionlabs.ai/articles/ai-api-pricing-comparison-grok-gemini-chatgpt-claude)
- [DeepSeek Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing)
- [DeepSeek-VL2 GitHub](https://github.com/deepseek-ai/DeepSeek-VL2)
- [Janus-Pro Multimodal AI](https://github.com/deepseek-ai/Janus)
