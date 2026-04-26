-- ============================================================================
-- 20260424000000_learned_senders.sql
--
-- Tier 3 of the orders-autopilot hardening pass (see
-- docs/superpowers/specs/2026-04-24-scraper-hardening-design.md once written).
--
-- Purpose
-- -------
-- A user-curated lookup table that maps a sender (full email or fallback
-- domain stem) to a canonical merchant name. The orders-autopilot pipeline
-- consults this table BEFORE its built-in keyword classifier and the LLM
-- fallback. When the user resolves a row in the iOS Settings → Order Review
-- queue, we write back the (sender → merchant) mapping here so the same
-- sender never has to be classified twice.
--
-- Lookup priority used by orders-autopilot:
--   1. learned_senders            (user-taught — highest trust)
--   2. hardcoded `known` list     (engineering-curated)
--   3. From: display name         (cleanDisplayName heuristic)
--   4. shopify body recovery
--   5. subject heuristic
--   6. domain stem prettify       (last resort)
--
-- Notes
-- -----
-- * (user_id, sender_email) is the primary lookup; full sender_email is
--   normalized lowercase before write/read.
-- * (user_id, sender_domain) is the fallback when the merchant rotates
--   noreply@ / orders@ / hello@ but keeps the same domain.
-- * sender_email is UNIQUE per user — the resolution path always upserts.
-- * normalized_merchant is denormalized so the autopilot can match
--   against `orders.normalized_merchant` without recomputing.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.learned_senders (
  id                            uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                       uuid          NOT NULL
                                              REFERENCES public.users(id) ON DELETE CASCADE,
  sender_email                  text          NOT NULL CHECK (length(sender_email) > 0),
  sender_domain                 text,
  merchant_name                 text          NOT NULL CHECK (length(merchant_name) > 0),
  normalized_merchant           text          NOT NULL CHECK (length(normalized_merchant) > 0),
  learned_from_email_id         text,
  learned_from_review_item_id   uuid          REFERENCES public.review_items(id) ON DELETE SET NULL,
  created_at                    timestamptz   NOT NULL DEFAULT now(),
  updated_at                    timestamptz   NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.learned_senders IS
  'User-curated sender→merchant mappings. Populated when the user resolves '
  'review-queue items. Consulted by orders-autopilot BEFORE keyword/LLM '
  'classification so the same sender is never classified twice.';

COMMENT ON COLUMN public.learned_senders.sender_email IS
  'Full lowercase email of the sender (e.g. "orders@hardgraft.com"). Primary '
  'lookup key. Not the From: display name.';

COMMENT ON COLUMN public.learned_senders.sender_domain IS
  'Lowercase domain stem (e.g. "hardgraft") used as a fallback match when '
  'the merchant rotates which mailbox sends order confirmations.';

COMMENT ON COLUMN public.learned_senders.normalized_merchant IS
  'lowercase, alphanumeric-only version of merchant_name. Mirrors the same '
  'derivation used in public.orders.normalized_merchant so a learned mapping '
  'lines up cleanly with existing rows.';

COMMENT ON COLUMN public.learned_senders.learned_from_review_item_id IS
  'Pointer back to the review_items row the user resolved to teach this '
  'mapping. Nullable so backfills / manual seeds remain possible.';

-- Per-user uniqueness on the full sender email. A given email address only
-- ever maps to one merchant for one user.
CREATE UNIQUE INDEX IF NOT EXISTS learned_senders_user_email_unique
  ON public.learned_senders (user_id, sender_email);

-- Secondary index for the (user_id, sender_domain) fallback path.
CREATE INDEX IF NOT EXISTS learned_senders_user_domain_idx
  ON public.learned_senders (user_id, sender_domain)
  WHERE sender_domain IS NOT NULL;

-- ─── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.learned_senders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS learned_senders_select_own ON public.learned_senders;
DROP POLICY IF EXISTS learned_senders_insert_own ON public.learned_senders;
DROP POLICY IF EXISTS learned_senders_update_own ON public.learned_senders;
DROP POLICY IF EXISTS learned_senders_delete_own ON public.learned_senders;

CREATE POLICY learned_senders_select_own
  ON public.learned_senders FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY learned_senders_insert_own
  ON public.learned_senders FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY learned_senders_update_own
  ON public.learned_senders FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY learned_senders_delete_own
  ON public.learned_senders FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ─── updated_at trigger ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.update_learned_senders_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS learned_senders_updated_at_trigger ON public.learned_senders;

CREATE TRIGGER learned_senders_updated_at_trigger
  BEFORE UPDATE ON public.learned_senders
  FOR EACH ROW
  EXECUTE FUNCTION public.update_learned_senders_updated_at();

COMMIT;
