export type SberNavigationCandidate = {
  href: string | null;
  text: string;
  context?: string;
};

export function selectSberLoyaltyControl<T extends SberNavigationCandidate>(
  candidates: T[],
): T | null {
  return candidates.find((candidate) => candidate.href?.includes('/loyalty/'))
    ?? candidates.find((candidate) => /сбер\s*спасибо|бонусы?\s+спасибо/i.test(candidate.text))
    ?? null;
}

export function selectSberCategoriesControl<T extends SberNavigationCandidate>(
  candidates: T[],
): T | null {
  return candidates.find((candidate) => candidate.href?.includes('/loyalty/main/categories'))
    ?? candidates.find((candidate) =>
      /^(?:посмотреть|выбрать|изменить)$/i.test(candidate.text) &&
      /мои категории|кешбэк на|кэшбэк на/i.test(candidate.context ?? ''),
    )
    ?? null;
}

export function findSberLoyaltyControl(root: ParentNode = document): HTMLElement | null {
  return selectSberLoyaltyControl(
    [...root.querySelectorAll<HTMLElement>('a[href], button, [role="button"]')].map((element) => ({
      element,
      href: element instanceof HTMLAnchorElement ? element.href : null,
      text: element.textContent?.replace(/\s+/g, ' ').trim() ?? '',
    })),
  )?.element ?? null;
}

export function findSberCategoriesControl(root: ParentNode = document): HTMLElement | null {
  return selectSberCategoriesControl(
    [...root.querySelectorAll<HTMLElement>('a[href], button, [role="button"]')].map((element) => {
      let contextElement: HTMLElement | null = element;
      let context = '';
      for (let depth = 0; contextElement && depth < 6; depth += 1) {
        context = contextElement.textContent?.replace(/\s+/g, ' ').trim() ?? '';
        if (/мои категории|кешбэк на|кэшбэк на/i.test(context)) break;
        contextElement = contextElement.parentElement;
      }
      return {
        element,
        href: element instanceof HTMLAnchorElement ? element.href : null,
        text: element.textContent?.replace(/\s+/g, ' ').trim() ?? '',
        context,
      };
    }),
  )?.element ?? null;
}
