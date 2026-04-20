# The Perch Share Extension Setup Guide

## Overview

This Share Extension allows users to save URLs from any app (Safari, Twitter, etc.) directly to The Perch as bookmarks. The extension writes to Supabase with minimal dependencies to stay within the 120MB memory limit.

## Architecture

### File Structure

```
ShareExtension/
├── ShareViewController.swift          # UIViewController + NSExtensionItem handling
├── ShareExtensionView.swift           # SwiftUI UI for the share sheet
├── ShareSupabaseClient.swift          # Lightweight Supabase client
├── SharedConstants.swift              # Constants shared with main app
└── SETUP.md                           # This file
```

### Data Flow

1. **User Action**: Taps Share → selects "Save to The Perch"
2. **Input Extraction**: `ShareViewController` extracts URL and title from `NSExtensionItem`
3. **UI Presentation**: `ShareExtensionView` displays the URL, title, and tags input
4. **Supabase Save**: `ShareSupabaseClient` inserts rows in `bookmarks` and `records` tables
5. **Confirmation**: Success checkmark animation, auto-dismiss after 1.5 seconds

## Setup Instructions

### 1. Create the Share Extension Target

In Xcode:

```
File → New → Target → App Extension → Share Extension
Name: ShareExtension
```

### 2. Configure Target Membership

Add files to the ShareExtension target:
- `ShareViewController.swift` ✓
- `ShareExtensionView.swift` ✓
- `ShareSupabaseClient.swift` ✓
- `SharedConstants.swift` ✓

### 3. Update ShareExtension.entitlements

Add App Groups and Keychain Sharing:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.theperch.shared</string>
    </array>
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)group.com.theperch.shared</string>
    </array>
</dict>
</plist>
```

### 4. Update Main App Entitlements

Ensure the main app also has these entitlements configured in its `.entitlements` file.

### 5. Configure Info.plist for ShareExtension

Add to `ShareExtension/Info.plist`:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.share-services</string>
    <key>NSExtensionActivationRule</key>
    <dict>
        <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
        <integer>1</integer>
        <key>NSExtensionActivationSupportsWebPageWithMaxCount</key>
        <integer>1</integer>
    </dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>UIExtensionPointIdentifier</key>
        <string>com.apple.share-services</string>
    </dict>
</dict>
```

### 6. Main App: Configure Shared Credentials

When the user logs in, the main app must write Supabase credentials to the shared App Group:

```swift
// In your main app's authentication handler:
import Foundation

func storeSharedSupabaseCredentials(
    supabaseURL: String,
    anonKey: String,
    authToken: String
) {
    // Store in shared UserDefaults
    if let defaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier) {
        defaults.set(supabaseURL, forKey: SharedConstants.supabaseURLKey)
        defaults.set(anonKey, forKey: SharedConstants.supabaseAnonKeyKey)
    }

    // Store auth token in shared Keychain
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: SharedConstants.keychainService,
        kSecAttrAccount as String: SharedConstants.authTokenKeychainKey,
        kSecAttrAccessGroup as String: SharedConstants.appGroupIdentifier,
    ]

    // Delete existing value
    SecItemDelete(query as CFDictionary)

    // Insert new value
    var attributes = query
    attributes[kSecValueData as String] = authToken.data(using: .utf8)

    SecItemAdd(attributes as CFDictionary, nil)
}
```

## Supabase Schema

The extension expects two tables:

### `bookmarks` Table

```sql
CREATE TABLE bookmarks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    title TEXT,
    domain TEXT,
    tags TEXT[] DEFAULT '{}',
    status TEXT DEFAULT 'pending', -- 'pending' or 'processed'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### `records` Table

```sql
CREATE TABLE records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    bookmark_id UUID REFERENCES bookmarks(id) ON DELETE CASCADE,
    type TEXT NOT NULL, -- 'bookmark', 'article', etc.
    category TEXT NOT NULL, -- 'bookmarks', 'articles', etc.
    display_hint TEXT, -- 'bookmark_card', 'article_card', etc.
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

## API Details

### ShareSupabaseClient.saveBookmark()

