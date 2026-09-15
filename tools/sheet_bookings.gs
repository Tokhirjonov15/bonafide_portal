/**
 * 반듯한정형외과 물리치료센터 비급여 예약리스트(Google Sheet) → 동선관리 Firestore `bookings/{YYYY-MM-DD}`
 * ---------------------------------------------------------------------------------------------
 * 어디에:  Apps Script 프로젝트(예약리스트 파일에 묶인 프로젝트 또는 독립 프로젝트)에 이 파일을 추가한다.
 *          기존 함수(getColorRatio 등)는 그대로 두고, 파일만 하나 더 만들면 된다.
 * 설정:    프로젝트 설정 › 스크립트 속성
 *            FIREBASE_API_KEY   동선관리 Firebase 웹 API 키
 *            BOT_EMAIL          동선관리에서 만든 봇 계정 (예: sheetbot) 이메일
 *            BOT_PASSWORD       그 비밀번호
 *            FILE_ID            (선택) 예약리스트 파일 ID — 비우면 이름 규칙으로 이번 달 파일을 찾는다
 *            FILE_NAME          (선택) 이름 규칙, 기본 '비급여 예약리스트 {M}월({YYYY})'
 * 시작:    installTriggers() 를 한 번 실행(권한 승인) → 5분마다 + 파일이 바뀔 때마다 오늘·내일 탭을 올리고,
 *          매일 00:15 에 다음 7일을 올리며 새 달 파일이 생기면 변경 감지 트리거를 옮겨 단다.
 * 읽기만:  이 스크립트는 예약리스트를 절대 수정하지 않는다.
 *
 * 탭 구조(2026-09 파일 기준, 바뀌면 LAYOUT 만 고친다):
 *   4행: 치료사 이름(B, E, H … 3열마다, AU~BC 는 취소/변경 열)   6행~53행: 15분 단위 행(2행 = 30분), A열에 30분마다 시각
 *   치료사 블록 3열 = [환자 '차트번호(진료실) 이름방문수', 치료코드 'CME15', 표시 '.']   병합 행 수 = 치료 시간
 *   BK~BN 6행~: Manual Tx 목록 [번호, 환자번호, 성함, 치료사]     BD~BJ: 달력(무시)
 *   색: 환자 칸 회색(#999999)=근무 외/차단, 연노랑(#ffe599)=내원, 나머지 색은 원문 그대로 보내고 동선관리에서 범례로 해석
 */
var PROJECT_ID = 'bonafide-dongseon-108e2';
var LAYOUT = {
  headerRow: 4, firstRow: 6, lastRow: 53,
  timeCol: 1,                 // A
  txFrom: 2, txTo: 46,        // B..AT  치료사 블록(3열씩)
  cancelFrom: 47, cancelTo: 55, // AU..BC 취소/변경(치료사당 1열)
  manualFrom: 63, manualTo: 66, // BK..BN Manual Tx
  blockColor: '#999999',      // 근무 외/차단 칸
  minutesPerRow: 15
};
var SYNC_DAYS_AHEAD = 1;      // 수시 동기화: 오늘 + 내일
var NIGHTLY_DAYS = 7;         // 야간 동기화: 오늘부터 7일

/* ───────────── 순수 파서 (Apps Script · Node 테스트 공용) ─────────────
   grid = { top, left, values[][], backgrounds[][], notes[][], merges:[{r1,c1,r2,c2}] }  (행·열 1부터, 절대 위치) */
