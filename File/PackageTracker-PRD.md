# 📦 PackageTracker — 產品需求文件 (PRD)

**文件版本：** 1.0  
**建立日期：** 2026-02-02  
**負責人：** Sunny  
**專案代號：** PackageTracker  

---

## 一、Executive Summary

### 1.1 產品概述

PackageTracker 是一款個人使用的 iOS 原生 App，目標是**在單一介面中統一管理所有包裹的配送狀態**，涵蓋國際快遞、台灣宅配、超商取貨及電商訂單。App 採用 SwiftUI 開發，追求高質感的 UI/UX 體驗。

### 1.2 核心問題

目前追蹤包裹的體驗極度碎片化：國際包裹要開 AfterShip 或物流商官網、momo 訂單要開 momo App、蝦皮包裹要開蝦皮 App、超商取貨又要看簡訊或 email。使用者需要在 5 個以上的 App 之間來回切換，才能掌握所有包裹的狀態。

### 1.3 產品目標

- **統一入口：** 所有包裹狀態匯集到一個 App
- **最大自動化：** 透過 Email 解析自動匯入包裹，盡量減少手動操作
- **台灣在地化：** 完整支援台灣主流電商與物流商的追蹤需求
- **高質感 UI：** 媲美 Parcel、菜鳥等一線包裹追蹤 App 的視覺體驗

### 1.4 目標使用者

本 App 定位為個人使用，目標使用者即開發者本人。設計上以「在台灣頻繁網購、偶爾有國際包裹」的使用情境為主。

---

## 二、數據來源策略 (Data Sources)

這是本專案的核心架構決策。所有包裹追蹤的資料取得，依循一個基本原則：

> **不追電商平台，追物流商。** 電商負責「產出單號」，物流商負責「提供狀態」。

### 2.1 包裹匯入管道（單號從哪來）

| 優先級 | 管道 | 自動化程度 | 說明 |
|:---|:---|:---|:---|
| P0 | 手動輸入 + 智慧辨識 | 🔵 手動 | 使用者貼上單號，App 自動判斷物流商 |
| P1 | Share Extension | 🟡 半自動 | 使用者在任何 App 看到單號，透過系統分享選單匯入 |
| P2 | Gmail API 出貨通知解析 | 🟢 全自動 | OAuth 授權一次後，自動掃描出貨通知信、抽取物流單號 |

### 2.2 物流追蹤來源（狀態從哪來）

| 類型 | 物流商 | 追蹤方式 | 技術路線 |
|:---|:---|:---|:---|
| **國際快遞** | DHL / FedEx / UPS / 順豐 等 | AfterShip API | RESTful API，JSON 回傳 |
| **台灣宅配** | 黑貓宅急便 | Web Scraping（HTML 解析） | URLSession + SwiftSoup |
| **台灣宅配** | 新竹物流 | Web Scraping（HTML 解析） | URLSession + SwiftSoup |
| **台灣宅配** | 宅配通 | Web Scraping（HTML 解析） | URLSession + SwiftSoup |
| **台灣宅配** | 中華郵政 | Web Scraping | 可能需 WKWebView（頁面互動較複雜） |
| **超商取貨** | 7-11（大智通/綠界） | Web Scraping（HTML 解析） | URLSession，查詢頁為 ASP.NET Server Render |
| **超商取貨** | 全家 | Web Scraping | 需測試是否有圖形驗證碼 |
| **超商取貨** | 萊爾富 / OK | Web Scraping | 優先級低，後續支援 |
| **電商自有** | 蝦皮 | Deep Link 跳轉 | 提供跳轉按鈕，不直接追蹤 |

### 2.3 電商 → 物流商對照

| 電商平台 | 常用物流商 | 取得單號方式 |
|:---|:---|:---|
| **momo** | 黑貓、新竹物流、富昇物流 | 出貨通知 email 內含物流單號 |
| **PChome 24h** | 黑貓（大宗）、自有倉配 | 出貨通知 email |
| **蝦皮購物** | 黑貓、7-11 交貨便、全家店到店、蝦皮店到店 | 出貨通知 email / App 推播 |
| **博客來** | 宅配通、超商取貨 | 出貨通知 email |
| **Yahoo 購物** | 黑貓、新竹物流 | 出貨通知 email |

---

## 三、功能需求 (Feature Requirements)

### 3.1 功能優先級總覽

