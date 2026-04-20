---
name: perch-workouts
description: "Resistance training tracking with pull/push/legs rotation, rest days, and calendar integration for the The Perch workouts section."
version: 1.0.0
---

# perch-workouts

## Trigger

Any task involving workout tracking, training schedules, exercise logging, or the pull/push/legs workout rotation.

## What it does

The workouts pipeline tracks resistance training sessions and displays them in the iOS app's WorkoutView. Workout sessions are stored in the Supabase `records` table with `category=workouts` and `type=workout_session`. The app supports a pull/push/legs rotation schedule, automatically determining the next workout type based on the last completed session. Rest days are calculated to ensure adequate recovery between training sessions.

Workouts are visible both in the dedicated Workouts tab and integrated into the CalendarView (showing training schedule alongside calendar events).

## Architecture

```
Manual entry (iOS app / agent)
        │
        │ dashboard_push via dashboard-sync
        ▼
  records table (category=workouts, type=workout_session)
        │
        │ DashboardViewModel
        ▼
  iOS: WorkoutView → WorkoutViewModel
         └─→ CalendarView (training schedule overlay)
```

### Training Schedule

The app uses a **pull / push / legs** rotation:

| Day | Workout Type | Description |
|-----|-------------|-------------|
| Day 1 | Pull | Back + biceps (pull-ups, rows, curls) |
| Day 2 | Push | Chest + triceps + shoulders (bench, press, dips) |
| Day 3 | Legs | Quads, hamstrings, calves (squats, deadlifts, lunges) |
| Day 4 | Rest | Active recovery or rest |
| Repeat | Pull | Cycle continues |

Rest days are determined by:
- After every Legs session
- If the last workout was >48 hours ago (gap detection)
- Manual rest day marking by the user

### Workout Session Data

Each session records:
- Workout type (pull, push, legs, rest)
- Duration (if tracked)
- Exercises performed
- Notes
- Date/time

## Data Schema

### records table (workouts category)

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Owner |
| `category` | TEXT | `workouts` |
| `type` | TEXT | `workout_session` |
| `title` | TEXT | e.g., "Pull Day", "Push Day", "Rest Day" |
| `data` | JSONB | Workout payload |
| `display_hint` | TEXT | Display hint for rendering |
| `created_at` | TIMESTAMPTZ | When logged |

### data payload

**Resistance workout**:
```json
{
  "workout_type": "pull",
  "exercises": [
    { "name": "Pull-ups", "sets": 4, "reps": 8, "weight_kg": 20 },
    { "name": "Barbell Rows", "sets": 3, "reps": 10, "weight_kg": 60 },
    { "name": "Face Pulls", "sets": 3, "reps": 15, "weight_kg": 25 }
  ],
  "duration_minutes": 65,
  "notes": "Felt strong today. Increased pull-up weight.",
  "date": "2026-04-20"
}
```

**Rest day**:
```json
{
  "workout_type": "rest",
  "notes": "Recovery day. Light walk.",
  "date": "2026-04-22"
}
```

## Calendar Integration

Workout schedule is visible in CalendarView by querying records with `category=workouts` and overlaying them on calendar events. The calendar shows:
- Colored indicators for pull/push/legs/rest days
- Workout name as event title
- Duration if recorded

The calendar integration uses the same `records` table query, filtered by date range.

## Adding a Workout Session

1. **Via iOS app**: Open WorkoutView → tap "+" → select workout type → fill in exercises
2. **Via agent**: Use `dashboard_push` tool with `type=workout_session`, `category=workouts`

```typescript
// Agent: log a workout
await dashboard_push({
  agent_id: "claudinho",
  user_id: "00000000-0000-0000-0000-000000000000",
  type: "workout_session",
  category: "workouts",
  title: "Push Day",
  data: {
    workout_type: "push",
    exercises: [...],
    duration_minutes: 55
  },
  display_hint: "workout_session"
});
```

## Maintenance

### Debugging

```bash
# Check recent workouts
curl -G "https://cgmaotzmeoiueyzlchaz.supabase.co/rest/v1/records" \
  -H "apikey: $ANON_KEY" \
  --data-urlencode "category=eq.workouts" \
  --data-urlencode "order=created_at.desc" \
  --data-urlencode "limit=20"
```

### Common Issues

- **Calendar not showing workouts**: Verify the CalendarView is querying `category=eq.workouts` alongside calendar events. The query should union both sources.
- **Wrong workout type detected**: The rotation is computed client-side based on the last workout. If the app shows the wrong next workout, check that the most recent `workout_session` record has the correct `workout_type` in its `data` field.
- **Missing exercise data**: If exercises are not appearing, check that `data.exercises` is a properly formatted JSON array in the record.
