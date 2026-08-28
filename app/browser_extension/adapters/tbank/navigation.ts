export type TbankLink = { href: string; text: string };

export function selectTbankMonthlyCashbackControl<T extends { text: string }>(
  controls: T[],
): T | null {
  const monthly = controls.filter((control) =>
    /повышенн\S*\s+к[еэ]шб[еэ]к/i.test(control.text),
  );
  return monthly.find((control) => !/выбрать/i.test(control.text)) ?? monthly[0] ?? null;
}

export function selectTbankMonthlyCashbackUrl(links: TbankLink[]): string | null {
  const candidates = links.filter((link) =>
    link.href.includes('/mybank/bonuses/high-cashback/offer/'),
  );
  const preferred = candidates.find((link) =>
    /категори|повышенн|к[еэ]шб[еэ]к/i.test(link.text),
  );
  return preferred?.href ?? candidates[0]?.href ?? null;
}

export function findTbankMonthlyCashbackUrl(root: ParentNode = document): string | null {
  return selectTbankMonthlyCashbackUrl(
    [...root.querySelectorAll<HTMLAnchorElement>('a[href]')].map((link) => ({
      href: link.href,
      text: link.textContent?.replace(/\s+/g, ' ').trim() ?? '',
    })),
  );
}

export function findTbankMonthlyCashbackControl(
  root: ParentNode = document,
): HTMLElement | null {
  return selectTbankMonthlyCashbackControl(
    [...root.querySelectorAll<HTMLElement>('button, [role="button"]')].map((element) => ({
      element,
      text: element.textContent?.replace(/\s+/g, ' ').trim() ?? '',
    })),
  )?.element ?? null;
}
