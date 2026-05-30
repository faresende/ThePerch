-- ============================================================================
-- 20260508140000_apply_review_answer.sql
--
-- The "self-extinguishing learning loop" for the order review queue.
--
-- When classification is unsure about a commerce email, the autopilot
-- queues a `review_items` row asking the user one question:
--   "is this a package?"
-- The user answers one of three ways. The iOS client maps that answer to
-- a (match_kind, match_value, action) via the PURE TS helper
-- `ruleFromReviewAnswer` (skill/dashboard-sync/src/merchant-rules.ts) and
-- calls this RPC. This function then does three things atomically so we
-- NEVER ask about that sender / merchant again:
--
--   (a) DURABLE RULE  — upsert a `merchant_rules` row (source='user_created')
--                       so future inbound email from that sender/merchant is
--                       short-circuited by the autopilot's apply_merchant_rule
--                       slot before it ever reaches the classifier.
--   (b) RETROACTIVE SWEEP — rewrite already-captured sibling `orders` for this
--                       user so their classification/visibility matches the
--                       verdict the user just gave. Returns the swept count.
--   (c) RESOLVE REVIEWS  — stamp resolved_at on the triggering review item AND
--                       sibling review items from the same source, so the
--                       queue self-empties (no re-asking).
--
-- Three-answer → action mapping (mirrors ruleFromReviewAnswer):
--   yes_track          → always_physical  (this sender ships real packages)
--   bought_but_digital → always_digital   (real purchase, nothing ships)
--   no_package         → skip_purchase    (not a trackable order at all)
--
-- Sweep semantics, per action (all scoped to the calling user):
--   always_physical → classification='physical', un-hide
--                       (hidden=false, hidden_reason=NULL)
--   always_digital  → classification='digital',  hide as digital
--                       (hidden=true,  hidden_reason='learned_digital')
--   skip_purchase   → leave classification, hide as not-a-package
--                       (hidden=true,  hidden_reason='learned_not_package')
--
-- Matching, per match_kind:
--   sender_email        — any source email of the order whose sender, lower-
--                         cased, equals match_value (match_value is stored
--                         lowercased by the caller / here).
--   sender_domain       — same, comparing the bare domain (split on '@').
--   normalized_merchant — orders.normalized_merchant = match_value verbatim.
--
-- Review-item sibling resolution (see the IMPORTANT note at step 4 about why
-- normalized_merchant only resolves the trigger item).
--
-- SECURITY DEFINER + auth guard copied from the merchant_rules RPCs
-- (20260428130000 / 20260429000000): require auth.uid() = p_user_id OR the
-- service_role. Any failure inside the body RAISEs — there is no best-effort
-- swallow here; the iOS client surfaces the error to the user, unlike the
-- background promotion path. Idempotent via CREATE OR REPLACE.
--
-- See docs/superpowers/specs (orders review queue / learning loop).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.apply_review_answer(
  p_user_id        uuid,
  p_match_kind     text,
  p_match_value    text,
  p_action         text,
  p_review_item_id uuid DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match_value text;
  v_swept       integer := 0;
BEGIN
  -- ─── 1. Auth + argument validation ──────────────────────────────────────
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'apply_review_answer: user_id is required';
  END IF;
  IF auth.role() <> 'service_role'
     AND (auth.uid() IS NULL OR p_user_id <> auth.uid()) THEN
    RAISE EXCEPTION 'unauthorized: cannot apply review answers for another user';
  END IF;
  IF p_action NOT IN ('always_physical','always_digital','skip_purchase') THEN
    RAISE EXCEPTION 'apply_review_answer: invalid action %', p_action;
  END IF;
  IF p_match_kind NOT IN ('sender_email','sender_domain','normalized_merchant') THEN
    RAISE EXCEPTION 'apply_review_answer: invalid match_kind %', p_match_kind;
  END IF;
  IF p_match_value IS NULL OR length(trim(p_match_value)) = 0 THEN
    RAISE EXCEPTION 'apply_review_answer: match_value is required';
  END IF;

  -- Normalize the stored/compared value: sender_email + sender_domain are
  -- case-insensitive (lowercase); normalized_merchant is already normalized
  -- by the caller, so store/compare it verbatim.
  IF p_match_kind IN ('sender_email','sender_domain') THEN
    v_match_value := lower(p_match_value);
  ELSE
    v_match_value := p_match_value;
  END IF;

  -- ─── 2. Upsert the durable rule ─────────────────────────────────────────
  INSERT INTO public.merchant_rules
    (user_id, match_kind, match_value, action, source, enabled, notes)
  VALUES
    (p_user_id, p_match_kind, v_match_value, p_action,
     'user_created', true, 'Learned from review answer')
  ON CONFLICT (user_id, match_kind, match_value) DO UPDATE
    SET action     = EXCLUDED.action,
        enabled    = true,
        source     = 'user_created',
        updated_at = now();

  -- ─── 3. Retroactive order sweep ─────────────────────────────────────────
  -- One UPDATE per action; the match predicate is selected by match_kind.
  -- The EXISTS sub-select on email_classifications mirrors the
  -- record_order_correction / promote_merchant_rules join idiom
  -- (ec.email_id = ANY(o.source_email_ids) AND ec.user_id = o.user_id).

  IF p_action = 'always_physical' THEN
    UPDATE public.orders o
       SET classification = 'physical',
           hidden         = false,
           hidden_reason  = NULL,
           updated_at     = now()
     WHERE o.user_id = p_user_id
       AND (
         (p_match_kind = 'sender_email' AND EXISTS (
            SELECT 1 FROM public.email_classifications ec
             WHERE ec.email_id = ANY(o.source_email_ids)
               AND ec.user_id  = o.user_id
               AND lower(ec.sender_email) = v_match_value))
      OR (p_match_kind = 'sender_domain' AND EXISTS (
            SELECT 1 FROM public.email_classifications ec
             WHERE ec.email_id = ANY(o.source_email_ids)
               AND ec.user_id  = o.user_id
               AND split_part(lower(ec.sender_email), '@', 2) = v_match_value))
      OR (p_match_kind = 'normalized_merchant'
            AND o.normalized_merchant = v_match_value)
       );
    GET DIAGNOSTICS v_swept = ROW_COUNT;

  ELSIF p_action = 'always_digital' THEN
    UPDATE public.orders o
       SET classification = 'digital',
           hidden         = true,
           hidden_reason  = 'learned_digital',
           updated_at     = now()
     WHERE o.user_id = p_user_id
       AND (
         (p_match_kind = 'sender_email' AND EXISTS (
            SELECT 1 FROM public.email_classifications ec
             WHERE ec.email_id = ANY(o.source_email_ids)
               AND ec.user_id  = o.user_id
               AND lower(ec.sender_email) = v_match_value))
      OR (p_match_kind = 'sender_domain' AND EXISTS (
            SELECT 1 FROM public.email_classifications ec
             WHERE ec.email_id = ANY(o.source_email_ids)
               AND ec.user_id  = o.user_id
               AND split_part(lower(ec.sender_email), '@', 2) = v_match_value))
      OR (p_match_kind = 'normalized_merchant'
            AND o.normalized_merchant = v_match_value)
       );
    GET DIAGNOSTICS v_swept = ROW_COUNT;

  ELSIF p_action = 'skip_purchase' THEN
    UPDATE public.orders o
       SET hidden        = true,
           hidden_reason = 'learned_not_package',
           updated_at    = now()
     WHERE o.user_id = p_user_id
       AND (
         (p_match_kind = 'sender_email' AND EXISTS (
            SELECT 1 FROM public.email_classifications ec
             WHERE ec.email_id = ANY(o.source_email_ids)
               AND ec.user_id  = o.user_id
               AND lower(ec.sender_email) = v_match_value))
      OR (p_match_kind = 'sender_domain' AND EXISTS (
            SELECT 1 FROM public.email_classifications ec
             WHERE ec.email_id = ANY(o.source_email_ids)
               AND ec.user_id  = o.user_id
               AND split_part(lower(ec.sender_email), '@', 2) = v_match_value))
      OR (p_match_kind = 'normalized_merchant'
            AND o.normalized_merchant = v_match_value)
       );
    GET DIAGNOSTICS v_swept = ROW_COUNT;
  END IF;

  -- ─── 4. Resolve the triggering review item + siblings ───────────────────
  -- Always resolve the trigger item (NULL-guarded). Only touch unresolved
  -- rows owned by this user.
  IF p_review_item_id IS NOT NULL THEN
    UPDATE public.review_items
       SET resolved_at = now(),
           updated_at  = now()
     WHERE id          = p_review_item_id
       AND user_id     = p_user_id
       AND resolved_at IS NULL;
  END IF;

  -- Resolve sibling review items from the same source so the queue never
  -- re-asks the same question.
  --
  -- sender_email / sender_domain: exact, case-insensitive match against
  -- review_items.source_sender_email — safe and precise.
  --
  -- IMPORTANT (normalized_merchant): we deliberately do NOT resolve siblings
  -- by merchant name here. review_items.suggested_merchant stores the RAW
  -- merchant guess (llm.merchant_name ?? senderName — see orders-autopilot.ts),
  -- whereas p_match_value is orders.normalized_merchant produced by the TS
  -- `normalizeMerchant` (email-classifier.ts), which NFD-decomposes accents
  -- and strips ALL non-alphanumerics including spaces. A naive
  -- regexp_replace(suggested_merchant,'[^a-zA-Z0-9]','','g') in SQL neither
  -- decomposes diacritics (Postgres would drop 'ü' entirely → "glashtte")
  -- nor strips suffix words (sarl/inc/lda), so it would silently mis-match
  -- common merchants and either over- or under-resolve. Until the app
  -- exposes its exact normalization to SQL, we resolve ONLY the trigger item
  -- for normalized_merchant (handled above) and leave siblings alone.
  IF p_match_kind = 'sender_email' THEN
    UPDATE public.review_items
       SET resolved_at = now(),
           updated_at  = now()
     WHERE user_id     = p_user_id
       AND resolved_at IS NULL
       AND lower(source_sender_email) = v_match_value;

  ELSIF p_match_kind = 'sender_domain' THEN
    UPDATE public.review_items
       SET resolved_at = now(),
           updated_at  = now()
     WHERE user_id     = p_user_id
       AND resolved_at IS NULL
       AND split_part(lower(source_sender_email), '@', 2) = v_match_value;
  END IF;

  -- ─── 5. Return the number of swept orders ───────────────────────────────
  RETURN v_swept;
END;
$$;

-- Lock execution down to signed-in users (service_role/postgres keep access
-- via Supabase defaults). Postgres auto-grants EXECUTE to PUBLIC on CREATE;
-- revoke PUBLIC + anon so this matches the other merchant_rules RPCs — only
-- authenticated callers reach it, and the in-body auth guard further confines
-- each call to the owning user.
REVOKE EXECUTE ON FUNCTION
  public.apply_review_answer(uuid, text, text, text, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION
  public.apply_review_answer(uuid, text, text, text, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION
  public.apply_review_answer(uuid, text, text, text, uuid) TO authenticated;
