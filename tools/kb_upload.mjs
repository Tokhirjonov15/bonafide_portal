// ─────────────────────────────────────────────────────────────
//  고시 체크 자료 올리기 (2026-10-27) — 심평원·복지부 자료 텍스트를 OpenAI 벡터 저장소에 올린다.
//  OpenAI 키는 서버(Worker Secrets)에만 있으므로 포털 서버(/api/dongseon/kb/admin)를 거쳐 올린다.
//
//    $env:KB_ADMIN_KEY = '<Secrets 에 넣은 KB_ADMIN_KEY>'
//    node tools/kb_upload.mjs "C:\Users\user\Desktop\dongseon folder\txt"            (처음: 저장소 만들고 전부 올림)
//    node tools/kb_upload.mjs "C:\...\txt" --reset                                    (새 저장소에 처음부터 다시)
//    node tools/kb_upload.mjs --status                                                 (처리 상태만)
//
//  폴더의 *.txt — 'NN_문서이름.txt', 본문은 쪽마다 '=== pN ===' 줄로 시작(PDF 에서 뽑은 그대로).
//  올릴 때 쪽 표시를 '[p.N]' 로 바꾸고 쪽 안에서도 약 500자마다 다시 넣는다 — 검색이 어느 조각을 찾아도 쪽 번호가 보이게.
// ─────────────────────────────────────────────────────────────
import fs from 'node:fs';
import path from 'node:path';

const PORTAL = process.env.PORTAL || 'https://bonafide-portal.seoulgijibae.workers.dev';
const KEY = process.env.KB_ADMIN_KEY;
if (!KEY) { console.error('KB_ADMIN_KEY 환경 변수가 없습니다.'); process.exit(1); }
const args = process.argv.slice(2);
const dir = args.find(a => !a.startsWith('--'));
const api = async (action, init = {}) => {
  const r = await fetch(`${PORTAL}/api/dongseon/kb/admin?action=${action}`, { ...init, headers: { 'x-kb-key': KEY, ...(init.headers || {}) } });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`${action}: ${j.error || r.status}`);
  return j;
};
function tagPages(raw) {
  const out = [];
  for (const block of raw.replace(/^\uFEFF/, '').split(/^=== p(\d+) ===\s*$/m).slice(1).reduce((acc, x, i, arr) => (i % 2 === 0 ? acc.concat([[x, arr[i + 1] || '']]) : acc), [])) {
    const [n, body] = block; const t = body.trim();
    if (!t || /^\(빈 페이지\)$/.test(t)) continue;
    let buf = `[p.${n}] `, run = 0;
    for (const line of t.split('\n')) {
      if (run > 500) { buf += `[p.${n}] `; run = 0; }
      buf += line + '\n'; run += line.length;
    }
    out.push(buf.trim());
  }
  return out.join('\n\n');
}

if (args.includes('--status')) { console.log(JSON.stringify(await api('status'), null, 1)); process.exit(0); }
if (!dir || !fs.existsSync(dir)) { console.error('텍스트 폴더를 주세요.'); process.exit(1); }
const files = fs.readdirSync(dir).filter(f => /\.txt$/i.test(f)).sort();
if (!files.length) { console.error('폴더에 .txt 가 없습니다.'); process.exit(1); }
const c = await api(args.includes('--reset') ? 'reset' : 'create', { method: 'POST' });
console.log('벡터 저장소:', c.vs, c.note || '');
for (const f of files) {
  const body = tagPages(fs.readFileSync(path.join(dir, f), 'utf8'));
  const j = await api('upload', { method: 'POST', headers: { 'content-type': 'text/plain; charset=utf-8', 'x-name': encodeURIComponent(f) }, body });
  console.log(`올림: ${f} (${Math.round(Buffer.byteLength(body) / 1024)}KB) → ${j.status}`);
}
console.log('다 올렸습니다. OpenAI 가 나눠 색인하는 데 몇 분 걸립니다 — 확인: node tools/kb_upload.mjs --status');
