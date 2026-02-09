# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PackageTraker** (取貨吧) is an iOS package tracking app targeting the Taiwan market. It helps users track packages from 18+ carriers and manage pickups from convenience stores and logistics centers.

- **Technology**: SwiftUI + SwiftData (local database) + Firebase (Auth, Firestore, FCM)
- **Target**: iOS 16+ (dark mode only, `.preferredColorScheme(.dark)`)
- **Project Type**: Xcode project (no SPM workspace)
- **Localization**: 3 languages (Traditional Chinese `zh-Hant`, Simplified Chinese `zh-Hans`, English `en`)
- **Authentication**: Apple Sign In via Firebase Auth (required before accessing main app)

## Build & Development Commands

### Building
```bash
# Build for Debug (default)
xcodebuild build -project PackageTraker.xcodeproj -scheme PackageTraker

# Build for Release
xcodebuild build -project PackageTraker.xcodeproj -scheme PackageTraker -configuration Release
```

### Running Tests
```bash
# Run all unit tests
xcodebuild test -project PackageTraker.xcodeproj -scheme PackageTraker -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run UI tests
xcodebuild test -project PackageTraker.xcodeproj -scheme PackageTraker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing PackageTrakerUITests

# Run specific test file
xcodebuild test -project PackageTraker.xcodeproj -scheme PackageTraker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing PackageTrakerTests/PackageTrakerTests
```

### Simulator
- **Available**: iPhone 17 Pro (iOS 26.2)
- **Note**: iPhone 16 is not available in this environment

## Architecture

### Data Model Layer (`PackageTraker/Models/`)

**Core Models:**
- `Package.swift` - SwiftData `@Model` for package data with properties like trackingNumber, carrier, status, pickupInfo, etc.
- `TrackingStatus.swift` - Enum representing 6 package states (pending, transit, delivered, exception, arrived, collected)
- `Carrier.swift` - 18+ carrier definitions grouped by `CarrierCategory` (convenienceStore, domestic, ecommerce, international, other)
- `TrackingEvent.swift` - Individual tracking checkpoint events
- `LinkedEmailAccount.swift` - Email linking for auto-import feature (currently disabled)

**Supporting Models:**
- `PaymentMethod.swift` - Payment method enum
- `PurchasePlatform.swift` - E-commerce platform source
- `ThemeColor.swift` - Custom color definitions

### Service Layer (`PackageTraker/Services/`)

**Tracking Services (`Services/Tracking/`):**
- `TrackingServiceProtocol.swift` - Interface defining `track()` and `importPackage()` methods
- `TrackingError.swift` - Enum for error handling with localized messages
- `TrackingManager.swift` - Main singleton `@MainActor ObservableObject` that orchestrates tracking via `TrackTwAPIService`

**Track.TW API Integration (`Services/TrackTw/`):**
- `TrackTwAPIClient.swift` - Low-level HTTP client for Track.TW API (base URL: `https://track.tw/api/v1`)
- `TrackTwAPIService.swift` - Adapts TrackTwAPIClient to TrackingServiceProtocol interface
- `TrackTwAPIModels.swift` - Request/response DTOs for Track.TW API
- `TrackTwTokenStorage.swift` - Keychain storage for API token

**Email Services (`Services/Gmail/`, `Services/EmailParsing/`):**
- Gmail OAuth integration (disabled via `FeatureFlags.emailAutoImportEnabled = false`)
- Taiwan-specific email parser for extracting tracking info from logistics emails
- Email link settings in Settings view

**Firebase Services (`Services/Firebase/`):**
- `FirebaseAuthService.swift` - Singleton `@MainActor ObservableObject` managing Apple Sign In via Firebase Auth. Handles nonce generation, credential exchange, Firestore user profile creation, and auth state listening.

**Other Services:**
- `CarrierDetector.swift` - Detects carrier from tracking number format
- `ThemeManager.swift` - Theme/appearance management
- `TrackingNumberOCRService.swift` - OCR for scanning tracking numbers

### View Layer (`PackageTraker/Views/`)

