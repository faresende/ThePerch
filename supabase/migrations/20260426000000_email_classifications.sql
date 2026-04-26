-- ============================================================================
-- 20260426000000_email_classifications.sql
--
-- Telemetry table for the orders-autopilot pipeline. One row per email
-- classified, capturing every signal the autopilot used to make its
-- decision.
--
-- Why
-- ---
-- Until this lands, every false-positive bug we've fixed (Amex trip
-- reminder, El Corte Inglés receipt, OUTLOOK CSS-selector, etc.) was
-- caught because the user noticed a wrong row in the iOS Orders tab.
-- The El Corte Inglés bug had been silently firing the LLM on every
-- "other" email for weeks because of a 1.0-confidence floor we couldn't
-- see. We need observability so we can:
--   1. Audit edge cases without re-running emails through the live
--      pipeline.
--   2. Detect drift early (e.g. "we started silently dropping all PT
--      orders this week").
--   3. Build a proper sender-reputation prior in #7.
--   4. Train a learned classifier in #8 once we have labeled data.
--
-- Owned by the dashboard-sync skill; written from
-- skill/dashboard-sync/src/classifications-store.ts.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.email_classifications (
  id                          uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                     uuid          NOT NULL
                                            REFERENCES public.users(id) ON DELETE CASCADE,

  -- Email identity (not a FK; emails live in JMAP, not Supabase).
  email_id                    text          NOT NULL,
  subject                     text,
  sender_email                text,
  sender_name                 text,

  -- Tier 1 (keyword) signals.
  tier1_purchase_score        numeric,
  tier1_shipping_score        numeric,
  tier1_type                  text,         -- 'purchase_confirmation' | 'shipping_notification' | 'other'
  tier1_confidence            numeric,
  tier1_matched_keywords      text[],       -- which signals fired

  -- Tier 2 (LLM second-pass) signals. NULL when the LLM was not called.
  llm_called                  boolean       NOT NULL DEFAULT false,
  llm_provider                text,         -- 'ollama' | 'anthropic' | 'failed' | NULL
  llm_is_purchase             boolean,
  llm_confidence              numeric,
  llm_merchant_name           text,
  llm_order_number            text,

  -- Tier 3 (learned_senders) signal.
  learned_sender_matched      boolean       NOT NULL DEFAULT false,
  learned_sender_match_axis   text,         -- 'sender_email' | 'sender_domain' | NULL

  -- Final outcome.
  final_action                text          NOT NULL,
                                            -- 'created_order' | 'updated_order' |
                                            -- 'linked_shipment' | 'created_review_item' |
                                            -- 'skipped' | 'error'
  merchant_source             text,         -- 'learnedSender' | 'known' | 'displayName' |
                                            -- 'shopifyBody' | 'subject' | 'domainStem' | NULL
  resolved_merchant           text,
  resolved_order_number       text,
  resolved_total_amount       numeric,
  resolved_currency           text,

  -- Pointers back to whatever the autopilot wrote (if anything).
  related_order_id            uuid          REFERENCES public.orders(id) ON DELETE SET NULL,
  related_review_item_id      uuid          REFERENCES public.review_items(id) ON DELETE SET NULL,

  -- Diagnostic detail when final_action = 'error', or a short note for
  -- the autopilot health view.
  detail                      text,

  classified_at               timestamptz   NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.email_classifications IS
  'Per-email telemetry from the orders-autopilot pipeline. One row per '
  'classification decision, used to audit false positives / negatives, build '
  'sender reputation priors, and (eventually) train a replacement classifier.';

COMMENT ON COLUMN public.email_classifications.tier1_matched_keywords IS
  'Names of the purchase/shipping/travel/marketing signals that fired in '
  'Tier 1 keyword scoring. Useful for offline debugging without re-running '
  'the email through the pipeline.';

COMMENT ON COLUMN public.email_classifications.final_action IS
  'What the autopilot ultimately did with this email. Reading the action '
  'distribution over time is the fastest way to spot regressions ("we '
  'stopped creating orders this week" / "we started queueing 3x as many '
  'review items").';

-- Most-recent-first per user is the dominant query (autopilot health view).
CREATE INDEX IF NOT EXISTS email_classifications_user_recent_idx
  ON public.email_classifications (user_id, classified_at DESC);

-- For "did we already classify this email" lookups during reprocessing.
CREATE INDEX IF NOT EXISTS email_classifications_email_id_idx
  ON public.email_classifications (email_id);

-- For sender-reputation queries ("how often does this sender produce
-- created_order vs skipped vs review_item").
CREATE INDEX IF NOT EXISTS email_classifications_user_sender_idx
  ON public.email_classifications (user_id, sender_email);

-- ─── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.email_classifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS email_classifications_select_own ON public.email_classifications;
DROP POLICY IF EXISTS email_classifications_insert_own ON public.email_classifications;
DROP POLICY IF EXISTS email_classifications_update_own ON public.email_classifications;
DROP POLICY IF EXISTS email_classifications_delete_own ON public.email_classifications;

CREATE POLICY email_classifications_select_own
  ON public.email_classifications FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY email_classifications_insert_own
  ON public.email_classifications FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY email_classifications_update_own
  ON public.email_classifications FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY email_classifications_delete_own
  ON public.email_classifications FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

COMMIT;
