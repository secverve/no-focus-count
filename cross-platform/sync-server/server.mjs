import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';

const port = Number(process.env.PORT || 8787);
const storageDirectory = path.resolve(process.env.NFC_SYNC_DATA_DIR || './data');
const expectedToken = process.env.NFC_SYNC_TOKEN || '';
const maximumBytes = 10 * 1024 * 1024;

if (!expectedToken) {
  throw new Error('NFC_SYNC_TOKEN 환경 변수가 필요합니다.');
}

function authorized(request) {
  const supplied = request.headers.authorization?.replace(/^Bearer\s+/i, '') ?? '';
  const left = Buffer.from(supplied);
  const right = Buffer.from(expectedToken);
  return left.length === right.length && timingSafeEqual(left, right);
}

function accountFromURL(url) {
  const match = new URL(url, 'http://localhost').pathname.match(/^\/state\/([A-Za-z0-9._-]{1,80})$/);
  return match?.[1];
}

async function readBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maximumBytes) throw new Error('payload-too-large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

function respond(response, status, payload) {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store'
  });
  response.end(JSON.stringify(payload));
}

await fs.mkdir(storageDirectory, { recursive: true });

createServer(async (request, response) => {
  try {
    const account = accountFromURL(request.url);
    if (!account) return respond(response, 404, { error: 'not-found' });
    if (!authorized(request)) return respond(response, 401, { error: 'unauthorized' });
    const file = path.join(storageDirectory, `${account}.json`);

    if (request.method === 'GET') {
      try {
        const data = JSON.parse(await fs.readFile(file, 'utf8'));
        return respond(response, 200, data);
      } catch (error) {
        if (error.code === 'ENOENT') return respond(response, 404, { error: 'account-empty' });
        throw error;
      }
    }

    if (request.method === 'PUT') {
      const data = JSON.parse(await readBody(request));
      const temporary = `${file}.tmp`;
      await fs.writeFile(temporary, JSON.stringify(data));
      await fs.rename(temporary, file);
      return respond(response, 200, { ok: true, updatedAt: new Date().toISOString() });
    }

    return respond(response, 405, { error: 'method-not-allowed' });
  } catch (error) {
    const status = error.message === 'payload-too-large' ? 413 : 500;
    return respond(response, status, { error: status === 413 ? 'payload-too-large' : 'server-error' });
  }
}).listen(port, () => {
  console.log(`No Focus Count sync server listening on :${port}`);
});
