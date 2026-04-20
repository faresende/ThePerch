# QUICKSTART.md - Perch Health Pipeline

## Health Data Flow

```
Oura Ring → Oura API → records table (category=health)
                         │
BioChecha (manual) ──────→ dashboard-sync → dashboard_records → iOS widgets
```

## Oura Metrics Available

| Metric | Type | Unit | Display |
|--------|------|------|---------|
| Sleep score | measurement | score (0-100) | chart |
| Deep sleep | measurement | minutes | chart |
| REM sleep | measurement | minutes | chart |
| Light sleep | measurement | minutes | chart |
| Awake time | measurement | minutes | chart |
| Readiness | measurement | score (0-100) | single_value |
| Resting HR | measurement | bpm | chart |
| HRV | measurement | ms | chart |

## Manual Body Metrics

| Metric | Unit | Source |
|--------|------|--------|
| Weight | kg | BioChecha / manual entry |
| Body fat % | % | BioChecha / manual entry |
| Muscle mass | kg | BioChecha / manual entry |

## Testing

```bash
# Query health records directly
curl -G "https://cgmaotzmeoiueyzlchaz.supabase.co/rest/v1/records" \
  -H "apikey: $ANON_KEY" \
  --data-urlencode "category=eq.health" \
  --data-urlencode "order=created_at.desc" \
  --data-urlencode "limit=10"
```

## Adding a New Metric

1. Write to `records` with `type=measurement`, `category=health`
2. Set `display_hint=chart` for trending display
3. Add to HealthViewModel's aggregation queries
4. Register in HealthView card renderer
