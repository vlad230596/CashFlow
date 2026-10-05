import { describe, expect, it } from 'vitest';
import { extractYandexCashbackCategories, parseYandexCashbackCardText, parseYandexPercent } from './cashback';

describe('extractYandexCashbackCategories selector list', () => {
  function item(title: string, description: string, secondaryClass = true) {
    return {
      innerText: `${title}\n${description}`,
      querySelector(selector: string) {
        if (selector.includes('ListItem_title__')) return { textContent: title };
        if (selector.includes('ListItem_descriptionSecondary') && secondaryClass) {
          return { textContent: description };
        }
        if (selector.includes('input[')) return { checked: true };
        return null;
      },
      getAttribute() { return null; },
    };
  }

  it.each(['−', '-'])('excludes a %s50%% delivery discount while keeping cashback conditions', (minus) => {
    const items = [
      item(`${minus}50% Еда и Деливери`, 'Скидка на доставку'),
      item('10% Кинопоиск', 'Билеты в приложении или на сайте', false),
    ];
    const root = {
      querySelectorAll(selector: string) {
        return selector.includes('selector-page-list-item') ? items : [];
      },
    } as unknown as ParentNode;
    expect(extractYandexCashbackCategories(root)).toEqual([
      expect.objectContaining({
        name: 'Кинопоиск', percent: 10, percentLabel: '10%', selected: true,
        description: 'Билеты в приложении или на сайте',
      }),
    ]);
  });

  it('does not reintroduce a discount through fallback extraction', () => {
    const root = {
      querySelectorAll(selector: string) {
        return selector.includes('selector-page-list-item')
          ? [item('−50% Еда и Деливери', 'Скидка на доставку')] : [];
      },
    } as unknown as ParentNode;
    expect(extractYandexCashbackCategories(root)).toEqual([]);
  });
});

describe('parseYandexPercent', () => {
  it('does not promise a discount as cashback', () => {
    expect(parseYandexPercent('−50%')).toEqual({ percent: null, percentLabel: null });
    expect(parseYandexPercent('-50%')).toEqual({ percent: null, percentLabel: null });
  });
  it('parses a selected monthly cashback percentage', () => {
    expect(parseYandexPercent(' 3% ')).toEqual({
      percent: 3,
      percentLabel: '3%',
    });
  });

  it('preserves the up-to qualifier', () => {
    expect(parseYandexPercent('до 5%')).toEqual({
      percent: 5,
      percentLabel: 'до 5%',
    });
  });

  it('handles a non-percentage benefit', () => {
    expect(parseYandexPercent('Яндекс Плюс')).toEqual({
      percent: null,
      percentLabel: null,
    });
  });
});

describe('parseYandexCashbackCardText', () => {
  it('keeps the time limit and additional condition', () => {
    expect(
      parseYandexCashbackCardText(
        'Одежда и обувь\nНе суммируется с категориями\n7%\nещё 43 дня',
      ),
    ).toEqual({
      name: 'Одежда и обувь',
      percent: 7,
      percentLabel: '7%',
      subtitle: 'ещё 43 дня',
      description: 'Не суммируется с категориями',
      expiresInLabel: 'ещё 43 дня',
    });
  });
});
