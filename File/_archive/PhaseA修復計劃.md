# Phase A 修復計劃

## 背景

Phase A（訂閱服務 + 設定頁面）的程式碼已完成 95%，經全面檢查發現 3 個問題需要修復。

### 已完成項目確認

| 項目 | 狀態 | 備註 |
|------|------|------|
| A.1 SubscriptionManager | ✅ 完整 | StoreKit 2 全功能，含 mock purchase |
| A.2 PaywallView | ✅ 完整 | 功能對比表、產品卡片、購買/恢復 |
| A.3 設定頁面 UI | ✅ 完整 | 帳號、額度卡片、通知設定、編輯 |
| A.4 主題付費牆 | ✅ 完整 | ThemeSettingsView 鎖定 + ThemeManager 檢查 |
| A.5 包裹數量限制 | ✅ 完整 | AddPackageView 5 包裹上限 |
| A.6 FeatureFlags | ✅ 完整 | subscriptionEnabled = true |
| 本地化 | ✅ 完整 | 3 語言 50+ 訂閱相關 key |

---

## 待修復問題（3 項）

### 問題 1：SettingsView dataManagementSection 未顯示

**檔案：** `PackageTraker/Views/Settings/SettingsView.swift`

**問題描述：**
- 第 784-810 行定義了 `dataManagementSection`（資料管理區塊，含清除資料按鈕）
- 但在 body 的 VStack（第 72-115 行）中從未呼叫此 section
- 使用者無法在設定頁面看到資料管理功能

**修復方式：**
在 `notificationSection`（第 85 行）之後加入 `dataManagementSection`：

```swift
// 通知設定
notificationSection

// 資料管理
dataManagementSection

// 評分卡片
rateAppSection
```

**修復後 section 順序：**
1. Account（帳號）
2. Package Quota（包裹額度，免費用戶）
3. General（一般設定）
4. Notification（通知）
5. **Data Management（資料管理）** ← 新加入
6. Rate App（評分）
7. Support（支援）
8. About（關於）
9. Other Apps（其他作品）

---

### 問題 2：缺少 In-App Purchase Entitlement

**檔案：** `PackageTraker/PackageTraker.entitlements`

**問題描述：**
- 目前只有 Apple Sign In、App Groups、APNs 三個權限
- 缺少 `com.apple.developer.in-app-purchases`
- StoreKit 2 上架 App Store 需要此權限

**目前內容：**
```xml
<dict>
    <key>aps-environment</key>
    <string>development</string>
    <key>com.apple.developer.applesignin</key>
    <array><string>Default</string></array>
    <key>com.apple.security.application-groups</key>
    <array><string>group.com.kenny.PackageTraker</string></array>
</dict>
```

**修復方式：**
在 `</dict>` 前新增：
```xml
<key>com.apple.developer.in-app-purchases</key>
<true/>
```

---

### 問題 3：缺少 StoreKit Configuration 測試檔

**新檔案：** `PackageTraker/Configuration.storekit`

**問題描述：**
- 沒有 `.storekit` 設定檔，無法在模擬器本地測試 IAP
- 目前只能用 SubscriptionManager 的 `mockPurchase()` 模擬

**修復方式：**
建立 StoreKit 2 測試設定檔，包含：

| 產品 | Product ID | 價格 | 類型 |
|------|-----------|------|------|
| 月費 | `com.kenny.PackageTraker.pro.monthly` | NT$60 | Auto-Renewable |
| 年費 | `com.kenny.PackageTraker.pro.yearly` | NT$600 | Auto-Renewable |

- **Subscription Group:** PackageTraker Pro
- 年費產品標示「省 NT$120」（相比 12 個月月費 NT$720）

**額外步驟（手動）：**
建立檔案後需在 Xcode → Scheme → Run → Options → StoreKit Configuration 中選擇此檔案。

---

## 驗證清單

- [ ] Build 成功無錯誤
- [ ] 設定頁面可見「資料管理」區塊（含清除資料按鈕）
- [ ] Entitlements 檔案包含 IAP 權限
- [ ] Xcode 設定 StoreKit Configuration 後，PaywallView 可載入產品資訊
- [ ] 模擬器中可完成測試購買流程（不需 mock purchase）
