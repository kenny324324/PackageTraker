# Gmail 連結功能設定指南

本文件說明如何設定 Gmail OAuth 認證，以啟用從郵件自動擷取物流資訊的功能。

## 1. Google Cloud Console 設定

### 1.1 建立專案

1. 前往 [Google Cloud Console](https://console.cloud.google.com/)
2. 點擊「選取專案」→「新增專案」
3. 輸入專案名稱（例如：PackageTraker）
4. 點擊「建立」

### 1.2 啟用 Gmail API

1. 在左側選單中選擇「API 和服務」→「程式庫」
2. 搜尋「Gmail API」
3. 點擊「Gmail API」
4. 點擊「啟用」

### 1.3 設定 OAuth 同意畫面

1. 在左側選單中選擇「API 和服務」→「OAuth 同意畫面」
2. 選擇「外部」使用者類型
3. 填寫應用程式資訊：
   - 應用程式名稱：PackageTraker
   - 使用者支援電子郵件：您的 Email
   - 開發人員聯絡資訊：您的 Email
4. 點擊「儲存並繼續」

### 1.4 設定範圍

1. 點擊「新增或移除範圍」
2. 搜尋並選擇以下範圍：
   - `https://www.googleapis.com/auth/gmail.readonly`（讀取郵件）
   - `email`（取得使用者 Email）
   - `profile`（取得使用者基本資訊）
3. 點擊「更新」
4. 點擊「儲存並繼續」

### 1.5 新增測試使用者

1. 點擊「新增使用者」
2. 輸入您要測試的 Gmail 帳號
3. 點擊「儲存並繼續」

### 1.6 建立 OAuth 憑證

1. 在左側選單中選擇「API 和服務」→「憑證」
2. 點擊「建立憑證」→「OAuth 用戶端 ID」
3. 應用程式類型選擇「iOS」
4. 填寫資訊：
   - 名稱：PackageTraker iOS
   - 軟體包 ID：您的 Bundle Identifier（例如：com.yourcompany.PackageTraker）
5. 點擊「建立」
6. **記錄產生的 Client ID**（格式：xxx.apps.googleusercontent.com）

---

## 2. Xcode 專案設定

### 2.1 Info.plist 配置

在 `Info.plist` 中新增以下設定：

```xml
<!-- Google Sign-In Client ID -->
<key>GIDClientID</key>
<string>YOUR_CLIENT_ID.apps.googleusercontent.com</string>

<!-- URL Scheme for OAuth callback -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_CLIENT_ID</string>
        </array>
    </dict>
</array>

<!-- Background Tasks -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.packagetraker.emailsync</string>
</array>
```

**注意：** 將 `YOUR_CLIENT_ID` 替換為您在 Google Cloud Console 取得的 Client ID（不含 `.apps.googleusercontent.com` 後綴）。

### 2.2 Xcode Capabilities

在 Xcode 中啟用以下 Capabilities：

1. 選擇專案 → Targets → Signing & Capabilities
2. 點擊「+ Capability」
3. 新增「Background Modes」，並勾選：
   - ✅ Background fetch
   - ✅ Background processing

---

## 3. 完整 Info.plist 範例

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- 其他現有設定... -->

    <!-- Google OAuth -->
    <key>GIDClientID</key>
    <string>123456789012-abcdefghijklmnop.apps.googleusercontent.com</string>

    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>com.googleusercontent.apps.123456789012-abcdefghijklmnop</string>
            </array>
        </dict>
    </array>

    <!-- Background Tasks -->
    <key>BGTaskSchedulerPermittedIdentifiers</key>
    <array>
        <string>com.packagetraker.emailsync</string>
    </array>

    <key>UIBackgroundModes</key>
    <array>
        <string>fetch</string>
        <string>processing</string>
    </array>
</dict>
</plist>
```

---

## 4. 驗證設定

### 4.1 測試 OAuth 登入

1. 執行 App
2. 進入「設定」頁面
3. 點擊「連結 Email」按鈕
4. 完成 Google 登入流程
5. 授權讀取郵件權限
6. 確認返回 App 後顯示已連結狀態

### 4.2 測試郵件同步

1. 確保 Gmail 中有物流相關郵件（蝦皮、momo、PChome 等）
2. 在包裹列表下拉刷新
3. 確認自動解析並新增包裹

### 4.3 測試背景同步

1. 連結 Email 後
2. 將 App 切換至背景
3. 等待 15 分鐘以上
4. 檢查是否有新包裹被自動新增

---

## 5. 故障排除

### 問題：登入時出現「未授權的用戶端」

**解決方案：**
- 確認 Bundle Identifier 與 Google Cloud Console 設定一致
- 確認 Client ID 正確填入 Info.plist

### 問題：登入後無法返回 App

**解決方案：**
- 確認 URL Scheme 正確設定
- 格式應為：`com.googleusercontent.apps.{CLIENT_ID}`

### 問題：無法讀取郵件

**解決方案：**
- 確認已授權 `gmail.readonly` 範圍
- 確認測試帳號已加入 OAuth 同意畫面的測試使用者

### 問題：背景同步不執行

**解決方案：**
- 確認 Background Modes 已正確設定
- iOS 會根據使用者習慣智慧排程，可能不會立即執行

---

## 6. 隱私與安全

- App 僅請求「唯讀」郵件權限，不會修改或刪除郵件
- OAuth tokens 使用 iOS Keychain 安全儲存
- 使用者可隨時在設定中解除連結
- 郵件內容僅在本機處理，不會上傳至任何伺服器

---

## 7. 支援的郵件來源

| 來源 | Sender 特徵 | 支援程度 |
|------|------------|---------|
| 蝦皮購物 | @shopee.tw, @spx.tw | ✅ 完整支援 |
| momo 購物 | @momo.com.tw | ✅ 完整支援 |
| PChome | @pchome.com.tw | ✅ 完整支援 |
| 7-11 交貨便 | @7-11.com.tw | ✅ 完整支援 |
| 全家店到店 | @family.com.tw | ✅ 完整支援 |
| 黑貓宅急便 | @t-cat.com.tw | ✅ 完整支援 |
| 順豐速運 | @sf-express.com | ✅ 完整支援 |
