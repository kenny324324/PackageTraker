# Track.TW API 規格文件

> 文件版本: 1.0  
> 更新日期: 2026-02-05  
> API 版本: v1  
> Base URL: `https://track.tw/api/v1`

---

## 認證方式

所有 API 請求需要在 Header 中加入：

```
Authorization: Bearer {your_api_token}
Accept: application/json
Content-Type: application/json  (POST/PATCH 請求)
```

### 取得 API Token

前往 [Track.TW API 申請](https://track.tw/member/#/dashboard/api) 頁面申請。

---

## API 端點列表

| 方法 | 端點 | 說明 |
|------|------|------|
| GET | `/user/profile` | 取得使用者資訊 |
| GET | `/carrier/available` | 取得可用物流廠商列表 |
| POST | `/package/import` | 匯入包裹 |
| GET | `/package/all/{folder}` | 取得資料夾中的包裹列表 |
| GET | `/package/tracking/{uuid}` | 查詢包裹貨態詳情 |
| PATCH | `/package/state/{uuid}/{action}` | 編輯包裹狀態 |

---

## 端點詳細說明

### 1. GET /user/profile

取得目前登入使用者的帳號資訊。

#### Request

```bash
curl -H "Authorization: Bearer {token}" \
     -H "Accept: application/json" \
     https://track.tw/api/v1/user/profile
```

#### Response

```json
{
  "email": "user@example.com",
  "name": "使用者名稱",
  "picture_url": "https://...",
  "notify_type_id": 2,
  "telegram": false,
  "line": false
}
```

| 欄位 | 類型 | 說明 |
|------|------|------|
| `email` | string | 使用者 Email |
| `name` | string | 使用者名稱 |
| `picture_url` | string | 大頭貼 URL |
| `notify_type_id` | integer | 通知類型 ID |
| `telegram` | boolean | 是否已綁定 Telegram |
| `line` | boolean | 是否已綁定 LINE |

---

### 2. GET /carrier/available

取得系統支援的所有物流廠商列表。

#### Request

```bash
curl -H "Authorization: Bearer {token}" \
     -H "Accept: application/json" \
     https://track.tw/api/v1/carrier/available
```

#### Response

```json
[
  {
    "id": "9a980809-8865-4741-9f0a-3daaaa7d9e19",
    "name": "7-Eleven店到店",
    "logo": "01HJY26MAS9QKMK5HBHBBWQZRS.png"
  },
  {
    "id": "9a980968-0ecf-4ee5-8765-fbeaed8a524e",
    "name": "全家店到店",
    "logo": "01HNAJEA09Y69YP1J095VVDPEP.png"
  }
]
```

| 欄位 | 類型 | 說明 |
|------|------|------|
| `id` | string (UUID) | 物流廠商 ID |
| `name` | string | 物流廠商名稱 |
| `logo` | string | Logo 檔案名稱 |

#### 支援的物流廠商

| 物流商 | UUID |
|--------|------|
| 7-Eleven店到店 | `9a980809-8865-4741-9f0a-3daaaa7d9e19` |
| 全家店到店 | `9a980968-0ecf-4ee5-8765-fbeaed8a524e` |
| 萊爾富店到店 | `9a980b3f-450f-4564-b73e-2ebd867666b0` |
| OK mart店到店 | `9a980d97-1101-4adb-87eb-78266878b384` |
| 蝦皮店到店 | `9a98100c-c984-463d-82a6-ae86ec4e0b8a` |
| 中華郵政 (郵局) | `9a9812d2-c275-4726-9bdc-2ae5b4c42c73` |
| 黑貓宅急便 | `9a98160d-27e3-40ab-9357-9d81466614e0` |
| PChome網家速配 | `9a981858-a4f4-484c-82ad-f1da04dcc5be` |
| momo富昇物流 | `9a983a0c-2100-4da2-a98f-f7c83970dc35` |
| 新竹物流 | `9a9840bc-a5d9-4c4a-8cd2-a79031b4ad53` |
| 嘉里大榮物流 | `9a98424a-935f-4b23-9a94-a08e1db52944` |
| 宅配通 | `9a984351-dc4f-405b-971c-671220c75f21` |
| 順豐速運 | `9b39c083-c77d-45a9-b403-2112bcddb1ae` |
| 台灣快遞 | `9bec8b8e-6903-471d-b04c-a85c1ead56a9` |
| FedEx聯邦快遞 | `9b8d0e69-d3b7-4fff-a066-50f9a81d8064` |
| UPS優比速國際物流 | `9b6d1f55-5a40-40ba-a16d-219d1f762192` |
| DHL Express | `9e2f3446-d91a-4b23-aa11-8a4bc40bde38` |
| 關務署 (海關) | `9a98475f-1ba5-4371-bec5-b13cffd6d54b` |

> 完整列表請呼叫 API 獲取最新資料

---

### 3. POST /package/import

匯入新包裹進行追蹤。

#### Request

```bash
curl -X POST \
     -H "Authorization: Bearer {token}" \
     -H "Accept: application/json" \
     -H "Content-Type: application/json" \
     -d '{
       "carrier_id": "9a980809-8865-4741-9f0a-3daaaa7d9e19",
       "tracking_number": ["ABC123456", "DEF789012"],
       "notify_state": "inactive"
     }' \
     https://track.tw/api/v1/package/import
```

#### Request Body

| 欄位 | 類型 | 必填 | 說明 |
|------|------|------|------|
| `carrier_id` | string (UUID) | ✅ | 物流廠商 ID |
| `tracking_number` | string[] | ✅ | 追蹤號碼陣列（支援批次匯入） |
| `notify_state` | string | ✅ | 通知狀態 |

#### notify_state 可選值

| 值 | 說明 |
|----|------|
| `inactive` | 不啟用主動通知 |
| `active` | 啟用主動通知（需先綁定 LINE 或 Telegram） |

#### Response

成功時返回追蹤號碼對應的 UUID：

```json
{
  "ABC123456": "85448832-8f44-4ff2-bcdf-fb884b941eb1",
  "DEF789012": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

#### 錯誤回應範例

```json
{
  "message": "The tracking number field must be an array.",
  "errors": {
    "tracking_number": ["The tracking number field must be an array."],
    "notify_state": ["The notify state field is required."]
  }
}
```

---

### 4. GET /package/all/{folder}

取得指定資料夾中的包裹列表。

#### Path Parameters

| 參數 | 類型 | 說明 |
|------|------|------|
| `folder` | string | 資料夾名稱 |

#### folder 可選值

| 值 | 說明 |
|----|------|
| `inbox` | 收件匣（追蹤中的包裹） |
| `archive` | 封存區 |

#### Query Parameters

| 參數 | 類型 | 必填 | 說明 |
|------|------|------|------|
| `page` | integer | ✅ | 頁碼（從 1 開始） |
| `size` | integer | ✅ | 每頁筆數 |

#### Request

```bash
curl -H "Authorization: Bearer {token}" \
     -H "Accept: application/json" \
     "https://track.tw/api/v1/package/all/inbox?page=1&size=10"
```

#### Response

```json
{
  "current_page": 1,
  "data": [
    {
      "id": "6d5817c4-c967-4c0e-9209-343cf81f95b3",
      "created_at": "2026-02-05T07:53:11.000000Z",
      "updated_at": "2026-02-05T07:53:11.000000Z",
      "user_id": "a0fd5932-a4c6-4dd4-a57e-1f110f071fa6",
      "package_id": "a0faf98e-7087-4de1-bd38-176719b8f535",
      "note": null,
      "notify_state": "inactive",
      "state": "inbox",
      "package": {
        "id": "a0faf98e-7087-4de1-bd38-176719b8f535",
        "tracking_number": "TW268979373141Z",
        "carrier_id": "9a98100c-c984-463d-82a6-ae86ec4e0b8a",
        "carrier": {
          "id": "9a98100c-c984-463d-82a6-ae86ec4e0b8a",
          "name": "蝦皮店到店"
        },
        "latest_package_history": {
          "id": "a0fd1bba-436e-4f36-a24d-b8f72a4d63d3",
          "created_at": "2026-02-03T03:32:03.000000Z",
          "updated_at": "2026-02-03T03:32:03.000000Z",
          "package_id": "a0faf98e-7087-4de1-bd38-176719b8f535",
          "time": 1770042668,
          "status": "[中和福美 - 智取店] 買家取件成功",
          "checkpoint_status": "delivered"
        }
      }
    }
  ],
  "first_page_url": "https://track.tw/api/v1/package/all/inbox?page=1",
  "from": 1,
  "last_page": 1,
  "last_page_url": "https://track.tw/api/v1/package/all/inbox?page=1",
  "links": [...],
  "next_page_url": null,
  "path": "https://track.tw/api/v1/package/all/inbox",
  "per_page": 10,
  "prev_page_url": null,
  "to": 1,
  "total": 1
}
```

#### 回應欄位說明

##### 分頁資訊

| 欄位 | 類型 | 說明 |
|------|------|------|
| `current_page` | integer | 目前頁碼 |
| `per_page` | integer | 每頁筆數 |
| `total` | integer | 總筆數 |
| `last_page` | integer | 最後一頁頁碼 |
| `from` | integer | 本頁起始筆數 |
| `to` | integer | 本頁結束筆數 |
| `next_page_url` | string/null | 下一頁 URL |
| `prev_page_url` | string/null | 上一頁 URL |

##### data 陣列中的物件

| 欄位 | 類型 | 說明 |
|------|------|------|
| `id` | string (UUID) | 使用者包裹關聯 ID（用於 state API） |
| `package_id` | string (UUID) | 包裹 ID（用於 tracking API） |
| `note` | string/null | 備註 |
| `notify_state` | string | 通知狀態 |
| `state` | string | 包裹狀態（inbox/archive） |
| `package` | object | 包裹詳情 |

##### package 物件

| 欄位 | 類型 | 說明 |
|------|------|------|
| `id` | string (UUID) | 包裹 ID |
| `tracking_number` | string | 追蹤號碼 |
| `carrier_id` | string (UUID) | 物流廠商 ID |
| `carrier` | object | 物流廠商資訊 |
| `latest_package_history` | object | 最新追蹤紀錄 |

---

### 5. GET /package/tracking/{uuid}

查詢包裹的完整追蹤歷史。

#### Path Parameters

| 參數 | 類型 | 說明 |
|------|------|------|
| `uuid` | string (UUID) | 使用者包裹關聯 ID（從 `/package/all` 取得的 `id`） |

#### Request

```bash
curl -H "Authorization: Bearer {token}" \
     -H "Accept: application/json" \
     https://track.tw/api/v1/package/tracking/{uuid}
```

#### Response

```json
{
  "id": "a0faf98e-7087-4de1-bd38-176719b8f535",
  "created_at": "2026-02-02T02:04:51.000000Z",
  "updated_at": "2026-02-05T07:53:12.000000Z",
  "carrier_id": "9a98100c-c984-463d-82a6-ae86ec4e0b8a",
  "tracking_number": "TW268979373141Z",
  "metadata": null,
  "package_history": [
    {
      "package_id": "a0faf98e-7087-4de1-bd38-176719b8f535",
      "time": 1770042668,
      "status": "[中和福美 - 智取店] 買家取件成功",
      "checkpoint_status": "delivered",
      "created_at": "2026-02-03T03:32:03.000000Z"
    },
    {
      "package_id": "a0faf98e-7087-4de1-bd38-176719b8f535",
      "time": 1770040743,
      "status": "包裹已配達買家取件門市 - [中和福美 - 智取店]",
      "checkpoint_status": "transit",
      "created_at": "2026-02-03T03:32:03.000000Z"
    },
    {
      "package_id": "a0faf98e-7087-4de1-bd38-176719b8f535",
      "time": 1769849590,
      "status": "包裹抵達理貨中心，處理中",
      "checkpoint_status": "transit",
      "created_at": "2026-02-02T02:04:52.000000Z"
    },
    {
      "package_id": "a0faf98e-7087-4de1-bd38-176719b8f535",
      "time": 1769596074,
      "status": "賣家已寄件成功",
      "checkpoint_status": "transit",
      "created_at": "2026-02-02T02:04:52.000000Z"
    },
    {
      "package_id": "a0faf98e-7087-4de1-bd38-176719b8f535",
      "time": 1769577914,
      "status": "賣家將於確認訂單後出貨",
      "checkpoint_status": "transit",
      "created_at": "2026-02-02T02:04:52.000000Z"
    }
  ],
  "carrier": {
    "id": "9a98100c-c984-463d-82a6-ae86ec4e0b8a",
    "name": "蝦皮店到店"
  }
}
```

#### 回應欄位說明

| 欄位 | 類型 | 說明 |
|------|------|------|
| `id` | string (UUID) | 包裹 ID |
| `created_at` | string (ISO 8601) | 建立時間 |
| `updated_at` | string (ISO 8601) | 更新時間 |
| `carrier_id` | string (UUID) | 物流廠商 ID |
| `tracking_number` | string | 追蹤號碼 |
| `metadata` | object/null | 額外資料 |
| `package_history` | array | 追蹤歷史（按時間倒序） |
| `carrier` | object | 物流廠商資訊 |

#### package_history 物件

| 欄位 | 類型 | 說明 |
|------|------|------|
| `package_id` | string (UUID) | 包裹 ID |
| `time` | integer | Unix 時間戳（秒） |
| `status` | string | 狀態描述文字 |
| `checkpoint_status` | string | 狀態代碼 |
| `created_at` | string (ISO 8601) | 紀錄建立時間 |

#### checkpoint_status 可能的值

| 值 | 說明 |
|----|------|
| `transit` | 運送中 |
| `delivered` | 已送達/已取件 |
| `pending` | 等待中 |
| `exception` | 異常 |

---

### 6. PATCH /package/state/{uuid}/{action}

變更包裹的狀態（封存、刪除等）。

#### Path Parameters

| 參數 | 類型 | 說明 |
|------|------|------|
| `uuid` | string (UUID) | 使用者包裹關聯 ID |
| `action` | string | 操作類型 |

#### action 可選值

| 值 | 說明 |
|----|------|
| `archive` | 封存包裹 |
| `delete` | 刪除包裹 |

#### Request

```bash
curl -X PATCH \
     -H "Authorization: Bearer {token}" \
     -H "Accept: application/json" \
     https://track.tw/api/v1/package/state/{uuid}/archive
```

#### Response

```json
{
  "success": true
}
```

---

## 錯誤處理

### HTTP 狀態碼

| 狀態碼 | 說明 |
|--------|------|
| 200 | 請求成功 |
| 302 | 重新導向（通常是認證失敗） |
| 400 | 請求參數錯誤 |
| 401 | 未授權（Token 無效） |
| 404 | 找不到資源 |
| 422 | 驗證錯誤 |
| 429 | 請求過於頻繁 |

### 錯誤回應格式

```json
{
  "message": "錯誤描述",
  "errors": {
    "field_name": ["詳細錯誤訊息"]
  }
}
```

---

## 速率限制

| Header | 說明 |
|--------|------|
| `X-RateLimit-Limit` | 每分鐘請求上限 |
| `X-RateLimit-Remaining` | 剩餘可用請求數 |

目前觀察到的限制：**60 次/分鐘**

---

## 使用範例

### Swift 實作範例

```swift
import Foundation

struct TrackTwAPI {
    static let baseURL = "https://track.tw/api/v1"
    let token: String
    
    func makeRequest(endpoint: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)\(endpoint)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    
    // 取得物流廠商列表
    func getCarriers() async throws -> [Carrier] {
        let request = makeRequest(endpoint: "/carrier/available")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([Carrier].self, from: data)
    }
    
    // 匯入包裹
    func importPackage(carrierId: String, trackingNumbers: [String]) async throws -> [String: String] {
        var request = makeRequest(endpoint: "/package/import")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "carrier_id": carrierId,
            "tracking_number": trackingNumbers,
            "notify_state": "inactive"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([String: String].self, from: data)
    }
    
    // 查詢包裹追蹤
    func getTracking(uuid: String) async throws -> PackageTracking {
        let request = makeRequest(endpoint: "/package/tracking/\(uuid)")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(PackageTracking.self, from: data)
    }
}
```

---

## 注意事項

1. **Accept Header 必填**：所有請求必須加上 `Accept: application/json`，否則可能返回 HTML 頁面或 302 重新導向。

2. **tracking_number 必須是陣列**：即使只有一個追蹤號碼，也必須用陣列格式 `["ABC123"]`。

3. **UUID 區分**：
   - `id`（使用者包裹關聯 ID）：用於 `/package/state` 和 `/package/tracking`
   - `package_id`（包裹 ID）：內部使用

4. **主動通知限制**：`notify_state: "active"` 需要先在帳號設定中綁定 LINE 或 Telegram。

5. **時間格式**：
   - API 回傳的 `time` 欄位是 Unix 時間戳（秒）
   - `created_at` / `updated_at` 是 ISO 8601 格式

---

## 更新紀錄

| 日期 | 版本 | 說明 |
|------|------|------|
| 2026-02-05 | 1.0 | 初版文件 |
