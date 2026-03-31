# The Perch Share Extension - Architecture & Implementation Guide

## System Overview

The Share Extension is a self-contained iOS extension that runs in a separate process from the main app. It allows users to save URLs to bookmarks without leaving their current app (Safari, Twitter, Mail, Notes, etc.).

```
┌─────────────────────────────────────────────────────────────────┐
│                     iOS System                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────┐        ┌──────────────────────┐     │
│  │  The Perch Main App  │        │ Share Extension      │     │
│  │  (Main Process)      │        │ (Separate Process)   │     │
│  ├──────────────────────┤        ├──────────────────────┤     │
│  │ - Auth/Login         │        │ - ShareViewController│     │
│  │ - Bookmarks View     │        │ - ShareView (SwiftUI)│     │
│  │ - Search             │        │ - ShareSupabaseClient│     │
│  │ - Settings           │        │ - SharedCredentials  │     │
│  │                      │        │                      │     │
│  │ saveCredentials() ──→│ Shared │← loadCredentials()  │     │
│  │                      │ App    │                      │     │
│  │ clearCredentials() ──→ Group │← hasCredentials()    │     │
│  └──────────────────────┘        └──────────────────────┘     │
│         │                              │                       │
│         │ (User Logs Out)              │ (Save Bookmark)       │
│         └──────────────────────────────┘                       │
│                     ↓                                           │
│         ┌───────────────────────────┐                          │
│         │ App Group UserDefaults    │                          │
│         │ group.com.theperch.shared │                          │
│         ├───────────────────────────┤                          │
│         │ - supabaseURL             │                          │
│         │ - anonKey                 │                          │
│         │ - userID                  │                          │
│         │                           │                          │
│         │ Keychain (Encrypted)      │                          │
│         │ - accessToken             │                          │
│         └───────────────────────────┘                          │
│                     ↓                                           │
│         ┌───────────────────────────┐                          │
│         │   HTTPS Requests          │                          │
│         │   to Supabase API         │                          │
│         └───────────────────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow Diagram

### Share Extension Activation Flow

```
User taps Share Button
    ↓
iOS presents share menu
    ↓
User selects "The Perch"
    ↓
┌─────────────────────────────────────────┐
│ ShareViewController.viewDidLoad()       │
├─────────────────────────────────────────┤
│ 1. extractSharedContent()               │
│    - Get extensionContext               │
│    - Process inputItems                 │
│    - Extract URL & title                │
│ 2. presentShareSheet()                  │
│    - Create ShareView (SwiftUI)         │
│    - Wrap in UIHostingController        │
│    - Present as medium sheet            │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ ShareView displays                      │
├─────────────────────────────────────────┤
│ - URL (truncated)                       │
│ - Page title (auto-extracted)           │
│ - Tag input field                       │
│ - Common tag chips                      │
│ - Save/Cancel buttons                   │
└─────────────────────────────────────────┘
    ↓
User taps "Save"
    ↓
┌─────────────────────────────────────────┐
│ saveBookmark() async                    │
├─────────────────────────────────────────┤
│ 1. Load credentials from App Group      │
│    - SharedCredentials.loadCredentials()│
│ 2. Call ShareSupabaseClient             │
│ 3. Show loading state (spinner)         │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ ShareSupabaseClient.saveBookmark()      │
├─────────────────────────────────────────┤
│ 1. Validate URL                         │
│ 2. Generate UUID for bookmark ID        │
│ 3. INSERT into bookmarks table          │
│    POST /rest/v1/bookmarks              │
│ 4. INSERT into records table            │
│    POST /rest/v1/records                │
│ 5. Return bookmark ID                   │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ Supabase Cloud                          │
├─────────────────────────────────────────┤
│ - Stores bookmark record                │
│ - Stores record for agent pipeline      │
│ - Triggers RLS policies                 │
│ - Notifies listening clients            │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ OpenClaw Agent "Archie"                 │
├─────────────────────────────────────────┤
│ - Monitors records table                │
│ - Fetches page content                  │
│ - Extracts metadata                     │
│ - Archives HTML                         │
│ - Updates record status                 │
│ - Indexes for search                    │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ ShareView shows success state           │
├─────────────────────────────────────────┤
│ - Green checkmark animation             │
│ - "Saved!" message                      │
│ - Auto-dismisses after 1 second         │
└─────────────────────────────────────────┘
    ↓
