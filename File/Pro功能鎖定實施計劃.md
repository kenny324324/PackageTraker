# Pro 功能鎖定實施計劃

## 概覽

本文件記錄 PackageTraker (取貨吧) App 的 Pro 訂閱功能鎖定機制設計與實施計劃。

**最後更新**: 2026-02-12 (v1.1)
**狀態**: 實施中

---

## 一、當前 Pro 功能清單

### 1.1 已確認的 Pro 功能（付費牆展示）

根據付費牆比較表（2026-02-12 更新），**官方確認的 4 個 Pro 功能**：

| 功能 | 屬性 | 免費版限制 | Pro 版權限 | 實施狀態 |
|------|------|-----------|-----------|----------|
| **包裹數量上限** | `maxPackageCount` | 最多 5 個 | 無限制 | 🔄 部分實施（需修復攔截） |
| **主題顏色** | `hasAllThemes` | 1 種（咖啡棕） | 全部解鎖 | ✅ 已完整實施 |
| **AI 截圖辨識** | `hasAIAccess` | 無法使用 (—) | 可使用 (✓) | 🚧 UI 已準備，功能未啟用 |
| **桌面小工具** | `widgetEnabled` | 小型 | 全尺寸 | 📅 Phase D 規劃中 |

### 1.2 從付費牆移除的功能（全用戶免費）

以下功能**不再作為 Pro 賣點**，已對所有登入用戶開放：

| 功能 | 實施狀態 | 備註 |
|------|----------|------|
| **推播通知** | ✅ 全用戶可用 | Firebase FCM (Phase 3) |
| **iCloud 同步** | ✅ 全用戶可用 | Firebase Firestore (Phase 2) |

**移除原因**: 這兩個功能在 Phase 2-3 實施時未加入 Pro 檢查，且改為 Pro 專屬需要大量改動並影響用戶體驗。為保持誠實行銷，已從付費牆移除。

---

## 二、功能鎖定模式分析

根據現有程式碼和用戶需求，Pro 功能的鎖定有兩種模式：

### 2.1 模式 A：功能區鎖定 + 引導購買

**特徵**：
- 功能入口在設定或特定頁面中
- 顯示鎖定圖示 + Pro 標籤
- 點擊後跳轉至訂閱畫面

**適用功能**：
- ✅ **主題顏色**（ThemeSettingsView）
  - 當前實施：顯示 lock + crown 圖示
  - 需改進：新增 Pro 膠囊標籤

**實施位置**：
- `ThemeSettingsView.swift` (line 75-126)
- 檢查條件：`!subscriptionManager.hasAllThemes && theme != .coffeeBrown`

**用戶體驗**：
```
[鎖定功能] → 點擊 → [顯示 PaywallView] → 購買 → 解鎖
```

---

### 2.2 模式 B：操作時攔截 + 彈出訂閱

**特徵**：
- 功能入口在主流程中（如新增包裹按鈕）
- 不顯示鎖定狀態，正常顯示按鈕
- 達到限制時才彈出訂閱畫面

**適用功能**：
- 🔄 **包裹數量限制**（新增包裹時）
  - 當前實施：設定頁顯示額度
  - 需改進：新增包裹時檢查額度

- 🚧 **AI 截圖辨識**（未啟用）
  - 當前實施：顯示 AI 卡片 + PRO 標籤
  - 點擊行為：免費用戶 → 訂閱畫面，Pro 用戶 → 選擇圖片

**實施位置**：
- 包裹數量：`AddPackageView.swift` 新增按鈕、`PackageListView.swift` 新增入口
- AI 辨識：`AIPromotionCard.swift` (line 20-23), `AddPackageView.swift` (line 329)

**用戶體驗**：
```
[點擊新增/AI按鈕] → 檢查權限 → [超過限制] → [顯示 PaywallView] → 購買 → 繼續操作
```

---

## 三、當前實施狀況與問題

