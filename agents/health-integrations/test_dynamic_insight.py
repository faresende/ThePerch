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
    """Reflective morning runs in `morning_post_wake` only — the 7am
    pre-wake slot can't see fresh sleep / weight data so retrospection
    there would be misleading."""

    def test_baseline_score_is_at_least_threshold(self):
        state = _base_state("morning_post_wake")
        result = score_reflective_morning(state)
        self.assertIsNotNone(result)
        self.assertGreaterEqual(result.score, 0.3)
        self.assertEqual(result.category, "reflective_morning")

    def test_returns_none_in_pre_wake_morning_slot(self):
        state = _base_state("morning")
        self.assertIsNone(score_reflective_morning(state),
            "pre-wake 7am slot must NOT trigger reflective categories")

    def test_returns_none_when_slot_isnt_morning(self):
        state = _base_state("midday")
        self.assertIsNone(score_reflective_morning(state))

    def test_short_nights_streak_boosts_score(self):
        state = _base_state("morning_post_wake")
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


from biochecha_dynamic_insight import (
    score_anticipatory_lunch_window,
    score_goal_pacing_protein,
    score_logistics_arriving_today,
    score_opportunistic_walk,
    score_opportunistic_workout,
    score_goal_pacing_calories,
    score_anomaly_recent_pattern,
    score_recap_day,
    score_anticipatory_tomorrow,
    score_reflective_evening,
    score_behavioral_capture_gap,
)


class TestAnticipatoryLunchWindow(unittest.TestCase):
    def test_high_score_when_busy_afternoon_and_low_calories(self):
        state = _base_state("midday")
        state = replace(state, now=datetime(2026, 4, 28, 12, 0, tzinfo=timezone.utc))
        # 3 events in next 4h → busy afternoon trigger
        state = replace(state, today_calendar_remaining=[
            CalendarEvent(
                start=datetime(2026, 4, 28, 14, 0, tzinfo=timezone.utc),
                end=datetime(2026, 4, 28, 14, 30, tzinfo=timezone.utc),
                title="Meeting 1",
            ),
            CalendarEvent(
                start=datetime(2026, 4, 28, 15, 0, tzinfo=timezone.utc),
                end=datetime(2026, 4, 28, 15, 30, tzinfo=timezone.utc),
                title="Meeting 2",
            ),
            CalendarEvent(
                start=datetime(2026, 4, 28, 16, 0, tzinfo=timezone.utc),
                end=datetime(2026, 4, 28, 16, 30, tzinfo=timezone.utc),
                title="Meeting 3",
            ),
        ])
        # No meals → calories=0 < 40% of 2500
        result = score_anticipatory_lunch_window(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.7)
        self.assertEqual(result.category, "anticipatory_lunch_window")

    def test_zero_when_not_midday(self):
        state = _base_state("morning")
        self.assertIsNone(score_anticipatory_lunch_window(state))


class TestGoalPacingProtein(unittest.TestCase):
    def test_score_scales_with_deficit(self):
        state = _base_state("midday")
        # Big deficit: 0g of 180g target.
        result = score_goal_pacing_protein(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.5)

    def test_low_score_when_on_track(self):
        state = _base_state("midday")
        state = replace(state, today_meals=[
            Meal(calories=500, protein=170, carbs=40, fat=15,
                 meal_time=datetime(2026, 4, 28, 12, 0, tzinfo=timezone.utc)),
        ])
        result = score_goal_pacing_protein(state)
        self.assertLess(result.score, 0.3,
            "near-target protein should not surface as a slot winner")


class TestLogisticsArrivingToday(unittest.TestCase):
    def test_high_score_when_eta_today(self):
        state = _base_state("afternoon")
        state = replace(state, today_orders_in_transit=[
            OrderSummary(
                merchant="Body & Fit", order_number="BF1429199",
                carrier="DHL", tracking_number="CQ478942688DE",
                eta_at=datetime(2026, 4, 28, 17, 0, tzinfo=timezone.utc),
                status="in_transit",
            ),
        ])
        result = score_logistics_arriving_today(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.8)
        self.assertIn("arriving", result.fact_bundle)


class TestOpportunisticWalk(unittest.TestCase):
    def test_fires_on_rest_day_with_calendar_gap(self):
        state = _base_state("afternoon")
        state = replace(state,
            now=datetime(2026, 4, 28, 15, 0, tzinfo=timezone.utc),
            workout_schedule_today="rest",
            today_calendar_remaining=[
                CalendarEvent(
                    start=datetime(2026, 4, 28, 17, 30, tzinfo=timezone.utc),
                    end=datetime(2026, 4, 28, 18, 0, tzinfo=timezone.utc),
                    title="Design review"),
            ],
        )
        result = score_opportunistic_walk(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.7)
        self.assertEqual(result.fact_bundle.get("gap_min"), 150)

    def test_skips_when_workout_scheduled_today(self):
        state = _base_state("afternoon")
        state = replace(state, workout_schedule_today="training")
        self.assertIsNone(score_opportunistic_walk(state))


