# Claudinho: Populate Supabase for The Perch iOS App (archived snapshot)

> Archived setup doc. The current setup is `ios/ThePerch/CLAUDINHO-SUPABASE-SETUP.md`.

You need to set up and populate the Supabase database for **The Perch**, an iOS dashboard app. The app connects to Supabase and expects specific tables with specific schemas.

## Connection Details

- **Supabase Project URL:** `https://<YOUR-PROJECT-REF>.supabase.co`
- **Your user UUID:** `<YOUR-USER-ID>`

Use the **Supabase SQL Editor** (or the CLI) to run the SQL below.

---

## Step 1: Create the Tables

Run this SQL to create all required tables:

```sql
-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- AGENTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS agents (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    emoji TEXT,
    model TEXT,
    is_active BOOLEAN DEFAULT true,
    last_heartbeat TIMESTAMPTZ,
    owner_id UUID,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- SECTIONS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS sections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    slug TEXT NOT NULL,
    display_name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_visible BOOLEAN DEFAULT true,
    config JSONB,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- DASHBOARD RECORDS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS dashboard_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id TEXT NOT NULL REFERENCES agents(id),
    user_id UUID NOT NULL,
    type TEXT NOT NULL,
    category TEXT NOT NULL,
    title TEXT NOT NULL,
    data JSONB NOT NULL DEFAULT '{}',
    display_hint TEXT NOT NULL DEFAULT 'single_value',
    annotations JSONB,
    pinned BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ
);

-- ============================================
-- TOKEN USAGE TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS token_usage (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    agent_id TEXT NOT NULL REFERENCES agents(id),
    date TIMESTAMPTZ NOT NULL,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    total_tokens INTEGER NOT NULL DEFAULT 0,
    cost_usd DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- HOME WIDGETS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS home_widgets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    widget_type TEXT NOT NULL,
    config JSONB,
    is_visible BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- ROW-LEVEL SECURITY (RLS)
-- ============================================
ALTER TABLE sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE dashboard_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE token_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE home_widgets ENABLE ROW LEVEL SECURITY;

-- Allow anon/authenticated reads for Fabio's data
-- (In production, tie these to auth.uid(). For now, filter by user_id.)
CREATE POLICY "Allow read for all" ON sections FOR SELECT USING (true);
CREATE POLICY "Allow read for all" ON dashboard_records FOR SELECT USING (true);
CREATE POLICY "Allow read for all" ON token_usage FOR SELECT USING (true);
CREATE POLICY "Allow read for all" ON home_widgets FOR SELECT USING (true);

-- Allow inserts/updates for agents (they write data)
CREATE POLICY "Allow all for agents" ON agents FOR ALL USING (true);
CREATE POLICY "Allow insert for all" ON dashboard_records FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow update for all" ON dashboard_records FOR UPDATE USING (true);
CREATE POLICY "Allow insert for all" ON sections FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow update for all" ON sections FOR UPDATE USING (true);
CREATE POLICY "Allow insert for all" ON token_usage FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow insert for all" ON home_widgets FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow update for all" ON home_widgets FOR UPDATE USING (true);
```

---

## Step 2: Seed the Agents

These are Fabio's OpenClaw agents:

```sql
INSERT INTO agents (id, display_name, emoji, model, is_active, last_heartbeat, owner_id) VALUES
    ('claudinho', 'Claudinho', '🤖', 'claude-sonnet-4-5-20250929', true, now(), '00000000-0000-0000-0000-000000000000'),
    ('biochecha', 'BioChecha', '🧬', 'claude-sonnet-4-5-20250929', true, now(), '00000000-0000-0000-0000-000000000000'),
    ('entregas', 'Entregas', '📦', 'claude-haiku-4-5-20251001', true, now(), '00000000-0000-0000-0000-000000000000'),
    ('calendario', 'Calendario', '📅', 'claude-haiku-4-5-20251001', true, now(), '00000000-0000-0000-0000-000000000000'),
    ('legal', 'Legal', '⚖️', 'claude-sonnet-4-5-20250929', true, now(), '00000000-0000-0000-0000-000000000000'),
    ('archie', 'Archie', '🔖', 'claude-haiku-4-5-20251001', true, now(), '00000000-0000-0000-0000-000000000000')
ON CONFLICT (id) DO UPDATE SET
    last_heartbeat = now(),
    is_active = true;
```

