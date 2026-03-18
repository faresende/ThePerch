# Changelog

All notable changes to ThePerch iOS app are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

_Nothing here yet. Add upcoming changes before next deploy._

---

## [Build 43] - 2026-03-18

### Fixed
- Push section content below floating pill bar
- Compile error in WorkoutView and push local changes
- Reduce triple card shadow to single (eliminates flicker on tab switch)
- Travel home card header uses suitcase icon (not airplane, avoids double plane)
- Heartbeat card status color (green/amber/red based on age)
- Calories header wrapping + shorten freshness labels
- Sleep score bar track now visible (was same color as card bg)
- Chip strip: smaller emoji, tighter spacing, proper vertical centering
- Chip strip fills width, 3 chips visible without cropping
- Chip strip uses cardStyle, removed fixed height, consistent borders
- Remove double padding on chip strip (align with other cards)
- Calendar event time labels wrapping vertically
- Add unknown record type fallback, fix calendar_event decoding, fix greeting
- Shorten stale data label (remove verbose 'Data may be outdated')
- Glass header extends to top edge, fix tab switch lag
- Full-width glass header bar (no rounded corners on sides)
- Layer ultraThinMaterial under glassEffect for visible translucency
- Resilient decoding for Supabase records (P0)
- Calorie and Workout tab bugs (P0)
- Sort daily records by updatedAt desc to capture intraday updates (P0)

### Added
- Workout cards + fix connection error persistence
- Chip strip replacing summary card (glanceable 3-chip quick view)
- Liquid Glass card treatment + glass header (Sprint 7)
- Travel feature (Sprint 1–3) + chart fixes + calories logic
- Travel tasks: pre-trip checklist + inline day tasks
- New app icon: P with subtle bird negative space, layered Liquid Glass variant
- SF Symbol leading icon to segment cards

### Changed
- Sleep & recovery card redesigned: score hero, kill rings, inline metrics
- Design audit fixes: all criticals + warnings
- Segment cards redesigned: remove tag pills, use status dots (card layout v3)
- Travel timeline: hotel split, names, type tags, weather condition display
- Inline day tasks moved before segment cards instead of after
- Code quality cleanup (Sprint 6)
- Admin safety + polish (Sprint 5)
- Calendar upgrade (Sprint 4)
- Missing states (Sprint 3)
- Visual consistency (Sprint 2)
- Crash prevention + auth foundation (Sprint 1)

### Removed
- Summary card (replaced by chip strip)
- Triple card shadow (replaced with single shadow)

---

## [Build 42] - 2026-02-XX

_Pre-changelog. See git history for details._

---

[Unreleased]: https://github.com/your-org/theperch/compare/build/43...HEAD
[Build 43]: https://github.com/your-org/theperch/compare/build/42...build/43
[Build 42]: https://github.com/your-org/theperch/releases/tag/build/42