function parseDaySheet(grid, L) {
  L = L || LAYOUT;
  var g = function (arr, r, c) { var row = arr[r - grid.top]; if (!row) return ''; var v = row[c - grid.left]; return v === undefined || v === null ? '' : v; };
  var val = function (r, c) { return g(grid.values, r, c); };
  var bg = function (r, c) { var s = String(g(grid.backgrounds, r, c) || '').toLowerCase(); return (s === '#ffffff' || s === 'white') ? '' : s; };
  var note = function (r, c) { return String(g(grid.notes, r, c) || '').trim(); };
  var mergeAt = {};
  (grid.merges || []).forEach(function (m) { for (var r = m.r1; r <= m.r2; r++) for (var c = m.c1; c <= m.c2; c++) mergeAt[r + ':' + c] = m; });
  var isStart = function (r, c) { var m = mergeAt[r + ':' + c]; return !m || (m.r1 === r && m.c1 === c); };
  var spanRows = function (r, c) { var m = mergeAt[r + ':' + c]; return m ? (m.r2 - m.r1 + 1) : 1; };
  /* 시각: A열 값(Date · 0~1 소수 · '9:00' 문자열). 비어 있으면(15분 행) 위 행 + 15분 */
  var timeOfRow = {}; var last = null;
  for (var r = L.firstRow; r <= L.lastRow; r++) {
    var m = toMinutes(val(r, L.timeCol));
    if (m !== null) last = m; else if (last !== null) last += L.minutesPerRow;
    timeOfRow[r] = last;
  }
  var hm = function (min) { if (min === null || min === undefined) return ''; return pad2(Math.floor(min / 60)) + ':' + pad2(min % 60); };
  var therapists = [], items = [], cancels = [], manual = [], blocks = [];
  for (var c = L.txFrom; c <= L.txTo; c += 3) {
    var th = String(val(L.headerRow, c)).trim();
    if (!th) continue;
    therapists.push(th);
    for (var r2 = L.firstRow; r2 <= L.lastRow; r2++) {
      var text = String(val(r2, c)).trim();
      var color = bg(r2, c);
      if (!isStart(r2, c)) continue;
      if (!text) continue;                            // 색만 있는 빈 칸(근무 외 회색 등)은 예약이 아니다
      var rows = spanRows(r2, c);
      var base = { th: th, t: hm(timeOfRow[r2]), dur: rows * L.minutesPerRow, text: text, color: color, note: note(r2, c) };
      var p = parsePatient(text);
      if (!p || color === L.blockColor) { base.kind = 'block'; blocks.push(base); continue; }   // 'ot30분', '1진 모니터링' 같은 메모·차단
      base.kind = 'pt'; base.mrn = p.mrn; base.room = p.room; base.name = p.name; base.visit = p.visit;
      base.code = String(val(r2, c + 1)).trim(); base.codeColor = bg(r2, c + 1); base.mark = String(val(r2, c + 2)).trim();
      items.push(base);
    }
  }
  for (var cc = L.cancelFrom; cc <= L.cancelTo; cc++) {
    var th2 = String(val(L.headerRow, cc)).trim();
    for (var r3 = L.firstRow; r3 <= L.lastRow; r3++) {
      var tx = String(val(r3, cc)).trim(); if (!tx || !isStart(r3, cc)) continue;
      var q = parsePatient(tx);
      cancels.push({ th: th2, t: hm(timeOfRow[r3]), text: tx, mrn: q ? q.mrn : '', name: q ? q.name : '', color: bg(r3, cc), note: note(r3, cc) });
    }
  }
  for (var r4 = L.firstRow; r4 <= L.lastRow + 20; r4++) {
    var mrn = numStr(val(r4, L.manualFrom + 1)), nm = String(val(r4, L.manualFrom + 2)).trim();
    if (!mrn && !nm) continue;
    if (/^(null|0)$/i.test(mrn) || /^0$/.test(nm)) continue;                 // 빈 행의 수식 결과('NULL', '0') 는 건너뜀
    if (!/^\d+$/.test(mrn) && !/^[가-힣A-Za-z]/.test(nm)) continue;          // 환자번호(숫자)나 성함 중 하나는 있어야 한 줄로 친다(성함이 아직 비어 있어도 표시)
    manual.push({ no: numStr(val(r4, L.manualFrom)), mrn: mrn, name: nm, th: String(val(r4, L.manualFrom + 3)).trim(),
                  color: bg(r4, L.manualFrom + 2) || bg(r4, L.manualFrom + 1), note: note(r4, L.manualFrom + 2) || note(r4, L.manualFrom + 1) });
  }
  /* 표 아래 숫자칸(54행~): A열 라벨(당월 누적 상담수·평균 내원률·비급여 합계 등) + B열 값 → 직원용 예약관리 통계 카드 */
  var stats = [];
  for (var r5 = L.lastRow + 1; r5 <= L.lastRow + 7; r5++) {   // 54~60행(참고사항·당월 누적 상담수·평균 내원률·비급여 합계)까지만
    var lab = String(val(r5, 1)).replace(/\s+/g, ' ').trim(); if (!lab) continue;
    var sv = val(r5, 2); if (sv === '' || sv === null || sv === undefined) continue;
    stats.push({ label: lab, value: (typeof sv === 'number') ? Math.round(sv * 100) / 100 : String(sv).trim() });
  }
  return { therapists: therapists, items: items, blocks: blocks, cancels: cancels, manual: manual, stats: stats };
}
/* '32750(1) 함수진1' · '16315(6) \n조기원15' · '9330(7)\n차중현97' → {mrn, room, name, visit} (안 맞으면 null) */
function parsePatient(text) {
  var m = /^\s*(\d{1,7})\s*\(\s*(\d{1,2})\s*\)\s*([^\d\n]+?)\s*(\d{1,3})?\s*$/.exec(String(text).replace(/\r?\n/g, ' '));
  if (!m) return null;
  return { mrn: m[1], room: m[2], name: m[3].replace(/\s+/g, ''), visit: m[4] ? parseInt(m[4], 10) : null };
}
function toMinutes(v) {
  if (v === '' || v === null || v === undefined) return null;
  if (Object.prototype.toString.call(v) === '[object Date]') return isNaN(v.getTime()) ? null : v.getHours() * 60 + v.getMinutes();
  if (typeof v === 'number') return v >= 0 && v < 1 ? Math.round(v * 24 * 60) : null;
  var m = /^\s*(\d{1,2})\s*[:시]\s*(\d{0,2})/.exec(String(v));
  return m ? parseInt(m[1], 10) * 60 + (m[2] ? parseInt(m[2], 10) : 0) : null;
}
function numStr(v) { if (v === '' || v === null || v === undefined) return ''; if (typeof v === 'number') return String(Math.round(v)); return String(v).trim().replace(/\.0+$/, ''); }
function pad2(n) { return (n < 10 ? '0' : '') + n; }

