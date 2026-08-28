export function isSupportedTbankUrl(rawUrl: string): boolean {
  try {
    const url = new URL(rawUrl);
    return url.protocol === 'https:' && url.hostname === 'www.tbank.ru';
  } catch {
    return false;
  }
}