Sheet dismisses
User returns to Safari/Twitter/etc.
```

## Component Responsibilities

### 1. ShareViewController
**Location**: `ShareViewController.swift`

**Responsibility**: Entry point and orchestrator

**Key Methods**:
- `viewDidLoad()` - Initialize and extract shared content
- `extractSharedContent()` - Parse NSExtensionContext
- `presentShareSheet()` - Create and present SwiftUI view
- `dismissWithError()` - Handle initialization errors

**Capabilities**:
- Extracts URL from multiple sources (NSItemProvider, plain text)
- Extracts page title from shared content
- Gracefully handles missing/invalid input
- Presents error alerts

**Does NOT**:
- Handle network requests
- Manage authentication
- Interact with Supabase directly

### 2. ShareView
**Location**: `ShareView.swift`

**Responsibility**: User interface and interaction

**Key State**:
```swift
@State var tags: [String] = []          // Current user-added tags
@State var tagInput: String = ""        // Text input field
@State var isLoading: Bool = false      // Network request in progress
@State var isSaved: Bool = false        // Success state
@State var errorMessage: String?        // Error message
@State var showError: Bool = false      // Show error overlay
```

**Key Views**:
- URL display (truncated, with link icon)
- Page title (when available)
- Tag input field
- Common tag chips (6 predefined tags)
- Save/Cancel buttons
- Loading spinner
- Success checkmark animation
- Error dialog with retry

**UX Principles**:
- Minimal, focused interface
- Fast response to user actions
- Clear visual feedback for all states
- Accessible labels and hints
- Smooth animations
- Dark mode support

**Does NOT**:
- Validate URLs (that's ShareSupabaseClient)
- Store credentials (that's SharedCredentials)
- Make network requests (that's ShareSupabaseClient)

### 3. ShareSupabaseClient
**Location**: `ShareSupabaseClient.swift`

**Responsibility**: Supabase integration and data persistence

**Public API**:
```swift
func saveBookmark(
    url: String,
    title: String?,
    tags: [String]
) async throws -> String  // Returns bookmark ID
```

**Internal Flow**:
1. Load credentials from SharedCredentials
2. Validate URL format
3. Generate UUID for bookmark
4. Make HTTP POST to `/rest/v1/bookmarks`
5. Make HTTP POST to `/rest/v1/records`
6. Validate HTTP responses
7. Return bookmark ID

**Error Types**:
- `credentialsNotFound` - App Group credentials missing
- `invalidURL` - URL format validation failed
- `invalidRequest` - Request building failed
- `networkError` - Connection/network issue
- `decodingError` - Response parsing failed
- `serverError` - HTTP 4xx/5xx response
- `unknownError` - Unexpected error

**Supabase Tables Written**:

**Table 1: bookmarks**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "url": "https://example.com/article",
  "original_title": "Article Title",
  "tags": ["article", "research"],
  "status": "pending",
  "submitted_from": "ios_share",
  "user_id": "user-uuid",
  "created_at": "2026-02-27T12:00:00Z"
}
```

**Table 2: records**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "type": "bookmark",
  "category": "bookmarks",
  "title": "Article Title",
  "display_hint": "bookmark_card",
  "data": {
    "url": "https://example.com/article",
    "original_title": "Article Title",
    "tags": ["article", "research"],
    "status": "pending",
    "submitted_from": "ios_share",
    "bookmark_id": "550e8400-e29b-41d4-a716-446655440000"
  },
  "user_id": "user-uuid",
  "agent_id": "main",
  "created_at": "2026-02-27T12:00:00Z"
}
```

**Network Details**:
- Uses URLSession with HTTPS
- Headers:
  - `Content-Type: application/json`
  - `Authorization: Bearer {accessToken}`
  - `apikey: {anonKey}`
  - `Prefer: return=minimal` (don't return full data)
- Timeout: Default 60 seconds (configurable)
- No retry logic (handled by UI)

**Does NOT**:
- Manage user authentication
- Store credentials locally
- Cache responses
- Handle client-side data validation beyond URL format

### 4. SharedCredentials
**Location**: `SharedCredentials.swift`

**Responsibility**: Secure credential sharing between app and extension

**Public API**:
```swift
// Called by main app after login
func saveCredentials(
    supabaseURL: String,
    anonKey: String,
    accessToken: String,
    userId: String
)

