-- Backfill legacy commerce row ownership to Fábio's authenticated account.
--
-- Why: older order rows were created before app auth was enforced, so `orders.user_id`
-- was left NULL. With proper auth + RLS, those rows become invisible to the app.
--
-- Scope: personal ThePerch production data for the canonical owner account.
-- Idempotent: reruns are safe.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM auth.users
    WHERE id = '00000000-0000-0000-0000-000000000000'::uuid
  ) THEN
    UPDATE public.orders
    SET user_id = '00000000-0000-0000-0000-000000000000'::uuid,
        updated_at = now()
    WHERE user_id IS NULL;

    UPDATE public.review_items
    SET user_id = '00000000-0000-0000-0000-000000000000'::uuid,
        updated_at = now()
    WHERE user_id IS NULL;
  ELSE
    RAISE NOTICE 'Canonical owner auth user not found, skipping ownership backfill';
  END IF;
END $$;