### 3.1 主題顏色鎖定 ✅ 完整實施

**檔案**: `ThemeSettingsView.swift`

**當前實施**：
```swift
let isLocked = FeatureFlags.subscriptionEnabled && !subscriptionManager.hasAllThemes && theme != .coffeeBrown

Button {
    if isLocked {
        showPaywall = true  // 跳轉訂閱畫面
    } else {
        themeManager.selectedTheme = theme  // 套用主題
    }
}
```

**鎖定 UI**：
- 顏色圓圈覆蓋半透明黑色遮罩
- 顯示鎖頭 + 皇冠圖示（黃色半透明）
- 灰色文字

**建議改進**：
- ✅ **已完成**: Pro 膠囊標籤已統一為黃橙漸層（2026-02-12）
- **可選**: 在鎖定主題右側新增 "Pro" 膠囊標籤（與截圖一致）

---

### 3.2 包裹數量限制 🔄 部分實施

**當前實施**：

1. **SubscriptionManager 定義**：
   ```swift
   var maxPackageCount: Int { isPro ? .max : 5 }
   ```

2. **SettingsView 顯示額度**：
   ```swift
   if FeatureFlags.subscriptionEnabled && !subscriptionManager.isPro {
       packageQuotaSection  // 顯示 5/5 進度條，點擊跳轉訂閱畫面
   }
   ```

**問題**：
- ❌ **未實施**: 新增包裹時未檢查額度限制
- ❌ **未實施**: 達到上限時未攔截新增操作

**用戶流程漏洞**：
```
免費用戶 → 已有 5 個包裹 → 點擊新增按鈕 → ❌ 可以繼續新增 → 超過限制
```

**需要修正的檔案**：
- `AddPackageView.swift` - 新增包裹前檢查額度
- `PackageListView.swift` - 新增按鈕點擊時檢查額度
- `MainTabView.swift` - Tab bar 新增按鈕（如果有）

---

### 3.3 AI 截圖辨識 🚧 UI 已準備，功能未啟用

**功能開關**: `FeatureFlags.aiVisionEnabled = false`

**當前實施**：

1. **AIPromotionCard** (`AIPromotionCard.swift`):
   ```swift
   Button {
       if subscriptionManager.hasAIAccess {
           onSelectImage()  // Pro 用戶直接選圖
       } else {
           onShowPaywall()  // 免費用戶跳轉訂閱畫面
       }
   }
   ```

2. **AddPackageView 內嵌 AI 卡片** (`AddPackageView.swift` line 304-377):
   - 顯示 AI 卡片 + PRO 標籤（免費用戶）
   - 點擊行為同上

**UI 狀態**：
- ✅ 已完成: Pro 膠囊標籤顏色統一為黃橙漸層
- ✅ 已完成: 卡片背景為紫藍漸層 + 紫色邊框
- ✅ 已完成: sparkles 圖示

**啟用條件**：
- 後端 AI Vision API 整合完成
- 修改 `FeatureFlags.aiVisionEnabled = true`

---

## 四、實施計劃

### 4.1 優先級定義

| 優先級 | 功能 | 原因 | 預計工時 |
|--------|------|------|---------|
| **P0** | 包裹數量限制攔截 | 核心商業模式，當前有漏洞 | 2 小時 |
| **P1** | 主題顏色 Pro 標籤優化 | 提升 UI 一致性（可選） | 1 小時 |
| **P2** | AI 功能啟用準備 | 等待後端整合 | 0.5 小時 |
| **P3** | Widget 功能實施 | Phase D 規劃 | 8 小時 |

---

### 4.2 P0: 包裹數量限制攔截實施

#### 4.2.1 需求分析

**攔截時機**：
1. 用戶點擊首頁「新增包裹」按鈕
2. 用戶在其他入口嘗試新增包裹