class TestAnomalyRecentPattern(unittest.TestCase):
    def test_three_short_nights_in_a_row(self):
        state = _base_state("morning")
        state = replace(state, sleep_last_7=[
            SleepNight(date="2026-04-26", duration_min=320),
            SleepNight(date="2026-04-27", duration_min=300),
            SleepNight(date="2026-04-28", duration_min=280),
        ])
        result = score_anomaly_recent_pattern(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.5)
        self.assertIn("pattern", result.fact_bundle)


class TestRecapDay(unittest.TestCase):
    def test_always_eligible_in_evening(self):
        state = _base_state("evening")
        result = score_recap_day(state)
        self.assertIsNotNone(result)
        self.assertEqual(result.score, 1.0)
        self.assertEqual(result.category, "recap_day")

    def test_skips_outside_evening(self):
        state = _base_state("morning")
        self.assertIsNone(score_recap_day(state))


class TestBehavioralCaptureGap(unittest.TestCase):
    def test_fires_when_no_meals_logged_today(self):
        state = _base_state("evening")
        state = replace(state, now=datetime(2026, 4, 28, 20, 0, tzinfo=timezone.utc))
        # No today_meals at 20:00 — capture is broken or skipped.
        result = score_behavioral_capture_gap(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.5)
        self.assertEqual(result.fact_bundle.get("hours_since_last"), None)
        self.assertEqual(result.fact_bundle.get("today_meal_count"), 0)


from biochecha_dynamic_insight import (
    score_logistics_event_out_for_delivery,
    score_logistics_event_eta_today,
    is_recent_topic_overlap,
    score_anticipatory_today_training,
    score_anticipatory_today_macros,
    score_body_composition_change,
    BodyComp,
)


class TestAnticipatoryTodayTraining(unittest.TestCase):
    def test_only_pre_wake_morning(self):
        state = _base_state("morning_post_wake")
        self.assertIsNone(score_anticipatory_today_training(state))
        state = _base_state("midday")
        self.assertIsNone(score_anticipatory_today_training(state))

    def test_training_day_with_meetings_scores_high(self):
        state = _base_state("morning")
        state = replace(state,
            workout_schedule_today="training",
            today_calendar_remaining=[
                CalendarEvent(
                    start=datetime(2026, 4, 28, 9, 0, tzinfo=timezone.utc),
                    end=datetime(2026, 4, 28, 13, 0, tzinfo=timezone.utc),
                    title="Workshop"),
                CalendarEvent(
                    start=datetime(2026, 4, 28, 14, 0, tzinfo=timezone.utc),
                    end=datetime(2026, 4, 28, 15, 0, tzinfo=timezone.utc),
                    title="1:1"),
            ],
        )
        result = score_anticipatory_today_training(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.7)
        self.assertEqual(result.fact_bundle["workout_today"], "training")
        self.assertGreaterEqual(result.fact_bundle["meetings_today_minutes"], 240)


class TestAnticipatoryTodayMacros(unittest.TestCase):
    def test_only_pre_wake_morning(self):
        state = _base_state("evening")
        self.assertIsNone(score_anticipatory_today_macros(state))

    def test_busy_day_with_no_eating_gap_scores_high(self):
        state = _base_state("morning")
        # 8am-9pm with back-to-back meetings → tight eating window
        events = []
        for hour in range(9, 20):
            events.append(CalendarEvent(
                start=datetime(2026, 4, 28, hour, 0, tzinfo=timezone.utc),
                end=datetime(2026, 4, 28, hour, 50, tzinfo=timezone.utc),
                title=f"Meeting {hour}"))
        state = replace(state, today_calendar_remaining=events)
        result = score_anticipatory_today_macros(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.7)
        self.assertLess(result.fact_bundle["biggest_eating_gap_min"], 90)


class TestBodyCompositionChange(unittest.TestCase):
    def test_only_post_wake_slot(self):
        state = _base_state("morning")
        self.assertIsNone(score_body_composition_change(state))

    def test_returns_none_when_no_data(self):
        state = _base_state("morning_post_wake")
        self.assertIsNone(score_body_composition_change(state))

    def test_significant_drop_scores_high(self):
        state = _base_state("morning_post_wake")
        state = replace(state,
            now=datetime(2026, 4, 28, 8, 0, tzinfo=timezone.utc),
            body_comp_last_30=[
                BodyComp(date=f"2026-04-{d}", weight_kg=99.5)
                for d in range(21, 28)
            ] + [
                BodyComp(date="2026-04-28", weight_kg=98.0,
                         body_fat_pct=18.0, fat_mass_kg=17.6,
                         muscle_mass_kg=53.3),
            ],
        )
        result = score_body_composition_change(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.7)
        self.assertEqual(result.fact_bundle["weight_kg_today"], 98.0)
        self.assertLess(result.fact_bundle["weight_delta_kg"], -1.0)


