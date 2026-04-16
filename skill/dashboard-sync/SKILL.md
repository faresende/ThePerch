# Dashboard Sync

Persists structured data to a Supabase cloud database for the native iOS Perch dashboard. Agents use this skill to save measurements, deliveries, events, statuses, and other records that the app displays in real-time. Also tracks agent health and token usage across the team.

## Important caveats

### Nutrition and custom display hints

The generic `dashboard_push` helper is behind the live ThePerch nutrition schema in one important way:

- it validates only a narrow allowlist of `type`, `category`, and `display_hint` values
- newer ThePerch nutrition rows like `type=meal`, `category=nutrition`, and hints such as `meal_log`, `progress_gauge`, and `macros_bar` may fail through the generic helper unless the underlying code has been updated

### Tracked deliveries

Tracked packages now have a separate canonical model:

- use `orders` + `shipments` for tracked deliveries shown in the current app Orders surface
- do NOT default new tracked packages into `dashboard_records`
- treat `dashboard_records` delivery rows as legacy compatibility cards only

## Tools

### dashboard_push

Saves a structured data record to the dashboard database. Used to persist measurements, deliveries, calendar events, reminders, notes, checklists, cost summaries, and status updates.

Parameters:
- agent_id (string, required): The agent identifier making this record
- user_id (string, required): UUID of the user this record belongs to
- type (string, required): Record type: `measurement`, `delivery`, `event`, `status`, `reminder`, `text_note`, `checklist`, `cost_summary`
- category (string, required): Logical category: `health`, `deliveries`, `calendar`, `admin`, `legal`
- title (string, required): Human-readable title (e.g., "Morning Weight", "Package Arrived")
- data (object, required): Type-specific payload. Structure depends on record type. Examples:
  - measurement: `{ value: number, unit: string, notes?: string }`
  - delivery: `{ carrier: string, tracking_number: string, status: string, delivery_date?: string }`
  - event: `{ start_time: string, end_time?: string, location?: string, attendees?: string[] }`
  - checklist: `{ items: Array<{ text: string, completed: boolean }>, progress?: number }`
  - cost_summary: `{ total_cost_usd: number, input_tokens: number, output_tokens: number, model: string }`
- display_hint (string, optional): UI rendering hint: `chart`, `single_value`, `status_list`, `timeline`, `checklist`, `cost_breakdown`
- annotations (object, optional): Metadata object with arbitrary structure for filtering/sorting
- pinned (boolean, optional): If true, prioritize this record in the dashboard UI
- expires_at (string, optional): ISO 8601 timestamp. Record auto-deletes at this time

Returns:
- success (boolean): Whether the record was created
- id (string): UUID of the created record
- created_at (string): ISO 8601 timestamp of creation

### dashboard_query

Queries recent records from the database with optional filtering. Use this when an agent needs historical context or wants to check for duplicate entries before saving.

Parameters:
- user_id (string, required): UUID of the user to query
- type (string, optional): Filter by record type (e.g., "measurement", "delivery")
- category (string, optional): Filter by category
- agent_id (string, optional): Filter by originating agent
- limit (number, optional): Max records to return (default: 50, max: 500)
- since (string, optional): ISO 8601 timestamp. Return records created after this time

Returns:
- records (array): List of matching records with all fields
- count (number): Total records matching the query
- error (string, optional): Error message if query failed

### dashboard_heartbeat

Updates agent status and logs token usage in a single operation. Call this periodically (e.g., after major agent work) to keep the dashboard informed of agent health and resource consumption.

Parameters:
- agent_id (string, required): The agent identifier
- user_id (string, required): UUID of the owner
- display_name (string, optional): Human-readable agent name
- emoji (string, optional): Emoji for the dashboard
- model (string, optional): LLM model being used (e.g., "claude-opus-4-6")
- is_active (boolean, optional): Current agent status
- input_tokens (number, optional): Tokens consumed on input this session
- output_tokens (number, optional): Tokens consumed on output this session
- estimated_cost_usd (number, optional): Estimated API cost

Returns:
- success (boolean): Whether the heartbeat was recorded
- agent_updated (boolean): Whether agent record was upserted
- usage_recorded (boolean): Whether token usage was logged
- last_heartbeat (string): ISO 8601 timestamp of heartbeat
