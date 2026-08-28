import { describe, expect, it } from 'vitest';
import { isSupportedTbankUrl } from './url';

describe('isSupportedTbankUrl', () => {
  it('accepts an authenticated T-Bank page', () => {
    expect(isSupportedTbankUrl('https://www.tbank.ru/mybank/')).toBe(true);
  });

  it('rejects lookalike and insecure origins', () => {
    expect(isSupportedTbankUrl('https://www.tbank.ru.example.com/mybank/')).toBe(
      false,
    );
    expect(isSupportedTbankUrl('http://www.tbank.ru/mybank/')).toBe(false);
  });
});
