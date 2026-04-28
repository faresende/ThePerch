#!/usr/bin/env python3
"""Unit tests for biochecha_dynamic_insight category scorers + ranker."""
import sys
import unittest
from dataclasses import replace
from datetime import datetime, timezone, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from biochecha_dynamic_insight import (
    AppState, NutritionTargets, SleepNight, Meal, CalendarEvent, OrderSummary,
    CategoryResult, EventTrigger,
    score_reflective_morning,
    rank,
)


def _base_state(slot: str = "morning") -> AppState:
    """Minimal state for tests — fill in only what each test needs."""
    return AppState(
        slot=slot,
        now=datetime(2026, 4, 28, 7, 0, tzinfo=timezone.utc),
        today_meals=[],
        today_targets=NutritionTargets(2500, 180, 280, 80),
        today_calendar_remaining=[],
        today_orders_in_transit=[],
        sleep_last_7=[],
        body_comp_last_30=[],
        workout_schedule_today="unknown",
        avg_steps_last_7_at_this_hour=0,
        event_trigger=None,
        recent_feedback=[],
    )


class TestReflectiveMorning(unittest.TestCase):
    def test_baseline_score_is_at_least_threshold(self):
        state = _base_state("morning")
        result = score_reflective_morning(state)
        self.assertIsNotNone(result)
        self.assertGreaterEqual(result.score, 0.3)
        self.assertEqual(result.category, "reflective_morning")

    def test_returns_none_when_slot_isnt_morning(self):
        state = _base_state("midday")
        self.assertIsNone(score_reflective_morning(state))

    def test_short_nights_streak_boosts_score(self):
        state = _base_state("morning")
        short_nights = [
            SleepNight(date=f"2026-04-{d}", duration_min=300.0)
            for d in (25, 26, 27, 28)
        ]
        state = replace(state, sleep_last_7=short_nights)
        result = score_reflective_morning(state)
        self.assertGreater(result.score, 0.6)
        self.assertIn("short_night_streak", result.fact_bundle)
        self.assertEqual(result.fact_bundle["short_night_streak"], 4)


class TestRanker(unittest.TestCase):
    def test_picks_highest_score(self):
        a = CategoryResult("reflective_morning", 0.5, {})
        b = CategoryResult("anomaly_recent_pattern", 0.7, {})
        winner = rank([a, b])
        self.assertEqual(winner.category, "anomaly_recent_pattern")

    def test_falls_back_to_quiet_day_when_below_threshold(self):
        weak = CategoryResult("reflective_morning", 0.1, {})
        winner = rank([weak])
        self.assertEqual(winner.category, "quiet_day_fallback")

    def test_tie_breaks_by_priority(self):
        a = CategoryResult("reflective_morning", 0.5, {})
        b = CategoryResult("anomaly_recent_pattern", 0.5, {})
        winner = rank([a, b])
        # anomaly_recent_pattern (priority 40) beats reflective_morning (10)
        self.assertEqual(winner.category, "anomaly_recent_pattern")


if __name__ == "__main__":
    unittest.main()