**檢查邏輯**：
```swift
let activePackageCount = packages.filter { !$0.isArchived }.count
let canAddPackage = activePackageCount < subscriptionManager.maxPackageCount || subscriptionManager.isPro

if !canAddPackage {
    // 顯示訂閱畫面
    showPaywall = true
} else {
    // 繼續新增流程
    showAddPackage = true
}
```

#### 4.2.2 實施步驟

##### Step 1: 修改 PackageListView.swift

**位置**: 新增按鈕點擊事件

**修改前**：
```swift
Button {
    showAddPackage = true
} label: {
    // ... 新增按鈕 UI
}
```

**修改後**：
```swift
@State private var showPaywall = false

Button {
    let activeCount = packages.filter { !$0.isArchived }.count
    if activeCount >= subscriptionManager.maxPackageCount && !subscriptionManager.isPro {
        showPaywall = true  // 達到限制，顯示訂閱畫面
    } else {
        showAddPackage = true  // 正常新增
    }
} label: {
    // ... 新增按鈕 UI
}
.fullScreenCover(isPresented: $showPaywall) {
    PaywallView()
}
```

**檔案位置**:
- `PackageTraker/Views/PackageList/PackageListView.swift`
- 搜尋關鍵字: `showAddPackage`

---

##### Step 2: 修改 MainTabView.swift (如果有 Tab Bar 新增按鈕)

**需求**: 檢查 MainTabView 是否有內建新增按鈕（類似 Instagram 的中間按鈕）

**如果有**：
- 同 Step 1 邏輯，在按鈕點擊時檢查額度
- 傳遞 `@Query` 包裹清單給 MainTabView（或透過 Environment）

**如果沒有**：
- 跳過此步驟

---

##### Step 3: 新增 Alert 提示（可選，更好的 UX）

**位置**: PackageListView

**實施**：
```swift
@State private var showQuotaAlert = false

Button {
    let activeCount = packages.filter { !$0.isArchived }.count
    if activeCount >= subscriptionManager.maxPackageCount && !subscriptionManager.isPro {
        showQuotaAlert = true  // 先顯示提示
    } else {
        showAddPackage = true
    }
}
.alert(String(localized: "quota.limitReached.title"), isPresented: $showQuotaAlert) {
    Button(String(localized: "quota.upgrade"), role: .none) {
        showPaywall = true
    }
    Button(String(localized: "common.cancel"), role: .cancel) {}
} message: {
    Text(String(localized: "quota.limitReached.message"))
}
```

**需新增的本地化字串**：
```
// en.lproj/Localizable.strings
"quota.limitReached.title" = "Package Limit Reached";
"quota.limitReached.message" = "Free plan allows up to 5 packages. Upgrade to Pro for unlimited tracking.";
"quota.upgrade" = "Upgrade to Pro";

// zh-Hant.lproj/Localizable.strings
"quota.limitReached.title" = "已達包裹上限";
"quota.limitReached.message" = "免費方案最多追蹤 5 個包裹。升級至 Pro 解鎖無限追蹤。";
"quota.upgrade" = "升級至 Pro";

// zh-Hans.lproj/Localizable.strings
"quota.limitReached.title" = "已达包裹上限";
"quota.limitReached.message" = "免费方案最多追踪 5 个包裹。升级至 Pro 解锁无限追踪。";
"quota.upgrade" = "升级至 Pro";
```

---

##### Step 4: 測試檢查清單

- [ ] 免費用戶新增第 5 個包裹 → 成功
- [ ] 免費用戶嘗試新增第 6 個包裹 → 顯示訂閱畫面（或 Alert）
- [ ] Pro 用戶新增第 6+ 個包裹 → 正常新增
- [ ] 封存包裹後，額度釋放 → 可以再新增
- [ ] 從其他入口新增（如果有多個入口）→ 同樣攔截

---

### 4.3 P1: 主題顏色 Pro 標籤優化（可選）

#### 4.3.1 當前狀態

