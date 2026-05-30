import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveETA } from './eta-ladder';

test('email ETA beats 17track and heuristic', () => {
  assert.deepEqual(resolveETA({ email: '2026-05-12', seventeenTrack: '2026-05-15', heuristic: '2026-05-20' }),
    { eta_at: '2026-05-12', eta_source: 'email' });
});
test('17track used when email absent', () => {
  assert.deepEqual(resolveETA({ email: null, seventeenTrack: '2026-05-15', heuristic: '2026-05-20' }),
    { eta_at: '2026-05-15', eta_source: '17track' });
});
test('heuristic used when both absent', () => {
  assert.deepEqual(resolveETA({ email: null, seventeenTrack: null, heuristic: '2026-05-20' }),
    { eta_at: '2026-05-20', eta_source: 'heuristic' });
});
test('null when nothing available — never blanks anything', () => {
  assert.equal(resolveETA({ email: null, seventeenTrack: null, heuristic: null }), null);
});