class TestLogisticsEventCategories(unittest.TestCase):
    def test_out_for_delivery_scores_high(self):
        state = _base_state("event_logistics")
        state = replace(state, event_trigger=EventTrigger(
            kind="out_for_delivery",
            merchant="Body & Fit", carrier="DHL",
            tracking_number="CQ478942688DE",
            old_status="in_transit", new_status="out_for_delivery",
            eta_at=None,
        ))
        result = score_logistics_event_out_for_delivery(state)
        self.assertIsNotNone(result)
        self.assertEqual(result.score, 1.0)

    def test_eta_today_only_fires_for_eta_today_event(self):
        state = _base_state("event_logistics")
        state = replace(state, event_trigger=EventTrigger(
            kind="eta_today",
            merchant="Hardgraft", carrier="DPD",
            tracking_number="15976785968210",
            old_status="in_transit", new_status="in_transit",
            eta_at=datetime(2026, 4, 28, 17, 0, tzinfo=timezone.utc),
        ))
        result = score_logistics_event_eta_today(state)
        self.assertIsNotNone(result)
        self.assertGreaterEqual(result.score, 0.9)


class TestDontChurnGuard(unittest.TestCase):
    def test_overlap_blocks_when_same_shipment_referenced(self):
        recent = {
            "winning_category": "logistics_event_out_for_delivery",
            "fact_bundle": {"tracking_number": "CQ478942688DE"},
        }
        self.assertTrue(is_recent_topic_overlap(recent, "CQ478942688DE"))

    def test_overlap_clears_when_different_shipment(self):
        recent = {
            "winning_category": "logistics_event_out_for_delivery",
            "fact_bundle": {"tracking_number": "AAAA"},
        }
        self.assertFalse(is_recent_topic_overlap(recent, "BBBB"))

    def test_overlap_clears_when_different_topic(self):
        recent = {
            "winning_category": "reflective_morning",
            "fact_bundle": {},
        }
        self.assertFalse(is_recent_topic_overlap(recent, "any-tracking"))


from biochecha_dynamic_insight import _pick_by_priority


class TestPickByPriority(unittest.TestCase):
    def test_prefers_higher_priority_source(self):
        rows = [
            {"measured_at": "2026-04-29T06:00:00+00:00", "metric": "weight_kg",
             "value": 99.5, "source": "withings"},
            {"measured_at": "2026-04-29T06:49:00+00:00", "metric": "weight_kg",
             "value": 98.1, "source": "inbody"},
        ]
        chosen = _pick_by_priority(rows, ("inbody", "withings"))
        self.assertEqual(chosen[("2026-04-29", "weight_kg")]["source"], "inbody")
        self.assertEqual(chosen[("2026-04-29", "weight_kg")]["value"], 98.1)

    def test_falls_back_to_lower_priority_when_primary_silent(self):
        rows = [
            {"measured_at": "2026-04-15T07:00:00+00:00", "metric": "weight_kg",
             "value": 99.0, "source": "withings"},
        ]
        chosen = _pick_by_priority(rows, ("inbody", "withings"))
        self.assertEqual(chosen[("2026-04-15", "weight_kg")]["source"], "withings")

    def test_within_same_source_keeps_latest(self):
        rows = [
            {"measured_at": "2026-04-29T06:00:00+00:00", "metric": "weight_kg",
             "value": 98.5, "source": "inbody"},
            {"measured_at": "2026-04-29T18:00:00+00:00", "metric": "weight_kg",
             "value": 98.1, "source": "inbody"},
        ]
        chosen = _pick_by_priority(rows, ("inbody", "withings"))
        self.assertEqual(chosen[("2026-04-29", "weight_kg")]["value"], 98.1)

    def test_unknown_source_ranks_last_but_still_appears(self):
        rows = [
            {"measured_at": "2026-04-29T07:00:00+00:00", "metric": "weight_kg",
             "value": 100.0, "source": "fitbit"},
        ]
        chosen = _pick_by_priority(rows, ("inbody", "withings"))
        # No higher-priority data — keep the unknown-source row.
        self.assertIn(("2026-04-29", "weight_kg"), chosen)


if __name__ == "__main__":
    unittest.main()
