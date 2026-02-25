# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PackageTraker** (取貨吧) is an iOS package tracking app targeting the Taiwan market. It helps users track packages from 18+ carriers and manage pickups from convenience stores and logistics centers.

- **Technology**: SwiftUI + SwiftData (local database) + Firebase (Auth, Firestore, FCM) + StoreKit 2
- **Target**: iOS 26+ (dark mode only, `.preferredColorScheme(.dark)`)
- **Project Type**: Xcode project (no SPM workspace)
- **Localization**: 3 languages (Traditional Chinese `zh-Hant`, Simplified Chinese `zh-Hans`, English `en`)
- **Authentication**: Apple Sign In via Firebase Auth (required before accessing main app)
- **Firebase Project**: `packagetraker-e80b0`

## Build & Development Commands

### Building
```bash
xcodebuild build -project PackageTraker.xcodeproj -scheme PackageTraker
xcodebuild build -project PackageTraker.xcodeproj -scheme PackageTraker -configuration Release
```

### Running Tests
```bash
# All unit tests
xcodebuild test -project PackageTraker.xcodeproj -scheme PackageTraker -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# UI tests only
xcodebuild test -project PackageTraker.xcodeproj -scheme PackageTraker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing PackageTrakerUITests

# Specific test file
xcodebuild test -project PackageTraker.xcodeproj -scheme PackageTraker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing PackageTrakerTests/PackageTrakerTests
```

### Cloud Functions Backend
```bash
cd functions && npm install && npm run build    # Build TypeScript
firebase deploy --only functions                 # Deploy to Firebase
```

### Simulator
- **Available**: iPhone 17 Pro (iOS 26.2)
- **Note**: iPhone 16 is not available in this environment

## Architecture

### Data Model Layer (`PackageTraker/Models/`)

- `Package.swift` - SwiftData `@Model` with trackingNumber, carrier, status, pickupInfo, etc.
- `TrackingStatus.swift` - 6 package states: pending, shipped, inTransit, arrivedAtStore, delivered, returned
- `Carrier.swift` - 22 carriers grouped by `CarrierCategory` (convenienceStore, domestic, ecommerce, international, other); 20 have `trackTwUUID` (API-trackable)
- `TrackingEvent` - SwiftData model defined inside `Package.swift` (not a separate file), linked via `@Relationship`
- Other models: `SubscriptionTier`, `PaymentMethod`, `PurchasePlatform`, `ThemeColor`, `LinkedEmailAccount`

### Service Layer (`PackageTraker/Services/`)

**Tracking (`Services/Tracking/` + `Services/TrackTw/`):**
- `TrackingManager.swift` - `@MainActor ObservableObject` wrapping `TrackTwAPIService` for single-package tracking (instantiated per-use, NOT a singleton)
- `PackageRefreshService.swift` - `@Observable` service managing batch refresh logic (progress, dedup). Created in `PackageTrakerApp` and injected via environment
- `TrackTwAPIClient.swift` - HTTP client for Track.TW API (`https://track.tw/api/v1`)
- `TrackTwAPIService.swift` - Adapts API client to `TrackingServiceProtocol`
- `TrackTwTokenStorage.swift` - Keychain storage for API token

**Firebase (`Services/Firebase/`):**
- `FirebaseAuthService.swift` - Apple Sign In via Firebase Auth, Firestore user profile, auth state listening
- `FirebaseSyncService.swift` - **Bidirectional** Firestore sync with real-time listener, loop prevention via `recentLocalWrites` echo window
- `FirebasePushService.swift` - FCM token lifecycle (register, upload, clear)

**Subscription (`Services/Subscription/`):**
- `SubscriptionManager.swift` - StoreKit 2 singleton managing in-app purchases
- Free tier: max 5 packages, no AI, no premium themes
- Pro tier: unlimited packages, AI access, all themes
- Product IDs: `com.kenny.PackageTraker.pro.{monthly,yearly,lifetime}`
- Syncs tier to Firestore and caches in `UserDefaults`

**AI Vision (`Services/AI/`):**
- `AIVisionService.swift` - Google Gemini 2.5 Flash REST API for screenshot analysis
- `AIVisionModels.swift` - `AIVisionResult` (Codable), `AIVisionError` enum, `detectedCarrier` keyword mapping for all carriers
- Extracts: trackingNumber, carrier, pickupLocation, pickupCode, packageName, purchasePlatform, amount
- Image preprocessing: resize to max 1024px, JPEG 0.8 quality

**Notification (`Services/Notification/`):**
- `NotificationService.swift` - `UNUserNotificationCenter` wrapper for local notifications
- `NotificationManager.swift` - Coordinates notification logic with user preferences from `UserDefaults`
- Handles arrival notifications and daily pickup reminders (10:00 AM via `UNCalendarNotificationTrigger`)