| 優先級 | 功能 | Phase |
|:---|:---|:---|
| **P0 - Must Have** | 手動新增包裹 + 物流商自動辨識 | Phase 1 |
| **P0 - Must Have** | AfterShip API 國際包裹追蹤 | Phase 1 |
| **P0 - Must Have** | 台灣宅配爬蟲（黑貓、新竹） | Phase 1 |
| **P0 - Must Have** | 統一包裹清單 + 狀態視覺化 | Phase 1 |
| **P0 - Must Have** | 本地資料持久化（SwiftData） | Phase 1 |
| **P1 - Should Have** | 7-11 / 全家超商取貨查詢 | Phase 2 |
| **P1 - Should Have** | Share Extension 匯入單號 | Phase 2 |
| **P1 - Should Have** | 包裹封存 / 歷史記錄 | Phase 2 |
| **P1 - Should Have** | 背景自動更新（Background App Refresh） | Phase 2 |
| **P2 - Nice to Have** | Gmail API 自動匯入 | Phase 3 |
| **P2 - Nice to Have** | 推播通知（本地通知） | Phase 3 |
| **P2 - Nice to Have** | 蝦皮 Deep Link 跳轉 | Phase 3 |
| **P2 - Nice to Have** | Widget（iOS 桌面小工具） | Phase 3 |
| **P3 - Future** | 更多物流商支援（萊爾富、OK、宅配通） | Phase 4 |
| **P3 - Future** | Apple Watch 伴隨 App | Phase 4 |
| **P3 - Future** | iCloud 同步 | Phase 4 |

---

### 3.2 User Stories 與驗收條件

#### Epic 1：包裹管理核心流程

**US-1.1 手動新增包裹**
```
身為使用者，我想要輸入物流單號來新增包裹追蹤，
這樣我就能在 App 中查看這個包裹的配送進度。

驗收條件：
- 使用者輸入單號後，App 自動辨識物流商（CarrierDetector）
- 若無法自動辨識，顯示物流商選擇清單供手動選擇
- 使用者可自訂包裹名稱（例如「momo 的藍牙耳機」）
- 新增後立即觸發一次狀態查詢
- 若單號格式明顯錯誤，顯示提示訊息
```

**US-1.2 包裹清單瀏覽**
```
身為使用者，我想要在首頁看到所有追蹤中包裹的清單，
並能快速辨別每個包裹的配送狀態。

驗收條件：
- 清單依「最新更新時間」排序
- 每張卡片顯示：包裹名稱、物流商、當前狀態、最後更新時間
- 不同狀態有對應的顏色與圖示（詳見 UI 規格）
- 支援下拉更新（Pull to Refresh）觸發全部包裹狀態刷新
- 空狀態（無包裹時）顯示引導畫面
```

**US-1.3 包裹詳情頁**
```
身為使用者，我想要查看某個包裹的完整配送時間軸，
這樣我能了解包裹目前到了哪裡、預計何時送達。

驗收條件：
- 以時間軸形式顯示所有物流節點（時間 + 地點 + 描述）
- 最新的節點在最上方
- 顯示物流商名稱與 Logo
- 提供「複製單號」按鈕
- 提供「在物流官網查看」的外部連結
```

**US-1.4 包裹刪除與封存**
```
身為使用者，我想要將已簽收的包裹封存或刪除，
這樣追蹤清單保持簡潔。

驗收條件：
- 左滑卡片可刪除或封存
- 已送達的包裹 App 自動建議封存
- 封存的包裹進入「歷史記錄」頁面，可隨時查看
- 刪除需二次確認
```

#### Epic 2：台灣在地物流追蹤

**US-2.1 黑貓宅急便追蹤**
```
身為使用者，我想要追蹤黑貓宅急便的包裹，
因為這是台灣最常用的宅配服務。

驗收條件：
- 輸入黑貓單號（12 碼純數字）後自動辨識
- 透過爬蟲取得完整物流時間軸
- 狀態映射到統一的 TrackingStatus enum
- 查詢失敗時顯示錯誤訊息，不讓 App crash
- 支援手動重新查詢
```

**US-2.2 新竹物流追蹤**
```
身為使用者，我想要追蹤新竹物流的包裹。

驗收條件：
- 與 US-2.1 相同的驗收標準，適用於新竹物流
```

**US-2.3 7-11 超商取貨查詢**
```
身為使用者，我想要查詢 7-11 超商取貨的包裹狀態，
這樣我知道何時可以去門市取貨。

驗收條件：
- 輸入取貨編號後，透過綠界查詢頁爬蟲取得狀態
- 狀態至少包含：處理中 / 配送中 / 已到店 / 已取貨
- 到店後以醒目方式提示
```

**US-2.4 全家超商取貨查詢**
```
身為使用者，我想要查詢全家超商取貨的包裹狀態。

驗收條件：
- 與 US-2.3 相同標準
- 若全家查詢頁有圖形驗證碼，降級為提供外部連結跳轉
```

