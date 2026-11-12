import type { CashbackCategory, PageProbe } from './types';
import { categoryKey } from './probe-runner';

/** Details that one page (or one probe) may show while another omits them. */
const DETAIL_FIELDS = [
  'subtitle', 'description', 'iconId', 'iconUrl', 'iconBackgroundColor',
  'expiresInLabel', 'maxCashbackAmount', 'minPurchaseAmount',
] as const;

/**
 * `primary` decides selection state; empty details are filled from
 * `secondary`. A category list without the detail sheet open must not erase a
 * cap or a description read earlier or on another page.
 */
export function combineCategory(primary: CashbackCategory, secondary: CashbackCategory): CashbackCategory {
  const combined: CashbackCategory = { ...primary };
  const target = combined as Record<(typeof DETAIL_FIELDS)[number], unknown>;
  for (const field of DETAIL_FIELDS) {
    if (target[field] == null && secondary[field] != null) target[field] = secondary[field];
  }
  return combined;
}

/** Saved (bank-confirmed) records describe the category best. */
function rank(category: CashbackCategory): number {
  return (category.confirmed === true ? 2 : 0) + (category.selected ? 1 : 0);
}

/**
 * Combines probes of several pages of one bank (for example Ozon's saved
 * month summary and its selection page) into one result.
 */
export function mergeBankProbes(probes: PageProbe[], preferredUrlParts: string[]): PageProbe | undefined {
  if (probes.length <= 1) return probes[0];
  const preference = (probe: PageProbe) => {
    const index = preferredUrlParts.findIndex((part) => probe.url.includes(part));
    return index < 0 ? preferredUrlParts.length : index;
  };
  const ordered = [...probes].sort((left, right) =>
    Number(right.categories.length > 0) - Number(left.categories.length > 0) ||
    preference(left) - preference(right));
  const base = ordered[0]!;

  const merged = new Map<string, CashbackCategory>();
  for (const probe of ordered) {
    for (const category of probe.categories) {
      const key = categoryKey(category);
      const existing = merged.get(key);
      if (!existing) merged.set(key, category);
      else if (rank(category) > rank(existing)) merged.set(key, combineCategory(category, existing));
      else merged.set(key, combineCategory(existing, category));
    }
  }
  const categories = [...merged.values()];
  const standard = categories.filter((category) => category.type === 'standard');
  const withCategories = probes.filter((probe) => probe.categories.length);
  const maxOf = (values: Array<number | null>) => {
    const present = values.filter((value): value is number => value != null);
    return present.length ? Math.max(...present) : null;
  };
  const captures = probes.flatMap((probe) => probe.capture ? [probe.capture] : []);
  return {
    ...base,
    authenticationStatus: categories.length ? 'authenticated' : base.authenticationStatus,
    categories,
    selection: {
      isLocked: withCategories.some((probe) => probe.selection.isLocked === true) ? true : null,
      selectedCount: standard.filter((category) => category.selected).length,
      visibleCount: standard.length,
      maxSelectable: maxOf(probes.map((probe) => probe.selection.maxSelectable)),
      totalOptions: maxOf([...probes.map((probe) => probe.selection.totalOptions), standard.length || null]),
      groups: [...new Set(probes.flatMap((probe) => probe.selection.groups))],
    },
    ...(captures.length ? {
      capture: {
        mode: captures.some((capture) => capture.mode === 'thorough') ? 'thorough' : 'passive',
        stable: withCategories.every((probe) => probe.capture?.stable !== false),
        waitedMs: Math.max(...captures.map((capture) => capture.waitedMs)),
        reads: captures.reduce((sum, capture) => sum + capture.reads, 0),
        advances: captures.reduce((sum, capture) => sum + capture.advances, 0),
        ...(captures.some((capture) => capture.selectionPage) ? { selectionPage: true } : {}),
      },
    } : {}),
  };
}
