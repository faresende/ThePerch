# ThePerch Code Audit - Production Readiness
**Date:** 2026-03-15

## CRITICAL (Crash Risk) — 6 issues

1. **Force unwrap in BackgroundRefreshService** — `task as! BGAppRefreshTask` will crash if wrong task type
2. **7 force casts in JSONValueDecoder** — `as! T` for Date/URL/Decimal, crash if type mismatch
3. **CacheService is `@unchecked Sendable`** with mutable file I/O and no synchronization (data corruption risk)
4. **CrashReporter is `@unchecked Sendable`** with mutable properties, no sync
5. **AppConfig placeholder URL force unwrap** — pattern precedent, silent network errors with placeholder Supabase URL
6. **AuthViewModel leaks authObserverTask** — Task runs forever, never cancelled, deinit can't access @MainActor property

## WARNING (Bug Risk) — 15 issues

1. **Hardcoded user ID** in AdminCommandService + HealthKitSyncService (Fábio's UUID, force unwrap)
2. **Auth gate commented out** — entire auth flow disabled, all data accessible without login
3. **Hardcoded "default_user" cache key** in 4 files — all users would share same cache
4. **Hardcoded "Fabio"** in greeting, settings, auth views
5. **3 duplicate relativeTime implementations** — divergence risk
6. **2 duplicate CardGalleryView files** — compile conflict risk
7. **SectionViewModelProtocol declared but never used** — dead protocol
8. **DateFormatting enum largely redundant** — duplicates PerchFormatters
9. **updateHomeWidgets is a no-op** — TODO comment, silently does nothing
10. **NotificationService.initTask potential retain** — Task stored but never cancelled/nil'd
11. **Duplicate network monitoring** — SupabaseService creates its own NWPathMonitor alongside NetworkMonitor singleton
12. **Missing Sendable conformance** on Record, Section, JSONValue, all payload structs (Swift 6 warnings)
13. **AdminViewModel fire-and-forget Tasks** — missing [weak self] on delayed state resets
14. **DashboardViewModel.preDecodeRecords nonisolated** accessing non-Sendable types
15. **Agent emoji/name mapping duplicated** in AdminViewModel + WidgetRouter

## POLISH (Cleanup) — 8+ issues

1. **~60 debug print() statements** in production code (data leak risk)
2. **2 TODO comments** left in code
3. **Legacy DispatchQueue.main.asyncAfter** instead of structured concurrency
4. **DecodingCache no totalCostLimit** — memory could grow unbounded
5. **AgentCost.percent always returns 0** — dead computed property
6. **MockData references** should verify all inside #if DEBUG
7. **AmbienceManager timer** never invalidated
8. **Duplicate agent helper functions** across files
