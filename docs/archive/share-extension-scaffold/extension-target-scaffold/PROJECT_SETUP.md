# The Perch Share Extension - Project Setup Guide

## Overview

This Share Extension allows users to save URLs from any iOS app (Safari, Twitter, Mail, etc.) directly to The Perch using a simple, fast share sheet.

## File Structure

```
ThePerchShare/
├── ShareViewController.swift          # Main entry point (UIViewController)
├── ShareView.swift                    # SwiftUI UI for the share sheet
├── ShareSupabaseClient.swift          # Lightweight Supabase client
├── SharedCredentials.swift            # App Group credential management
└── PROJECT_SETUP.md                   # This file
```

## Step 1: Create the Share Extension Target

1. In Xcode, open your The Perch project
2. File → New → Target
3. Select "Share Extension"
4. Name it "ThePerchShare"
5. Uncheck "Include UI Configuration"

## Step 2: Configure App Groups

### In the Main App Target:
1. Select your main app target
2. Signing & Capabilities → + Capability
3. Add "App Groups"
4. Set the group identifier to: `group.com.theperch.shared`

### In the Share Extension Target:
1. Select the ThePerchShare target
2. Signing & Capabilities → + Capability
3. Add "App Groups"
4. Set the group identifier to: `group.com.theperch.shared`

### In the Share Extension Target:
1. Select the ThePerchShare target
2. Signing & Capabilities → + Capability
3. Add "Keychain Sharing"
4. Set the keychain group to: `group.com.theperch.shared`

## Step 3: Configure Info.plist

The extension needs these keys in its Info.plist:

```xml
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
```

## Step 4: Set Deployment Target

- Set the deployment target to **iOS 17.0 or later**
- The extension uses SwiftUI features that require iOS 17+

## Step 5: Link Frameworks

In Build Phases for the ThePerchShare target:
- Link Binary With Libraries: (typically already included)
  - Foundation
  - UIKit
  - SwiftUI

## Step 6: Replace Files

1. Copy all Swift files from this folder into the Share Extension target
2. Make sure to add them to the ThePerchShare target, NOT the main app target

## Step 7: Integration with Main App

After a user logs in to the main app, call this in your authentication code:

```swift
import Foundation

// After successful login
let credentials = SharedCredentials()
credentials.saveCredentials(
    supabaseURL: "https://your-project.supabase.co",
    anonKey: "your-anon-key",
    accessToken: userAuthToken,
    userId: userID
)
```

On logout:
```swift
let credentials = SharedCredentials()
credentials.clearCredentials()
```

## Step 8: Backend Schema

The extension writes to two tables in Supabase:

### bookmarks table
```sql
CREATE TABLE bookmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  url TEXT NOT NULL,
  original_title TEXT,
  tags TEXT[] DEFAULT '{}',
  status TEXT DEFAULT 'pending',
  submitted_from TEXT DEFAULT 'ios_share',
  user_id UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### records table
```sql
CREATE TABLE records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL,
  category TEXT NOT NULL,
  title TEXT,
  display_hint TEXT,
  data JSONB,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  agent_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

## Step 9: Testing

### Simulator Testing:
1. Run the main app on the simulator to populate credentials
2. Open Safari or Notes app
3. Share a URL using the Share button
4. Select "The Perch" from the share menu
5. Verify the extension appears

### Device Testing:
1. Build and run the main app on device
2. Build and run the share extension on the same device
3. Test sharing from Safari or other apps

### Debugging:
- Console output can be viewed in Xcode using the extension's debug session
- Check Supabase dashboard to verify records are being inserted

## Step 10: Archiving & Distribution

The share extension automatically includes when you archive the main app:

1. Product → Archive
2. Verify both the main app and share extension are included
3. Xcode will bundle them together automatically

## Common Issues

### "Supabase credentials not found"
- The main app hasn't saved credentials to App Group UserDefaults
- Ensure you called `SharedCredentials().saveCredentials(...)` after login
- Extension only works if main app has been opened and user logged in

### Extension doesn't appear in Share menu
- Check that App Groups capability is set correctly in both targets
- Restart the device
- Verify the extension target is in the main app's target dependencies

### Keychain errors
- Ensure Keychain Sharing capability is enabled in the extension
- Check that group ID matches exactly: `group.com.theperch.shared`

### Supabase connection errors
- Verify SUPABASE_URL and SUPABASE_ANON_KEY are correct in UserDefaults
- Check that access token is valid
- Ensure Supabase RLS policies allow inserts from anonymous/extension process

## Performance Notes

- The share sheet uses `.medium()` detent for compact presentation
- URL extraction happens asynchronously to avoid blocking
- Supabase writes happen in the background
- Success animation auto-dismisses after 1 second for quick UX

## Security Considerations

- Access token is stored in Keychain (encrypted)
- Supabase URL and Anon Key in UserDefaults (shared but not sensitive)
- Extension runs in sandbox - cannot access main app's data directly
- Uses App Groups container for secure credential sharing
- All network requests use HTTPS

## Architecture Diagram

```
┌─────────────────────────────────┐
│  Safari / Twitter / Any App     │
└──────────────┬──────────────────┘
               │ Share URL
               ▼
┌─────────────────────────────────┐
│  ShareViewController            │
│  - Extracts URL & title         │
│  - Presents ShareView           │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  ShareView (SwiftUI)            │
│  - Shows URL, title, tags       │
│  - User taps "Save"             │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  App Group UserDefaults         │
│  - Read: supabaseURL, anonKey   │
│         accessToken, userID     │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  ShareSupabaseClient            │
│  - Writes to bookmarks table    │
│  - Writes to records table      │
└──────────────┬──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│  Supabase Cloud                 │
│  - Stores bookmark & record     │
│  - Triggers OpenClaw Agent      │
└─────────────────────────────────┘
```

## Next Steps

1. Create the extension target in Xcode
2. Add App Groups and Keychain Sharing capabilities
3. Copy these Swift files into the extension
4. Update your main app to call `saveCredentials()` after login
5. Test on device or simulator
6. Monitor Supabase records table for incoming bookmarks
7. Configure OpenClaw agent "Archie" to process pending bookmarks

## Archie Agent Integration

The OpenClaw agent "Archie" monitors the records table for:
- `type: "bookmark"`
- `status: "pending"`
- `submitted_from: "ios_share"`

Archie will:
1. Fetch the full page content from the URL
2. Extract metadata and clean HTML
3. Store archived content in Supabase
4. Update status to "processed"
5. Index for search

No additional configuration needed - the agent is trigger-based on records insertion.