#### Epic 3：智慧匯入

**US-3.1 Share Extension**
```
身為使用者，我想要從任何 App（email、Line、Safari）
透過系統分享功能將單號傳入 PackageTracker。

驗收條件：
- iOS Share Sheet 中出現 PackageTracker 選項
- 接收文字內容後自動偵測其中的物流單號
- 若偵測到單號，直接跳轉到新增確認畫面
- 若未偵測到，提示使用者手動輸入
```

**US-3.2 Gmail 自動匯入**
```
身為使用者，我想要連結 Gmail 帳號後，
App 自動從出貨通知信中抽取物流單號並建立追蹤。

驗收條件：
- 提供「連結 Gmail」按鈕，走 OAuth 2.0 授權流程
- 授權 scope 僅限 gmail.readonly
- 自動掃描近 7 天的出貨通知（寄件者 filter）
- 支援的電商 email parser：momo、PChome、蝦皮、博客來
- 抽取到的單號與物流商自動建立追蹤
- 已匯入的信件不重複處理（記錄 email message ID）
- 使用者可手動觸發重新掃描
- 提供「取消連結」功能
```

#### Epic 4：背景更新與通知

**US-4.1 背景自動更新**
```
身為使用者，我想要 App 在背景自動更新包裹狀態，
這樣每次打開 App 都能看到最新資訊。

驗收條件：
- 利用 iOS Background App Refresh 機制
- 系統允許時自動觸發所有追蹤中包裹的狀態更新
- 更新完成後將結果寫入本地資料庫
- 不影響電池續航（遵守 iOS 背景執行限制）
```

**US-4.2 本地推播通知**
```
身為使用者，當包裹狀態有重大變更時（例如到店、送達），
我想要收到推播通知。

驗收條件：
- 狀態從「配送中」變為「已到店」或「已送達」時觸發通知
- 通知內容包含包裹名稱與新狀態
- 使用者可在設定中關閉通知
```

---

## 四、技術架構 (Technical Architecture)

### 4.1 技術棧

| 層級 | 技術選型 | 說明 |
|:---|:---|:---|
| **UI 框架** | SwiftUI | iOS 原生，聲明式 UI |
| **最低支援版本** | iOS 17.0 | 使用 SwiftData、最新 SwiftUI API |
| **程式語言** | Swift 5.9+ | |
| **資料持久化** | SwiftData | Apple 原生 ORM，取代 Core Data |
| **網路請求** | URLSession（原生） | 不額外引入 Alamofire，減少依賴 |
| **HTML 解析** | SwiftSoup | Swift 版 Jsoup，用於爬蟲 |
| **JSON 解析** | Codable（原生） | 搭配 JSONDecoder.keyDecodingStrategy |
| **背景任務** | BGTaskScheduler | iOS 原生背景更新 API |
| **Gmail 整合** | Google Sign-In SDK + Gmail API | OAuth 2.0 + REST API |
| **架構模式** | MVVM | ViewModel + ObservableObject |

### 4.2 系統架構圖

