// 감시 프로그램 자동 업데이트 배포 (2026-11-15) — tools/bitplus_watcher.ps1 을 사이트(public/dongseon/bit/)에 올릴 파일로 복사하고
// watcher.json { ver, sha256 } 을 만든다. ver 는 파일 안의 $MyVer 값. git push 로 배포되면 각 PC 의 감시 프로그램이 30분 안에 스스로 바꾼다.
//   node tools/publish_watcher.mjs
import fs from 'node:fs'; import path from 'node:path'; import crypto from 'node:crypto';
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const src = path.join(root, 'tools', 'bitplus_watcher.ps1');
const dir = path.join(root, 'public', 'dongseon', 'bit');
const buf = fs.readFileSync(src);
const m = /\$MyVer = '([^']+)'/.exec(buf.toString('utf8'));
if (!m) { console.error('$MyVer 를 찾지 못했습니다'); process.exit(1); }
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, 'bitplus_watcher.ps1'), buf);
const sha256 = crypto.createHash('sha256').update(buf).digest('hex').toUpperCase();
fs.writeFileSync(path.join(dir, 'watcher.json'), JSON.stringify({ ver: m[1], sha256, at: new Date().toISOString() }) + '\n');
console.log('published', m[1], sha256);