---

## Step 3: Seed the Sections

The app uses a horizontally-paged view. Each section becomes a swipeable page. The `slug` must match a `RecordCategory` value exactly for the section to load records. The "home" slug is special (shows highlights).

```sql
INSERT INTO sections (user_id, slug, display_name, sort_order, is_visible) VALUES
    ('00000000-0000-0000-0000-000000000000', 'home', 'The Perch', 0, true),
    ('00000000-0000-0000-0000-000000000000', 'health', 'Health', 1, true),
    ('00000000-0000-0000-0000-000000000000', 'deliveries', 'Deliveries', 2, true),
    ('00000000-0000-0000-0000-000000000000', 'calendar', 'Calendar', 3, true),
    ('00000000-0000-0000-0000-000000000000', 'admin', 'Admin', 4, true),
    ('00000000-0000-0000-0000-000000000000', 'legal', 'Legal', 5, true),
    ('00000000-0000-0000-0000-000000000000', 'bookmarks', 'Bookmarks', 6, true);
```

---

## Step 4: Seed Sample Records

These are example records showing the exact JSON structure the app expects in the `data` column. Each `type` + `display_hint` + `data` combination maps to a specific card view in the app.

### Valid Values

**type** (must be one of): `measurement`, `delivery`, `event`, `status`, `reminder`, `text_note`, `checklist`, `cost_summary`, `bookmark`

**category** (must be one of): `health`, `deliveries`, `calendar`, `admin`, `legal`, `bookmarks`

**display_hint** (must be one of): `chart`, `single_value`, `status_list`, `timeline`, `checklist`, `cost_breakdown`, `bookmark_card`, `bookmark_grid`

### Health Records (agent: biochecha)

```sql
INSERT INTO dashboard_records (agent_id, user_id, type, category, title, data, display_hint, pinned) VALUES

-- Single value measurement (e.g., weight, blood pressure, heart rate)
('biochecha', '00000000-0000-0000-0000-000000000000', 'measurement', 'health',
 'Weight',
 '{"metric": "weight", "value": 78.5, "unit": "kg", "context": "Morning weigh-in", "timestamp": "2026-02-27T08:00:00Z"}',
 'single_value', true),

-- Another measurement
('biochecha', '00000000-0000-0000-0000-000000000000', 'measurement', 'health',
 'Blood Pressure',
 '{"metric": "blood_pressure", "value": 120, "unit": "mmHg", "context": "Systolic reading", "timestamp": "2026-02-27T08:05:00Z"}',
 'single_value', false),

-- Health reminder
('biochecha', '00000000-0000-0000-0000-000000000000', 'reminder', 'health',
 'Vitamin D Supplement',
 '{"title": "Take Vitamin D", "due": "2026-02-27T09:00:00Z", "list": "Health", "completed": false, "source": "biochecha"}',
 'single_value', false);
```

### Delivery Records (agent: entregas)

```sql
INSERT INTO dashboard_records (agent_id, user_id, type, category, title, data, display_hint, pinned) VALUES

('entregas', '00000000-0000-0000-0000-000000000000', 'delivery', 'deliveries',
 'Amazon - USB-C Hub',
 '{"order_id": "114-3941689-1234567", "carrier": "Amazon Logistics", "tracking_number": "TBA304962851000", "status": "Out for Delivery", "eta": "2026-02-27T18:00:00Z", "items": [{"name": "USB-C Hub 7-in-1", "quantity": 1, "description": "Anker USB-C Hub"}], "tracking_url": "https://track.amazon.com/TBA304962851000"}',
 'status_list', true),

('entregas', '00000000-0000-0000-0000-000000000000', 'delivery', 'deliveries',
 'iHerb - Supplements',
 '{"order_id": "IH-89234512", "carrier": "DHL", "tracking_number": "1234567890", "status": "In Transit", "eta": "2026-03-02T12:00:00Z", "items": [{"name": "Omega-3 Fish Oil", "quantity": 2, "description": "Nordic Naturals"}, {"name": "Magnesium Glycinate", "quantity": 1, "description": "Doctor''s Best"}], "tracking_url": null}',
 'status_list', false);
```

