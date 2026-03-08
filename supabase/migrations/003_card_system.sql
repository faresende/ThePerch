-- ==========================================================================
-- The Perch - Card system schema extensions
--
-- Extends public.records with universal card metadata.
-- Adds public.token_usage.user_id for multi-tenant RLS (required by 001_enable_rls.sql)
-- ==========================================================================

-- --------------------------------------------------------------------------
-- 1) records table extensions
-- --------------------------------------------------------------------------
ALTER TABLE public.records
  ADD COLUMN IF NOT EXISTS schema_version INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS subtitle TEXT,
  ADD COLUMN IF NOT EXISTS actions JSONB,
  ADD COLUMN IF NOT EXISTS refresh_policy TEXT NOT NULL DEFAULT 'push',
  ADD COLUMN IF NOT EXISTS importance INT NOT NULL DEFAULT 50,
  ADD COLUMN IF NOT EXISTS urgency INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS accent_color TEXT,
  ADD COLUMN IF NOT EXISTS icon TEXT,
  ADD COLUMN IF NOT EXISTS state TEXT NOT NULL DEFAULT 'ok',
  ADD COLUMN IF NOT EXISTS error_message TEXT;

-- Optional constraints (safe; may fail if existing data violates; run manually if desired)
-- ALTER TABLE public.records
--   ADD CONSTRAINT records_importance_range CHECK (importance >= 0 AND importance <= 100);
-- ALTER TABLE public.records
--   ADD CONSTRAINT records_urgency_range CHECK (urgency >= 0 AND urgency <= 100);
-- ALTER TABLE public.records
--   ADD CONSTRAINT records_refresh_policy_allowed CHECK (refresh_policy IN ('push','pull','interval'));
-- ALTER TABLE public.records
--   ADD CONSTRAINT records_state_allowed CHECK (state IN ('ok','loading','error'));

CREATE INDEX IF NOT EXISTS idx_records_state ON public.records(state);

-- --------------------------------------------------------------------------
-- 2) token_usage: add user_id for multi-tenant RLS
-- --------------------------------------------------------------------------
ALTER TABLE public.token_usage
  ADD COLUMN IF NOT EXISTS user_id UUID;

-- Backfill user_id from agent owner_id where possible
UPDATE public.token_usage tu
SET user_id = a.owner_id
FROM public.agents a
WHERE tu.agent_id = a.id
  AND tu.user_id IS NULL;

-- Make non-null after backfill (only if you are confident all rows backfilled)
-- ALTER TABLE public.token_usage
--   ALTER COLUMN user_id SET NOT NULL;

-- Index + FK
CREATE INDEX IF NOT EXISTS idx_token_usage_user_id_date ON public.token_usage(user_id, date);

ALTER TABLE public.token_usage
  ADD CONSTRAINT IF NOT EXISTS token_usage_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
