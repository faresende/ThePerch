import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ruleFromReviewAnswer,
  reviewAnswerRpcParams,
  type ReviewSubject,
} from './merchant-rules';

const USER = '11111111-1111-1111-1111-111111111111';
const REVIEW = '22222222-2222-2222-2222-222222222222';

// ─── ruleFromReviewAnswer: the three-answer → action mapping ──────────────

test('ruleFromReviewAnswer maps each answer to its action (sender email present)', () => {
  const subj: ReviewSubject = { senderEmail: 'Orders@Shop.COM', normalizedMerchant: 'shop' };
  assert.deepEqual(ruleFromReviewAnswer(subj, 'yes_track'), {
    match_kind: 'sender_email',
    match_value: 'orders@shop.com',
    action: 'always_physical',
  });
  assert.deepEqual(ruleFromReviewAnswer(subj, 'no_package'), {
    match_kind: 'sender_email',
    match_value: 'orders@shop.com',
    action: 'skip_purchase',
  });
  assert.deepEqual(ruleFromReviewAnswer(subj, 'bought_but_digital'), {
    match_kind: 'sender_email',
    match_value: 'orders@shop.com',
    action: 'always_digital',
  });
});

test('ruleFromReviewAnswer falls back to normalized_merchant when senderEmail is null', () => {
  const subj: ReviewSubject = { senderEmail: null, normalizedMerchant: 'peak design' };
  assert.deepEqual(ruleFromReviewAnswer(subj, 'yes_track'), {
    match_kind: 'normalized_merchant',
    match_value: 'peak design',
    action: 'always_physical',
  });
});

// ─── reviewAnswerRpcParams: the unit-testable RPC param core ───────────────

test('reviewAnswerRpcParams builds yes_track params with a sender email (lowercased)', () => {
  const subj: ReviewSubject = { senderEmail: 'Orders@Shop.COM', normalizedMerchant: 'shop' };
  assert.deepEqual(reviewAnswerRpcParams(USER, subj, 'yes_track', REVIEW), {
    p_user_id: USER,
    p_match_kind: 'sender_email',
    p_match_value: 'orders@shop.com',
    p_action: 'always_physical',
    p_review_item_id: REVIEW,
  });
});

test('reviewAnswerRpcParams builds no_package params (skip_purchase)', () => {
  const subj: ReviewSubject = { senderEmail: 'info@noise.io', normalizedMerchant: 'noise' };
  assert.deepEqual(reviewAnswerRpcParams(USER, subj, 'no_package', REVIEW), {
    p_user_id: USER,
    p_match_kind: 'sender_email',
    p_match_value: 'info@noise.io',
    p_action: 'skip_purchase',
    p_review_item_id: REVIEW,
  });
});

test('reviewAnswerRpcParams builds bought_but_digital params (always_digital)', () => {
  const subj: ReviewSubject = { senderEmail: 'receipts@store.app', normalizedMerchant: 'store' };
  assert.deepEqual(reviewAnswerRpcParams(USER, subj, 'bought_but_digital', REVIEW), {
    p_user_id: USER,
    p_match_kind: 'sender_email',
    p_match_value: 'receipts@store.app',
    p_action: 'always_digital',
    p_review_item_id: REVIEW,
  });
});

test('reviewAnswerRpcParams falls back to normalized_merchant when senderEmail is null', () => {
  const subj: ReviewSubject = { senderEmail: null, normalizedMerchant: 'peak design' };
  assert.deepEqual(reviewAnswerRpcParams(USER, subj, 'yes_track', REVIEW), {
    p_user_id: USER,
    p_match_kind: 'normalized_merchant',
    p_match_value: 'peak design',
    p_action: 'always_physical',
    p_review_item_id: REVIEW,
  });
});

test('reviewAnswerRpcParams passes a null reviewItemId through unchanged', () => {
  const subj: ReviewSubject = { senderEmail: 'orders@shop.com', normalizedMerchant: 'shop' };
  assert.deepEqual(reviewAnswerRpcParams(USER, subj, 'no_package', null), {
    p_user_id: USER,
    p_match_kind: 'sender_email',
    p_match_value: 'orders@shop.com',
    p_action: 'skip_purchase',
    p_review_item_id: null,
  });
});
