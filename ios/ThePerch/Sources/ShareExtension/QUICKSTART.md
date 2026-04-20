# The Perch Share Extension - Quick Start Checklist

## Files Included

```
ShareExtension/
├── ShareViewController.swift          # Extension view controller (NSExtensionItem handling)
├── ShareExtensionView.swift           # SwiftUI UI (compact, clean bookmark save form)
├── ShareSupabaseClient.swift          # Lightweight Supabase API client
├── SharedConstants.swift              # Shared constants between app and extension
├── MainAppIntegration.swift           # Example integration code for main app
├── SETUP.md                           # Detailed setup guide
└── QUICKSTART.md                      # This file
```

## Step-by-Step Setup

### 1. Add Files to Your Project

- [ ] Copy all `.swift` files to your Xcode project
- [ ] Ensure `SharedConstants.swift` is in a location accessible to BOTH the main app and share extension targets

### 2. Create ShareExtension Target in Xcode

```
File → New → Target → App Extension → Share Extension
Name: ShareExtension
```

### 3. Configure Target Membership

Select each file and set:
- **Target Membership**: ✓ ShareExtension
- Also check if needed for main app: ✓ ThePerch (for SharedConstants.swift)

### 4. Set Up Entitlements

**Create/Edit `ShareExtension.entitlements`:**

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

**Update main app entitlements** (`ThePerch.entitlements`) to include the same App Group:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.theperch.shared</string>
</array>
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)group.com.theperch.shared</string>
</array>
```

### 5. Configure Info.plist for ShareExtension

Edit `ShareExtension/Info.plist` and add:

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
</dict>
```

### 6. Update Main App Authentication Flow

In your main app's authentication handler (e.g., after Supabase login):

```swift
import Foundation

// After successful Supabase authentication
func storeCredentialsForShareExtension(session: AuthSession) {
    MainAppAuthenticationIntegration.storeSharedSupabaseCredentials(
        supabaseURL: "https://your-project.supabase.co",
        supabaseAnonKey: "your-anon-key",
        authToken: session.accessToken,
        userID: session.user.id.uuidString
    )
}

// On logout
func clearCredentialsOnLogout() {
    MainAppAuthenticationIntegration.clearSharedSupabaseCredentials()
}
```

### 7. Prepare Supabase Tables

Ensure your Supabase database has these tables:

```sql
-- Bookmarks table
CREATE TABLE bookmarks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    url TEXT NOT NULL,
    title TEXT,
    domain TEXT,
    tags TEXT[] DEFAULT '{}',
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Records table
CREATE TABLE records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    bookmark_id UUID REFERENCES bookmarks(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    category TEXT NOT NULL,
    display_hint TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

Enable RLS (Row Level Security) if needed:

```sql
ALTER TABLE bookmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own bookmarks" ON bookmarks
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can insert their own records" ON records
    FOR INSERT WITH CHECK (auth.uid() = user_id);
```

## How It Works

1. User taps Share → selects "Save to The Perch"
2. `ShareViewController` extracts URL and title
3. `ShareExtensionView` displays the form (optional tags input)
4. User taps Save
5. `ShareSupabaseClient` inserts rows in `bookmarks` and `records` tables
6. Success checkmark appears → auto-dismisses after 1.5 seconds

## What Gets Saved

**Bookmarks Table:**
- `id`: UUID (auto-generated)
- `url`: The shared URL
- `title`: Page title (or domain if not available)
- `domain`: Extracted domain
- `tags`: Array of tags (from comma-separated input)
- `status`: Set to `'pending'`
- `created_at`: Timestamp

**Records Table:**
- `id`: UUID (auto-generated)
- `bookmark_id`: References the bookmarks row
- `type`: Set to `'bookmark'`
- `category`: Set to `'bookmarks'`
- `display_hint`: Set to `'bookmark_card'`
- `metadata`: JSON with url, title, tags
- `created_at`: Timestamp

## Testing

### 1. Build & Run

- [ ] Select the ShareExtension scheme in Xcode
- [ ] Choose Safari (or another app) as the launch target
- [ ] Build and run

### 2. Test from Safari

- [ ] Open a web page
- [ ] Tap Share → Scroll and select "Save to The Perch"
- [ ] Verify the URL and title appear
- [ ] Add some tags (optional)
- [ ] Tap Save
- [ ] Verify success checkmark appears and dismisses

### 3. Check Supabase

- [ ] Go to Supabase dashboard
- [ ] Navigate to bookmarks table
- [ ] Verify a new row exists with your URL
- [ ] Check records table for the corresponding record

## Debugging

### Extension doesn't appear in Share menu

- Check entitlements are properly configured
- Verify NSExtension is in Info.plist
- Try restarting the device/simulator
- Check that main app and extension have matching bundle IDs

### "Missing credentials" error

- Verify main app has called `storeSharedSupabaseCredentials`
- Check UserDefaults keys are correct
- Verify Keychain has the auth token stored
- Ensure App Group identifier matches in both targets

### Network/Auth errors

- Verify Supabase URL and anon key are correct
- Check auth token is valid (not expired)
- Confirm user has write permissions on bookmarks/records tables
- Try logging out and logging back in to refresh token

## Customization TODO Items for the user

The UI in `ShareExtensionView.swift` has TODO comments for customization:

1. **Line ~73**: Add favicon fetching for the domain circle
2. **Color scheme**: Update from blue placeholder to The Perch branding colors
3. **Typography**: Adjust fonts and sizing for consistency with main app
4. **Icons**: Replace placeholder link icon with The Perch brand icon
5. **Animations**: Enhance the success state animation
6. **Accessibility**: Add voice-over labels and dynamic type support

## Performance Notes

- Extension stays well under 120MB memory limit
- No heavy dependencies (Foundation + SwiftUI only)
- URLSession used directly (no full Supabase SDK)
- Lightweight JSON handling
- Expected memory usage: 15-25MB

## Security

- Auth tokens stored securely in Keychain
- Keychain items scoped to App Group
- URLs validated before storage (basic check)
- No sensitive data logged or exposed
- Follows iOS security best practices

## Next Steps

1. Follow the setup steps above
2. Run SETUP.md for detailed configuration
3. Test with a real app (Safari, Twitter, etc.)
4. Customize UI in ShareExtensionView.swift
5. Add favicon fetching
6. Consider adding collections/folders selection
7. Implement sync status indication

## Questions?

Refer to:
- `SETUP.md` for detailed configuration
- `ShareViewController.swift` for extension initialization
- `ShareExtensionView.swift` for UI customization
- `ShareSupabaseClient.swift` for Supabase integration
- `MainAppIntegration.swift` for main app integration examples