**ThemeSettingsView 鎖定 UI**：
```swift
if isLocked {
    HStack(spacing: 4) {
        Image(systemName: "lock.fill")
        Image(systemName: "crown.fill")
    }
    .foregroundStyle(.yellow.opacity(0.7))
}
```

#### 4.3.2 建議改進（與截圖一致）

**修改為**：
```swift
if isLocked {
    HStack(spacing: 8) {
        // 鎖頭圖示
        Image(systemName: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)

        // Pro 標籤
        Text("Pro")
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
```

**優點**：
- 與其他 Pro 標籤樣式統一（AI 卡片、設定頁面）
- 更明確標示 Pro 專屬功能

**檔案位置**: `ThemeSettingsView.swift` line 106-119

---

### 4.4 P2: AI 功能啟用準備

#### 4.4.1 當前狀態

- ✅ UI 完整實施（AIPromotionCard, AddPackageView）
- ✅ Pro 檢查邏輯已就緒 (`hasAIAccess`)
- ✅ Pro 膠囊標籤顏色已統一
- 🚧 功能開關關閉 (`aiVisionEnabled = false`)

#### 4.4.2 啟用步驟

**Step 1**: 後端 AI Vision API 整合完成

**Step 2**: 測試 AI 辨識功能
- [ ] Pro 用戶可以選擇圖片
- [ ] AI 正確辨識追蹤號碼 + 物流商
- [ ] 結果可以填入表單

**Step 3**: 開啟功能開關
```swift
// FeatureFlags.swift
static let aiVisionEnabled = true
```

**Step 4**: 測試免費/Pro 用戶流程
- [ ] 免費用戶點擊 AI 卡片 → 跳轉訂閱畫面
- [ ] Pro 用戶點擊 AI 卡片 → 選擇圖片 → 辨識 → 填入

---

### 4.5 P3: Widget 功能實施（Phase D）

#### 4.5.1 功能範圍

**Widget 類型**：
- 小型 Widget: 顯示最新 1-2 個包裹狀態
- 中型 Widget: 顯示最新 3-4 個包裹狀態
- 大型 Widget: 顯示最新 5-6 個包裹狀態

**Pro 限制**：
- 免費版：僅小型 Widget
- Pro 版：全尺寸 Widget + 自訂顯示內容

#### 4.5.2 技術架構

**新增 Target**：
- Widget Extension (SwiftUI)
- App Group 共享資料容器

**資料同步**：
```swift
// 透過 App Group 共享 SwiftData 容器
let container = ModelContainer(
    for: Package.self,
    configurations: ModelConfiguration(
        groupContainer: .identifier("group.com.kenny.PackageTraker")
    )
)
```

**檔案結構**：
```
PackageTrakerWidget/
├── PackageTrackerWidget.swift        # Widget 主檔案
├── PackageWidgetEntry.swift          # Widget 資料模型
├── SmallPackageWidget.swift          # 小型 Widget
├── MediumPackageWidget.swift         # 中型 Widget（Pro）
└── LargePackageWidget.swift          # 大型 Widget（Pro）
```

#### 4.5.3 Pro 鎖定邏輯

**Widget Configuration**：
```swift
@main
struct PackageTrackerWidget: Widget {
    let kind: String = "PackageTrackerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PackageWidgetView(entry: entry)
        }
        .configurationDisplayName("包裹追蹤")
        .description("隨時查看包裹追蹤狀態")
        .supportedFamilies([
            .systemSmall,         // 免費版可用
            .systemMedium,        // Pro 專屬
            .systemLarge          // Pro 專屬
        ])
    }
}
```

**Widget View Pro 檢查**：
```swift
struct PackageWidgetView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallPackageWidget(entry: entry)  // 免費版可用

        case .systemMedium, .systemLarge:
            if SubscriptionManager.shared.isPro {
                // Pro 用戶顯示完整 Widget
                if family == .systemMedium {
                    MediumPackageWidget(entry: entry)
                } else {
                    LargePackageWidget(entry: entry)
                }
            } else {
                // 免費用戶顯示升級提示
                UpgradePromptWidget()
            }
        }
    }
}
```