```
┌──────────────────────────────────────────────────────────┐
│                    PackageTracker App                     │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────────── View Layer ──────────────────┐     │
│  │  PackageListView  │  PackageDetailView          │     │
│  │  AddPackageView   │  SettingsView               │     │
│  │  GmailSetupView   │  HistoryView                │     │
│  └─────────────────────────────────────────────────┘     │
│                          │                               │
│                          ▼                               │
│  ┌─────────────── ViewModel Layer ─────────────────┐     │
│  │  PackageListViewModel                           │     │
│  │    - packages: [Package]                        │     │
│  │    - refreshAll()                               │     │
│  │    - addPackage(trackingNumber:)                 │     │
│  │    - archivePackage(_:)                          │     │
│  │                                                 │     │
│  │  PackageDetailViewModel                         │     │
│  │    - trackingEvents: [TrackingEvent]             │     │
│  │    - refreshStatus()                            │     │
│  │                                                 │     │
│  │  GmailImportViewModel                           │     │
│  │    - scanEmails()                               │     │
│  │    - parseShipmentNotification(_:)              │     │
│  └─────────────────────────────────────────────────┘     │
│                          │                               │
│                          ▼                               │
│  ┌──────────── Service / Repository Layer ─────────┐     │
│  │                                                 │     │
│  │  ┌─── TrackingService (Protocol) ────────────┐  │     │
│  │  │  func track(number:carrier:) async throws  │  │     │
│  │  │       -> TrackingResult                    │  │     │
│  │  └───────────────────────────────────────────┘  │     │
│  │        ▲              ▲              ▲          │     │
│  │        │              │              │          │     │
│  │  ┌─────────┐  ┌─────────────┐  ┌──────────┐   │     │
│  │  │AfterShip│  │TW Logistics │  │ Gmail    │   │     │
│  │  │ Service │  │  Scrapers   │  │ Service  │   │     │
│  │  └─────────┘  └─────────────┘  └──────────┘   │     │
│  │                     ▲                           │     │
│  │          ┌──────────┼──────────┐               │     │
│  │          │          │          │               │     │
│  │     ┌────────┐ ┌────────┐ ┌────────┐         │     │
│  │     │ 黑貓   │ │ 新竹   │ │ 7-11   │ ...     │     │
│  │     │Scraper │ │Scraper │ │Scraper │         │     │
│  │     └────────┘ └────────┘ └────────┘         │     │
│  │                                                 │     │
│  │  ┌─── CarrierDetector ───────────────────────┐  │     │
│  │  │  func detect(trackingNumber:) -> Carrier?  │  │     │
│  │  │  （正則匹配辨識物流商）                      │  │     │
│  │  └───────────────────────────────────────────┘  │     │
│  │                                                 │     │
│  │  ┌─── PackageRepository ─────────────────────┐  │     │
│  │  │  SwiftData ModelContext CRUD               │  │     │
│  │  └───────────────────────────────────────────┘  │     │
│  └─────────────────────────────────────────────────┘     │
│                          │                               │
│                          ▼                               │
│  ┌──────────────── Data Layer ─────────────────────┐     │
│  │  SwiftData Models                               │     │
│  │  ┌─────────┐  ┌──────────────┐  ┌───────────┐  │     │
│  │  │ Package │  │ TrackingEvent│  │ GmailSync │  │     │
│  │  └─────────┘  └──────────────┘  └───────────┘  │     │
│  └─────────────────────────────────────────────────┘     │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  Extensions                                              │
│  ┌─────────────────┐  ┌─────────────────────────────┐    │
│  │ Share Extension  │  │ Background Task Scheduler   │    │
│  └─────────────────┘  └─────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
                          │
            ┌─────────────┼─────────────┐
            ▼             ▼             ▼
     ┌────────────┐ ┌──────────┐ ┌───────────┐
     │ AfterShip  │ │ 物流商   │ │ Gmail     │
     │ REST API   │ │ 查詢網頁 │ │ REST API  │
     └────────────┘ └──────────┘ └───────────┘
```

### 4.3 核心資料模型

```swift
// MARK: - 統一包裹狀態

enum TrackingStatus: String, Codable, CaseIterable {
    case pending        // 待處理（剛建立追蹤）
    case infoReceived   // 已接收資訊（物流商已收到單號）
    case inTransit      // 運輸中
    case outForDelivery // 配送中（最後一哩）
    case arrivedAtStore // 已到店（超商取貨專用）
    case delivered      // 已送達 / 已取貨
    case exception      // 異常（退件、遺失等）
    case expired        // 查無此單 / 已過期
}

// MARK: - 物流商定義

enum Carrier: String, Codable, CaseIterable {
    // 國際（走 AfterShip）
    case dhl, fedex, ups, sfExpress, yanwen, cainiao
    // 台灣宅配（走本地爬蟲）
    case tcat           // 黑貓宅急便
    case hct            // 新竹物流
    case ecan           // 宅配通
    case postTW         // 中華郵政
    // 超商取貨（走本地爬蟲）
    case sevenEleven    // 7-11 交貨便 / 大智通
    case familyMart     // 全家店到店
    case hiLife         // 萊爾富
    case okMart         // OK 超商
    // 電商自有（僅 Deep Link）
    case shopee         // 蝦皮店到店
    // 其他
    case other

    var trackingMethod: TrackingMethod {
        switch self {
        case .dhl, .fedex, .ups, .sfExpress, .yanwen, .cainiao:
            return .aftership
        case .tcat, .hct, .ecan, .postTW,
             .sevenEleven, .familyMart, .hiLife, .okMart:
            return .scraper
        case .shopee:
            return .deepLink
        case .other:
            return .manual
        }
    }
}

enum TrackingMethod {
    case aftership  // 透過 AfterShip API
    case scraper    // 透過本地網頁爬蟲
    case deepLink   // 僅提供跳轉外部 App
    case manual     // 手動更新
}

// MARK: - SwiftData Models

@Model
class Package {
    var id: UUID
    var trackingNumber: String
    var carrier: Carrier
    var customName: String?          // 使用者自訂名稱
    var sourcePlatform: String?      // 來源電商（momo / PChome 等）
    var currentStatus: TrackingStatus
    var lastUpdated: Date
    var createdAt: Date
    var isArchived: Bool
    var aftershipId: String?         // AfterShip tracking ID（若適用）
    var gmailMessageId: String?      // 對應的 Gmail message ID（防重複匯入）

    @Relationship(deleteRule: .cascade)
    var events: [TrackingEvent]
}

@Model
class TrackingEvent {
    var id: UUID
    var timestamp: Date
    var status: TrackingStatus
    var description: String          // 物流節點描述（例：「包裹已到達台北轉運中心」）
    var location: String?            // 地點（若有）
    var rawData: String?             // 原始資料（debug 用）

    var package: Package?
}

@Model
class GmailSyncRecord {
    var id: UUID
    var gmailMessageId: String       // Gmail message ID
    var emailSubject: String
    var emailFrom: String
    var processedAt: Date
    var extractedTrackingNumber: String?
    var extractedCarrier: Carrier?
    var wasSuccessful: Bool
}
```