// Called by extension before API requests
func loadCredentials() -> (
    supabaseURL: String,
    anonKey: String,
    accessToken: String,
    userId: String
)?

// Called by main app on logout
func clearCredentials()

// Called by extension to check availability
func hasCredentials() -> Bool
```

**Storage Strategy**:

| Data | Storage | Why |
|------|---------|-----|
| `supabaseURL` | UserDefaults | Non-sensitive, shared |
| `anonKey` | UserDefaults | Non-sensitive, public |
| `accessToken` | Keychain | Sensitive, encrypted |
| `userId` | UserDefaults | Non-sensitive, shared |

**App Group**: `group.com.theperch.shared`

**Keychain Service**: `com.theperch.shared`

**Keychain Access Group**: `group.com.theperch.shared`

**Keychain Accessibility**: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

**Implementation Details**:
- Uses standard Foundation APIs (UserDefaults, Security framework)
- No external dependencies
- Both app and extension have read/write access
- Survives app updates
- Cleared on app uninstall (with other app data)

**Does NOT**:
- Validate credentials
- Refresh tokens
- Make network requests
- Handle authentication flows

## Integration Points

### From Main App (Before You Integrate)

Your main app needs to call these at key points:

**1. After Login Success**
```swift
func handleAuthenticationSuccess(user: User, token: String) {
    let credentials = SharedCredentials()
    credentials.saveCredentials(
        supabaseURL: "https://your-project.supabase.co",
        anonKey: "your-anon-key-from-supabase",
        accessToken: token,
        userId: user.id
    )
}
```

**2. On Logout**
```swift
func handleLogout() {
    let credentials = SharedCredentials()
    credentials.clearCredentials()
}
```

**3. Optional: Monitor Extension Activity**
```swift
// Poll for recent bookmarks from extension
func checkRecentShares() async {
    let bookmarks = try await supabaseClient
        .from("bookmarks")
        .select()
        .eq("submitted_from", value: "ios_share")
        .gte("created_at", value: Date().addingTimeInterval(-3600))
        .order("created_at", ascending: false)
        .execute()

    // Use this for notifications, badges, etc.
}
```

### From Extension (Already Implemented)

**1. Credential Loading**
- Extension calls `SharedCredentials.loadCredentials()`
- Returns nil if main app hasn't called `saveCredentials()` yet
- Extension shows user-friendly error message

**2. Supabase Writing**
- Extension calls `ShareSupabaseClient.saveBookmark()`
- Writes to two tables atomically (or errors)
- Returns bookmark ID for confirmation

**3. Error Handling**
- Extension catches all errors
- Shows appropriate UI for each error type
- User can tap "Retry" to try again

## Security Model

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| User's access token exposed | Keychain encryption, device-only storage |
| Supabase URL hijacked | HTTPS only, pinning optional |
| Tags or URLs intercepted | HTTPS encryption |
| Extension without app credentials | Graceful error, helpful message |
| Malicious RLS policies | Extension has no control, relies on Supabase |
| Token expiration | Main app responsible for refresh |

### Trust Boundaries

```
Trusted (Under User Control):
├── Main app (user installed, authenticated)
└── Extension (bundled with main app)

Semi-Trusted (Third-party but encrypted):
├── Device Keychain (OS-managed, encrypted)
├── App Group UserDefaults (encrypted at rest)
└── Supabase Cloud (HTTPS, user-controlled)

