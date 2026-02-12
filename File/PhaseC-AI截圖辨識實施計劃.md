# Phase C - AI 截圖辨識實施計劃

## 模型選擇：Gemini 2.5 Flash

### 選擇理由
- **成本最低**：每次請求 ~$0.0002 USD
- **免費額度最高**：1000 次/天（Google AI Studio Free Tier）
- **整合改動最小**：現有程式碼已用 Gemini REST API，只需改 model name
- **原生 JSON 模式**：支援 `responseMimeType: application/json`
- **圖片辨識能力強**：對 OCR + 結構化資料擷取表現優異

### 成本估算
| 使用情境 | 每日請求數 | 每月成本 (USD) |
|---------|-----------|---------------|
| 正常使用（免費額度內） | < 1000 | $0 |
| 中度使用 | 5,000 | $0.80 |
| 高度使用 | 10,000 | $1.80 |
| Pro 用戶平均 (20次/天) | 600/月 | $0.12 |

---

## 使用權限設計

### 階段 1：Beta 測試階段（現在）
所有測試用戶均可使用 AI 功能，用於觀察實際使用頻率和調整模型效果。

| 用戶類型 | AI 辨識權限 | 每日次數限制 | 說明 |
|---------|-------------|-------------|------|
| **測試用戶** | ✅ 可用 | 5 次/天 | 觀察實際使用頻率，調整 prompt |

**Beta 階段目標**：
- 驗證 AI 辨識準確度（目標：trackingNumber confidence > 90%）
- 收集錯誤案例，優化 system prompt
- 測試圖片壓縮策略（目前：1024px + JPEG 80%）
- 確認 API 延遲可接受（目標：< 3 秒）

---

### 階段 2：Public Release

#### 權限矩陣

| 用戶類型 | AI 辨識權限 | 每日次數限制 | 說明 |
|---------|-------------|-------------|------|
| **Free 用戶** | ❌ 完全不可用 | 0 次 | 點擊 AI 功能 → 顯示 PaywallView |
| **試用期用戶** | ✅ 可用 | 5 次/天 | 7 天試用期，首次使用時觸發 |
| **Pro 月費/年費** | ✅ 可用 | 50 次/天 | 正常用戶絕對夠用 |
| **Pro 終身買斷** | ✅ 可用 | 100 次/天 | 終身用戶給予更高額度 |

#### 試用期機制
- **觸發時機**：Free 用戶首次點擊 AI 截圖辨識功能時
- **試用彈窗**：
  ```
  標題：🎁 免費試用 AI 智能辨識
  內容：體驗 7 天 AI 截圖辨識功能
        • 自動擷取單號、物流商、取件資訊
        • 每天 5 次免費辨識
        • 隨時可升級 Pro 享 50 次/天

  按鈕：[開始試用] [稍後再說]
  ```
- **試用期資料儲存**：
  - Firestore: `/users/{uid}/aiTrial { startDate, isActive, usedCount }`
  - UserDefaults 本地快取（避免每次都查 Firestore）

#### 額度用完提示
**試用用戶（5次用完）**：
```
標題：今日 AI 辨識額度已用完
內容：升級 Pro 立即享 50 次/天

按鈕：[升級 Pro] [明天再用]
```

**Pro 用戶（50/100次用完）**：
```
標題：今日 AI 辨識額度已用完
內容：明天 00:00 (台灣時間) 額度將自動重置

按鈕：[知道了]
```

---

## 成本控制方案

### 方案 1：App 端限流（主要防禦）
在 `AIVisionService.swift` 實作：
- **用戶級別限流**：根據訂閱等級限制每日次數
- **計數器重置**：每天 00:00 (台灣時區) 自動重置
- **本地 + 雲端雙重驗證**：
  - UserDefaults 本地計數（快速檢查，離線可用）
  - Firestore 雲端計數（防止越獄/時間修改作弊）

### 方案 2：Google Cloud 預算警報（保險機制）
在 Google Cloud Console 設定：
- **每日預算上限**：$5 USD（超過自動停用 API）
- **警報閾值**：$1, $2.5, $4（Email 通知開發者）
- **最壞情況**：單月最多 $150 USD

### 方案 3：監控與應急響應
- **Firestore 每日統計**：記錄總請求數、各用戶請求數
- **異常偵測**：單一用戶超過 200 次/天 → 自動封鎖 + Email 通知
- **緊急開關**：`FeatureFlags.aiVisionEnabled = false` 可遠端關閉功能

---

## 實施步驟

### Step 1：升級 Gemini 模型（必須，2.0 Flash 將於 2026/3/31 停用）
- [x] 修改 `AIVisionService.swift` line 23: `gemini-2.0-flash` → `gemini-2.5-flash`

