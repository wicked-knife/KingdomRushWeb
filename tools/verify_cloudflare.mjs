// Validate streamed reconstruction without launching a browser or buffering the PCK.
import { readFileSync, createReadStream, statSync, writeFileSync } from 'node:fs';
import { Readable } from 'node:stream';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';

const root = new URL('../build/cloudflare/', import.meta.url);
const code = readFileSync(new URL('_worker.js', root), 'utf8');
const { default: worker } = await import('data:text/javascript;base64,' + Buffer.from(code).toString('base64'));
const manifest = JSON.parse(readFileSync(new URL('../build/cloudflare_manifest.json', import.meta.url)));
const packs = JSON.parse(readFileSync(new URL('web_packs.json', root)));
const env = { ASSETS: { async fetch(request) {
  const path = new URL(request.url).pathname.slice(1);
  try {
    const file = new URL(path, root);
    const length = statSync(file).size;
    const body = request.method === 'HEAD' ? null : Readable.toWeb(createReadStream(file));
    return new Response(body, { headers: {
      'Content-Length': String(length), 'Content-Type': 'application/octet-stream',
      'Cache-Control': 'public, max-age=31536000, immutable',
    } });
  } catch { return new Response('Not found', { status: 404 }); }
} } };
const base = process.argv[2]?.replace(/\/$/, '') || 'https://example.com';
const fetchRequest = request => process.argv[2] ? fetch(request) : worker.fetch(request, env);
let checkedPacks = 0;
let checkedStreams = 0;
if (process.argv[2]) {
  const html = await fetch(base + '/');
  assert.equal(html.status, 200);
  assert.match(await html.text(), /Kingdom Rush Web/);
  console.log('Entry HTML: OK');
}
for (const file of Object.values(packs.packs)) {
  if (process.argv[3] && process.argv[3] !== '/' + file.url) continue;
  const response = await fetchRequest(new Request(base + '/' + file.url));
  assert.equal(response.status, 200);
  assert.match(response.headers.get('Cache-Control') || '', /immutable/);
  const hash = createHash('sha256');
  let size = 0;
  for await (const chunk of response.body) { hash.update(chunk); size += chunk.length; }
  assert.equal(size, file.size);
  assert.ok(size <= 24 * 1024 * 1024);
  assert.equal(hash.digest('hex'), file.sha256);
  checkedPacks += 1;
}
console.log(`Immutable pack hashes/cache/limits: ${checkedPacks} packs checked`);
for (const [path, file] of Object.entries(manifest)) {
  if (process.argv[3] && process.argv[3] !== path) continue;
  const url = base + path;
  const head = await fetchRequest(new Request(url, { method: 'HEAD' }));
  assert.equal(head.status, 200);
  // The CDN can omit Content-Length when applying Brotli/gzip (notably WASM).
  if (!head.headers.get('Content-Encoding')) {
    assert.equal(head.headers.get('Content-Length'), String(file.size));
  }
  assert.equal(head.headers.get('Content-Type'), file.type);
  const response = await fetchRequest(new Request(url));
  assert.equal(response.status, 200);
  const hash = createHash('sha256');
  let length = 0;
  let nextProgress = 64 * 1024 * 1024;
  for await (const chunk of response.body) {
    hash.update(chunk); length += chunk.length;
    if (process.argv[2] && length >= nextProgress) {
      console.log(`${path}: ${Math.floor(length / 1024 / 1024)} MiB downloaded`);
      nextProgress += 64 * 1024 * 1024;
    }
  }
  assert.equal(length, file.size);
  assert.equal(hash.digest('hex'), file.sha256);
  console.log(`${path}: ${length} bytes, SHA-256 matches`);
  const cached = await fetchRequest(new Request(url, { headers: { 'If-None-Match': head.headers.get('ETag') } }));
  assert.equal(cached.status, 304);
  assert.equal((await fetchRequest(new Request(url, { method: 'POST' }))).status, 405);
  checkedStreams += 1;
  console.log(`${path}: ${length} bytes, SHA-256 matches, HEAD/304/405 passed`);
}
if (!process.argv[2] && !process.argv[3]) {
  const sha = value => createHash('sha256').update(value).digest('hex');
  writeFileSync(new URL('../build/cloudflare_verification.json', import.meta.url), JSON.stringify({
    passed: true, immutable_packs: checkedPacks, streamed_files: checkedStreams,
    manifest_sha256: sha(readFileSync(new URL('web_packs.json', root))),
    worker_sha256: sha(readFileSync(new URL('_worker.js', root))),
    headers_sha256: sha(readFileSync(new URL('_headers', root))),
    browser_tested: false, remote_tested: false,
  }, null, 2));
}