### Calendar Records (agent: calendario)

```sql
INSERT INTO dashboard_records (agent_id, user_id, type, category, title, data, display_hint, pinned) VALUES

('calendario', '00000000-0000-0000-0000-000000000000', 'event', 'calendar',
 'Dentist Appointment',
 '{"title": "Dentist Appointment", "start": "2026-02-28T10:00:00Z", "end": "2026-02-28T11:00:00Z", "location": "Clínica Dental Centro, Madrid", "agent_notes": "Regular checkup. Bring insurance card."}',
 'timeline', false),

('calendario', '00000000-0000-0000-0000-000000000000', 'event', 'calendar',
 'Team Standup',
 '{"title": "Team Standup", "start": "2026-02-27T15:00:00Z", "end": "2026-02-27T15:30:00Z", "location": "Google Meet", "agent_notes": "Daily sync with the team"}',
 'timeline', true),

('calendario', '00000000-0000-0000-0000-000000000000', 'reminder', 'calendar',
 'Pay Rent',
 '{"title": "Pay Rent", "due": "2026-03-01T10:00:00Z", "list": "Bills", "completed": false, "source": "calendario"}',
 'single_value', false);
```

### Admin Records (agent: claudinho)

```sql
INSERT INTO dashboard_records (agent_id, user_id, type, category, title, data, display_hint, pinned) VALUES

-- Agent status overview
('claudinho', '00000000-0000-0000-0000-000000000000', 'status', 'admin',
 'Claudinho Status',
 '{"state": "active", "uptime_hours": 168.5, "last_activity": "2026-02-27T21:30:00Z", "current_task": "Monitoring dashboard sync"}',
 'status_list', true),

-- Cost summary
('claudinho', '00000000-0000-0000-0000-000000000000', 'cost_summary', 'admin',
 'February API Costs',
 '{"period": "February 2026", "date": "2026-02-27T00:00:00Z", "total_cost_usd": 14.52, "breakdown": {"claudinho": 6.30, "biochecha": 3.10, "entregas": 1.80, "calendario": 1.50, "legal": 1.22, "archie": 0.60}}',
 'cost_breakdown', true),

-- Text note
('claudinho', '00000000-0000-0000-0000-000000000000', 'text_note', 'admin',
 'System Note',
 '{"body": "All agents healthy. Dashboard sync running every 5 minutes. Last full sync completed at 21:30 UTC.", "tags": ["system", "status"]}',
 'single_value', false);
```

### Legal Records (agent: legal)

```sql
INSERT INTO dashboard_records (agent_id, user_id, type, category, title, data, display_hint, pinned) VALUES

-- AIMA compliance checklist
('legal', '00000000-0000-0000-0000-000000000000', 'checklist', 'legal',
 'AIMA Compliance Checklist',
 '{"items": [{"text": "Register AI systems with national authority", "done": true}, {"text": "Complete risk assessment for high-risk AI", "done": true}, {"text": "Document training data provenance", "done": false}, {"text": "Establish human oversight procedures", "done": true}, {"text": "Submit transparency report", "done": false}]}',
 'checklist', true),

-- Legal text note
('legal', '00000000-0000-0000-0000-000000000000', 'text_note', 'legal',
 'EU AI Act Update',
 '{"body": "New guidance published on February 15 regarding AI agent disclosure requirements. Review needed for OpenClaw compliance.", "tags": ["eu-ai-act", "compliance", "review"]}',
 'single_value', false);
```

### Bookmark Records (agent: archie)