### 4.4 物流商辨識邏輯 (CarrierDetector)

```swift
struct CarrierDetector {

    struct DetectionResult {
        let carrier: Carrier
        let confidence: Double    // 0.0 ~ 1.0
    }

    /// 台灣本地物流商辨識規則
    static let patterns: [(regex: String, carrier: Carrier, confidence: Double)] = [
        // 黑貓宅急便：12 碼純數字
        (#"^\d{12}$"#,                        .tcat,         0.8),
        // 新竹物流：數字為主，通常 10-12 碼
        (#"^\d{10,12}$"#,                     .hct,          0.5),  // 與黑貓重疊，需降低信心度
        // 7-11 交貨便：常見 TW 開頭 + 數字
        (#"^TW\d{12,15}[A-Z]?$"#,            .sevenEleven,  0.9),
        // 綠界 ECPay 格式
        (#"^\d{10,13}$"#,                     .sevenEleven,  0.4),  // 需使用者確認
        // 全家店到店：特定前綴
        (#"^[A-Z]{2}\d{10,13}$"#,             .familyMart,   0.6),
        // 中華郵政國際：2 字母 + 9 數字 + 2 字母（如 RR123456789TW）
        (#"^[A-Z]{2}\d{9}TW$"#,              .postTW,       0.95),
        // 中華郵政國內掛號
        (#"^\d{13}$"#,                        .postTW,       0.4),
        // 順豐速運
        (#"^SF\d{12,13}$"#,                  .sfExpress,    0.95),
    ]

    static func detect(_ trackingNumber: String) -> [DetectionResult] {
        let trimmed = trackingNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        var results: [DetectionResult] = []

        for pattern in patterns {
            if trimmed.range(of: pattern.regex, options: .regularExpression) != nil {
                results.append(DetectionResult(
                    carrier: pattern.carrier,
                    confidence: pattern.confidence
                ))
            }
        }

        return results.sorted { $0.confidence > $1.confidence }
    }
}
```

### 4.5 爬蟲架構（策略模式）

```swift
// MARK: - 統一追蹤結果

struct TrackingResult {
    let trackingNumber: String
    let carrier: Carrier
    let currentStatus: TrackingStatus
    let events: [TrackingEventDTO]
    let rawResponse: String?         // 保留原始 HTML/JSON 供 debug
}

struct TrackingEventDTO {
    let timestamp: Date
    let status: TrackingStatus
    let description: String
    let location: String?
}

// MARK: - 追蹤服務協定

protocol TrackingServiceProtocol {
    var supportedCarriers: [Carrier] { get }
    func track(number: String, carrier: Carrier) async throws -> TrackingResult
}

// MARK: - 各物流商爬蟲實作（範例：黑貓）

final class TcatScraper: TrackingServiceProtocol {
    let supportedCarriers: [Carrier] = [.tcat]

    func track(number: String, carrier: Carrier) async throws -> TrackingResult {
        // 1. 發送 HTTP 請求到黑貓查詢頁
        // 2. 用 SwiftSoup 解析 HTML
        // 3. 抽取物流節點資訊
        // 4. 映射到統一的 TrackingResult
        ...
    }
}

// MARK: - 統一追蹤管理器

final class TrackingManager {
    private let services: [TrackingServiceProtocol]

    init() {
        self.services = [
            AfterShipService(),      // 國際快遞
            TcatScraper(),           // 黑貓
            HctScraper(),            // 新竹物流
            SevenElevenScraper(),    // 7-11
            FamilyMartScraper(),     // 全家
            // ... 更多物流商
        ]
    }

    func track(number: String, carrier: Carrier) async throws -> TrackingResult {
        guard let service = services.first(where: {
            $0.supportedCarriers.contains(carrier)
        }) else {
            throw TrackingError.unsupportedCarrier(carrier)
        }
        return try await service.track(number: number, carrier: carrier)
    }
}
```