Untrusted (Not under control):
├── Network (HTTPS mitigates)
├── Other apps (can't access App Group)
└── OS (we assume doesn't spy on Keychain)
```

### Credential Lifecycle

```
1. User logs into main app
   ↓
2. Auth succeeds, main app gets token
   ↓
3. Main app calls saveCredentials(token)
   ↓
4. Credentials stored in App Group
   ├── UserDefaults: URL, key, userID
   └── Keychain: encrypted token
   ↓
5. Extension can now read credentials
   ↓
6. Extension calls saveBookmark(url, tags)
   ↓
7. Extension reads from App Group
   ├── Gets URL from UserDefaults
   └── Gets token from Keychain
   ↓
8. Extension makes HTTPS request to Supabase
   ├── Authorizes with token
   ├── Uses anonKey in headers
   └── Sends user_id in payload
   ↓
9. Supabase RLS ensures user can only write their own records
   ↓
10. Main app calls clearCredentials() on logout
   ↓
11. All credentials securely deleted
```

## Testing Strategy

### Unit Tests (In ShareExtensionTests.swift)

**SharedCredentialsTests**
- ✅ Save and load credentials
- ✅ Load returns nil when empty
- ✅ Clear credentials
- ✅ hasCredentials() boolean logic
- ✅ Token stored in Keychain (not UserDefaults)

**ShareSupabaseClientTests**
- ✅ Requires credentials to save bookmark
- ✅ Validates URL format
- ✅ Mock Supabase responses

**URLExtractionTests**
- ✅ Parse valid URLs
- ✅ Reject invalid URLs
- ✅ Truncate long URLs for display

**TagParsingTests**
- ✅ Parse comma-separated tags
- ✅ Trim whitespace
- ✅ Remove duplicates
- ✅ Handle empty input

**ErrorHandlingTests**
- ✅ All error types have descriptions
- ✅ Errors conform to LocalizedError

### Integration Tests

**Manual Test Checklist**:
```
Setup:
  ✅ Create extension target in Xcode
  ✅ Add App Groups capability
  ✅ Add Keychain Sharing capability
  ✅ Copy all Swift files
  ✅ Set iOS 17+ deployment target

Authentication:
  ✅ Open main app and log in
  ✅ Extension can load credentials
  ✅ Open main app and log out
  ✅ Extension shows "credentials not found"

Sharing:
  ✅ Share URL from Safari
  ✅ Share URL from Twitter
  ✅ Share URL from Mail
  ✅ Share URL from Notes
  ✅ Extension properly detects URL

UI:
  ✅ Sheet appears as medium detent
  ✅ URL displays (truncated if long)
  ✅ Title auto-fills when available
  ✅ Tag input field works
  ✅ Common tag chips toggle
  ✅ Comma-separated tags auto-parse
  ✅ Tags display as removable chips
  ✅ Save button is enabled

Saving:
  ✅ Click Save → loading spinner appears
  ✅ After 1-2 sec → success checkmark
  ✅ Sheet dismisses automatically
  ✅ Return to Safari/Twitter/etc.

Database:
  ✅ Check bookmarks table in Supabase
  ✅ New record exists with correct URL
  ✅ Tags saved as array
  ✅ submitted_from = "ios_share"
  ✅ status = "pending"

  ✅ Check records table in Supabase
  ✅ New record exists with type: "bookmark"
  ✅ data.url matches
  ✅ data.tags matches
  ✅ agent_id = "main"

Errors:
  ✅ No credentials → helpful error message
  ✅ Invalid URL format → error with retry
  ✅ Network timeout → error with retry
  ✅ Server error → shows status code

Performance:
  ✅ Sheet appears instantly
  ✅ URL extraction is fast (<50ms)
  ✅ Save completes in <2 seconds
  ✅ Success animation is smooth
  ✅ No memory leaks (check Xcode)
```

## Extension Target Configuration

### Capabilities Required

**App Groups**
```
Identifier: group.com.theperch.shared
Container access: enabled
```

**Keychain Sharing** (Extension only)
```
Keychain groups: group.com.theperch.shared
```

### Info.plist Configuration

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0">
<dict>
    <!-- ... other keys ... -->

    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.share-services</string>
        <key>NSExtensionActivationRule</key>
        <dict>
            <key>NSExtensionActivationSupportsText</key>
            <true/>
            <key>NSExtensionActivationSupportsURL</key>
            <true/>
        </dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>NSExtensionActivationRule</key>
            <dict>
                <key>NSExtensionActivationSupportsText</key>
                <true/>
                <key>NSExtensionActivationSupportsURL</key>
                <true/>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
```

### Build Settings

- **Deployment Target**: iOS 17.0
- **Swift Language Version**: 5.9+
- **Code Signing**: Same team as main app
- **Bundle Identifier**: com.theperch.ios.shareextension (or similar)

### Linking

The extension automatically includes:
- Foundation
- UIKit
- SwiftUI
- Security (for Keychain)

## Performance Characteristics

### Speed

| Operation | Time | Notes |
|-----------|------|-------|
| Sheet presentation | 100ms | UIHostingController + SwiftUI |
| URL extraction | 50ms | NSItemProvider loading |
| Tag parsing | 10ms | String manipulation |
| Credential loading | 20ms | UserDefaults + Keychain |
| Bookmark save | 500-1000ms | Network dependent |
| Success animation | 400ms | Spring animation |
| Auto-dismiss | 1000ms | After success |

### Memory

- Baseline: ~20MB
- With image in clipboard: +10-20MB
- After save: Cleaned up automatically

### Network

- Supabase write: ~200-500ms (depending on network)
- No retries in extension (user can tap retry button)
- Timeout: 60 seconds (configurable)

## Future Enhancements

### Planned Features

1. **Offline Support**
   - Queue bookmarks if network is unavailable
   - Sync when connection restored
   - Show pending count badge

2. **Screenshot Integration**
   - Capture screenshot with bookmark
   - Store as attachment
   - Use for visual preview

3. **Reading List**
   - Integrate with iOS Reading List
   - Option to save to both Perch and Reading List
   - Export/import from Reading List

4. **Custom Metadata**
   - Extract author, publication date
   - Parse Open Graph tags
   - Store in data.metadata

5. **Smart Tags**
   - Suggest tags based on URL/title
   - Learn from user's tag patterns
   - Auto-complete in tag field

### Extensibility Points

1. **Custom Processors**
   - Extend ShareSupabaseClient with custom processors
   - Hook into save pipeline

2. **Theme Customization**
   - Override color scheme
   - Custom tag colors
   - Brand-specific styling

3. **Analytics**
   - Track share events
   - Monitor extension usage
   - Identify popular sources

## Debugging

### Enable Debug Logging

Add to ShareViewController.swift:
```swift
private let debug = true

private func log(_ message: String) {
    if debug {
        print("[ThePerchShare] \(message)")
    }
}
```

### Monitor Extension Process

In Xcode:
1. Run main app
2. Debug → Attach to Process by PID or Name
3. Search for "ThePerchShare"
4. View console output

### View Shared Credentials

In SceneDelegate or app startup:
```swift
let creds = SharedCredentials()
if let (url, key, token, user) = creds.loadCredentials() {
    print("URL: \(url)")
    print("Key: \(key.prefix(10))...")
    print("Token: \(token.prefix(10))...")
    print("User: \(user)")
}
```

## Deployment

### App Store Submission

1. Include extension in target dependencies
2. Share extension will be auto-bundled
3. Use same developer account/team
4. No separate listing in App Store
5. Marketing materials can mention Share Extension

### Pre-Release Testing

1. TestFlight: Automatically includes extension
2. Internal testing on device
3. Manual test checklist above
4. Monitor crash logs post-release

## References

- iOS Share Extensions: https://developer.apple.com/design/human-interface-guidelines/extensions
- SwiftUI: https://developer.apple.com/xcode/swiftui/
- Supabase REST API: https://supabase.com/docs/reference/api
- App Groups: https://developer.apple.com/documentation/foundation/app_groups
- Keychain Services: https://developer.apple.com/documentation/security/keychain_services
