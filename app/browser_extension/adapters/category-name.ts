const latinLookalikes: Record<string, string> = {
  A: 'А', a: 'а', B: 'В', C: 'С', c: 'с', E: 'Е', e: 'е', H: 'Н', K: 'К', k: 'к',
  M: 'М', O: 'О', o: 'о', P: 'Р', p: 'р', T: 'Т', X: 'Х', x: 'х', Y: 'У', y: 'у',
};

/**
 * Replaces Latin lookalike letters inside words that also contain Cyrillic.
 *
 * Alfa-Bank renders some titles as «Kниги», «Цвeты» or «Кафе и pестораны».
 * Such a name never equals the bank category in the MCC rules, so the app
 * could not find its MCC codes. Purely Latin words («Alfa Pay») stay as they are.
 * Keep in sync with `fold_latin_lookalikes` in backend/canonical_categories.py.
 */
export function foldLatinLookalikes(value: string): string {
  return value.replace(/[A-Za-zА-Яа-яЁё]+/g, (word) => (
    /[А-Яа-яЁё]/.test(word)
      ? word.replace(/[A-Za-z]/g, (letter) => latinLookalikes[letter] ?? letter)
      : word
  ));
}
