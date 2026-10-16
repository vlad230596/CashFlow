import { describe, expect, it } from 'vitest';
import { parseSelectionPlan, selectionPlanPeriodLabel } from './selection-plan';
const plan = {
  schemaVersion: 1, kind: 'cashback_selection_plan', generatedAt: '2026-10-14T00:00:00Z',
  effectiveDate: '2026-11-01', banks: [{ bankId: 'vtb', cardId: 1, cardLabel: 'Card',
    desiredCategories: [{ name: 'Кафе', percent: 5 }] }],
};
describe('selection plan bridge contract', () => {
  it('accepts old plans and a selected future period', () => {
    expect(parseSelectionPlan(plan)?.effectiveDate).toBe('2026-11-01');
    const parsed = parseSelectionPlan({ ...plan, period: { from: '2026-11-01', to: '2026-11-30' } });
    expect(selectionPlanPeriodLabel(parsed!)).toBe('2026-11-01 — 2026-11-30');
  });
  it('rejects malformed stored plans without rendering broken arrays', () => {
    expect(parseSelectionPlan({ kind: 'cashback_selection_plan' })).toBeNull();
    expect(parseSelectionPlan({ ...plan, banks: 'bad' })).toBeNull();
    expect(parseSelectionPlan({ ...plan, effectiveDate: '2026-02-30' })).toBeNull();
    expect(parseSelectionPlan({ ...plan, period: { from: '2026-12-01', to: '2026-11-30' } })).toBeNull();
  });
});
