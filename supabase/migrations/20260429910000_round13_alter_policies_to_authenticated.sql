-- 20260429910000_round13_alter_policies_to_authenticated.sql
--
-- Round 13 audit (MEDIUM M-2): 34 RLS policies across 11 public tables
-- target role `{public}` instead of `{authenticated}`. `public` matches
-- every role including anon. Today this is safe because R12 revoked
-- anon's table grants AND `auth.uid()` is NULL for anon (so the USING
-- clause's user_id check fails). But:
--   - It's defense-in-depth: a `pg_dump` restore that re-applied the
--     default Supabase grants would re-introduce anon, and these
--     `{public}`-targeted policies would still gate by auth.uid() —
--     but it's one less defense layer.
--   - It's pattern-mismatch with newer policies (R6's
--     `agents_select_own` and `agent_users_select_own` both correctly
--     target `{authenticated}`).
--
-- service_role doesn't need to be in the role list because it has
-- BYPASSRLS — it never goes through policy evaluation. Just authenticated.
--
-- Postgres 17's `ALTER POLICY ... TO role` lets us flip the role
-- without rewriting the USING / WITH CHECK clauses. Idempotent.

ALTER POLICY agents_delete_own                     ON public.agents                  TO authenticated;
ALTER POLICY agents_insert_own                     ON public.agents                  TO authenticated;
ALTER POLICY agents_update_own                     ON public.agents                  TO authenticated;

ALTER POLICY food_memories_delete_own              ON public.food_memories           TO authenticated;
ALTER POLICY food_memories_insert_own              ON public.food_memories           TO authenticated;
ALTER POLICY food_memories_select_accessible       ON public.food_memories           TO authenticated;
ALTER POLICY food_memories_update_own              ON public.food_memories           TO authenticated;

ALTER POLICY food_memory_observations_insert_own        ON public.food_memory_observations TO authenticated;
ALTER POLICY food_memory_observations_select_accessible ON public.food_memory_observations TO authenticated;

ALTER POLICY home_widgets_all_own                  ON public.home_widgets            TO authenticated;

ALTER POLICY orders_delete_own                     ON public.orders                  TO authenticated;
ALTER POLICY orders_insert_own                     ON public.orders                  TO authenticated;
ALTER POLICY orders_select_own                     ON public.orders                  TO authenticated;
ALTER POLICY orders_update_own                     ON public.orders                  TO authenticated;

ALTER POLICY records_delete_own                    ON public.records                 TO authenticated;
ALTER POLICY records_insert_own                    ON public.records                 TO authenticated;
ALTER POLICY records_read_own                      ON public.records                 TO authenticated;
ALTER POLICY records_update_own                    ON public.records                 TO authenticated;

ALTER POLICY review_items_delete_own               ON public.review_items            TO authenticated;
ALTER POLICY review_items_insert_own               ON public.review_items            TO authenticated;
ALTER POLICY review_items_select_own               ON public.review_items            TO authenticated;
ALTER POLICY review_items_update_own               ON public.review_items            TO authenticated;

ALTER POLICY sections_all_own                      ON public.sections                TO authenticated;

ALTER POLICY shipments_delete_own                  ON public.shipments               TO authenticated;
ALTER POLICY shipments_insert_own                  ON public.shipments               TO authenticated;
ALTER POLICY shipments_select_own                  ON public.shipments               TO authenticated;
ALTER POLICY shipments_update_own                  ON public.shipments               TO authenticated;

ALTER POLICY token_usage_delete_own                ON public.token_usage             TO authenticated;
ALTER POLICY token_usage_insert_own                ON public.token_usage             TO authenticated;
ALTER POLICY token_usage_select_own                ON public.token_usage             TO authenticated;
ALTER POLICY token_usage_update_own                ON public.token_usage             TO authenticated;

ALTER POLICY users_insert_own                      ON public.users                   TO authenticated;
ALTER POLICY users_read_own                        ON public.users                   TO authenticated;
ALTER POLICY users_update_own                      ON public.users                   TO authenticated;