**Gmail / Email Parsing (`Services/Gmail/` + `Services/EmailParsing/`):**
- Gmail OAuth + email fetching for auto-importing tracking numbers from order confirmation emails
- Feature-flagged off (`emailAutoImportEnabled = false`)

**Other Services:**
- `CarrierDetector.swift` - Auto-detects carrier from tracking number regex patterns (see `File/物流商辨識規則總覽.md`)
- `ThemeManager.swift` - Theme/appearance management
- `Services/OCR/TrackingNumberOCRService.swift` - Barcode OCR scanning
- `Services/Widget/WidgetDataService.swift` - Bridges main app data to App Group for widget
- `Services/Debug/DebugNotificationService.swift` - `#if DEBUG` test notification helpers

### View Layer (`PackageTraker/Views/`)

- `MainTabView.swift` - 3 tabs: PackageList (0), History (1), Settings (2). Uses `@Binding var selectedTab: Int` from `PackageTrakerApp`
- `SplashView.swift` - Cold start animation for already-authenticated users
- Subdirectories per feature: `Auth/`, `PackageList/`, `AddPackage/`, `AI/`, `PackageDetail/`, `History/`, `Settings/`, `Subscription/`
- AI scanning flow: `AddMethodSheet` → `AIScanningView` → `AIQuickAddSheet`

### Widget Extension (`PackageTrakerWidget/`)

- Separate target with its own `WidgetSharedModels.swift` (does NOT import main app)
- Supports `.systemSmall`, `.systemMedium`, `.systemLarge` sizes
- `PackageTimelineProvider` refreshes every 15 minutes
- App Group: `group.com.kenny.PackageTraker` for data sharing
- Deep link URL scheme: `packagetraker://package/{id}`
- Currently feature-flagged off (`FeatureFlags.widgetEnabled = false`)

### Cloud Functions Backend (`functions/`)

Firebase Cloud Functions v2 (TypeScript, Node.js 20, asia-east1):
- `scheduler.ts` - 15-minute tracking poll via Track.TW API
- `triggers.ts` - Firestore `onDocumentUpdated` → FCM push on status change
- `dailyReminder.ts` - 10:00 AM Taiwan time pickup reminder
- `alertEmail.ts` - `onSystemAlertCreated` for system alert notifications
- `services/trackTwApi.ts` - Track.TW HTTP client
- `services/pushNotification.ts` - FCM push via firebase-admin
- `i18n/notifications.ts` - Multilingual push templates (zh-Hant, zh-Hans, en)
- `utils/carrierNames.ts`, `utils/statusMapper.ts` - Shared mapping utilities

**Note:** `backend/` is a deprecated Python/FastAPI service (replaced by Track.TW API). Do not modify.

## App Flow & Authentication

### AppFlow State Machine

```swift
enum AppFlow: Equatable {
    case signIn     // Not authenticated → SignInView
    case coldStart  // Authenticated cold start → SplashView
    case main       // Main app → MainTabView
}
```

### ZStack Overlay Transition Pattern

MainTabView is **always present** at the bottom of the ZStack to avoid TabView/NavigationStack layout animation glitches. SignInView and SplashView are overlay layers that fade out via `.transition(.opacity)`. Key points:
- `selectedTab` reset to 0 before each transition to main
- `.opacity(appFlow == .main ? 1 : 0)` hides MainTabView during sign-out
- Sign-out handled via `.onChange(of: authService.isAuthenticated)`

### Push Notification Deep Link Flow

1. Notification tap → `NotificationDelegate.didReceive` extracts `packageId`
2. Posts `Notification.Name.didTapPackageNotification`
3. `PackageTrakerApp.onReceive` → sets `selectedTab = 0` + `pendingPackageId`
4. Binding chain → `PackageListView.onChange(of: pendingPackageId)` → navigates to detail

## Firestore Data Structure

```
/users/{uid}
  ├── appleId, email, createdAt, lastActive, language
  ├── fcmToken, subscriptionTier, subscriptionProductID
  ├── notificationSettings { enabled, arrivalNotification, pickupReminder, shippedNotification }
  └── /packages/{packageId}
        ├── trackingNumber, carrier, status, isArchived
        ├── isDeleted?, deletedAt? (soft delete)
        ├── customName?, pickupCode?, pickupLocation?, storeName?
        └── /events/{eventId} { timestamp, status, description, location? }
```

## Key Patterns & Conventions

### SwiftData
- Models: `@Model final class`, relationships with `@Relationship(deleteRule: .cascade)`
- Enum storage: raw values (`carrierRawValue`, `statusRawValue`) with computed property getters
- Container in `PackageTrakerApp` with models: `Package`, `TrackingEvent`, `LinkedEmailAccount`

