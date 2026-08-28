import { describe, expect, it } from 'vitest';
import { extractSelection } from './page-probe';
import type { CashbackCategory } from './types';

const category = (selected: boolean, group: string | null = null): CashbackCategory => ({
  type: 'standard',
  name: 'Категория',
  percent: 5,
  percentLabel: '5%',
  subtitle: null,
  description: null,
  iconUrl: null,
  iconBackgroundColor: null,
  selected,
  group,
  expiresInLabel: null,
});

describe('extractSelection', () => {
  it('extracts an explicit choose-from limit', () => {
    const root = { textContent: 'Можно выбрать 5 категорий из 8' } as ParentNode;
    expect(extractSelection([category(true), category(false)], root)).toEqual({
      isLocked: null,
      selectedCount: 1,
      visibleCount: 2,
      maxSelectable: 5,
      totalOptions: 8,
      groups: [],
    });
  });

  it('does not infer an unknown maximum from visible cards', () => {
    const root = { textContent: 'Ваши категории на август' } as ParentNode;
    expect(extractSelection([category(true, 'На август')], root)).toMatchObject({
      selectedCount: 1,
      visibleCount: 1,
      maxSelectable: null,
      totalOptions: null,
      groups: ['На август'],
    });
  });

  it('reads text from a document element', () => {
    const root = {
      textContent: null,
      documentElement: { textContent: 'Выберите 3 категории на август' },
    } as unknown as ParentNode;
    expect(extractSelection([category(false), category(false)], root)).toMatchObject({
      maxSelectable: 3,
      totalOptions: 2,
    });
  });
});
