# Dashboard Sync Skill - Quick Start Guide

## 5-Minute Setup

### 1. Install Dependencies
```bash
cd /sessions/practical-amazing-tesla/mnt/ThePerch/skill/dashboard-sync
npm install
```

### 2. Configure Environment
Copy `.env.example` to `.env` and fill in your Supabase credentials:
```bash
cp .env.example .env
```

Edit `.env`:
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-here
```

### 3. Build
```bash
npm run build
```

This generates `dist/index.js` with compiled code.

### 4. Import in OpenClaw
```typescript
import { dashboard_push, dashboard_query, dashboard_heartbeat } from '@theperch/dashboard-sync';

// Or import all tools:
import tools from '@theperch/dashboard-sync';
```

## Three Core Functions

### Push a Record
```typescript
const result = await dashboard_push({
  agent_id: 'my-agent',
  user_id: 'user-uuid-here',
  type: 'measurement',           // or: delivery, event, status, reminder, text_note, checklist, cost_summary
  category: 'health',            // or: deliveries, calendar, admin, legal
  title: 'Morning Weight',
  data: { value: 82.5, unit: 'kg' },
  display_hint: 'chart',         // optional
  pinned: true                   // optional
});

if (result.success) {
  console.log('Record saved:', result.id);
} else {
  console.error('Error:', result.error);
}
```

### Query Records
```typescript
const result = await dashboard_query({
  user_id: 'user-uuid-here',
  type: 'measurement',        // optional
  category: 'health',         // optional
  limit: 30,
  since: '2025-02-20T00:00:00Z'  // optional: ISO 8601 timestamp
});

if (result.records.length > 0) {
  result.records.forEach(record => {
    console.log(`${record.title}: ${JSON.stringify(record.data)}`);
  });
}
```

### Record Heartbeat
```typescript
const result = await dashboard_heartbeat({
  agent_id: 'my-agent',
  user_id: 'user-uuid-here',
  model: 'claude-opus-4-7',
  is_active: true,
  input_tokens: 1000,
  output_tokens: 500,
  estimated_cost_usd: 0.01
});

if (result.success) {
  console.log('Heartbeat recorded at:', result.last_heartbeat);
}
```

## Auto-Capture Helpers

### Parse Weight
```typescript
import { parseWeightEntry } from './src/auto-capture';

const data = parseWeightEntry("I weigh 82.5 kg");
// Returns: { value: 82.5, unit: 'kg', notes: 'I weigh 82.5 kg' }
```

### Parse Delivery
```typescript
import { parseDeliveryStatus } from './src/auto-capture';

const data = parseDeliveryStatus("FedEx tracking 1Z999AA10123456784 out for delivery");
// Returns: { carrier: 'fedex', tracking_number: '1Z999AA10123456784', status: 'out_for_delivery' }
```

### Build Cost Summary
```typescript
import { buildCostSummary } from './src/auto-capture';

const summary = buildCostSummary(usageRecords);
// Returns: { total_cost_usd: 0.01, input_tokens: 1000, output_tokens: 500, model: 'claude-opus-4-7' }
```

## Common Patterns

### Save Health Measurement
```typescript
await dashboard_push({
  agent_id: 'health-coach',
  user_id: userId,
  type: 'measurement',
  category: 'health',
  title: 'Blood Pressure',
  data: { value: '120/80', unit: 'mmHg' },
  display_hint: 'single_value'
});
```

### Track Package
```typescript
const delivery = parseDeliveryStatus(userMessage);
if (delivery) {
  await dashboard_push({
    agent_id: 'logistics',
    user_id: userId,
    type: 'delivery',
    category: 'deliveries',
    title: `${delivery.carrier} Package`,
    data: delivery,
    display_hint: 'status_list'
  });
}
```

### Schedule Event
```typescript
await dashboard_push({
  agent_id: 'calendar',
  user_id: userId,
  type: 'event',
  category: 'calendar',
  title: 'Team Meeting',
  data: {
    start_time: '2025-02-27T14:00:00Z',
    end_time: '2025-02-27T15:00:00Z',
    location: 'Conference Room A',
    attendees: ['alice@example.com']
  },
  display_hint: 'timeline'
});
```

### Create Checklist
```typescript
await dashboard_push({
  agent_id: 'task-manager',
  user_id: userId,
  type: 'checklist',
  category: 'admin',
  title: 'Sprint Tasks',
  data: {
    items: [
      { text: 'Review PRs', completed: true },
      { text: 'Write tests', completed: false },
      { text: 'Deploy', completed: false }
    ],
    progress: 33
  },
  display_hint: 'checklist'
});
```

### Log Token Usage
```typescript
// After processing
await dashboard_heartbeat({
  agent_id: 'my-agent',
  user_id: userId,
  input_tokens: tokensIn,
  output_tokens: tokensOut,
  estimated_cost_usd: cost,
  model: 'claude-opus-4-7'
});
```

## Troubleshooting

### "SUPABASE_URL not found"
Make sure your `.env` file is created and readable. The skill reads environment variables on startup.

### "Failed to insert record"
Check that:
1. `user_id` is a valid UUID
2. `type` is one of the 8 valid types
3. `category` is one of the 5 valid categories
4. `data` matches the type's expected structure

### "Query returned no results"
Remember that queries filter by `user_id`, so make sure you're querying the same user who created the records.

### "Token usage not recorded"
Token usage requires both `input_tokens` OR `output_tokens` AND a `model` field in the heartbeat call.

## Development Commands

```bash
# Watch mode (auto-recompile on changes)
npm run dev

# Build once
npm run build

# Run tests
npm test

# Type checking
npx tsc --noEmit
```

## Next Steps

1. Read [SKILL.md](./SKILL.md) for detailed tool specifications
2. Read [README.md](./README.md) for complete documentation
3. Check [src/types.ts](./src/types.ts) for all TypeScript interfaces
4. See [src/index.ts](./src/index.ts) for implementation details

## Support

For issues or questions:
1. Check error messages in the console
2. Review the README.md for detailed documentation
3. Inspect the type definitions in src/types.ts
4. Check your Supabase database schema matches the expected tables