### Localization
```swift
String(localized: "key.name")
// MUST add to all 3 files: en.lproj/, zh-Hant.lproj/, zh-Hans.lproj/ Localizable.strings
```

### Feature Flags (`FeatureFlags.swift`)
```swift
emailAutoImportEnabled = false   // Gmail auto-import (disabled)
subscriptionEnabled = true       // StoreKit 2 subscription
aiVisionEnabled = true           // Gemini AI screenshot scan (testing: temporarily enabled)
widgetEnabled = false            // iOS Widget Extension
```

### Singleton Services
Most services use `static let shared` singleton pattern: `SubscriptionManager.shared`, `AIVisionService.shared`, `NotificationManager.shared`, `FirebaseSyncService.shared`, `FirebaseAuthService.shared`, `FirebasePushService.shared`, `TrackTwAPIClient.shared`, `ThemeManager.shared`
- Exception: `TrackingManager` is NOT a singleton — instantiated as needed (e.g., by `PackageRefreshService`)
- Exception: `PackageRefreshService` is `@Observable` and injected via SwiftUI environment from `PackageTrakerApp`

### Custom Theme
- Colors: `.appAccent`, `.cardBackground`, `.secondaryCardBackground`
- Background: `.adaptiveGradientBackground()`, `.adaptiveBackground()`
- Input: `.adaptiveInputStyle()`

### API Keys
- `Secrets.swift` contains `trackTwAPIToken` and `geminiAPIKey` (placeholders, actual values from environment/Keychain)
- Track.TW token also in Firebase Secret Manager (`TRACKW_TOKEN`) for Cloud Functions

## Track.TW API Integration

1. **Import**: `TrackTwAPIClient.importPackages(carrierId, [trackingNumbers])` → returns `[trackingNumber: relationId]`
2. **Track**: `TrackTwAPIClient.getTracking(relationId)` → returns checkpoints with status

- Only carriers with `trackTwUUID` computed property are auto-trackable (20 of 22)
- Relation IDs cached in-memory (`TrackTwAPIService.relationIdCache`) and persisted (`Package.trackTwRelationId`)

## AI Scanning Carrier Detection Flow

截圖 → Gemini AI 辨識 → 格式驗證 → 物流商決定 → API 驗證 → 結果頁

### Carrier Detection Logic (`AIScanningView.processAIWorkflow`)

1. **格式驗證**: `CarrierDetector.isValidFormat()` 檢查單號 (5-50 字元, 英數)
2. **物流商決定** (三層 fallback):
   - AI `detectedCarrier` 有結果 → `CarrierDetector` 交叉驗證 (confidence ≥ 0.8 且不同 → 以格式為準)
   - AI 無法辨識 → `CarrierDetector.detectBest()` 從單號格式判斷
   - 都判斷不了 → 擋掉，顯示錯誤
3. **API 驗證**: Track.TW import + track；結果無事件且 pending → 擋掉

### Two Detection Systems

- **AI 關鍵字** (`AIVisionModels.detectedCarrier`): 從 Gemini 回傳的 carrier 文字模糊比對 (e.g. "蝦皮" → `.shopee`)
- **正則規則** (`CarrierDetector.patterns`): 從單號格式比對 (e.g. `^TW\d{12,15}[A-Z]?$` → `.sevenEleven`)
- 完整規則清單見 `File/物流商辨識規則總覽.md`

### Adding Detection Rules for a New Carrier

1. `AIVisionModels.swift` — 在 `detectedCarrier` mappings 加入 AI 關鍵字
2. `CarrierDetector.swift` — 加入正則 pattern (注意排序：高特徵性前綴在前，純數字在後)
3. `AIVisionService.swift` — 更新 system prompt 的常見物流商和單號格式列表
4. 更新 `File/物流商辨識規則總覽.md`

## Common Development Tasks

### Adding a New Carrier
1. Add case to `Carrier` enum in `Models/Carrier.swift`
2. Add to `CarrierCategory`, display name, and `trackTwUUID` (if supported)
3. (Optional) Add logo to `Assets.xcassets/Logos/`
4. Add localized name to all 3 `.strings` files

### Adding UI Text
1. Add key to `en.lproj/Localizable.strings`
2. Add to `zh-Hant.lproj/Localizable.strings` (Traditional Chinese)
3. Add to `zh-Hans.lproj/Localizable.strings` (Simplified Chinese)
4. Use: `String(localized: "key.name")`

### Tests

Test files in `PackageTrakerTests/` and `PackageTrakerUITests/` are minimal boilerplate stubs. There is no meaningful test coverage — do not rely on tests to catch regressions.