### 4.6 Gmail Email Parser 架構

```swift
// MARK: - Email Parser Protocol

protocol EmailParserProtocol {
    /// 此 parser 支援的寄件者 email 地址（用於篩選）
    var senderPatterns: [String] { get }

    /// 從 email HTML body 中抽取物流資訊
    func parse(subject: String, body: String) -> EmailParseResult?
}

struct EmailParseResult {
    let trackingNumber: String
    let carrier: Carrier?            // 若能從信件判斷出物流商
    let sourcePlatform: String       // 電商平台名稱
    let productName: String?         // 商品名稱（若能抽取）
    let estimatedDelivery: Date?     // 預計到貨日（若有）
}

// MARK: - 各電商 Parser 實作

final class MomoEmailParser: EmailParserProtocol {
    let senderPatterns = [
        "service@momoshop.com.tw",
        "noreply@momoshop.com.tw"
    ]

    func parse(subject: String, body: String) -> EmailParseResult? {
        // 從 momo 出貨通知信的 HTML 中：
        // 1. 用正則或 SwiftSoup 找到「物流單號」欄位
        // 2. 判斷物流商（信件中通常會寫「黑貓」「新竹物流」等）
        // 3. 回傳結構化結果
        ...
    }
}

final class PChomeEmailParser: EmailParserProtocol { ... }
final class ShopeeEmailParser: EmailParserProtocol { ... }
final class BooksEmailParser: EmailParserProtocol { ... }  // 博客來

// MARK: - Gmail 掃描服務

final class GmailScanService {
    private let parsers: [EmailParserProtocol] = [
        MomoEmailParser(),
        PChomeEmailParser(),
        ShopeeEmailParser(),
        BooksEmailParser(),
    ]

    /// 所有支援的寄件者，用於 Gmail API query filter
    var allSenderFilters: String {
        let senders = parsers.flatMap { $0.senderPatterns }
        return senders.map { "from:\($0)" }.joined(separator: " OR ")
    }

    /// 掃描 Gmail 並回傳解析結果
    func scanAndParse() async throws -> [EmailParseResult] {
        // 1. 用 Gmail API 搜尋：query = allSenderFilters + newer_than:7d
        // 2. 取得符合條件的 email 清單
        // 3. 過濾已處理過的 message ID
        // 4. 對每封信嘗試所有 parser
        // 5. 回傳解析成功的結果
        ...
    }
}
```

---

## 五、UI/UX 設計規格

### 5.1 頁面結構

```
TabView
├── 📦 包裹（PackageListView）       ← 主頁
│   ├── 追蹤中 Section
│   └── 已送達 Section（最近 7 天）
├── 📂 歷史（HistoryView）           ← 封存的包裹
└── ⚙️ 設定（SettingsView）
     ├── Gmail 連結
     ├── 通知設定
     └── 關於
```

### 5.2 物流狀態視覺系統

| 狀態 | 顏色 | SF Symbol | 說明 |
|:---|:---|:---|:---|
| pending | `Color.gray` | `clock` | 待處理 |
| infoReceived | `Color.orange` | `doc.text` | 已收到資訊 |
| inTransit | `Color.blue` | `shippingbox` | 運輸中 |
| outForDelivery | `Color.indigo` | `bicycle` | 外出配送中 |
| arrivedAtStore | `Color.purple` | `building.2` | 已到超商門市 |
| delivered | `Color.green` | `checkmark.circle.fill` | 已送達 |
| exception | `Color.red` | `exclamationmark.triangle` | 異常 |
| expired | `Color.secondary` | `xmark.circle` | 查無 / 過期 |

### 5.3 卡片設計

```
┌─────────────────────────────────────────┐
│  🟦  momo 藍牙耳機                      │
│      黑貓宅急便 · 1234 5678 9012         │
│                                         │
│  🔵 運輸中                     2 小時前   │
│     包裹已從台北轉運中心發出              │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  🟩  蝦皮手機殼                          │
│      7-11 交貨便 · TW268979373141Z       │
│                                         │
│  🟣 已到店（7-11 中和景安店）    30 分鐘前  │
│     請於 7 天內前往取貨                    │
└─────────────────────────────────────────┘
```