**Main Navigation:**
- `MainTabView.swift` - Tab bar with 3 tabs: PackageList (tag 0), History (tag 1), Settings (tag 2). Uses `@Binding var selectedTab: Int` controlled by `PackageTrakerApp`.
- `SplashView.swift` - Cold start launch animation (box drop + progress bar), for already-authenticated users
- `Auth/SignInView.swift` - Apple Sign In screen (box drop animation + sign in button + loading progress bar)

**Feature Views:**
- `PackageList/` - List of active packages with pull-to-refresh tracking
- `AddPackage/` - Multi-step package addition with carrier selection and manual entry
- `PackageDetail/` - Package info, tracking events, delivery details
- `History/` - Archived packages management
- `Settings/` - User preferences, account section (Apple ID display, sign out), theme settings
- `Email/` - Gmail account management (feature disabled)

### UI Components (`PackageTraker/Components/`)

Reusable SwiftUI components for common patterns (backgrounds, input styling, cards, etc.).

### Assets & Localization

**Assets:**
- `Assets.xcassets/` - App icon, logo images for 18+ carriers
- Logos stored in `Logo/` directory (PNG files for carrier branding)

**Localization:**
- `.strings` files in `en.lproj/`, `zh-Hant.lproj/`, `zh-Hans.lproj/`
- Pattern: `String(localized: "key.name")` automatically uses correct language
- **IMPORTANT**: Must add all new user-facing strings to all 3 `.strings` files

### Supporting Files

- `PackageTrakerApp.swift` - App entry point with `AppFlow` enum state machine, Firebase init, SwiftData container, ZStack overlay transition pattern
- `PackageTraker.entitlements` - Apple Sign In + APNs (development) entitlements
- `GoogleService-Info.plist` - Firebase configuration (not tracked in git)
- `Info.plist` - App metadata, privacy permissions, `UIBackgroundModes` (fetch, processing, remote-notification)
- `Secrets.swift` - API token placeholder (actual token from environment/Keychain)
- `FeatureFlags.swift` - Feature toggles (currently: `emailAutoImportEnabled = false`)

## Track.TW API Integration

The app migrated from multiple custom scrapers (2026-02-05) to a unified Track.TW API service.

### API Flow

1. **Import Package** → `TrackTwAPIClient.importPackages(carrierId, [trackingNumbers])`
   - Returns: `[trackingNumber: relationId]` mapping
   - Cached in `Package.trackTwRelationId` and `TrackTwAPIService.relationIdCache`

2. **Track Package** → `TrackTwAPIClient.getTracking(relationId)`
   - Returns: `TrackingCheckpoint[]` with status and timeline
   - Converted to `TrackingResult` with localized status

### Carrier Support

- Only carriers with `trackTwUUID` property are auto-trackable
- Access UUID: `Carrier.trackTwUUID` (computed property)
- Define in Carrier model's switch statement
- Unsupported carriers throw `TrackingError.unsupportedCarrier`

### Error Handling

`TrackingError` enum provides localized error messages:
- `.unsupportedCarrier` - Carrier not supported by API
- `.networkError` - Connectivity issues
- `.parsingError` - Malformed API response
- `.trackingNumberNotFound` - Invalid tracking number
- `.unauthorized` - API token expired/invalid
- `.rateLimited` - Rate limit exceeded
- `.invalidResponse` / `.serverError` - API server issues

## App Flow & Authentication Architecture

### AppFlow State Machine

The app uses an `AppFlow` enum to manage navigation between auth/splash/main screens:

```swift
enum AppFlow: Equatable {
    case signIn     // Not authenticated → show SignInView
    case coldStart  // Authenticated cold start → show SplashView (box drop + progress bar)
    case main       // Main app → show MainTabView
}
```

**Initialization logic** (in `PackageTrakerApp.init()`):
- `FirebaseApp.configure()` is called first
- `Auth.auth().currentUser` (synchronous after configure) determines initial flow:
  - `!= nil` → `.coldStart` (user was previously signed in)
  - `== nil` → `.signIn` (needs to authenticate)

### ZStack Overlay Transition Pattern

