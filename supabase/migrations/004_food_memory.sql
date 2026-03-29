CREATE TABLE IF NOT EXISTS public.food_memories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL DEFAULT 'personal' CHECK (scope IN ('personal', 'shared')),
  canonical_name TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  brand TEXT,
  aliases TEXT[] NOT NULL DEFAULT '{}',
  serving_description TEXT,
  serving_basis TEXT NOT NULL DEFAULT 'custom' CHECK (
    serving_basis IN ('per_item', 'per_100g', 'per_serving', 'custom')
  ),
  calories NUMERIC(10, 2) NOT NULL DEFAULT 0,
  protein NUMERIC(10, 2) NOT NULL DEFAULT 0,
  carbs NUMERIC(10, 2) NOT NULL DEFAULT 0,
  fat NUMERIC(10, 2) NOT NULL DEFAULT 0,
  fiber NUMERIC(10, 2) NOT NULL DEFAULT 0,
  portion_notes TEXT,
  source TEXT NOT NULL DEFAULT 'manual' CHECK (
    source IN ('manual', 'llm', 'corrected', 'verified_shared')
  ),
  usage_count INT NOT NULL DEFAULT 0,
  last_used_at TIMESTAMPTZ,
  confidence_score NUMERIC(5, 4) NOT NULL DEFAULT 0,
  verification_state TEXT NOT NULL DEFAULT 'personal_default' CHECK (
    verification_state IN ('personal_default', 'shared_candidate', 'shared_verified', 'rejected')
  ),
  reference_meal_record_id UUID REFERENCES public.records(id) ON DELETE SET NULL,
  photo_fingerprint TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (
    (scope = 'personal' AND user_id IS NOT NULL)
    OR (scope = 'shared')
  )
);

CREATE TABLE IF NOT EXISTS public.food_memory_observations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  food_memory_id UUID NOT NULL REFERENCES public.food_memories(id) ON DELETE CASCADE,
  meal_record_id UUID REFERENCES public.records(id) ON DELETE SET NULL,
  action TEXT NOT NULL CHECK (
    action IN ('created_from_analysis', 'matched', 'corrected', 'promoted_to_shared', 'demoted')
  ),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_food_memories_personal_identity
  ON public.food_memories(user_id, scope, normalized_name)
  WHERE scope = 'personal';

CREATE UNIQUE INDEX IF NOT EXISTS idx_food_memories_shared_identity
  ON public.food_memories(scope, normalized_name)
  WHERE scope = 'shared';

CREATE INDEX IF NOT EXISTS idx_food_memories_user_id ON public.food_memories(user_id);
CREATE INDEX IF NOT EXISTS idx_food_memories_normalized_name ON public.food_memories(normalized_name);
CREATE INDEX IF NOT EXISTS idx_food_memories_scope ON public.food_memories(scope);
CREATE INDEX IF NOT EXISTS idx_food_memories_verification_state ON public.food_memories(verification_state);
CREATE INDEX IF NOT EXISTS idx_food_memories_last_used_at ON public.food_memories(last_used_at DESC);
CREATE INDEX IF NOT EXISTS idx_food_memory_observations_food_memory_id
  ON public.food_memory_observations(food_memory_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_food_memory_observations_meal_record_id
  ON public.food_memory_observations(meal_record_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_food_memories_aliases_gin ON public.food_memories USING GIN (aliases);

CREATE OR REPLACE FUNCTION public.update_food_memories_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_food_memories_updated_at ON public.food_memories;
CREATE TRIGGER trigger_food_memories_updated_at
BEFORE UPDATE ON public.food_memories
FOR EACH ROW
EXECUTE FUNCTION public.update_food_memories_updated_at();

ALTER TABLE public.food_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.food_memory_observations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS food_memories_select_accessible ON public.food_memories;
CREATE POLICY food_memories_select_accessible
  ON public.food_memories FOR SELECT
  USING (
    (scope = 'personal' AND user_id = auth.uid())
    OR (scope = 'shared' AND verification_state = 'shared_verified')
  );

DROP POLICY IF EXISTS food_memories_insert_own ON public.food_memories;
CREATE POLICY food_memories_insert_own
  ON public.food_memories FOR INSERT
  WITH CHECK (
    scope = 'personal'
    AND user_id = auth.uid()
  );

DROP POLICY IF EXISTS food_memories_update_own ON public.food_memories;
CREATE POLICY food_memories_update_own
  ON public.food_memories FOR UPDATE
  USING (
    scope = 'personal'
    AND user_id = auth.uid()
  )
  WITH CHECK (
    scope = 'personal'
    AND user_id = auth.uid()
  );

DROP POLICY IF EXISTS food_memories_delete_own ON public.food_memories;
CREATE POLICY food_memories_delete_own
  ON public.food_memories FOR DELETE
  USING (
    scope = 'personal'
    AND user_id = auth.uid()
  );

DROP POLICY IF EXISTS food_memory_observations_select_accessible ON public.food_memory_observations;
CREATE POLICY food_memory_observations_select_accessible
  ON public.food_memory_observations FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.food_memories fm
      WHERE fm.id = food_memory_observations.food_memory_id
        AND (
          (fm.scope = 'personal' AND fm.user_id = auth.uid())
          OR (fm.scope = 'shared' AND fm.verification_state = 'shared_verified')
        )
    )
  );

DROP POLICY IF EXISTS food_memory_observations_insert_own ON public.food_memory_observations;
CREATE POLICY food_memory_observations_insert_own
  ON public.food_memory_observations FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.food_memories fm
      WHERE fm.id = food_memory_observations.food_memory_id
        AND fm.scope = 'personal'
        AND fm.user_id = auth.uid()
    )
  );