/* ───────────── Apps Script 쪽 ───────────── */
function props_() { return PropertiesService.getScriptProperties(); }
function tz_() { return Session.getScriptTimeZone() || 'Asia/Seoul'; }
function ymd_(d) { return Utilities.formatDate(d, tz_(), 'yyyy-MM-dd'); }
function addDays_(d, n) { var x = new Date(d.getTime()); x.setDate(x.getDate() + n); return x; }

/* 이번 달(또는 주어진 날짜의 달) 예약리스트 파일 */
function findFile_(d) {
  var id = props_().getProperty('FILE_ID');
  if (id) return SpreadsheetApp.openById(id);
  var pat = props_().getProperty('FILE_NAME') || '비급여 예약리스트 {M}월({YYYY})';
  var name = pat.replace('{M}', String(d.getMonth() + 1)).replace('{YYYY}', String(d.getFullYear()));
  var it = DriveApp.searchFiles("title contains '" + name.replace(/'/g, "\\'") + "' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false");
  var best = null;
  while (it.hasNext()) { var f = it.next(); if (!best || f.getLastUpdated() > best.getLastUpdated()) best = f; }
  if (!best) throw new Error('예약리스트 파일을 찾지 못함: ' + name + ' (FILE_ID 속성으로 지정할 수도 있음)');
  return SpreadsheetApp.openById(best.getId());
}
/* 탭 하나 → grid */
function readGrid_(sheet) {
  var L = LAYOUT, top = L.headerRow, left = 1, nRows = L.lastRow + 20 - top + 1, nCols = L.manualTo;
  var rg = sheet.getRange(top, left, nRows, nCols);
  var merges = rg.getMergedRanges().map(function (m) { return { r1: m.getRow(), c1: m.getColumn(), r2: m.getLastRow(), c2: m.getLastColumn() }; });
  return { top: top, left: left, values: rg.getValues(), backgrounds: rg.getBackgrounds(), notes: rg.getNotes(), merges: merges };
}
/* 날짜 하나 동기화 (변화 없으면 쓰지 않음) */
function syncDate(d) {
  var ss = findFile_(d);
  var tab = String(d.getDate()) + '일';
  var sheet = ss.getSheetByName(tab);
  if (!sheet) { Logger.log('탭 없음: ' + tab); return 'no-tab'; }
  var parsed = parseDaySheet(readGrid_(sheet), LAYOUT);
  var date = ymd_(d);
  var doc = { date: date, file: ss.getName(), fileId: ss.getId(), tab: tab, therapists: parsed.therapists, items: parsed.items, blocks: parsed.blocks, cancels: parsed.cancels, manual: parsed.manual, stats: parsed.stats };
  var body = JSON.stringify(doc);
  var key = 'hash_' + date, h = hash_(body);
  if (props_().getProperty(key) === h) return 'unchanged';
  doc.updatedAt = new Date().toISOString();
  firestoreSet_('bookings/' + date, doc);
  props_().setProperty(key, h);
  Logger.log('올림: ' + date + ' 예약 ' + parsed.items.length + '건, 취소 ' + parsed.cancels.length + ', 도수 ' + parsed.manual.length);
  return 'written';
}
function syncRange_(days) {
  var lock = LockService.getScriptLock(); if (!lock.tryLock(20000)) return;
  try { var now = new Date(); for (var i = 0; i <= days; i++) { try { syncDate(addDays_(now, i)); } catch (e) { Logger.log('오류 ' + ymd_(addDays_(now, i)) + ': ' + e); props_().setProperty('lastErr', new Date().toISOString() + ' ' + e); } } }
  finally { lock.releaseLock(); }
}
function syncRecent() { syncRange_(SYNC_DAYS_AHEAD); }                 // 5분 트리거
function onSheetChange(e) {                                               // 파일 변경 트리거(값·서식·병합 모두)
  var p = props_(), last = Number(p.getProperty('lastChangeSync') || 0), now = Date.now();
  if (now - last < 8000) { p.setProperty('pending', '1'); return; }       // 연속 편집은 8초에 한 번만
  p.setProperty('lastChangeSync', String(now)); p.deleteProperty('pending');
  syncRange_(SYNC_DAYS_AHEAD);
}
function nightly() {                                                      // 00:15 — 다음 7일 + 새 달 파일이면 변경 트리거 옮기기
  syncRange_(NIGHTLY_DAYS);
  try { ensureChangeTrigger_(); } catch (e) { Logger.log('트리거 갱신 실패: ' + e); }
}
function ensureChangeTrigger_() {
  var ss = findFile_(new Date()), id = ss.getId();
  var have = false;
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() !== 'onSheetChange') return;
    if (t.getTriggerSourceId && t.getTriggerSourceId() === id) have = true; else ScriptApp.deleteTrigger(t);
  });
  if (!have) ScriptApp.newTrigger('onSheetChange').forSpreadsheet(id).onChange().create();
}
/* 한 번 실행: 트리거 설치(+ 권한 승인) */
function installTriggers() {
  ScriptApp.getProjectTriggers().forEach(function (t) { if (['syncRecent', 'nightly', 'onSheetChange'].indexOf(t.getHandlerFunction()) >= 0) ScriptApp.deleteTrigger(t); });
  ScriptApp.newTrigger('syncRecent').timeBased().everyMinutes(5).create();
  ScriptApp.newTrigger('nightly').timeBased().atHour(0).nearMinute(15).everyDays(1).create();
  ensureChangeTrigger_();
  syncRange_(SYNC_DAYS_AHEAD);
  Logger.log('설치 완료. 파일: ' + findFile_(new Date()).getName());
}
/* 지금 상태 보기 */
function status() {
  var p = props_().getProperties(); var out = {};
  Object.keys(p).forEach(function (k) { if (k !== 'BOT_PASSWORD' && k !== 'FIREBASE_API_KEY') out[k] = p[k]; });
  out.triggers = ScriptApp.getProjectTriggers().map(function (t) { return t.getHandlerFunction() + '/' + t.getEventType(); });
  Logger.log(JSON.stringify(out, null, 2)); return out;
}
/* 시험: 특정 날짜 파싱 결과만 보기(쓰지 않음) — 예: previewDate('2026-09-13') */
function previewDate(ymd) {
  var d = new Date(ymd + 'T12:00:00'); var ss = findFile_(d); var sheet = ss.getSheetByName(String(d.getDate()) + '일');
  var r = parseDaySheet(readGrid_(sheet), LAYOUT); Logger.log(JSON.stringify(r, null, 1)); return r;
}