```swift
func saveBookmark(url: String, title: String, tags: [String]) async throws -> UUID
```

**Behavior:**
1. Extracts domain from the URL automatically
2. Inserts a row in the `bookmarks` table with `status='pending'`
3. Inserts a row in the `records` table with `type='bookmark'`
4. Returns the bookmark UUID on success
5. Throws `ShareSupabaseError` on failure

**Error Handling:**
- `.missingCredentials`: Supabase URL, key, or auth token not configured
- `.invalidURL`: Invalid Supabase base URL
- `.networkError`: Connection or network-related issue
- `.decodingError`: Failed to encode/decode JSON
- `.serverError(code, details)`: Supabase returned an HTTP error

## Keychain Access

The extension uses a lightweight `KeychainHelper` struct to access the shared auth token:

```swift
let token = KeychainHelper.retrieve(
    key: SharedConstants.authTokenKeychainKey,
    service: SharedConstants.keychainService
)

KeychainHelper.store(
    key: SharedConstants.authTokenKeychainKey,
    value: token,
    service: SharedConstants.keychainService
)
```

**Important:** Keychain items must include the `kSecAttrAccessGroup` with the app group identifier for cross-target access.

## UI Customization

The `ShareExtensionView.swift` contains TODO comments for the user to customize:

1. **Favicon Fetching** (line ~73): Replace the placeholder blue circle with actual favicons
2. **Design Polish**: Update colors, spacing, fonts, and animations
3. **Branding**: Replace placeholder icons and colors with The Perch branding

Current placeholder design includes:
- Blue circle with link icon for domain
- Page title and URL display
- Comma-separated tags input field
- Simple Save/Cancel buttons
- Green checkmark on success

## Performance & Memory

The extension is designed to stay well under the 120MB memory limit:

- **No heavy dependencies**: Uses only Foundation and SwiftUI
- **Direct URLSession**: No full Supabase SDK
- **Minimal JSON parsing**: Only decodes error responses
- **Lightweight UI**: SwiftUI view, not heavy component libraries

Expected memory usage: 15-25MB

## Troubleshooting

### Extension not appearing in Share menu

- Verify App Group entitlements are configured correctly
- Check that `NSExtension` is properly configured in Info.plist
- Ensure the extension scheme is properly set up in Xcode

### "Missing credentials" error

- Verify the main app has successfully logged in and written credentials to the shared App Group
- Check UserDefaults and Keychain are accessible via the App Group identifier
- Ensure both targets have the same App Group identifier in entitlements

### Supabase authentication fails

- Verify the auth token is still valid (not expired)
- Check that the token is properly formatted (should be a JWT)
- Ensure user has appropriate permissions on the `bookmarks` and `records` tables

### UI not rendering

- Verify `ShareViewController` is properly hosting the SwiftUI view
- Check that `UIHostingController` is correctly added to the view hierarchy
- Ensure the extension is running on iOS 14+

## Testing

### Local Testing

1. Run the main app target to set up credentials
2. Switch to the ShareExtension scheme in Xcode
3. Select a URL-sharing test app (e.g., Safari) as the launch target
4. Build and run
5. In the test app, tap Share → The Perch

### Unit Testing

For comprehensive testing:

```swift
// Test bookmark creation
func testSaveBookmark() async throws {
    let client = ShareSupabaseClient()
    let uuid = try await client.saveBookmark(
        url: "https://example.com",
        title: "Example",
        tags: ["test", "demo"]
    )
    XCTAssertNotNil(uuid)
}
```

## Security Notes

1. **Auth Token Handling**: Never log or expose the auth token
2. **Keychain Access**: Properly scoped to the app group identifier
3. **URL Validation**: URLs are stored as-is; no sanitization is performed on the client
4. **Permissions**: The extension runs with the same sandbox restrictions as the main app

## Future Enhancements

- [ ] Favicon caching and fetching
- [ ] Rich link previews (Open Graph metadata)
- [ ] Collections/folder selection
- [ ] Custom colors/priority levels
- [ ] Widget support for quick access
- [ ] Sync status indication
- [ ] Offline queue with background sync