**UpgradePromptWidget**：
```swift
struct UpgradePromptWidget: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)

            Text("Pro 專屬")
                .font(.headline)
                .foregroundStyle(.white)

            Text("升級解鎖中型與大型 Widget")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link(destination: URL(string: "packagetraker://upgrade")!) {
                Text("升級至 Pro")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
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
        .padding()
        .background(Color.appBackground)
    }
}
```

#### 4.5.4 Deep Link 處理

**Info.plist 設定**：
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>packagetraker</string>
        </array>
    </dict>
</array>
```

**App Deep Link 處理**：
```swift
// PackageTrakerApp.swift
.onOpenURL { url in
    if url.scheme == "packagetraker" {
        if url.host == "upgrade" {
            showPaywall = true
        }
    }
}
```

#### 4.5.5 實施工時估算

| 任務 | 預計工時 | 備註 |
|------|---------|------|
| Widget Extension 設定 + App Group | 1 小時 | Xcode target 設定 |
| SwiftData 共享容器實作 | 1 小時 | App Group 資料同步 |
| Small Widget 實作 | 2 小時 | 免費版 Widget |
| Medium/Large Widget 實作 | 2 小時 | Pro 專屬 Widget |
| UpgradePromptWidget 實作 | 1 小時 | 免費版升級提示 |
| Deep Link 處理 | 0.5 小時 | Widget → App 跳轉 |
| 測試 + 除錯 | 1.5 小時 | 各尺寸測試 |
| **總計** | **9 小時** | - |

---

## 五、Pro 標籤 UI 規範

### 5.1 標準 Pro 膠囊樣式

**✅ 統一規範（2026-02-12 已實施）**：

```swift
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
```

**視覺效果**：
- 🟡 黃橙漸層背景（金色主題）
- ⚪ 白色粗體文字
- 💊 膠囊形狀 (Capsule)
- 📏 固定內距 (h: 6, v: 2)

### 5.2 已更新的檔案

- ✅ `SettingsView.swift` (line 242-257) - 帳號卡片 Pro 標籤
- ✅ `AccountDetailView.swift` (line 176-191) - 訂閱狀態 Pro 標籤
- ✅ `AIPromotionCard.swift` (line 51-66) - AI 卡片 Pro 標籤
- ✅ `AddPackageView.swift` (line 329-344) - 內嵌 AI 卡片 Pro 標籤

### 5.3 設計一致性檢查清單

**使用場景**：
- [x] 帳號卡片（已訂閱用戶）
- [x] 訂閱狀態顯示
- [x] AI 功能鎖定提示
- [ ] 主題顏色鎖定（可選，當前為 lock + crown）
- [ ] Widget 升級提示（Phase D）

---

## 六、測試計劃

### 6.1 單元測試

**測試範圍**：
- [ ] `SubscriptionManager.maxPackageCount` 正確返回 5 (free) 或 .max (pro)
- [ ] `SubscriptionManager.hasAIAccess` 正確返回 false (free) 或 true (pro)
- [ ] `SubscriptionManager.hasAllThemes` 正確返回 false (free) 或 true (pro)

**測試檔案**: `PackageTrakerTests/SubscriptionManagerTests.swift`

---

### 6.2 UI 測試

#### 免費用戶流程

**包裹數量限制**：
- [ ] 新增第 1-5 個包裹 → 成功
- [ ] 嘗試新增第 6 個包裹 → 顯示訂閱畫面
- [ ] 封存 1 個包裹 → 可以再新增 1 個

**主題顏色**：
- [ ] 咖啡棕色可以選擇
- [ ] 其他顏色顯示鎖定圖示
- [ ] 點擊鎖定顏色 → 跳轉訂閱畫面

**AI 辨識**：
- [ ] 顯示 AI 卡片 + PRO 標籤
- [ ] 點擊 AI 卡片 → 跳轉訂閱畫面

#### Pro 用戶流程

**包裹數量**：
- [ ] 可以新增超過 5 個包裹
- [ ] 設定頁面不顯示額度卡片

**主題顏色**：
- [ ] 所有顏色可以選擇
- [ ] 不顯示鎖定圖示

**AI 辨識**：
- [ ] 顯示 AI 卡片（無 PRO 標籤）
- [ ] 點擊 AI 卡片 → 選擇圖片

---

### 6.3 購買流程測試

**StoreKit Configuration 測試環境**：
- [ ] Lifetime 產品購買 → Pro 狀態立即更新
- [ ] Monthly 產品購買 → Pro 狀態立即更新
- [ ] Yearly 產品購買 → Pro 狀態立即更新
- [ ] 恢復購買 → Pro 狀態正確恢復

**Sandbox 測試環境**：
- [ ] 真實購買流程測試
- [ ] 訂閱續訂測試
- [ ] 訂閱取消測試
- [ ] 多設備同步測試

---

## 七、本地化字串清單

### 7.1 需新增的字串（P0 實施）

#### en.lproj/Localizable.strings
```
"quota.limitReached.title" = "Package Limit Reached";
"quota.limitReached.message" = "Free plan allows up to 5 packages. Upgrade to Pro for unlimited tracking.";
"quota.upgrade" = "Upgrade to Pro";
```

#### zh-Hant.lproj/Localizable.strings
```
"quota.limitReached.title" = "已達包裹上限";
"quota.limitReached.message" = "免費方案最多追蹤 5 個包裹。升級至 Pro 解鎖無限追蹤。";
"quota.upgrade" = "升級至 Pro";
```

#### zh-Hans.lproj/Localizable.strings
```
"quota.limitReached.title" = "已达包裹上限";
"quota.limitReached.message" = "免费方案最多追踪 5 个包裹。升级至 Pro 解锁无限追踪。";
"quota.upgrade" = "升级至 Pro";
```

---

## 八、常見問題 (FAQ)

### Q1: 為什麼包裹數量限制當前沒有攔截？
**A**: 當前實施只在設定頁面顯示額度，但新增包裹時未檢查。這是實施上的疏漏，需要在 P0 階段修正。

### Q2: AI 功能何時會啟用？
**A**: 等待後端 AI Vision API 整合完成。UI 與 Pro 鎖定邏輯已準備就緒，只需修改 `FeatureFlags.aiVisionEnabled = true`。

### Q3: 為什麼主題顏色使用 lock + crown 而不是 Pro 標籤？
**A**: 當前設計偏向鎖定圖示化表達。可以改為 Pro 標籤以統一 UI（見 P1 計劃）。

### Q4: 推播通知和 iCloud 同步是否為 Pro 功能？
**A**: 目前這兩個功能對所有用戶開放。付費牆文案可能需要更新，或考慮未來將其納入 Pro 專屬。

### Q5: Lifetime 購買在測試環境不顯示 Apple Pay 畫面，正常嗎？
**A**: 正常。StoreKit Configuration 環境中，NonConsumable 產品（Lifetime）可能跳過支付 UI。RecurringSubscription（月費/年費）會顯示續訂條款確認。

---

## 九、付費牆改版記錄（2026-02-12）

### 9.1 改版內容

**從網格改為比較表格式**：
- **舊版**: 2x3 網格，顯示 6 個功能（包含已移除的推播和同步）
- **新版**: 比較表，顯示 4 個功能（免費版 vs Pro 版）

**視覺改進**：
```
┌─────────────────────────────────────────┐
│ 功能比較                                 │
├──────────────┬──────────┬───────────────┤
│              │ 免費版   │ Pro 版        │
├──────────────┼──────────┼───────────────┤
│ 📦 包裹數量   │ 最多 5 個 │ 無限制        │
│ 🎨 主題顏色   │ 1 種     │ 全部解鎖      │
│ ✨ AI 截圖    │ —        │ ✓             │
│ 📱 桌面小工具 │ 小型     │ 全尺寸        │
└──────────────┴──────────┴───────────────┘
```

**文案修正**：
- 標題下方 subtitle:
  - 舊: "解鎖無廣告、無限追蹤等更多功能"
  - 新: "無限包裹追蹤、AI 辨識、自訂主題與桌面小工具"
  - 移除「無廣告」（App 本來就沒廣告）

### 9.2 實施檔案

**修改檔案**:
- `Views/Subscription/PaywallView.swift`
  - 新增 `featureComparisonSection`
  - 新增 `comparisonRow()` helper
  - 移除舊的 `featureGridSection` 和 `featureItem()`

**本地化字串新增** (3 語言):
- `paywall.comparison.title` - 功能比較
- `paywall.comparison.free` - 免費版
- `paywall.comparison.pro` - Pro 版
- `paywall.comparison.packages.*` - 包裹數量相關
- `paywall.comparison.themes.*` - 主題顏色相關
- `paywall.comparison.ai.*` - AI 辨識相關
- `paywall.comparison.widget.*` - Widget 相關

---

## 十、附錄

### 附錄 A: 相關程式碼檔案清單

**核心服務**：
- `Models/SubscriptionTier.swift` - 訂閱層級定義
- `Services/Subscription/SubscriptionManager.swift` - 訂閱邏輯核心
- `FeatureFlags.swift` - 功能開關

**UI 實施**：
- `Views/Subscription/PaywallView.swift` - 訂閱購買畫面
- `Views/Settings/SettingsView.swift` - 設定頁面（Pro 卡片、額度卡片）
- `Views/Settings/AccountDetailView.swift` - 帳號詳情頁面
- `Views/Settings/ThemeSettingsView.swift` - 主題設定頁面
- `Views/AddPackage/AddPackageView.swift` - 新增包裹頁面
- `Views/AddPackage/AIPromotionCard.swift` - AI 推廣卡片
- `Views/PackageList/PackageListView.swift` - 包裹清單頁面

**本地化**：
- `en.lproj/Localizable.strings` - 英文
- `zh-Hant.lproj/Localizable.strings` - 繁體中文
- `zh-Hans.lproj/Localizable.strings` - 簡體中文

**StoreKit 設定**：
- `Configuration.storekit` - 測試產品設定

---

### 附錄 B: Git Commit 記錄

**訂閱系統實施歷史**：
- `[pending]` (2026-02-12) - 付費牆改為比較表格式 + Pro 膠囊顏色統一 + 移除虛假功能
- `c773e79` (2026-02-12) - 重新設計訂閱頁面並新增終身買斷方案
- `[earlier]` (2026-02-09~10) - Firebase Phase 1-4 完整實施

---

### 附錄 C: 參考文件

- `File/後端推播系統實施計劃.md` - Firebase 後端實施完整計劃
- `CLAUDE.md` - 專案架構與開發規範
- Apple StoreKit 2 官方文件
- Firebase Cloud Functions 文件

---

## 變更記錄

### v1.1 (2026-02-12)
- ✅ 付費牆改為比較表格式
- ✅ 只保留 4 個真正的 Pro 功能（包裹、主題、AI、Widget）
- ✅ 移除虛假功能（推播、iCloud 同步）
- ✅ 修正 subtitle 文案（移除「無廣告」）
- ✅ 統一 Pro 膠囊顏色為黃橙漸層
- ✅ 新增比較表本地化字串（3 語言）

### v1.0 (2026-02-12)
- 初始版本
- Pro 功能盤點與分類
- 實施計劃制定

---

**文件版本**: v1.1
**建立日期**: 2026-02-12
**最後修改**: 2026-02-12
**負責人**: Claude Code + Jonathan Yu
