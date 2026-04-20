# perch-bookmarks

## Trigger

Any task involving saved links, bookmarks, URL management, or the bookmark ingestion pipeline (iOS Share Extension, Safari Extension, Telegram, web chat).

## What it does

The bookmarks pipeline captures links saved by the user from any surface (iOS Share Extension, Safari Extension, Telegram bot, or web chat), stores them in the Supabase `records` table with `category=bookmarks` and `type=bookmark`, then enriches them via an OpenClaw agent (Archie) that fetches the page, extracts a title, generates a summary, and assigns tags.

Bookmarks go through a lifecycle: `pending` → `processing` → `processed` (or `failed`). The bookmark-watcher cron job in the dashboard-sync skill polls for pending bookmarks and triggers agent enrichment.

## Architecture

```
User saves link (iOS Share / Safari / Telegram / Web)
        │
        │ Direct write to Supabase
        ▼
  records table (category=bookmarks, type=bookmark, status=pending)
        │
        │ cron job (every 2 min)
        ▼
  bookmark-watcher (dashboard-sync)
  ├─ Poll: bookmarks with status='pending'
  ├─ Call Archie agent for enrichment
  └─ Update: enriched_title, summary, tags, status='processed'
        │
        ▼
  iOS: BookmarksView → BookmarksViewModel → SupabaseService
         └─→ BookmarksCard (grid/list layout)
```

### Submission Sources

| Source | Mechanism |
|--------|-----------|
| iOS Share Extension | Share sheet → direct Supabase write with `submitted_from: 'ios_share'` |
| Safari Extension | Same pipeline |
| Telegram | Bot command `/save <url>` → agent writes to Supabase |
| Web chat | Agent tool call to save bookmark |

### Enrichment Data

After Archie processes a bookmark, these fields are populated:
- `enriched_title`: Title extracted from page `<title>` tag
- `summary`: 2-3 sentence page summary
- `tags`: Array of inferred topic tags (e.g., `["swiftui", "ios", "tutorial"]`)
- `domain`: Extracted root domain
- `image_url`: Open Graph image if found
- `reading_time_minutes`: Estimated reading time
- `processed_at`: ISO8601 timestamp

## Data Schema

### records table (bookmarks category)

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Owner |
| `category` | TEXT | `bookmarks` |
| `type` | TEXT | `bookmark` |
| `title` | TEXT | User-provided or original page title |
| `data` | JSONB | Bookmark payload |
| `display_hint` | TEXT | `bookmark_card` or `bookmark_grid` |
| `created_at` | TIMESTAMPTZ | When saved |

### data payload

```json
{
  "url": "https://developer.apple.com/documentation/swiftui",
  "original_title": "SwiftUI | Apple Developer Documentation",
  "enriched_title": "SwiftUI | Apple Developer Documentation",
  "summary": "Comprehensive guide to building user interfaces with SwiftUI...",
  "tags": ["swiftui", "ios", "apple", "documentation"],
  "status": "processed",
  "domain": "developer.apple.com",
  "image_url": "https://.../og-image.png",
  "reading_time_minutes": 15,
  "submitted_from": "ios_share",
  "processed_at": "2026-04-20T10:00:00+01:00"
}
```

### Status lifecycle

`pending` → `processing` → `processed` / `failed`

## Search and Retrieval

Bookmarks are queried by `category=bookmarks`. The iOS app supports:
- Text search across `title` and `summary`
- Tag filtering (tags stored as JSON array in `data->tags`)
- Domain filtering
- Sort by `created_at` or `processed_at`

```sql
-- Find bookmarks by tag
SELECT * FROM records
WHERE category = 'bookmarks'
  AND data->'tags' ? 'swiftui'
ORDER BY created_at DESC;
```

## Maintenance

### Debugging

```bash
# Check pending bookmarks
curl -G "https://cgmaotzmeoiueyzlchaz.supabase.co/rest/v1/records" \
  -H "apikey: $ANON_KEY" \
  --data-urlencode "category=eq.bookmarks" \
  --data-urlencode "data->>status=eq.pending" \
  --data-urlencode "limit=10"

# Check all bookmark statuses
curl -G ".../records" \
  -H "apikey: $ANON_KEY" \
  --data-urlencode "category=eq.bookmarks" \
  --data-urlencode "order=created_at.desc" \
  --data-urlencode "limit=20"
```

### Common Issues

- **Bookmark stuck in `processing`**: The watcher considers bookmarks `processing` for >10 minutes as stuck and marks them `failed`. If a bookmark is stuck, check the Archie agent logs.
- **Tags not extracted**: Archie enrichment may fail on paywalled or JavaScript-rendered pages. The `summary` and `tags` fields may be empty in those cases.
- **iOS Share Extension not saving**: Check that the Share Extension's Supabase write is using the correct user_id and that RLS policies allow inserts.
