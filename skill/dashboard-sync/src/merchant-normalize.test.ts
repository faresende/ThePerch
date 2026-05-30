import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalMerchant } from './merchant-normalize';
test('collapses Amazon TLD variants', () => {
  assert.equal(canonicalMerchant('Amazon'), 'amazon');
  assert.equal(canonicalMerchant('Amazon.es'), 'amazon');
  assert.equal(canonicalMerchant('Amazon.nl'), 'amazon');
  assert.equal(canonicalMerchant('amazon.co.uk'), 'amazon');
});
test('collapses known brand aliases', () => {
  assert.equal(canonicalMerchant('TAP Air Portugal'), 'tap');
  assert.equal(canonicalMerchant('TAP Portugal'), 'tap');
  assert.equal(canonicalMerchant('Transportes Aéreos Portugueses'), 'tap');
  assert.equal(canonicalMerchant('Vista Alegre Atlantis'), 'vista alegre');
});
test('lowercases + trims unknown merchants unchanged', () => {
  assert.equal(canonicalMerchant('  Peak Design '), 'peak design');
  assert.equal(canonicalMerchant('Notino'), 'notino');
});