### Step 2：取得 Gemini API Key
1. 前往 [Google AI Studio](https://aistudio.google.com/app/apikey)
2. 登入 Google 帳號
3. 點擊「Get API Key」→「Create API Key」
4. 複製 API Key
5. 貼到 `PackageTraker/Secrets.swift`:
   ```swift
   static let geminiAPIKey = "YOUR_ACTUAL_KEY_HERE"
   ```

### Step 3：實作使用次數限流
建立新檔案 `AIUsageTracker.swift`，功能：
- 追蹤每日使用次數（本地 + Firestore）
- 根據訂閱等級檢查配額
- 試用期管理（7 天倒數、狀態追蹤）
- 台灣時區 00:00 自動重置計數器

### Step 4：修改 AIVisionService 整合限流
在 `analyzePackageImage()` 前加入檢查：
```swift
// 1. 檢查訂閱權限（已有）
guard SubscriptionManager.shared.hasAIAccess else {
    throw AIVisionError.subscriptionRequired
}

// 2. 檢查每日配額（新增）
try await AIUsageTracker.shared.checkAndIncrementUsage()

// 3. 呼叫 Gemini API
let result = try await callGeminiAPI(...)
```

### Step 5：UI 整合
- **AddPackageView**：
  - Free 用戶點 AI 卡片 → 彈出試用對話框
  - 試用/Pro 用戶額度用完 → 顯示相應提示
- **SettingsView**：
  - 新增「AI 辨識使用量」卡片（今日已用 X/50 次）
  - 試用用戶顯示「試用剩餘 X 天」

### Step 6：Firestore 資料結構
```
/users/{uid}
  ├── aiTrial { startDate, isActive, expiresAt }
  ├── aiUsage { date, count, resetAt }
  └── aiStats { totalUsed, lastUsedAt }
```

### Step 7：本地化字串
新增到 3 語言 `.strings` 檔案：
```
"ai.trial.title" = "免費試用 AI 智能辨識";
"ai.trial.message" = "體驗 7 天 AI 截圖辨識功能...";
"ai.quota.exceeded.trial" = "今日 AI 辨識額度已用完";
"ai.quota.exceeded.pro" = "明天 00:00 (台灣時間) 額度將自動重置";
"ai.usage.today" = "今日已用 %d/%d 次";
"ai.trial.daysLeft" = "試用剩餘 %d 天";
```

### Step 8：開啟功能
- 修改 `FeatureFlags.swift`: `aiVisionEnabled = true`

### Step 9：測試
- [x] Free 用戶點擊 AI → 彈出試用對話框
- [x] 試用用戶使用 5 次後 → 顯示額度用完提示
- [x] Pro 用戶正常使用 → 計數正確
- [x] Pro 用戶達到 50 次 → 顯示額度用完
- [x] 次日 00:00 → 計數器自動重置
- [x] 修改系統時間作弊 → 雲端驗證阻止
- [x] 離線使用 → 本地計數器運作，下次聯網時同步

---

## 風險評估

| 風險 | 影響 | 機率 | 緩解措施 |
|------|------|------|---------|
| 惡意用戶狂刷 API | 成本暴增 | 低 | App 限流 + Google 預算上限 |
| 越獄破解限流 | 繞過限制 | 中 | Firestore 雲端驗證 + 異常偵測 |
| Gemini API 不穩定 | 用戶體驗差 | 低 | 30 秒 timeout + 友善錯誤提示 |
| 辨識準確度不足 | 用戶抱怨 | 中 | Beta 測試調整 prompt + 所有欄位可編輯 |
| 免費額度用完 | 開始計費 | 低 | 1000次/天對消費者 app 很充裕 |

---

## 長期優化方向

### 優化 1：混合 OCR 策略（如果超過免費額度）
```
流程：
1. 先用本地 Tesseract OCR 嘗試辨識 (免費)
2. 若 confidence < 60% → 再呼叫 Gemini AI
3. 預估可減少 70-80% API 呼叫
```

### 優化 2：圖片快取（避免重複辨識）
```
1. 計算圖片 hash
2. 檢查 Firestore 是否有相同圖片的辨識結果
3. 有 → 直接返回快取結果 (省 API 費用)
4. 無 → 呼叫 API + 儲存結果
```

### 優化 3：進階 Pro 方案
如果 AI 功能很受歡迎，可推出：
- **Pro Plus** ($4.99/月)：無限次數 AI 辨識
- **企業方案** (商議)：API 直連、批次處理

---

## 參考資料

- [Gemini API Pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Gemini API Rate Limits](https://ai.google.dev/gemini-api/docs/rate-limits)
- [Gemini 2.0 Flash Deprecation](https://discuss.ai.google.dev/t/model-deprecations-and-replacements-gemini-flash-2-0/109757)
- [LLM Pricing Comparison 2026](https://www.cloudidr.com/llm-pricing)

---

## 版本歷史

| 日期 | 版本 | 變更 |
|------|------|------|
| 2026-02-12 | v1.0 | 初始版本，確定使用 Gemini 2.5 Flash + 限流策略 |
