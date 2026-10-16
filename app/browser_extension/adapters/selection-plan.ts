import { z } from 'zod';
import type { CashbackSelectionPlanDocument } from './types';

const calendarDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => {
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.valueOf()) && date.toISOString().slice(0, 10) === value;
});
const planSchema = z.object({
  schemaVersion: z.literal(1),
  kind: z.literal('cashback_selection_plan'),
  generatedAt: z.string().refine(value => Number.isFinite(Date.parse(value))),
  effectiveDate: calendarDate,
  period: z.object({ from: calendarDate, to: calendarDate })
    .refine(period => period.from <= period.to).optional(),
  banks: z.array(z.object({
    bankId: z.enum(['tbank', 'yandex', 'alfa', 'sber', 'ozon', 'vtb']),
    cardId: z.number().int().positive(),
    cardLabel: z.string(),
    desiredCategories: z.array(z.object({
      name: z.string().trim().min(1),
      percent: z.number().finite().nonnegative().nullable(),
    })),
  })),
});

/** Storage and bridge messages are untrusted even when exported by Flutter. */
export function parseSelectionPlan(value: unknown): CashbackSelectionPlanDocument | null {
  const result = planSchema.safeParse(value);
  return result.success ? result.data : null;
}

export function selectionPlanPeriodLabel(plan: CashbackSelectionPlanDocument): string {
  return plan.period ? `${plan.period.from} — ${plan.period.to}` : plan.effectiveDate;
}