```sql
INSERT INTO dashboard_records (agent_id, user_id, type, category, title, data, display_hint, pinned) VALUES

('archie', '00000000-0000-0000-0000-000000000000', 'bookmark', 'bookmarks',
 'Anthropic Model Spec',
 '{"url": "https://docs.anthropic.com/en/docs/about-claude/soul", "original_title": "The Anthropic Model Spec", "enriched_title": "Claude''s Soul: The Anthropic Model Spec", "summary": "Comprehensive guide to how Claude is designed to behave, including safety, helpfulness, and honesty principles.", "tags": ["ai", "anthropic", "claude", "safety"], "status": "processed", "domain": "docs.anthropic.com", "image_url": null, "reading_time_minutes": 25, "submitted_from": "ios_share", "processed_at": "2026-02-25T14:00:00Z"}',
 'bookmark_card', true),

('archie', '00000000-0000-0000-0000-000000000000', 'bookmark', 'bookmarks',
 'SwiftUI Navigation Patterns',
 '{"url": "https://developer.apple.com/tutorials/swiftui/navigation", "original_title": "SwiftUI Navigation", "enriched_title": "Modern Navigation Patterns in SwiftUI", "summary": "Apple''s official tutorial covering NavigationStack, NavigationSplitView, and programmatic navigation in SwiftUI.", "tags": ["swift", "swiftui", "ios", "apple"], "status": "processed", "domain": "developer.apple.com", "image_url": null, "reading_time_minutes": 15, "submitted_from": "safari_extension", "processed_at": "2026-02-26T10:30:00Z"}',
 'bookmark_card', false),

('archie', '00000000-0000-0000-0000-000000000000', 'bookmark', 'bookmarks',
 'arXiv - Attention Is All You Need',
 '{"url": "https://arxiv.org/abs/1706.03762", "original_title": "Attention Is All You Need", "enriched_title": null, "summary": "The seminal paper introducing the Transformer architecture.", "tags": ["ml", "transformers", "paper"], "status": "processed", "domain": "arxiv.org", "image_url": null, "reading_time_minutes": 30, "submitted_from": "telegram", "processed_at": null}',
 'bookmark_card', false);
```

---

## Step 5: Seed Token Usage (Optional)

```sql
INSERT INTO token_usage (user_id, agent_id, date, input_tokens, output_tokens, total_tokens, cost_usd) VALUES
    ('00000000-0000-0000-0000-000000000000', 'claudinho', '2026-02-27T00:00:00Z', 45000, 12000, 57000, 0.85),
    ('00000000-0000-0000-0000-000000000000', 'biochecha', '2026-02-27T00:00:00Z', 18000, 5000, 23000, 0.34),
    ('00000000-0000-0000-0000-000000000000', 'entregas', '2026-02-27T00:00:00Z', 12000, 3000, 15000, 0.22),
    ('00000000-0000-0000-0000-000000000000', 'calendario', '2026-02-27T00:00:00Z', 10000, 2500, 12500, 0.19),
    ('00000000-0000-0000-0000-000000000000', 'legal', '2026-02-27T00:00:00Z', 22000, 8000, 30000, 0.45),
    ('00000000-0000-0000-0000-000000000000', 'archie', '2026-02-27T00:00:00Z', 8000, 2000, 10000, 0.15),
    ('00000000-0000-0000-0000-000000000000', 'claudinho', '2026-02-26T00:00:00Z', 52000, 15000, 67000, 1.00),
    ('00000000-0000-0000-0000-000000000000', 'biochecha', '2026-02-26T00:00:00Z', 20000, 6000, 26000, 0.39);
```

---

## How Agents Should Write Data Going Forward

Once the tables exist, any OpenClaw agent can push records to The Perch by inserting into `dashboard_records`. The pattern is:

```sql
INSERT INTO dashboard_records (agent_id, user_id, type, category, title, data, display_hint, pinned)
VALUES (
    'your_agent_id',
    '00000000-0000-0000-0000-000000000000',
    'measurement',        -- type
    'health',             -- category
    'Heart Rate',         -- title
    '{"metric": "heart_rate", "value": 72, "unit": "bpm", "context": "Resting", "timestamp": "2026-02-27T12:00:00Z"}',
    'single_value',       -- display_hint
    false                 -- pinned
);
```

To update agent heartbeats (keeps the "healthy" indicator green in the app):

```sql
UPDATE agents SET last_heartbeat = now() WHERE id = 'your_agent_id';
```

---

## After Running All SQL

Once all tables are populated, go to the iOS app's `SupabaseService.swift` and change:

```swift
private var useMockData = true
```

to:

```swift
private var useMockData = false
```

Then rebuild and run the app. It should pull real data from Supabase!
