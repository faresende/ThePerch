-- 20260429000000_merchant_rules_auth_guards.sql
--
-- Hardens the SECURITY DEFINER RPCs that back the merchant_rules
-- (Phase 2 corrections-and-rules) feature. Both functions accept a
-- user_id parameter; without an auth check, an authenticated user
-- could pass another user's id and:
--   - promote_merchant_rules: scan another user's order_corrections
--     and write rules into their merchant_rules row
--   - apply_merchant_rule: probe whether another user has a rule for
--     a given sender (info disclosure)
--
-- Fix: require auth.uid() to match p_user_id, OR the caller to be the
-- service_role (which the orders-autopilot runs under server-side).

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
  IF auth.role() <> 'service_role'
     AND (auth.uid() IS NULL OR p_user_id <> auth.uid()) THEN
    RAISE EXCEPTION 'unauthorized: cannot promote rules for another user';
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
    rd.dismissals::int,
    'Auto-learned after ' || rd.dismissals || E' \'not an order\' corrections'
  FROM recent_dismissals rd
  ON CONFLICT (user_id, match_kind, match_value) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted;
END;
$$;


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
  IF auth.role() <> 'service_role'
     AND (auth.uid() IS NULL OR p_user_id <> auth.uid()) THEN
    RETURN;  -- silent: don't leak whether another user has rules
  END IF;
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