MainTabView is **always present at the bottom** of the ZStack to avoid TabView/NavigationStack internal layout animations on first insertion. SignInView and SplashView are rendered as **overlay layers** that fade out via `.transition(.opacity)`:

```swift
ZStack {
    // Bottom: always present, already laid out
    MainTabView(selectedTab: $selectedTab)
        .allowsHitTesting(appFlow == .main)
        .opacity(appFlow == .main ? 1 : 0)

    // Overlay: sign in (fades out when dismissed)
    if appFlow == .signIn {
        SignInView(...) { onLoadingComplete() }
            .transition(.opacity)
            .zIndex(1)
    }

    // Overlay: cold start splash (fades out when dismissed)
    if appFlow == .coldStart {
        SplashView(...) { onLoadingComplete() }
            .transition(.opacity)
            .zIndex(1)
    }
}
.animation(.easeOut(duration: 0.4), value: appFlow)
```

**Key design decisions:**
- `MainTabView` always at bottom avoids the "slide from top-left corner" glitch caused by TabView/NavigationStack implicit layout animations
- `selectedTab` is a `@Binding` from `PackageTrakerApp` → reset to 0 before each transition to main (prevents showing Settings tab after login)
- `.opacity(appFlow == .main ? 1 : 0)` on MainTabView hides it during sign-out transition
- Both `withAnimation` in closures and `.animation(value:)` on ZStack for animation reliability
- Sign-out is handled via `.onChange(of: authService.isAuthenticated)` → transitions to `.signIn`

### Firebase Auth Flow

1. **Sign In**: SignInView → Apple Sign In button → `FirebaseAuthService.signInWithApple()` → Firebase credential exchange → `authService.isAuthenticated` becomes `true` → `.onChange` in SignInView triggers loading → progress bar → `onLoadingComplete()` → fade to main
2. **Cold Start**: Already authenticated → SplashView → box drop animation → data loading → `onLoadingComplete()` → fade to main
3. **Sign Out**: SettingsView → sign out button → `authService.signOut()` → `isAuthenticated` becomes `false` → `PackageTrakerApp.onChange` transitions to `.signIn`

### Firestore User Profile

On first sign-in, `FirebaseAuthService.createUserProfileIfNeeded()` creates `/users/{uid}` in Firestore with:
- `appleId`, `email`, `createdAt`, `lastActive`
- `notificationSettings` (enabled, arrivalNotification, pickupReminder)

On subsequent sign-ins, only `lastActive` is updated.

## Key Patterns & Conventions

### SwiftData

- Models marked with `@Model` and `final class`
- Relationships use `@Relationship(deleteRule: .cascade)` for cleanup
- Raw values stored for enums (`carrierRawValue`, `statusRawValue`)
- Computed properties for type conversion: `var carrier: Carrier { Carrier(rawValue: carrierRawValue)! }`
- Container defined in `PackageTrakerApp` with models: `Package`, `TrackingEvent`, `LinkedEmailAccount`

### Localization

```swift
// Always use localized strings for user-facing text
String(localized: "key.name")

// Add keys to all 3 .strings files:
// - en.lproj/Localizable.strings
// - zh-Hant.lproj/Localizable.strings
// - zh-Hans.lproj/Localizable.strings
```

### Custom Theme

- Colors: `.appAccent`, `.cardBackground`, `.secondaryCardBackground`
- Extensions in `Components/` or `Extensions/`
- Background styling: `.adaptiveGradientBackground()`, `.adaptiveBackground()`
- Input styling: `.adaptiveInputStyle()`

### Async/Await

- `TrackingManager` and API services use `async/await`
- `TrackingManager.track()` loads cached relation IDs before API call
- Parallel refresh: `TrackingManager.refreshAll()` uses `TaskGroup` for concurrent tracking

### Error Handling

```swift
// Services throw typed errors (TrackingError, etc.)
do {
    let result = try await trackingManager.track(package: package)
} catch let error as TrackingError {
    // Handle specific error with localized message
    showError(error.errorDescription)
}
```

## Important Implementation Notes

### Carrier Detection

`CarrierDetector.swift` identifies carriers from tracking number format. Useful for auto-selecting carrier when user scans a number.

