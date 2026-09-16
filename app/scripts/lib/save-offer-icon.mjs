import { createHash } from 'node:crypto';
import { Resolver } from 'node:dns/promises';
import { mkdir, writeFile } from 'node:fs/promises';
import { get as httpsGet } from 'node:https';
import { join, relative } from 'node:path';

const MIME_EXTENSIONS = new Map([
  ['image/svg+xml', 'svg'],
  ['image/png', 'png'],
  ['image/jpeg', 'jpg'],
  ['image/webp', 'webp'],
  ['image/gif', 'gif'],
  ['image/avif', 'avif'],
]);
const MAX_ICON_BYTES = 5 * 1024 * 1024;

async function fetchWithPublicDns(url, redirects = 0) {
  if (redirects > 3) throw new Error('Too many icon redirects.');
  const resolver = new Resolver();
  resolver.setServers(['8.8.8.8', '1.1.1.1']);
  return new Promise((resolveResult, reject) => {
    const request = httpsGet(url, {
      timeout: 15_000,
      lookup(hostname, options, callback) {
        resolver.resolve4(hostname).then(
          (addresses) => options.all
            ? callback(null, addresses.map((address) => ({ address, family: 4 })))
            : callback(null, addresses[0], 4),
          callback,
        );
      },
    }, (response) => {
      if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
        response.resume();
        fetchWithPublicDns(new URL(response.headers.location, url), redirects + 1)
          .then(resolveResult, reject);
        return;
      }
      if (response.statusCode !== 200) {
        response.resume();
        reject(new Error(`Icon request failed: HTTP ${response.statusCode}`));
        return;
      }
      const chunks = [];
      let size = 0;
      response.on('data', (chunk) => {
        size += chunk.length;
        if (size > MAX_ICON_BYTES) response.destroy(new Error('Icon exceeds size limit.'));
        else chunks.push(chunk);
      });
      response.on('end', () => resolveResult({
        bytes: Buffer.concat(chunks),
        mimeType: response.headers['content-type']?.split(';')[0]?.toLowerCase() || '',
      }));
      response.on('error', reject);
    });
    request.on('timeout', () => request.destroy(new Error('Icon request timed out.')));
    request.on('error', reject);
  });
}

function decodeDataUrl(url) {
  const match = url.match(/^data:(image\/(?:svg\+xml|png|jpeg|webp|gif|avif))((?:;[^,]+)*),([\s\S]*)$/i);
  if (!match) throw new Error('Unsupported image data URL.');
  const mimeType = match[1].toLowerCase();
  const bytes = /(?:^|;)base64(?:;|$)/i.test(match[2])
    ? Buffer.from(match[3], 'base64')
    : Buffer.from(decodeURIComponent(match[3]), 'utf8');
  return { bytes, mimeType };
}

export async function saveOfferIcon({ offerId, icon, outputDirectory }) {
  if (!icon) return null;
  let bytes;
  let mimeType;
  if (icon.kind === 'svg') {
    bytes = Buffer.from(icon.value, 'utf8');
    mimeType = 'image/svg+xml';
  } else if (icon.kind === 'dataUrl') {
    ({ bytes, mimeType } = decodeDataUrl(icon.value));
  } else if (icon.kind === 'url') {
    const url = new URL(icon.value);
    if (!['https:', 'http:'].includes(url.protocol)) throw new Error('Unsupported icon URL protocol.');
    if (url.protocol === 'https:' && process.env.OFFER_ICON_PUBLIC_DNS === '1') {
      ({ bytes, mimeType } = await fetchWithPublicDns(url));
    } else try {
      const response = await fetch(url, { signal: AbortSignal.timeout(15_000) });
      if (!response.ok) throw new Error(`Icon request failed: HTTP ${response.status}`);
      mimeType = response.headers.get('content-type')?.split(';')[0]?.toLowerCase() || '';
      const contentLength = Number(response.headers.get('content-length'));
      if (contentLength > MAX_ICON_BYTES) throw new Error('Icon exceeds size limit.');
      bytes = Buffer.from(await response.arrayBuffer());
    } catch (error) {
      if (url.protocol !== 'https:' || !['ENOTFOUND', 'EAI_AGAIN', 'UND_ERR_CONNECT_TIMEOUT'].includes(error.cause?.code)) throw error;
      ({ bytes, mimeType } = await fetchWithPublicDns(url));
    }
  } else {
    throw new Error(`Unsupported icon kind: ${icon.kind}`);
  }
  const extension = MIME_EXTENSIONS.get(mimeType);
  if (!extension) throw new Error(`Unsupported icon content type: ${mimeType}`);
  if (!bytes.length || bytes.length > MAX_ICON_BYTES) throw new Error('Icon is empty or exceeds size limit.');
  const digest = createHash('sha256').update(bytes).digest('hex');
  const safeId = String(offerId).replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 70) || 'offer';
  const filename = `${safeId}-${digest.slice(0, 12)}.${extension}`;
  const path = join(outputDirectory, filename);
  await mkdir(outputDirectory, { recursive: true });
  await writeFile(path, bytes);
  return {
    path: relative(outputDirectory, path),
    mimeType,
    sha256: digest,
    size: bytes.length,
  };
}
