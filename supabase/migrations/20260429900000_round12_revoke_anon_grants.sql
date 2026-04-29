-- 20260429900000_round12_revoke_anon_grants.sql
--
-- Round 12 audit (MEDIUM M-1): RLS denies anon for SELECT/INSERT/UPDATE/
-- DELETE on every public table because no policy targets `anon` (NULL =
-- NULL → false). But Postgres TRUNCATE bypasses RLS. And REFERENCES lets
-- anon create FKs pointing at these tables, usable as a row-existence
-- oracle under some PostgREST patterns. R10 only revoked anon on
-- `bookmarks`; the other 22+ public tables still inherit `arwdDxtm` from
-- the Supabase template.
--
-- Sweep: revoke ALL on every public table where anon currently has any
-- grant. Idempotent (REVOKE on something not granted is a no-op).

REVOKE ALL ON TABLE public.active_shipments_summary    FROM anon;
REVOKE ALL ON TABLE public.agent_runs                  FROM anon;
REVOKE ALL ON TABLE public.agent_runs_latest           FROM anon;
REVOKE ALL ON TABLE public.agent_users                 FROM anon;
REVOKE ALL ON TABLE public.agents                      FROM anon;
REVOKE ALL ON TABLE public.dashboard_records           FROM anon;
REVOKE ALL ON TABLE public.email_classifications       FROM anon;
REVOKE ALL ON TABLE public.food_memories               FROM anon;
REVOKE ALL ON TABLE public.food_memory_observations    FROM anon;
REVOKE ALL ON TABLE public.health_metrics              FROM anon;
REVOKE ALL ON TABLE public.home_widgets                FROM anon;
REVOKE ALL ON TABLE public.insight_feedback            FROM anon;
REVOKE ALL ON TABLE public.insights                    FROM anon;
REVOKE ALL ON TABLE public.learned_senders             FROM anon;
REVOKE ALL ON TABLE public.merchant_rules              FROM anon;
REVOKE ALL ON TABLE public.order_corrections           FROM anon;
REVOKE ALL ON TABLE public.order_items                 FROM anon;
REVOKE ALL ON TABLE public.orders                      FROM anon;
REVOKE ALL ON TABLE public.records                     FROM anon;
REVOKE ALL ON TABLE public.review_items                FROM anon;
REVOKE ALL ON TABLE public.sections                    FROM anon;
REVOKE ALL ON TABLE public.shipments                   FROM anon;
REVOKE ALL ON TABLE public.token_usage                 FROM anon;
REVOKE ALL ON TABLE public.users                       FROM anon;

-- Note: the iOS app and skill-side code authenticate as the user (JWT)
-- via the `authenticated` role, never as `anon`. The Supabase Auth flow
-- (sign-up / sign-in / password recovery) goes through `auth.*` schema
-- via the supabase-js client and doesn't touch public tables under
-- `anon`. So this sweep is purely defense-in-depth — it doesn't change
-- any working code path.