### Relation ID Caching Strategy

- `TrackTwAPIService` caches in-memory during app session (`relationIdCache`)
- `Package.trackTwRelationId` persists relation ID to database
- On app restart: `TrackingManager.track(package:)` loads cached ID into service before calling API
- Optimization: Avoid re-importing already-tracked packages

### Pickup Location Handling

- Convenience store pickups: extracted from checkpoint (7-11, FamilyMart, etc.)
- Stored in `Package.pickupLocation`, `Package.storeName`, `Package.pickupCode`
- User can override with `Package.userPickupLocation`

### Archived Packages

- Soft delete: `Package.isArchived = true`
- Excluded from refresh: `refreshAll()` filters with `!package.isArchived`
- History view displays archived packages

### Feature Flags

Currently only `emailAutoImportEnabled` is used. To add a flag:

```swift
struct FeatureFlags {
    static let myNewFeature = false
}

// Check in code:
if FeatureFlags.myNewFeature { /* ... */ }
```

## Testing Guidelines

- Unit tests in `PackageTrakerTests/PackageTrakerTests.swift`
- UI tests in `PackageTrakerUITests/`
- Mock data: `PackageTraker/MockData/`
- Use SwiftData in-memory containers for tests

## Common Development Tasks

### Adding a New Carrier

1. Add case to `Carrier` enum in `Models/Carrier.swift`
2. Add to appropriate `CarrierCategory` in computed property
3. Add display name in switch statement
4. Add `trackTwUUID` if Track.TW supports it
5. (Optional) Add carrier logo to `Assets.xcassets/Logos/`
6. Add localized carrier name to all 3 `.strings` files (if using `String(localized:)`)

### Adding a New Tracking Status

1. Add case to `TrackingStatus` enum in `Models/TrackingStatus.swift`
2. Update checkpoint_status mapping in `TrackTwAPIService.convertToTrackingResult()`
3. Add status-specific UI in views (colors, icons, descriptions)
4. Add localized status name to `.strings` files

### Adding UI Text

1. Add key to `en.lproj/Localizable.strings`
2. Add same key to `zh-Hant.lproj/Localizable.strings` with Chinese translation
3. Add same key to `zh-Hans.lproj/Localizable.strings` with Simplified Chinese
4. Use: `String(localized: "key.name")`

### Debugging API Issues

- `TrackTwAPIClient` makes HTTP requests to `https://track.tw/api/v1`
- Token retrieved from Keychain via `TrackTwTokenStorage`
- Check network inspector in Xcode for request/response
- API errors mapped to `TrackingError` types for display

## File Structure Summary

```
PackageTraker/
├── Models/                    # SwiftData models and enums
│   ├── Package.swift
│   ├── Carrier.swift
│   ├── TrackingStatus.swift
│   └── ...
├── Services/                  # Business logic layer
│   ├── TrackingManager.swift  # Main coordination service
│   ├── TrackTw/              # Track.TW API integration
│   ├── Firebase/             # Firebase integration
│   │   └── FirebaseAuthService.swift  # Apple Sign In + Auth
│   ├── Gmail/                # Email integration (disabled)
│   └── ...
├── Views/                     # SwiftUI views
│   ├── MainTabView.swift     # 3-tab view with @Binding selectedTab
│   ├── Auth/
│   │   └── SignInView.swift  # Apple Sign In screen
│   ├── PackageList/
│   ├── AddPackage/
│   ├── PackageDetail/
│   └── ...
├── Components/               # Reusable UI components
├── Extensions/               # Swift extensions
├── Assets.xcassets/          # Images, colors, app icon
├── *.lproj/                  # Localization files
├── PackageTraker.entitlements # Apple Sign In + APNs
├── GoogleService-Info.plist  # Firebase config (not in git)
└── PackageTrakerApp.swift    # Entry point with AppFlow state machine
```

```
File/                          # Project documentation
├── 後端推播系統實施計劃.md     # Full 4-phase push notification backend plan
├── 背景追蹤與推播系統計劃.md   # Background tracking plan
├── AI-截圖辨識升級計畫.md     # AI screenshot recognition plan
├── PackageTracker-PRD.md      # Product requirements document
└── TrackTW-API-Spec.md        # Track.TW API specification
```

