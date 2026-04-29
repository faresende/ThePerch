# Dashboard Sync Skill

An OpenClaw skill for The Perch that persists structured data to Supabase, enabling the native iOS dashboard to display real-time agent activity, measurements, deliveries, events, and resource consumption.

## Overview

The skill provides three core tools:

1. **dashboard_push** — Save structured data records (measurements, deliveries, events, etc.)
2. **dashboard_query** — Read recent records with filtering
3. **dashboard_heartbeat** — Update agent status and log token usage

## Installation

```bash
npm install
npm run build
```

## Environment Setup

Set these environment variables before running:

```bash
export SUPABASE_URL=https://your-project.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

The service role key allows unrestricted access for server-side operations. Never expose this key in client-side code.

## Database Schema

### records table
Stores all dashboard entries with comprehensive metadata.

```
id              UUID          Primary key
agent_id        TEXT          Agent that created the record
user_id         UUID          User who owns the record
type            TEXT          Record type (measurement, delivery, etc.)
category        TEXT          Logical grouping (health, deliveries, etc.)
title           TEXT          Human-readable title
data            JSONB         Type-specific payload
display_hint    TEXT          Rendering hint for iOS UI (optional)
annotations     JSONB         Arbitrary metadata for filtering (optional)
pinned          BOOLEAN       Prioritize in dashboard UI
created_at      TIMESTAMPTZ   Record creation timestamp
updated_at      TIMESTAMPTZ   Last update timestamp
expires_at      TIMESTAMPTZ   Auto-deletion timestamp (optional)
```

### agents table
Tracks agent status and last activity.

```
id              TEXT          Agent identifier (primary key)
display_name    TEXT          Human-readable name
emoji           TEXT          Emoji for dashboard UI
model           TEXT          LLM model being used
is_active       BOOLEAN       Current agent status
last_heartbeat  TIMESTAMPTZ   Latest heartbeat timestamp
owner_id        UUID          User who owns the agent
```

### token_usage table
Logs API token consumption for cost tracking.

```
id                      UUID          Primary key
agent_id                TEXT          Agent consuming tokens
date                    DATE          Usage date
input_tokens            INTEGER       Tokens consumed on input
output_tokens           INTEGER       Tokens consumed on output
model                   TEXT          Model used
estimated_cost_usd      NUMERIC       Estimated API cost
Unique constraint       (agent_id, date, model)
```

## Usage Examples

### Push a Weight Measurement

```typescript
import { dashboard_push } from '@theperch/dashboard-sync';

await dashboard_push({
  agent_id: 'agent-health-01',
  user_id: '550e8400-e29b-41d4-a716-446655440000',
  type: 'measurement',
  category: 'health',
  title: 'Morning Weight',
  data: {
    value: 82.5,
    unit: 'kg',
    notes: 'Post-workout measurements'
  },
  display_hint: 'chart',
  pinned: true
});
```

### Query Recent Records

```typescript
import { dashboard_query } from '@theperch/dashboard-sync';

const result = await dashboard_query({
  user_id: '550e8400-e29b-41d4-a716-446655440000',
  type: 'measurement',
  category: 'health',
  limit: 30,
  since: '2025-02-20T00:00:00Z'
});

console.log(`Found ${result.count} records`);
result.records.forEach(record => {
  console.log(`${record.title}: ${JSON.stringify(record.data)}`);
});
```

### Record Agent Heartbeat

```typescript
import { dashboard_heartbeat } from '@theperch/dashboard-sync';