### 5.4 設計原則

- 使用 SwiftUI 原生元件，遵循 Apple Human Interface Guidelines
- 卡片使用 `.background(.regularMaterial)` 搭配圓角，營造質感
- 支援 Dark Mode
- 支援 Dynamic Type（無障礙字體大小）
- 動畫使用 `.spring()` 保持 iOS 原生感
- 空狀態使用 `ContentUnavailableView`（iOS 17+）

---

## 六、開發階段規劃 (Development Phases)

### Phase 1：核心追蹤功能（預估 3-4 週）

**目標：App 能跑起來，手動追蹤包裹可用。**

| 週次 | 任務 | 產出 |
|:---|:---|:---|
| W1 | 專案初始化、SwiftData 模型建立、基本 MVVM 架構 | Xcode 專案骨架 |
| W1 | CarrierDetector 實作（正則辨識物流商） | 可單元測試的辨識模組 |
| W2 | AfterShip API 串接（Service 層） | 國際包裹追蹤可用 |
| W2 | 黑貓宅急便爬蟲實作 | 台灣宅配追蹤可用 |
| W3 | 新竹物流爬蟲實作 | 第二個台灣物流商 |
| W3 | TrackingManager 統一管理器 | 所有 Service 透過統一介面調用 |
| W3-W4 | UI 開發：PackageListView、AddPackageView、PackageDetailView | 完整的主要 UI 畫面 |
| W4 | 下拉刷新、錯誤處理、Loading 狀態 | 完善使用體驗 |

**Phase 1 完成標準：**
- 能手動輸入單號、自動辨識物流商
- 能追蹤 AfterShip 支援的國際快遞
- 能追蹤黑貓、新竹物流的宅配包裹
- 包裹清單有完整的狀態視覺化
- 資料持久化到 SwiftData

### Phase 2：台灣在地化 + Share Extension（預估 2-3 週）

**目標：覆蓋台灣超商取貨場景，新增半自動匯入方式。**

| 週次 | 任務 | 產出 |
|:---|:---|:---|
| W5 | 7-11 綠界查詢頁爬蟲 | 7-11 超商取貨可追蹤 |
| W5 | 全家查詢爬蟲（含驗證碼降級方案） | 全家超商取貨可追蹤 |
| W6 | Share Extension 開發 | 從任何 App 分享單號進來 |
| W6 | 包裹封存 / 歷史記錄 | 完整的包裹生命週期管理 |
| W7 | Background App Refresh | 背景自動更新狀態 |
| W7 | 本地推播通知（到店/送達通知） | 被動接收重要狀態變更 |

**Phase 2 完成標準：**
- 支援 7-11 與全家超商取貨查詢
- Share Extension 可從 Line / email / Safari 匯入單號
- App 背景自動更新包裹狀態
- 包裹送達或到店時推播通知

### Phase 3：Gmail 自動化（預估 3-4 週）

**目標：實現最接近「全自動」的體驗。**

| 週次 | 任務 | 產出 |
|:---|:---|:---|
| W8 | Google Sign-In SDK 整合、OAuth 流程 | Gmail 授權連結可用 |
| W9 | Gmail API 串接（email 列表、內容讀取） | 可搜尋及讀取出貨通知信 |
| W9-W10 | momo Email Parser | 自動解析 momo 出貨通知 |
| W10 | PChome / 蝦皮 / 博客來 Email Parser | 支援更多電商 |
| W11 | 整合測試、重複匯入防護、錯誤處理 | 穩定的自動匯入流程 |
| W11 | 蝦皮 Deep Link 跳轉 | 快速開啟蝦皮 App 查看 |

**Phase 3 完成標準：**
- Gmail 授權一次後自動掃描出貨通知
- 支援 momo / PChome / 蝦皮 / 博客來 的 email 解析
- 已匯入的 email 不重複處理
- 使用者打開 App 即看到自動匯入的包裹

### Phase 4：進階功能（未來規劃）

- iOS Widget（桌面小工具顯示最新包裹狀態）
- 更多物流商支援（萊爾富、OK、宅配通）
- iCloud 同步（跨裝置）
- Apple Watch 伴隨 App
- Siri Shortcuts 整合（「嘿 Siri，我的包裹到了嗎？」）

---

## 七、風險評估與因應

### 7.1 技術風險