```
Key/                           # APNs keys (not in git)
└── AuthKey_*.p8              # APNs authentication key for Firebase Cloud Messaging
```

## Firebase Push Notification Backend (In Progress)

Full implementation plan in `File/後端推播系統實施計劃.md`. The system enables server-side package tracking every 15 minutes with FCM push notifications when packages arrive.

### Phase Status

| Phase | Description | Status |
|-------|-------------|--------|
| **Phase 1** | Firebase setup + Apple Sign In | **Completed** (2026-02-09) |
| **Phase 2** | Firestore data sync + FCM token | **Completed** (2026-02-09) |
| **Phase 3** | Cloud Functions backend | **Completed** (2026-02-09) |
| **Phase 4** | Deep Link + UI polish | **Completed** (2026-02-09) |

### Phase 1 Completed Work

**New files created:**
- `Services/Firebase/FirebaseAuthService.swift` - Apple Sign In via Firebase Auth, Firestore user profile creation
- `Views/Auth/SignInView.swift` - Sign in screen with box drop animation, Apple Sign In button, loading progress bar
- `PackageTraker.entitlements` - Apple Sign In + APNs development entitlements
- `GoogleService-Info.plist` - Firebase project configuration

**Modified files:**
- `PackageTrakerApp.swift` - Added `AppFlow` enum, Firebase init, ZStack overlay transition pattern, `@State selectedTab` with binding to MainTabView
- `MainTabView.swift` - Changed to 3 tabs (removed AddPackage tab), `selectedTab` changed from `@State` to `@Binding`
- `SettingsView.swift` - Added account section (Apple ID display, sign out button with confirmation)
- `Info.plist` - Added `UIBackgroundModes` (remote-notification), existing permissions preserved
- `en.lproj/Localizable.strings` - Added auth.* and settings.account/signOut keys
- `zh-Hant.lproj/Localizable.strings` - Added Traditional Chinese translations
- `zh-Hans.lproj/Localizable.strings` - Added Simplified Chinese translations
- `project.pbxproj` - Firebase SDK dependencies, new file references

**Firebase SDK dependencies added (via SPM):**
- `FirebaseAuth`
- `FirebaseCore`
- `FirebaseFirestore`

**Localization keys added:**
- `auth.signIn.subtitle`, `auth.signIn.termsLine1`, `auth.signIn.termsLink`, `auth.signIn.and`, `auth.signIn.privacyLink`
- `auth.error.title`, `auth.error.invalidCredential`
- `settings.account`, `settings.appleId`, `settings.signOut`, `settings.signOut.confirmTitle`, `settings.signOut.confirmMessage`

### Phase 2 Completed Work

**Design decisions (differs from original plan):**
- **Upload-only sync** (not bidirectional): SwiftData is source of truth, Firestore is cloud mirror
- **Fire-and-forget**: Sync operations don't block UI, failures only logged
- **Soft delete**: `isDeleted: true` + `deletedAt` timestamp instead of removing documents
- **Non-blocking startup**: Initial sync and FCM registration run in background `Task { }`
- **No FirebaseModels.swift**: Conversion done directly in FirebaseSyncService

**New files created:**
- `Services/Firebase/FirebaseSyncService.swift` - Firestore upload sync (syncPackage, deletePackage as soft-delete, syncAllPackages)
- `Services/Firebase/FirebasePushService.swift` - FCM token lifecycle (register, upload, clear, MessagingDelegate)

**Modified files:**
- `PackageTrakerApp.swift` - Added AppDelegate for APNs token forwarding, FCM init, sign-in FCM registration
- `Views/SplashView.swift` - Non-blocking initial sync + FCM registration on cold start
- `Views/Auth/SignInView.swift` - Non-blocking initial sync after sign-in
- `Services/PackageRefreshService.swift` - Sync to Firestore after refresh
- `Views/AddPackage/PackageInfoView.swift` - Sync on add/update package
- `Views/PackageDetail/EditPackageSheet.swift` - Sync on edit
- `Views/PackageDetail/PackageDetailView.swift` - Soft-delete on delete
- `Views/PackageList/PackageListView.swift` - Soft-delete on swipe delete
- `Views/Settings/SettingsView.swift` - Clear FCM token on sign-out, sync delete on clear data

