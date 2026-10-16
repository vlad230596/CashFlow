import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { extractCashbackAmounts } from './cashback-amounts';
import { limitsFromConditions } from './extended/core';
const fixture = JSON.parse(readFileSync(new URL('../../../contracts/cashback-amounts.v1.json', import.meta.url), 'utf8')) as {
  cases: Array<{ text: string; maxCashbackAmount: number | null; minPurchaseAmount: number | null }>;
};
describe('shared monetary import contract', () => {
  for (const item of fixture.cases) {
    it(`monthly and partner parsers agree: ${item.text || 'empty'}`, () => {
      const expected = { maxCashbackAmount: item.maxCashbackAmount, minPurchaseAmount: item.minPurchaseAmount };
      expect(extractCashbackAmounts(item.text)).toEqual(expected);
      expect(limitsFromConditions(item.text)).toEqual(expected);
    });
  }
});