| 風險 | 發生機率 | 影響程度 | 因應策略 |
|:---|:---|:---|:---|
| 物流商網站改版導致爬蟲失效 | **高** | 高 | 策略模式解耦，每個爬蟲獨立，壞一個不影響其他。定期手動驗證。 |
| 全家查詢頁有圖形驗證碼 | 中 | 中 | 降級方案：提供「在瀏覽器開啟」按鈕跳轉外部查詢。 |
| AfterShip 免費額度不夠 | 低 | 中 | 個人使用通常 50 筆/月足夠。超出則升級或改用物流商官方 API。 |
| Gmail API OAuth 審核嚴格 | 低 | 中 | 使用 Google Cloud 測試模式，自己帳號加入測試用戶，不需正式審核。 |
| iOS Background Fetch 執行頻率不可控 | **高** | 低 | 預期行為，搭配「打開 App 時立即刷新」作為補充。 |
| 物流商查詢頁需 JavaScript 渲染 | 中 | 中 | 需實測。若遇到，該物流商改用 WKWebView 隱藏式載入。 |

### 7.2 產品風險

| 風險 | 因應策略 |
|:---|:---|
| Email 格式改版導致 parser 失效 | Parser 內建 fallback：若正則匹配失敗，嘗試寬鬆匹配；若仍失敗，標記為「需手動確認」。 |
| 多個物流商單號格式重疊（如黑貓 vs 新竹都是 12 碼數字） | CarrierDetector 回傳多個候選結果加信心度分數，讓使用者確認。 |
| 包裹太多造成 API 呼叫過頻 | 對爬蟲實施 rate limiting；已送達包裹停止輪詢；分批更新。 |

---

## 八、技術備忘 (Technical Notes)

### 8.1 AfterShip API 要點

- API Base URL: `https://api.aftership.com/v4`
- 認證方式: Header `as-api-key: {YOUR_API_KEY}`
- 免費方案: 50 trackings/month
- 注意：`POST /couriers/detect` Body 為 `{"tracking_number": "..."}`
- 注意：`POST /trackings` Body 需包在 `{"tracking": {...}}` 之下
- JSON 命名風格: snake_case → Swift Codable 用 `.convertFromSnakeCase`

### 8.2 台灣物流商查詢 URL

| 物流商 | 查詢 URL | 備註 |
|:---|:---|:---|
| 黑貓 | `https://www.t-cat.com.tw/inquire/trace.aspx?no={單號}` | 需測試是否為 Server Render |
| 新竹物流 | `https://www.hct.com.tw/search/searchgoods_con.aspx?no={單號}` | 待實測 |
| 7-11 綠界 | `https://trace.ecpay.com.tw/tps/Trace.aspx?SNo={單號}` | ASP.NET，大機率 Server Render |
| 中華郵政 | `https://postserv.post.gov.tw/pstmail/main_mail.html` | 互動較複雜 |

### 8.3 第三方套件依賴

| 套件 | 用途 | 安裝方式 |
|:---|:---|:---|
| **SwiftSoup** | HTML 解析（爬蟲用） | Swift Package Manager |
| **Google Sign-In for iOS** | Gmail OAuth 2.0 | SPM |
| **GoogleAPIClientForRESTCore** | Gmail API 呼叫 | SPM |
| **KeychainAccess**（選用） | 安全儲存 API Key / Token | SPM |

### 8.4 iOS 權限需求

| 權限 | 用途 | 觸發時機 |
|:---|:---|:---|
| 通知 (`UNUserNotificationCenter`) | 推播包裹狀態變更 | 首次開啟 App 或進入設定時請求 |
| 背景更新 (`BGTaskScheduler`) | 背景自動刷新包裹狀態 | Info.plist 宣告，無需使用者授權 |
| 網路 | API 呼叫與爬蟲 | 預設允許 |

---

## 九、Definition of Done

整個專案在以下條件全部達成時視為 v1.0 完成：

- [ ] 手動輸入單號、自動辨識物流商，建立追蹤
- [ ] AfterShip API 追蹤國際包裹（完整時間軸）
- [ ] 黑貓宅急便網頁爬蟲追蹤可用
- [ ] 新竹物流網頁爬蟲追蹤可用
- [ ] 7-11 超商取貨爬蟲查詢可用
- [ ] 包裹清單 UI 含狀態顏色 + 圖示
- [ ] 包裹詳情頁含完整時間軸
- [ ] 下拉刷新更新所有包裹
- [ ] SwiftData 資料持久化
- [ ] Share Extension 可從外部 App 匯入單號
- [ ] Gmail 連結後自動掃描出貨通知
- [ ] 支援 momo / PChome 出貨信解析
- [ ] 背景自動更新 + 到店/送達推播通知
- [ ] 支援 Dark Mode
- [ ] 無 Crash、基本錯誤處理完善

---

*文件結束。本 PRD 將隨開發進展持續更新。*