**Firebase Console setup:**
- Firestore Database: Standard edition, asia-east1 (Taiwan)
- Security Rules: `allow read, write: if request.auth != null && request.auth.uid == userId`

**Firestore data structure:**
```
/users/{uid}
  ├── appleId, email, createdAt, lastActive, fcmToken
  ├── notificationSettings { enabled, arrivalNotification, pickupReminder }
  └── /packages/{packageId}
        ├── trackingNumber, carrier, status, isArchived
        ├── isDeleted?, deletedAt? (soft delete)
        ├── customName?, pickupCode?, pickupLocation?, storeName?, ...
        └── /events/{eventId} { timestamp, status, description, location? }
```

### Phase 3 Completed Work

**New files created (backend, Cloud Functions v2):**
- `firebase.json` - Firebase project configuration
- `.firebaserc` - Project link (packagetraker-e80b0)
- `functions/package.json` - Node.js dependencies (axios, firebase-admin, firebase-functions)
- `functions/tsconfig.json` - TypeScript configuration
- `functions/src/index.ts` - Entry point: initializeApp + export 2 functions
- `functions/src/scheduler.ts` - 15-minute tracking poll (`onSchedule`, asia-east1, 512MiB)
- `functions/src/triggers.ts` - Firestore status change → FCM push (`onDocumentUpdated`)
- `functions/src/services/trackTwApi.ts` - Track.TW API HTTP client (axios)
- `functions/src/services/pushNotification.ts` - FCM push via firebase-admin messaging
- `functions/src/utils/statusMapper.ts` - Status mapping (mirrors iOS `TrackingStatus.fromTrackTw()`)

**Modified files (iOS bug fix):**
- `PackageTraker/Services/Firebase/FirebaseAuthService.swift` - Fixed `notificationSettings` not being created when user doc already exists (race condition with FCM token upload)

**Deployment:**
- Region: asia-east1, Runtime: Node.js 20
- Token stored via Firebase Secret Manager (`TRACKW_TOKEN`)

### Phase 4 Completed Work

**Modified files:**
- `PackageTraker/PackageTrakerApp.swift` - NotificationDelegate added `didReceive` for notification tap handling; added `pendingPackageId` state and `.onReceive()` for deep link; added `Notification.Name.didTapPackageNotification`
- `PackageTraker/Views/MainTabView.swift` - Added `@Binding var pendingPackageId: UUID?`, passes to PackageListView
- `PackageTraker/Views/PackageList/PackageListView.swift` - Added `@Binding var pendingPackageId: UUID?`, `.onChange(of:)` triggers navigation via existing `navigationDestination(item:)`

**Deep link flow:**
1. User taps push notification → `NotificationDelegate.didReceive` extracts `packageId` from payload
2. Posts `Notification.Name.didTapPackageNotification` via Foundation NotificationCenter
3. `PackageTrakerApp.onReceive` → sets `selectedTab = 0` + `pendingPackageId = uuid`
4. Binding chain → `MainTabView` → `PackageListView`
5. `PackageListView.onChange(of: pendingPackageId)` → finds Package in `@Query` results → sets `selectedPackage` → existing `navigationDestination(item:)` pushes `PackageDetailView`

### Known Issues / TODOs

- `SignInView.openPrivacyPolicy()` uses placeholder URL (Apple EULA instead of custom privacy policy)
- Firestore security rules may need tightening for events subcollection
- Push notification text is Chinese-only; needs localization (zh-Hant/zh-Hans/en) and richer content (pickup code, deadline)

## Removed Legacy Services (2026-02-05)

The following services were removed after migration to Track.TW API:
- `ParcelTwService.swift`
- `TrackTwScraper.swift` (web scraping, replaced by API)
- `FamilyMartTracker.swift`
- `ShopeeTracker.swift`
- `OKMartTracker.swift`

They are deleted from codebase but documented here for context.
