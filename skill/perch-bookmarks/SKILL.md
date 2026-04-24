---
name: perch-bookmarks
description: "URL bookmarking system with titles, favicons, and tags stored in Supabase records table."
version: 1.0.0
---

# perch-bookmarks

## Trigger

Any task involving saving, retrieving, searching, or managing bookmarks/links for The Perch. Also triggered when debugging bookmark-related cards, tag management, or bookmark display issues in the iOS app.

## What it does

This skill manages the bookmark data pipeline for The Perch, allowing URLs to be saved with titles, favicons, and tags for later retrieval. Bookmarks are stored in the Supabase `records` table with `category=bookmarks` and `type=bookmark`. The iOS app renders bookmarks as card grids or individual bookmark cards, with search and tag-based filtering.

Bookmarks can be created from any source: agent conversations, web browsing, email links, or direct app input. Each bookmark carries structured metadata (URL, title, favicon URL, tags) in the `data` JSON field, enabling flexible categorization and retrieval.

## Architecture

```
Agent / Manual Input / Browser Extension
     │
     │  direct API or agent command
     ▼
┌──────────────────────────────────────────────────────┐
│              Supabase `records` table                 │
│                                                      │
│  category = "bookmarks"                              │
│  type = "bookmark"                                   │
│  data (JSON): url, title, favicon, tags              │
└──────────────────────────────────────────────────────┘
                      │
                      │  anon key + user auth (RLS)
                      ▼
            ┌──────────────────────┐
            │   The Perch iOS App  │
            │                      │
            │  BookmarksViewModel  │
            │    ├─ BookmarkCard   │
            │    ├─ Search/filter  │
            │    └─ Tag browser    │
            │                      │
            │  BookmarksView       │
            └──────────────────────┘
```

### Data Flow

1. **Input**: Bookmarks are saved via agent commands ("bookmark this: https://..."), direct API calls, or within the app.
2. **Enrichment**: The agent can fetch the page title and favicon automatically if only a URL is provided.
3. **Persistence**: Records use `category=bookmarks`, `type=bookmark`, with all metadata in the `data` JSON field.
4. **Display**: The iOS `BookmarksViewModel` supports full-text search on titles and filtering by tags. `BookmarkCard` renders individual links with favicon preview.

## Data Schema

### Supabase `records` table (bookmark rows)

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Owner (references auth.users) |
| `category` | text | Always `"bookmarks"` |
| `type` | text | Always `"bookmark"` |
| `title` | text | Page title or user-provided label |
| `data` | JSONB | Bookmark payload (see below) |
| `created_at` | timestamptz | Record creation time |

### Bookmark Data (`type=bookmark`, `data` JSON)

```json
{
  "url": "https://developer.apple.com/documentation/swiftui",
  "title": "SwiftUI Documentation",
  "favicon": "https://developer.apple.com/favicon.ico",
  "tags": ["ios", "swift", "documentation", "reference"],
  "description": "Apple's official SwiftUI framework documentation",
  "domain": "developer.apple.com"
}
```

### Minimal Bookmark

Only the URL is strictly required. The agent or app can fill in the rest:

```json
{
  "url": "https://example.com/article",
  "tags": []
}
```

## Setup

### Prerequisites

- Supabase project with migrations applied (see perch-supabase)
- No additional services required (bookmarks are self-contained in `records`)

### Saving a Bookmark

```bash
# Via Supabase REST API
curl -X POST "https://<YOUR-PROJECT-REF>.supabase.co/rest/v1/records" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "user_id": "<YOUR_USER_UUID>",
    "category": "bookmarks",
    "type": "bookmark",
    "title": "SwiftUI Documentation",
    "data": {
      "url": "https://developer.apple.com/documentation/swiftui",
      "title": "SwiftUI Documentation",
      "favicon": "https://developer.apple.com/favicon.ico",
      "tags": ["ios", "swift", "documentation"],
      "domain": "developer.apple.com"
    }
  }'
```

### Enriching a URL (Agent Flow)

When saving a bookmark from a bare URL:
1. Fetch the page with `web_fetch` to extract the title and meta description
2. Derive the favicon URL from `domain + /favicon.ico` or parse `<link rel="icon">` from the HTML
3. Prompt for tags or auto-suggest based on content analysis
4. Write the enriched record to Supabase

## Maintenance

### Debugging

- **Bookmarks not appearing**: Verify `category=bookmarks` and `type=bookmark` are set correctly. The iOS `BookmarksViewModel` filters on both fields.
- **Search not finding a bookmark**: The search is text-based on `title` and `data->>'title'`. Tag-based filtering uses the `tags` array in the `data` JSON.
- **Missing favicon**: Favicons are optional. If the URL doesn't serve a favicon, the app shows a fallback icon based on the first letter of the domain.

### Monitoring

```sql
-- Recent bookmarks
SELECT title, data->>'url' as url, data->>'tags' as tags, created_at
FROM records
WHERE category = 'bookmarks'
ORDER BY created_at DESC
LIMIT 20;

-- Bookmarks by tag (PostgreSQL JSON array containment)
SELECT title, data->>'url' as url
FROM records
WHERE category = 'bookmarks'
  AND data->'tags' ? 'ios';
```

### Common Issues

- **Duplicate bookmarks**: Check for existing records with the same URL before inserting. Use `data->>'url'` for deduplication.
- **Broken favicon URLs**: Some sites serve favicons on non-standard paths. Fall back to `https://{domain}/favicon.ico` or Google's favicon API: `https://www.google.com/s2/favicons?domain={domain}&sz=64`
- **Too many tags**: Tags are freeform strings. Consider normalizing common tags (e.g., "iOS" vs "ios" vs "IOS") in the agent layer.
