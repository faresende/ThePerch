# perch-nutrition

## Trigger

Any task involving nutrition tracking, meal logging, macro/calorie targets, supplement records, or the nutrition data pipeline for The Perch. Also triggered when debugging nutrition-related cards or display issues in the iOS app.

## What it does

This skill manages the nutrition data pipeline for The Perch, covering meal logging, supplement tracking, and progress visualization. Nutrition data lives in the `dashboard_records` table with `category=nutrition` and uses specific `type` values to distinguish between meals, supplements, and daily progress summaries. The iOS app renders these via dedicated card components like `MealCard`, `MacrosCard`, and `CaloriesCard`.

Meals are logged with calorie and macronutrient breakdowns (protein, carbs, fat). The pipeline supports daily calorie and macro targets, and progress summaries show how the current day's intake compares to goals. Supplements are tracked separately for quick reference.

## Architecture

```
Manual Input / Agent Logging
     │
     │  dashboard_push or direct API
     ▼
┌──────────────────────────────────────────────────────┐
│         Supabase `dashboard_records` table            │
│                                                      │
│  category = "nutrition"                              │
│  type: meal | supplement | progress_summary          │
│  display_hint: meal_log | progress_gauge | macros_bar│
│  data (JSON): calories, macros, meal details         │
└──────────────────────────────────────────────────────┘
                      │
                      │  anon key + user auth (RLS)
                      ▼
            ┌──────────────────────┐
            │   The Perch iOS App  │
            │                      │
            │  NutritionViewModel  │
            │    ├─ MealCard       │
            │    ├─ MacrosCard     │
            │    ├─ CaloriesCard   │
            │    └─ NutritionHomeCard
            └──────────────────────┘
```

### Data Flow

1. **Input**: Meals are logged via the agent (e.g., "I had chicken breast and rice for lunch") or through direct app input.
2. **Processing**: The agent parses the meal description, estimates calories and macros, and writes to `dashboard_records`.
3. **Persistence**: Records use `category=nutrition` with type-specific `display_hint` values.
4. **Display**: The iOS `NutritionViewModel` aggregates daily totals and renders progress cards.

## Data Schema

### Supabase `dashboard_records` table (nutrition rows)

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Owner (references auth.users) |
| `type` | text | `"meal"`, `"supplement"`, or `"progress_summary"` |
| `category` | text | Always `"nutrition"` |
| `display_hint` | text | `"meal_log"`, `"progress_gauge"`, or `"macros_bar"` |
| `title` | text | Human-readable title (e.g., "Lunch", "Daily Progress", "Creatine") |
| `data` | JSONB | Type-specific payload (see below) |
| `created_at` | timestamptz | Record creation time |

### Meal (`type=meal`, `display_hint=meal_log`)

```json
{
  "meal_name": "Lunch",
  "calories": 650,
  "protein_g": 45,
  "carbs_g": 60,
  "fat_g": 22,
  "items": [
    { "name": "Chicken breast", "amount": "200g", "calories": 330 },
    { "name": "Basmati rice", "amount": "150g cooked", "calories": 195 },
    { "name": "Olive oil", "amount": "1 tbsp", "calories": 120 }
  ],
  "time": "12:30",
  "notes": "Post-workout meal"
}
```

### Supplement (`type=supplement`)

```json
{
  "name": "Creatine Monohydrate",
  "dosage": "5g",
  "time": "08:00",
  "notes": "With breakfast"
}
```

### Progress Summary (`type=progress_summary`)

```json
{
  "date": "2025-04-20",
  "target_calories": 2800,
  "consumed_calories": 1950,
  "remaining_calories": 850,
  "target_protein_g": 180,
  "consumed_protein_g": 120,
  "target_carbs_g": 300,
  "consumed_carbs_g": 210,
  "target_fat_g": 90,
  "consumed_fat_g": 65,
  "meals_logged": 3
}
```

### Display Hints for Nutrition

| Display Hint | Type | iOS Card |
|-------------|------|----------|
| `meal_log` | `meal` | `MealCard` |
| `progress_gauge` | `progress_summary` | `CaloriesCard` |
| `macros_bar` | `progress_summary` | `MacrosCard` |
| (none / auto) | `supplement` | `SingleValueCard` or custom |

## Setup

### Prerequisites

- Supabase project with migrations applied (see perch-supabase)
- Daily calorie/macro targets configured (stored in the agent's configuration)

### Logging a Meal

```bash
# Via Supabase REST API (service role key)
curl -X POST "https://cgmaotzmeoiueyzlchaz.supabase.co/rest/v1/dashboard_records" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "user_id": "00000000-0000-0000-0000-000000000000",
    "type": "meal",
    "category": "nutrition",
    "display_hint": "meal_log",
    "title": "Lunch",
    "data": {
      "meal_name": "Lunch",
      "calories": 650,
      "protein_g": 45,
      "carbs_g": 60,
      "fat_g": 22,
      "items": [{"name": "Chicken breast", "amount": "200g", "calories": 330}],
      "time": "12:30"
    }
  }'
```

### Known Issue

The generic `dashboard_push` helper validates a narrow allowlist of `type`, `category`, and `display_hint` values. Newer nutrition rows with `type=meal`, `category=nutrition`, and hints like `meal_log`, `progress_gauge`, or `macros_bar` may fail through the generic helper unless the underlying code has been updated. Use direct Supabase API calls as a workaround, or update the `dashboard_push` validation allowlist.

## Maintenance

### Debugging

- **Meals not appearing in app**: Check that `category=nutrition` and the correct `display_hint` is set. The iOS `NutritionViewModel` filters by category and type.
- **Macro totals wrong**: Verify that progress summaries are recalculated after each meal is logged. The agent should update the daily summary record, not just append meal records.
- **dashboard_push rejects nutrition records**: This is the known issue above. Use direct API calls or update the validation allowlist.

### Monitoring

```sql
-- Check today's nutrition records
SELECT type, title, data->>'calories' as calories, created_at
FROM dashboard_records
WHERE category = 'nutrition'
  AND created_at > CURRENT_DATE
ORDER BY created_at DESC;
```

### Common Issues

- **Duplicate meal entries**: If the agent logs a meal twice, deduplicate by checking `title` + `created_at` proximity before inserting
- **Progress gauge stuck at 0%**: The progress summary record needs to be updated (not just created) as meals are logged throughout the day
- **Nutrition card not on Home tab**: Verify that a `sections` row with the nutrition category is visible for the user
