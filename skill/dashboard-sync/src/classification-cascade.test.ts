import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { classifyForTracking } from './classification-cascade';

const dir = path.join(__dirname, '..', 'test', 'fixtures', 'classification');
for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.json'))) {
  const fx = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'));
  test(`classifies ${fx.label} as ${fx.expected.classification}`, async () => {
    const result = await classifyForTracking(fx.input, {
      lookupRule: async () => null,
      llm: async () => ({ classification: 'physical', confidence: 0.95 }),
    });
    assert.equal(result.classification, fx.expected.classification);
  });
}
