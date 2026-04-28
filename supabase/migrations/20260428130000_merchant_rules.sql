-- ============================================================================
-- 20260428130000_merchant_rules.sql
--
-- Corrections-and-rules feedback loop — Phase 2 distill layer.
--
-- Adds:
--   1. merchant_rules table              — durable rules that gate the orders
--                                          autopilot. One row per (user,
--                                          match_kind, match_value).
--   2. promote_merchant_rules RPC        — scans recent not_an_order
--                                          corrections, auto-creates a
--                                          sender_domain rule when a domain
--                                          crosses the threshold (3+ in 60d).
--   3. apply_merchant_rule RPC           — lookup helper used by the TS
--                                          autopilot's processEmail short-
--                                          circuit slot. Returns the matching
--                                          enabled rule (or NULL).
--   4. record_order_correction enhanced  — calls promote_merchant_rules() at
--                                          the tail of the not_an_order
--                                          branch so promotion is atomic
--                                          with the correction insert.
--
-- See docs/superpowers/specs/2026-04-27-orders-corrections-and-rules-design.md
-- (Phase 2 section) for design rationale.
-- ============================================================================

BEGIN;

-- ─── 1. merchant_rules table ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.merchant_rules (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  -- Match: one of three kinds, with the corresponding value.
  --   sender_email       — exact match on lowercase sender email
  --   sender_domain      — match on the email's bare domain (e.g. "apple.com")
  --   normalized_merchant — match on orders.normalized_merchant (used only
  --                         for user-created rules; auto-promotion uses domain)
  match_kind  text NOT NULL CHECK (match_kind IN
                  ('sender_email','sender_domain','normalized_merchant')),
  match_value text NOT NULL,

  -- Action when a rule matches an inbound email:
  --   skip_purchase   — short-circuit before classifier; never becomes an order
  --   require_review  — bypass auto-create, queue a review_item for confirm
  action      text NOT NULL CHECK (action IN ('skip_purchase','require_review')),

  -- Provenance: how the rule landed in the table.
  source      text NOT NULL CHECK (source IN ('auto_promoted','user_created')),

  -- Promotion telemetry: how many corrections triggered this rule. NULL for
  -- user_created rules. Used by the iOS Settings list to show "auto-learned
  -- after 3 corrections".
  promoted_from_correction_count integer,

  -- User-friendly description shown in iOS Settings. Auto-promoted rules
  -- get a stock string ("Auto-learned after N 'not an order' corrections");
  -- user-created rules carry whatever the user typed.
  notes       text,

  -- Lifecycle: disabled rules are kept (history) but no longer apply.
  enabled     boolean NOT NULL DEFAULT true,

  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),

  -- Natural key: a user can't have two rules for the same target.
  UNIQUE (user_id, match_kind, match_value)
);

COMMENT ON TABLE public.merchant_rules IS
  'Phase 2 distill layer of corrections-and-rules. Auto-promoted from
   order_corrections via promote_merchant_rules(); also accepts manual
   rules created by the user from iOS Settings.';

CREATE INDEX IF NOT EXISTS merchant_rules_user_enabled_idx
  ON public.merchant_rules (user_id, enabled);

CREATE INDEX IF NOT EXISTS merchant_rules_lookup_idx
  ON public.merchant_rules (user_id, match_kind, match_value)
  WHERE enabled = true;

ALTER TABLE public.merchant_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS merchant_rules_select_own ON public.merchant_rules;
DROP POLICY IF EXISTS merchant_rules_insert_own ON public.merchant_rules;
DROP POLICY IF EXISTS merchant_rules_update_own ON public.merchant_rules;
DROP POLICY IF EXISTS merchant_rules_delete_own ON public.merchant_rules;

CREATE POLICY merchant_rules_select_own ON public.merchant_rules
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY merchant_rules_insert_own ON public.merchant_rules
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY merchant_rules_update_own ON public.merchant_rules
  FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY merchant_rules_delete_own ON public.merchant_rules
  FOR DELETE TO authenticated USING (auth.uid() = user_id);


-- ─── 2. promote_merchant_rules RPC ────────────────────────────────────────
--
-- Scans the user's recent not_an_order corrections, groups by the source
-- email's sender_domain, and inserts a sender_domain rule for any domain
-- that's been corrected ≥3 times in the last 60 days.
--
-- Why JOIN to email_classifications: parse_trace_snapshot stores
-- source_email_ids but not the sender directly. email_classifications has
-- sender_email which we split into a bare domain at lookup time.
--
-- Idempotent: inserts are guarded by ON CONFLICT DO NOTHING against the
-- (user_id, match_kind, match_value) UNIQUE. Returns the count of newly-
-- created rules.

