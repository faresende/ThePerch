-- ============================================================================
-- 20260426000001_review_items_source_columns.sql
--
-- Extends `public.review_items` with structured columns the iOS review
-- queue UI needs to render rows + take action without parsing the free-
-- form `reason` text. Without these, the iOS "Confirm as order" button
-- can't pre-fill the merchant / order_number / total it asks the user
-- to confirm — it'd have to either be a fully manual form (annoying)
-- or re-fetch the email from JMAP (expensive, not always available).
--
-- New columns are all nullable so existing rows continue to render —
-- the UI falls back to showing the `reason` text when these are NULL.
-- New review_items written by orders-autopilot.ts will populate them
-- (see commit landing at the same time).
-- ============================================================================

BEGIN;

ALTER TABLE public.review_items
  ADD COLUMN IF NOT EXISTS source_email_id        text,
  ADD COLUMN IF NOT EXISTS source_subject         text,
  ADD COLUMN IF NOT EXISTS source_sender_email    text,
  ADD COLUMN IF NOT EXISTS source_sender_name     text,
  ADD COLUMN IF NOT EXISTS suggested_merchant     text,
  ADD COLUMN IF NOT EXISTS suggested_order_number text,
  ADD COLUMN IF NOT EXISTS suggested_total_amount numeric,
  ADD COLUMN IF NOT EXISTS suggested_currency     text;

COMMENT ON COLUMN public.review_items.source_email_id IS
  'JMAP / Gmail message ID of the email that triggered this review item. '
  'Lets the iOS UI deep-link back to the source email and lets the '
  'autopilot identify duplicates without re-parsing `reason` text.';

COMMENT ON COLUMN public.review_items.suggested_merchant IS
  'The autopilot''s best guess at the merchant name when it queued this '
  'item. The iOS "Confirm as order" button uses this as the default '
  'merchant for the order it creates.';

COMMIT;