await dashboard_heartbeat({
  agent_id: 'agent-health-01',
  user_id: '550e8400-e29b-41d4-a716-446655440000',
  display_name: 'Health Coach Bot',
  emoji: '🏥',
  model: 'claude-opus-4-7',
  is_active: true,
  input_tokens: 5420,
  output_tokens: 1230,
  estimated_cost_usd: 0.00285
});
```

## Record Types

### measurement
Health metrics, weight, vitals, sensor readings.

```json
{
  "value": 82.5,
  "unit": "kg",
  "notes": "Optional notes"
}
```

### delivery
Package tracking and shipment status.

```json
{
  "carrier": "fedex",
  "tracking_number": "1Z999AA10123456784",
  "status": "in_transit",
  "delivery_date": "2025-02-28T00:00:00Z"
}
```

### event
Calendar events and scheduled activities.

```json
{
  "start_time": "2025-02-26T14:00:00Z",
  "end_time": "2025-02-26T15:00:00Z",
  "location": "Conference Room A",
  "attendees": ["alice@example.com", "bob@example.com"]
}
```

### status
Agent status updates, system state.

```json
{
  "state": "processing",
  "message": "Analyzing user input"
}
```

### reminder
Task reminders and notifications.

```json
{
  "due_date": "2025-02-28T09:00:00Z",
  "description": "Team standup",
  "priority": "high"
}
```

### text_note
Simple text notes and logs.

```json
{
  "content": "Meeting notes from today's sync"
}
```

### checklist
Task lists with completion tracking.

```json
{
  "items": [
    { "text": "Review PRs", "completed": true },
    { "text": "Update docs", "completed": false }
  ],
  "progress": 50
}
```

### cost_summary
Token usage and API cost aggregation.

```json
{
  "total_cost_usd": 0.00285,
  "input_tokens": 5420,
  "output_tokens": 1230,
  "model": "claude-opus-4-7"
}
```

## Helper Functions

### parseWeightEntry
Extracts weight value from natural language.

```typescript
import { parseWeightEntry } from '@theperch/dashboard-sync/src/auto-capture';

const result = parseWeightEntry("I weigh 82.5 kg today");
// { value: 82.5, unit: 'kg', notes: 'I weigh 82.5 kg today' }
```

### parseDeliveryStatus
Extracts delivery information from text.

```typescript
import { parseDeliveryStatus } from '@theperch/dashboard-sync/src/auto-capture';

const result = parseDeliveryStatus("FedEx tracking 1Z999AA10123456784 out for delivery");
// { carrier: 'fedex', tracking_number: '1Z999AA10123456784', status: 'out_for_delivery' }
```

### buildCostSummary
Aggregates token usage into a cost_summary record.

```typescript
import { buildCostSummary } from '@theperch/dashboard-sync/src/auto-capture';

const summary = buildCostSummary(usageRecords);
// { total_cost_usd: 0.00285, input_tokens: 5420, output_tokens: 1230, model: 'claude-opus-4-7' }
```

## Development

### Build TypeScript

```bash
npm run build
```

### Watch for changes

```bash
npm run dev
```

### Type checking

```bash
npx tsc --noEmit
```

## Error Handling

All tool handlers return objects with a `success` boolean and optional `error` string:

```typescript
const result = await dashboard_push({...});

if (!result.success) {
  console.error('Failed to save record:', result.error);
  // Handle error appropriately
}
```

## Security

- **Service Role Key**: Uses Supabase service role key for unrestricted writes (server-side only)
- **Input Validation**: All tool inputs are validated before database operations
- **HTTPS**: Communication with Supabase is encrypted
- **Environment Variables**: Sensitive credentials must be environment variables, never hardcoded

## Performance Considerations

- **Queries**: Dashboard query limits to 500 records maximum to prevent large result sets
- **Indexes**: Ensure database indexes on `user_id`, `created_at`, `type`, `category`, `agent_id`
- **Expiration**: Use `expires_at` to auto-clean old records instead of manual deletion
- **Batching**: For high-volume inserts, consider batching multiple records in a single transaction

## Testing

Tests can be added in the `__tests__` directory. To run:

```bash
npm test
```

## Contributing

Maintain these patterns:
- TypeScript strict mode required
- JSDoc comments for all exported functions
- Input validation in tool handlers
- Structured error responses
- Consistent data types across tools

## License

MIT