CREATE OR REPLACE FUNCTION public.promote_merchant_rules(
  p_user_id uuid DEFAULT auth.uid()
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted integer := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'promote_merchant_rules: user_id is required';
  END IF;

  WITH recent_dismissals AS (
    SELECT
      lower(split_part(ec.sender_email, '@', 2)) AS sender_domain,
      COUNT(*) AS dismissals
    FROM public.order_corrections oc
    JOIN public.email_classifications ec
      ON ec.email_id = ANY(oc.source_email_ids)
     AND ec.user_id  = oc.user_id
    WHERE oc.user_id = p_user_id
      AND oc.kind    = 'not_an_order'
      AND oc.created_at > now() - interval '60 days'
      AND ec.sender_email IS NOT NULL
      AND position('@' IN ec.sender_email) > 0
    GROUP BY 1
    HAVING COUNT(*) >= 3
  )
  INSERT INTO public.merchant_rules
    (user_id, match_kind, match_value, action, source,
     promoted_from_correction_count, notes)
  SELECT
    p_user_id,
    'sender_domain',
    rd.sender_domain,
    'skip_purchase',
    'auto_promoted',
    rd.dismissals,
    'Auto-learned after ' || rd.dismissals || E' \'not an order\' corrections'
  FROM recent_dismissals rd
  ON CONFLICT (user_id, match_kind, match_value) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.promote_merchant_rules(uuid) TO authenticated;


-- ─── 3. apply_merchant_rule RPC ───────────────────────────────────────────
--
-- Lookup helper for the TS autopilot. Given a sender email, returns the
-- first matching enabled rule, in priority order:
--   1. sender_email exact match
--   2. sender_domain match (split on '@')
--   3. (normalized_merchant — caller can pass it for completeness; not
--      consulted by the auto-promotion path but available for manual rules)
--
-- Returns one row or zero rows. Caller checks .action to decide.

CREATE OR REPLACE FUNCTION public.apply_merchant_rule(
  p_user_id              uuid,
  p_sender_email         text,
  p_normalized_merchant  text DEFAULT NULL
) RETURNS TABLE (
  rule_id     uuid,
  match_kind  text,
  match_value text,
  action      text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email  text := lower(p_sender_email);
  v_domain text;
BEGIN
  IF v_email IS NULL OR position('@' IN v_email) = 0 THEN
    RETURN;
  END IF;
  v_domain := split_part(v_email, '@', 2);

  RETURN QUERY
  SELECT mr.id, mr.match_kind, mr.match_value, mr.action
  FROM public.merchant_rules mr
  WHERE mr.user_id = p_user_id
    AND mr.enabled = true
    AND (
         (mr.match_kind = 'sender_email'        AND mr.match_value = v_email)
      OR (mr.match_kind = 'sender_domain'       AND mr.match_value = v_domain)
      OR (mr.match_kind = 'normalized_merchant' AND p_normalized_merchant IS NOT NULL
                                               AND mr.match_value = p_normalized_merchant)
    )
  ORDER BY
    CASE mr.match_kind
      WHEN 'sender_email'        THEN 1
      WHEN 'sender_domain'       THEN 2
      WHEN 'normalized_merchant' THEN 3
    END
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_merchant_rule(uuid, text, text) TO authenticated;


-- ─── 4. record_order_correction: invoke promotion at tail ─────────────────
--
-- Append a single line to the not_an_order branch so promotion runs
-- atomically with the correction insert. Wrapped in a sub-block to
-- swallow any promotion failure (we never want a rule-engine bug to
-- break the user's "Not an order" tap).

CREATE OR REPLACE FUNCTION public.record_order_correction(
  p_order_id uuid,
  p_kind     text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_correction_id  uuid;
  v_user_id        uuid;
  v_trace          jsonb;
  v_source_emails  text[];
BEGIN
  IF p_kind NOT IN ('not_an_order','wrong_tracking','already_delivered') THEN
    RAISE EXCEPTION 'invalid correction kind: %', p_kind;
  END IF;

  SELECT user_id, parse_trace, source_email_ids
    INTO v_user_id, v_trace, v_source_emails
    FROM public.orders
    WHERE id = p_order_id;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'order not found: %', p_order_id;
  END IF;
  IF v_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: order belongs to another user';
  END IF;

  INSERT INTO public.order_corrections
    (user_id, order_id, kind, source_email_ids, parse_trace_snapshot)
    VALUES (v_user_id, p_order_id, p_kind, v_source_emails, v_trace)
    RETURNING id INTO v_correction_id;

  -- State transition per kind
  IF p_kind = 'not_an_order' THEN
    UPDATE public.orders
       SET status = 'dismissed_by_user',
           dismissed_at = now(),
           updated_at = now()
     WHERE id = p_order_id;

    -- Phase 2: distill into merchant_rules. Best-effort — wrap so a
    -- promotion error never breaks the user's correction.
    BEGIN
      PERFORM public.promote_merchant_rules(v_user_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'promote_merchant_rules failed for user %: %', v_user_id, SQLERRM;
    END;

  ELSIF p_kind = 'wrong_tracking' THEN
    UPDATE public.shipments
       SET tracking_number = NULL,
           carrier = NULL,
           tracking_url = NULL,
           updated_at = now()
     WHERE order_id = p_order_id;

  ELSIF p_kind = 'already_delivered' THEN
    UPDATE public.orders
       SET manual_delivered_at = now(),
           updated_at = now()
     WHERE id = p_order_id;
  END IF;

  RETURN v_correction_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_order_correction(uuid, text)
  TO authenticated;


-- ─── 5. updated_at touch trigger ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.merchant_rules_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS merchant_rules_set_updated_at ON public.merchant_rules;
CREATE TRIGGER merchant_rules_set_updated_at
  BEFORE UPDATE ON public.merchant_rules
  FOR EACH ROW EXECUTE FUNCTION public.merchant_rules_touch_updated_at();

COMMIT;
