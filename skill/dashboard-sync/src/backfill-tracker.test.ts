import test from 'node:test';
import assert from 'node:assert/strict';
import { planOrderBackfill, planShipmentRepair } from './backfill-tracker';

test('hides hard-excluded merchants, keeps physical, archives unsure history', () => {
  const orders = [
    { id: '1', merchant_name: 'TAP Air Portugal', normalized_merchant: 'tap', sender: 'booking@flytap.com' },
    { id: '2', merchant_name: 'Peak Design', normalized_merchant: 'peak design', sender: 'orders@peakdesign.com' },
    { id: '3', merchant_name: 'Mystery Co', normalized_merchant: 'mystery co', sender: 'hi@mystery.io' },
  ];
  const plan = planOrderBackfill(orders);
  assert.equal(plan.find(p => p.id === '1')!.action, 'hide');     // airline
  assert.equal(plan.find(p => p.id === '2')!.action, 'keep');     // physical merchant
  assert.equal(plan.find(p => p.id === '3')!.action, 'archive');  // unsure history → archived, NOT queued
});

test('plans: delete empty-tracking, split multipiece, collapse dupes', () => {
  const ships = [
    { id: 'a', tracking_number: '' },
    { id: 'b', tracking_number: '7197712620 / 001959496839433548' },
    { id: 'c', tracking_number: 'JD0146' },
    { id: 'd', tracking_number: 'JD0146' },
  ];
  const plan = planShipmentRepair(ships);
  assert.equal(plan.deleteEmpty.length, 1);
  assert.equal(plan.split.length, 1);
  assert.deepEqual(plan.split[0].into, ['7197712620', '001959496839433548']);
  assert.equal(plan.collapseDupes.length, 1);
});