/* ───────────── Firebase ───────────── */
function idToken_() {
  var cache = CacheService.getScriptCache(), tok = cache.get('idToken'); if (tok) return tok;
  var p = props_(), key = p.getProperty('FIREBASE_API_KEY'), email = p.getProperty('BOT_EMAIL'), pw = p.getProperty('BOT_PASSWORD');
  if (!key || !email || !pw) throw new Error('스크립트 속성 FIREBASE_API_KEY / BOT_EMAIL / BOT_PASSWORD 를 넣어 주세요');
  var refresh = p.getProperty('refreshToken'); var res;
  if (refresh) {
    res = UrlFetchApp.fetch('https://securetoken.googleapis.com/v1/token?key=' + key, { method: 'post', payload: { grant_type: 'refresh_token', refresh_token: refresh }, muteHttpExceptions: true });
    if (res.getResponseCode() === 200) { var j = JSON.parse(res.getContentText()); cache.put('idToken', j.id_token, 3000); p.setProperty('refreshToken', j.refresh_token); return j.id_token; }
    p.deleteProperty('refreshToken');
  }
  res = UrlFetchApp.fetch('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=' + key,
    { method: 'post', contentType: 'application/json', payload: JSON.stringify({ email: email, password: pw, returnSecureToken: true }), muteHttpExceptions: true });
  if (res.getResponseCode() !== 200) throw new Error('Firebase 로그인 실패: ' + res.getContentText().slice(0, 200));
  var k = JSON.parse(res.getContentText()); cache.put('idToken', k.idToken, 3000); p.setProperty('refreshToken', k.refreshToken); return k.idToken;
}
function firestoreSet_(path, obj) {
  var url = 'https://firestore.googleapis.com/v1/projects/' + PROJECT_ID + '/databases/(default)/documents/' + path;
  var res = UrlFetchApp.fetch(url, { method: 'patch', contentType: 'application/json', headers: { Authorization: 'Bearer ' + idToken_() }, payload: JSON.stringify({ fields: fsFields_(obj) }), muteHttpExceptions: true });
  if (res.getResponseCode() === 401 || res.getResponseCode() === 403) { CacheService.getScriptCache().remove('idToken'); }
  if (res.getResponseCode() >= 300) throw new Error('Firestore 쓰기 실패 ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
}
/* JS 값 → Firestore REST 타입 */
function fsVal_(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(fsVal_) } };
  return { mapValue: { fields: fsFields_(v) } };
}
function fsFields_(o) { var f = {}; Object.keys(o).forEach(function (k) { if (o[k] !== undefined) f[k] = fsVal_(o[k]); }); return f; }
function hash_(s) { return Utilities.base64Encode(Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, s, Utilities.Charset.UTF_8)); }
