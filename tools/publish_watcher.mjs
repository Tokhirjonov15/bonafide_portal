// 감시 프로그램 자동 업데이트 배포 (2026-11-15) — tools/bitplus_watcher.ps1 을 사이트(public/dongseon/bit/)에 올릴 파일로 복사하고
// watcher.json { ver, sha256 } 을 만든다. ver 는 파일 안의 $MyVer 값. git push 로 배포되면 각 PC 의 감시 프로그램이 30분 안에 스스로 바꾼다.
// 같은 날 DB 에이전트도: tools/bit_db_agent.ps1 → bit_db_agent.ps1 + agent.json { ver = 파일 안의 $VER, sha256 } (db2.8 부터 스스로 바꾼다)
//   node tools/publish_watcher.mjs            (둘 다)
//   node tools/publish_watcher.mjs watcher    (감시만)   /   node tools/publish_watcher.mjs agent   (DB 에이전트만)   /   … capture (캡처 바만)
import fs from 'node:fs'; import path from 'node:path'; import crypto from 'node:crypto';
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const dir = path.join(root, 'public', 'dongseon', 'bit');
const only = process.argv[2] || '';
const items = [
  { key: 'watcher', src: 'bitplus_watcher.ps1', json: 'watcher.json', re: /\$MyVer = '([^']+)'/ },
  { key: 'agent', src: 'bit_db_agent.ps1', json: 'agent.json', re: /\$VER = '([^']+)'/ },
  { key: 'capture', src: 'slip_capture.ps1', json: 'capture.json', re: /\$CapVer = '([^']+)'/ },   // 진료실 캡처 바 — 감시 v4.0 이 sha256 으로 비교해 바꿔 준다 (2026-11-17)
];
fs.mkdirSync(dir, { recursive: true });
for (const it of items) {
  if (only && only !== it.key) continue;
  const buf = fs.readFileSync(path.join(root, 'tools', it.src));
  const m = it.re.exec(buf.toString('utf8'));
  if (!m) { console.error(it.src + ': 버전 표시를 찾지 못했습니다'); process.exit(1); }
  fs.writeFileSync(path.join(dir, it.src), buf);
  const sha256 = crypto.createHash('sha256').update(buf).digest('hex').toUpperCase();
  fs.writeFileSync(path.join(dir, it.json), JSON.stringify({ ver: m[1], sha256, at: new Date().toISOString() }) + '\n');
  console.log('published', it.src, m[1], sha256);
}
