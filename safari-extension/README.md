# The Perch Safari Web Extension

A Safari Web Extension for macOS that lets you save bookmarks directly to The Perch via Supabase.

## Features

- Save current page as a bookmark with one click
- Auto-populated page title and URL
- Add custom tags for organization
- Real-time status feedback (saving, saved, error)
- Dark mode support
- Secure credential storage in extension storage

## Setup Instructions

### 1. Configure Credentials

First, you need to gather your Supabase credentials:

1. Open **Extension Settings**:
   - Click the extension icon in Safari's toolbar
   - Click "Preferences" or use the popup's options link

2. Enter your credentials:
   - **Supabase Project URL**: Found in your Supabase dashboard (e.g., `https://your-project.supabase.co`)
   - **Supabase Anon Key**: Found in Settings → API → `anon` key
   - **JWT Auth Token**: From your The Perch login session

3. Click **Save Settings**

### 2. Load as Unsigned Extension (macOS)

Since this is an unsigned extension, you'll need to enable extension development in Safari:

1. Open Safari
2. Go to **Safari → Settings → Advanced**
3. Check "Show Develop menu in menu bar"
4. Go to **Develop → Allow Unsigned Extensions**
5. Go to **Develop → Enter Web Extension Development Mode**

Now you can load the extension:

1. Go to **Safari → Settings → Extensions**
2. Click the **+** button in the bottom left
3. Select this folder and confirm
4. The Perch extension should now be active

### 3. Using the Extension

1. Navigate to any webpage
2. Click The Perch extension icon in the Safari toolbar
3. The current page title and URL will be auto-filled
4. (Optional) Add comma-separated tags for organization
5. Click **Save Bookmark**
6. You'll see a success message and the popup will auto-close

## Converting to a Proper Safari App Extension

Eventually, you may want to convert this to a signed Safari App Extension for distribution via the Mac App Store:

1. Open Xcode
2. Create a new macOS App project
3. File → Add Packages → Add the web extension folder
4. Use Xcode's "Convert to Safari Web Extension" template
5. Follow Apple's guidelines for signing and notarization
6. Submit to the Mac App Store

## Troubleshooting

### "Configuration missing" error
- Open extension settings and re-enter your Supabase credentials
- Ensure your JWT token is still valid (may need to log back into The Perch)

### "Failed to save bookmark" error
- Check that your Supabase project is accessible and the `bookmarks` table exists
- Verify your anon key has INSERT permissions on both `bookmarks` and `records` tables
- Check browser console (Develop → JavaScript Console) for detailed error messages

### Settings not saving
- Ensure you're using Safari and extension storage is enabled
- Try clearing all settings and re-entering them

## Project Structure

```
safari-extension/
├── manifest.json       # Extension configuration
├── popup.html         # Popup UI
├── popup.js          # Popup logic & Supabase integration
├── options.html      # Settings page
├── options.js        # Settings logic
├── background.js     # Service worker
├── README.md         # This file
└── icons/           # Extension icons (16, 48, 128px)
```

## Security Notes

- Your Supabase anon key and JWT token are stored in extension storage
- These are encrypted by Safari's storage system
- Never share your credentials with anyone
- If a token is compromised, regenerate it in your Supabase dashboard and The Perch app

## Future Enhancements

- Reading list import/export
- Bulk operations
- Offline caching
- Deep integration with The Perch web app
- Customizable keyboard shortcuts
