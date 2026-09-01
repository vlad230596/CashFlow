import { describe, expect, it } from 'vitest';
import { buildCategoryIconId, buildFallbackCategoryIcon } from './category-icon';

describe('category icons', () => {
  it('builds a stable bank-scoped id', () => {
    const category = { type: 'standard' as const, name: 'Спорт и фитнес', percentLabel: '10%' };
    expect(buildCategoryIconId('sber', category)).toBe(buildCategoryIconId('sber', category));
    expect(buildCategoryIconId('sber', category)).not.toBe(buildCategoryIconId('alfa', category));
  });

  it('creates a standalone svg fallback', () => {
    expect(buildFallbackCategoryIcon('sber', 'Спорт и фитнес')).toMatch(
      /^data:image\/svg\+xml;charset=utf-8,/,
    );
  });
});
