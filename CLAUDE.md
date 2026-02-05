# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PackageTraker** (取貨吧) is an iOS package tracking app targeting the Taiwan market. It helps users track packages from 18+ carriers and manage pickups from convenience stores and logistics centers.

- **Technology**: SwiftUI + SwiftData (local database)
- **Target**: iOS 16+ (dark mode only, `.preferredColorScheme(.dark)`)
- **Project Type**: Xcode project (no SPM workspace)
- **Localization**: 3 languages (Traditional Chinese `zh-Hant`, Simplified Chinese `zh-Hans`, English `en`)

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

**Other Services:**
- `CarrierDetector.swift` - Detects carrier from tracking number format
- `ThemeManager.swift` - Theme/appearance management
- `TrackingNumberOCRService.swift` - OCR for scanning tracking numbers

### View Layer (`PackageTraker/Views/`)

**Main Navigation:**
- `MainTabView.swift` - Tab bar with 4 tabs: PackageList, AddPackage, History, Settings
- `SplashView.swift` - Launch animation screen

**Feature Views:**
- `PackageList/` - List of active packages with pull-to-refresh tracking
- `AddPackage/` - Multi-step package addition with carrier selection and manual entry
- `PackageDetail/` - Package info, tracking events, delivery details
- `History/` - Archived packages management
- `Settings/` - User preferences, Gmail linking (disabled), theme settings
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

- `PackageTrakerApp.swift` - App entry point, SwiftData container setup, background task registration
- `Info.plist` - App metadata and privacy permissions
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
│   ├── Gmail/                # Email integration (disabled)
│   └── ...
├── Views/                     # SwiftUI views
│   ├── MainTabView.swift
│   ├── PackageList/
│   ├── AddPackage/
│   ├── PackageDetail/
│   └── ...
├── Components/               # Reusable UI components
├── Extensions/               # Swift extensions
├── Assets.xcassets/          # Images, colors, app icon
├── *.lproj/                  # Localization files
└── PackageTrakerApp.swift    # Entry point
```

## Removed Legacy Services (2026-02-05)

The following services were removed after migration to Track.TW API:
- `ParcelTwService.swift`
- `TrackTwScraper.swift` (web scraping, replaced by API)
- `FamilyMartTracker.swift`
- `ShopeeTracker.swift`
- `OKMartTracker.swift`

They are deleted from codebase but documented here for context.
