# Archived health-integration scripts

These scripts are retained for reference but are no longer part of any
live pipeline.

| File | Retired | Replaced by |
|---|---|---|
| `biochecha_daily_insight.py` | 2026-04-28 | The time-aware-insights stack: `biochecha_dynamic_insight.py` (4 cron-fired slots) + `biochecha_post_wake_insight.py` (InBody-watcher fired) + `biochecha_event_insight.py` (17track-fired). |

Restore with `git mv` if you ever need the old behavior back.
