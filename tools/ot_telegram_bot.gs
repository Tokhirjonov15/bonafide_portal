/* ═════════════════════════════════════════════════════════════════════════
   연장근무(OT) 텔레그램 봇  —  Google Apps Script (2026-09-27)

   단톡방에 올라오는 연장근무 메시지를 Claude 가 읽어
   구글시트 "반듯한 OS 연장근무" 의 해당 달 탭에 자동으로 적는다.

   ── 기재 규칙 (담당자 확인 2026-09-27) ─────────────────────────────────
   · 1.5배는 "더할 때"만 붙는다. 빼는 것(사용)은 언제나 1배.
   · 연장(출근 전·퇴근 후·점심 근무) → 연장 행에 =분*1.5 수식.
     메시지에 "1.5배X" 가 있으면 그대로(곱하지 않음). 같은 날 두 번이면 수식에 이어 붙임.
   · 추가(휴무일 추가근무) → 480분까지 추가 행에 1배, 480 넘는 분은 추가연장 행에 =분*1.5.
     보라 배경(#9900ff). (480 기준은 사용설명서 사진에서 온 것 — 담당자 재확인 2026-09-29)
   · 사용("사용일"·연장근무에서 차감) → 연장 행에 음수, 1배로 그대로 뺀다(1.5배 금지).
     초록 배경(#00ff00). (담당자 확인 2026-09-29)
   · 9/30 근무를 10월에 올려도 9월 탭에 적는다.
   · 칸 메모에 원문·보낸이·시각을 남긴다.
   · 원래 메시지에 "답장"으로 수정을 올리면: 원래 기록을 빼고 새 기록을 넣는다.
   · 봇이 이해 못하면 ❓, 오류가 나면 ⚠️ 로 방에 답한다.

   ── 설치 순서 ──────────────────────────────────────────────────────────
   1. BotFather 에서 새 봇 생성 → 토큰 복사. /setprivacy → Disable (방 메시지 전부 수신).
   2. script.google.com 새 프로젝트 → 이 파일 붙여넣기.
      프로젝트 설정 → 시간대 Asia/Seoul 확인.
   3. 프로젝트 설정 → 스크립트 속성:
        TG_TOKEN   = 봇 토큰
        CLAUDE_KEY = Anthropic API 키
        SHEET_ID   = 시트 ID (주소의 /d/와 /edit 사이) — 처음엔 시트 "사본"으로 시험!
        SECRET     = 아무 임의 문자열 (웹훅 검증용)
        GROUP_ID   = (비워 두면 봇이 방에서 chat id 를 알려 준다 → 넣고 저장)
        MODEL      = (선택) 기본 claude-sonnet-5
   4. 배포 → 새 배포 → 웹 앱: "나(소유자)로 실행", 액세스 "모든 사용자" → URL 복사.
   5. 편집기에서 setWebhook() 함수를 한 번 실행 (WEBAPP_URL 속성에 4의 URL 저장 후).
   6. 봇을 단톡방에 초대. 아무 메시지를 보내면 GROUP_ID 안내가 온다 → 속성에 저장.
   7. 시험이 끝나면 SHEET_ID 를 진짜 시트로 바꾼다.
   ════════════════════════════════════════════════════════════════════════ */

const PROP = PropertiesService.getScriptProperties();
const TG = 'https://api.telegram.org/bot' + PROP.getProperty('TG_TOKEN');

/* ───────── 텔레그램 웹훅 입구 ───────── */
function doPost(e) {
  try {
    if (PROP.getProperty('SECRET') && e.parameter.token !== PROP.getProperty('SECRET')) return ok();
    const u = JSON.parse(e.postData.contents || '{}');
    if (!u.message || !u.message.text) return ok();

    /* 같은 업데이트 두 번 처리 방지(텔레그램 재전송 대비) */
    const cache = CacheService.getScriptCache();
    const key = 'upd_' + u.update_id;
    if (cache.get(key)) return ok();
    cache.put(key, '1', 21600);

    handleMessage(u.message);
  } catch (err) {
    /* 어떤 오류든 봇으로 알린다 — 조용히 사라지지 않게 */
    try { tg('sendMessage', { chat_id: PROP.getProperty('GROUP_ID'), text: '⚠️ 봇 오류: ' + err.message }); } catch (_) {}
  }
  return ok();
}
function ok() { return ContentService.createTextOutput('ok'); }

function handleMessage(msg) {
  const chatId = String(msg.chat.id);
  const gid = PROP.getProperty('GROUP_ID');
  if (!gid) {   // 아직 방이 등록 안 됨 — chat id 를 알려 주고 끝
    tg('sendMessage', { chat_id: chatId, text: '이 방의 chat id: ' + chatId + '\n스크립트 속성 GROUP_ID 에 저장해 주세요.' });
    return;
  }
  if (chatId !== String(gid)) return;          // 등록된 방만
  const text = (msg.text || '').trim();
  if (!text || text.startsWith('/')) return;   // 명령·빈 메시지 무시
  if (msg.from && msg.from.is_bot) return;

  const replyText = (msg.reply_to_message && msg.reply_to_message.text) ? msg.reply_to_message.text : '';

  /* OT 메시지로 보이지 않으면 조용히 넘어간다(잡담 방해 금지).
     "삭제"·"취소" 는 원래 메시지에 답장일 때만 받는다 — 그냥 대화 중의 '취소' 에 끼어들지 않도록 (2026-09-29) */
  if (!/\d\s*분|\d+\s*시간|수정/.test(text) && !(replyText && /삭제|취소|잘못/.test(text))) return;

  const sender = ((msg.from && msg.from.first_name) || '') + ((msg.from && msg.from.last_name) ? ' ' + msg.from.last_name : '');
  const msgDate = Utilities.formatDate(new Date(msg.date * 1000), 'Asia/Seoul', 'yyyy-MM-dd');

  const parsed = parseWithClaude(text, replyText, sender, msgDate);

  if (parsed.errors && parsed.errors.length && !(parsed.entries || []).length) {
    reply(msg, '❓ ' + parsed.errors.join('\n❓ '));
    return;
  }

  const ss = SpreadsheetApp.openById(PROP.getProperty('SHEET_ID'));
  const done = [], probs = (parsed.errors || []).slice();

  /* 수정: 원래 기록을 먼저 뺀다 */
  (parsed.remove || []).forEach(function (en) {
    try { applyEntry(ss, en, msg, sender, true); done.push('↩️ 취소 ' + fmtEntry(en)); }
    catch (err) { probs.push('취소 실패 ' + fmtEntry(en) + ' — ' + err.message); }
  });
  (parsed.entries || []).forEach(function (en) {
    try { applyEntry(ss, en, msg, sender, false); done.push('✅ ' + fmtEntry(en)); }
    catch (err) { probs.push(fmtEntry(en) + ' — ' + err.message); }
  });

  let out = done.join('\n');
  if (probs.length) out += (out ? '\n' : '') + '❓ ' + probs.join('\n❓ ');
  reply(msg, out || '❓ 기재할 내용을 찾지 못했습니다.');
}

/* 방에 되돌려 줄 한 줄 — 실제로 칸에 들어간 값까지 보여 준다(1.5배인지 바로 확인되게) */
function fmtEntry(en) {
  const head = en.name + ' · ' + en.date.slice(5).replace('-', '/') + ' · ' + en.kind + ' ' + en.minutes + '분';
  if (en.kind === '연장') return head + (en.mult15 === false ? ' (1.5배X → ' + en.minutes + ')' : ' ×1.5 → ' + (en.minutes * 1.5));
  if (en.kind === '사용') return head + ' 차감 (1배 → -' + en.minutes + ')';
  if (en.minutes > 480) return head + ' (480까지 1배, 초과 ' + (en.minutes - 480) + '분 ×1.5)';
  return head + ' (1배)';
}
function reply(msg, text) {
  tg('sendMessage', { chat_id: msg.chat.id, reply_to_message_id: msg.message_id, text: text });
}

/* ───────── Claude 로 메시지 해석 ───────── */
function parseWithClaude(text, replyText, sender, msgDate) {
  const sys = [
    '너는 병원 직원들의 연장근무(OT) 메시지를 구글시트 기재용 JSON 으로 바꾸는 해석기다.',
    '반드시 JSON 만 출력한다. 형식:',
    '{"entries":[{"date":"YYYY-MM-DD","name":"이름","minutes":정수,"kind":"연장|추가|사용","mult15":true|false,"desc":"짧은 설명"}],"remove":[같은 형식],"errors":["이유"]}',
    '',
    '규칙:',
    '- 메시지를 보낸 사람과 근무한 사람은 다를 수 있다. 이름은 반드시 메시지 본문에서 찾는다.',
    '- 한 메시지에 여러 기록이 있을 수 있다. 각각 entries 항목으로.',
    '- kind: 출근 전/퇴근 후/점심 근무·"출근전 근무"·"퇴근시간전근무" 등 근무일의 연장 = "연장".',
    '  휴무일에 나와 일한 것·"추가근무" = "추가".',
    '  쌓인 시간을 쓴 것 = "사용". "사용일"·"연장근무 사용"·"연장에서 차감"·"연장근무 90분 썼습니다"·',
    '  "조퇴/늦게 출근하며 연장근무로 대체" 는 문장에 "연장근무" 가 들어 있어도 모두 "사용" 이다.',
    '  구분 기준은 낱말이 아니라 방향이다 — 시간이 늘어나면 연장/추가, 줄어들면 사용.',
    '- minutes: 본문에 적힌 분(分)을 그대로 쓴다. 시간 범위와 분이 다르면 적힌 분을 믿는다.',
    '  분이 없고 시간 범위만 있으면 범위로 계산한다. 둘 다 없으면 errors 에 이유를 적고 그 항목은 버린다. 추측 금지.',
    '  minutes 는 언제나 양수다. 빼는 것은 음수가 아니라 kind="사용" 으로 표시한다.',
    '- mult15: kind="연장" 일 때만 쓴다. 기본 true, 본문에 "1.5배X"·"1.5배 안함" 이 있으면 false.',
    '  kind 가 "추가" 또는 "사용" 이면 반드시 false — 이 둘은 1배다.',
    '- "Total 연장근무시간"·"남은연장근무시간" 같은 합계 숫자는 기록이 아니다. 무시한다.',
    '- date: 연도가 없으면 메시지 날짜(아래) 기준 가장 가까운 과거(오늘 포함)로 정한다. "사용일 9/23" 처럼 사용 날짜가 따로 있으면 그 날짜다.',
    '- 답장 원문이 주어지고 새 메시지에 "수정" 이 있으면: 답장 원문을 해석해 remove 에, 고쳐진 내용을 entries 에 넣는다.',
    '  새 메시지가 "삭제"·"취소"·"잘못 올렸습니다" 처럼 지우라는 뜻뿐이면: 답장 원문을 remove 에만 넣고 entries 는 비운다.',
    '  답장 원문이 없는데 고치거나 지우라고 하면, 무엇을 고칠지 알 수 없으므로 errors 에',
    '  "고칠 원래 메시지에 답장으로 보내 주세요" 라고 적는다. 지어내지 않는다.',
    '- 확실하지 않은 것은 errors 에 한국어 한 줄로 적는다. 지어내지 않는다.'
  ].join('\n');
  const usr = '메시지 날짜: ' + msgDate + '\n보낸 사람: ' + sender + (replyText ? '\n--- 답장 원문 ---\n' + replyText : '') + '\n--- 메시지 ---\n' + text;

  const res = UrlFetchApp.fetch('https://api.anthropic.com/v1/messages', {
    method: 'post', contentType: 'application/json', muteHttpExceptions: true,
    headers: (function () {
      const h = { 'x-api-key': PROP.getProperty('CLAUDE_KEY'), 'anthropic-version': '2023-06-01' };
      /* 워크스페이스에 묶이지 않은 키는 워크스페이스 ID 를 함께 보내야 한다 (스크립트 속성 WORKSPACE_ID) */
      const w = PROP.getProperty('WORKSPACE_ID');
      if (w) h['anthropic-workspace-id'] = w;
      return h;
    })(),
    payload: JSON.stringify({
      model: PROP.getProperty('MODEL') || 'claude-sonnet-5',
      max_tokens: 2000,
      system: sys,
      messages: [{ role: 'user', content: usr }]
    })
  });
  if (res.getResponseCode() !== 200) throw new Error('Claude API ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 300));
  const body = JSON.parse(res.getContentText());
  const txt = (body.content || []).map(function (b) { return b.text || ''; }).join('');
  const m = txt.match(/\{[\s\S]*\}/);
  if (!m) throw new Error('Claude 응답에서 JSON 을 찾지 못했습니다.');
  const out = JSON.parse(m[0]);
  out.entries = out.entries || []; out.remove = out.remove || []; out.errors = out.errors || [];
  /* 최소 검증 + 규칙 고정 (해석이 틀려도 1.5배가 잘못 붙지 않도록) */
  function clean(list) {
    return list.filter(function (en) {
      if (!en.name || !en.date || !en.minutes || !en.kind) { out.errors.push('빠진 값이 있는 항목을 건너뜀'); return false; }
      en.minutes = Math.abs(Number(en.minutes));                 // 분은 항상 양수
      if (en.kind !== '연장') en.mult15 = false;                 // 추가·사용은 1배
      return en.minutes > 0;
    });
  }
  out.entries = clean(out.entries); out.remove = clean(out.remove);
  return out;
}

/* ───────── 시트에 기재 ───────── */
function applyEntry(ss, en, msg, sender, isRemove) {
  const d = new Date(en.date + 'T09:00:00');
  const sh = findMonthTab(ss, d.getFullYear(), d.getMonth() + 1);
  const row = findPersonRow(sh, en.name);          // 연장 행
  const col = findDayCol(sh, d.getDate());
  const min = Math.abs(Number(en.minutes)) * (isRemove ? -1 : 1);
  const note = '[' + Utilities.formatDate(new Date(msg.date * 1000), 'Asia/Seoul', 'M/d HH:mm') + ' ' + sender + (isRemove ? ' 수정취소' : '') + '] ' + (msg.text || '').slice(0, 180);

  if (en.kind === '사용') {
    const cell = sh.getRange(row, col);
    addToCell(cell, -min, false);                  // 음수, 1배 — 쓴 분을 그대로 뺀다
    cell.setBackground('#00ff00');
    appendNote(cell, note);
  } else if (en.kind === '연장') {
    const cell = sh.getRange(row, col);
    addToCell(cell, min, en.mult15 !== false);     // 더할 때만 1.5배
    appendNote(cell, note);
  } else if (en.kind === '추가') {
    /* 추가 행에 480분까지 1배, 480 넘는 분은 추가연장 행에 =분*1.5 로. (2026-09-29 확인) */
    const c1 = sh.getRange(row + 1, col), c2 = sh.getRange(row + 2, col);
    const total = numOf(c1) + rawOver(c2) + min;    // rawOver: 추가연장 칸의 1.5배 이전 원래 분
    if (total < 0) throw new Error('추가근무가 음수가 됩니다(' + total + '분)');
    const base = Math.min(total, 480), over = Math.max(total - 480, 0);
    c1.setValue(base > 0 ? base : '');
    if (over > 0) c2.setFormula('=' + over + '*1.5'); else c2.setValue('');
    c1.setBackground(base > 0 ? '#9900ff' : null);
    c2.setBackground(over > 0 ? '#9900ff' : null);  /* 수정으로 0 이 되면 색도 지운다 */
    appendNote(c1, note);
    if (over > 0) appendNote(c2, note);
  } else {
    throw new Error('알 수 없는 종류: ' + en.kind);
  }
}

/* 칸에 분을 이어 붙인다. mult15 면 =분*1.5 수식으로 */
function addToCell(cell, min, mult15) {
  const f = cell.getFormula();                     // '=30*1.5' 처럼 수식이면
  const v = cell.getValue();
  const piece = mult15 ? (min < 0 ? '-' + (-min) + '*1.5' : min + '*1.5') : (min < 0 ? String(min) : String(min));
  if (f) {
    cell.setFormula(f + (piece.charAt(0) === '-' ? piece : '+' + piece));
  } else if (v !== '' && v !== null && !isNaN(v) && Number(v) !== 0) {
    cell.setFormula('=' + Number(v) + (piece.charAt(0) === '-' ? piece : '+' + piece));
  } else {
    cell.setFormula(mult15 || piece.charAt(0) === '-' ? '=' + piece : piece);
  }
}
function numOf(range) { const v = range.getValue(); return (v === '' || v === null || isNaN(v)) ? 0 : Number(v); }
/* 추가연장 칸은 =분*1.5 수식으로 적는다. 같은 날 또 들어오면 다시 계산해야 하므로 원래 분을 되돌려 읽는다.
   사람이 손으로 넣은 값·모르는 수식이면 덮어쓰지 않고 멈춘다 — 잘못 계산하는 것보다 안전하다. */
function rawOver(range) {
  const f = String(range.getFormula() || '').trim();
  if (!f) {
    const v = range.getValue();
    if (v === '' || v === null || isNaN(v) || Number(v) === 0) return 0;
    throw new Error('추가연장 칸(' + range.getA1Notation() + ')에 손으로 넣은 값 ' + v + ' 이 있습니다 — 직접 확인해 주세요');
  }
  const m = f.match(/^=\s*(\d+(?:\.\d+)?)\s*\*\s*1\.5$/);
  if (m) return Number(m[1]);
  throw new Error('추가연장 칸(' + range.getA1Notation() + ') 수식 "' + f + '" 을 해석할 수 없습니다 — 직접 확인해 주세요');
}
function appendNote(cell, note) {
  const old = cell.getNote();
  cell.setNote(old ? old + '\n' + note : note);
}

/* 달 탭: '2026년 9월' → '2026년9월' → '2026년 09월' → '2026년09월' 순으로 찾는다 */
function findMonthTab(ss, y, m) {
  const names = [y + '년 ' + m + '월', y + '년' + m + '월', y + '년 0' + m + '월', y + '년0' + m + '월'];
  for (var i = 0; i < names.length; i++) { const sh = ss.getSheetByName(names[i]); if (sh) return sh; }
  throw new Error(y + '년 ' + m + '월 탭이 없습니다');
}
/* 이름 행: B열에서 이름을 찾고 D열이 "연장" 인 행 */
function findPersonRow(sh, name) {
  const last = sh.getLastRow();
  const bs = sh.getRange(1, 2, last, 1).getValues();
  const ds = sh.getRange(1, 4, last, 1).getValues();
  for (var r = 0; r < last; r++) {
    if (String(bs[r][0]).trim() === name && String(ds[r][0]).trim() === '연장') return r + 1;
  }
  throw new Error("'" + name + "' 을(를) 시트에서 찾지 못했습니다");
}
/* 날짜 열: 4행 머리글에서 "N일" */
function findDayCol(sh, day) {
  const heads = sh.getRange(4, 1, 1, sh.getLastColumn()).getValues()[0];
  for (var c = 0; c < heads.length; c++) if (String(heads[c]).trim() === day + '일') return c + 1;
  throw new Error(day + '일 열을 찾지 못했습니다');
}

/* ───────── 텔레그램 API ───────── */
function tg(method, payload) {
  return UrlFetchApp.fetch(TG + '/' + method, {
    method: 'post', contentType: 'application/json', muteHttpExceptions: true,
    payload: JSON.stringify(payload)
  });
}

/* ───────── 폴링(권장): 1분마다 텔레그램에서 새 메시지를 가져온다 ─────────
   구글 웹 앱은 POST 응답을 302 로 돌려주는데 텔레그램 웹훅은 302 를 오류로 본다(2026-09-27 확인).
   그래서 웹훅 대신 시간 트리거로 getUpdates 를 쓴다. 설치:
   ① removeWebhook() 한 번 실행  ② installTrigger() 한 번 실행 — 끝. 배포(웹 앱)는 필요 없다. */
function pollUpdates() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(1000)) return;                 // 이전 실행이 아직 돌고 있으면 건너뜀
  try {
    const off = Number(PROP.getProperty('LAST_UPDATE') || 0) + 1;
    const r = JSON.parse(tg('getUpdates', { offset: off, timeout: 0, allowed_updates: ['message'] }).getContentText());
    if (!r.ok) throw new Error('getUpdates: ' + JSON.stringify(r).slice(0, 200));
    (r.result || []).forEach(function (u) {
      PROP.setProperty('LAST_UPDATE', String(u.update_id));   // 처리 전에 저장 — 한 메시지가 계속 오류를 내며 막는 일 방지
      if (u.message && u.message.text) {
        try { handleMessage(u.message); }
        catch (err) {
          try { tg('sendMessage', { chat_id: u.message.chat.id, reply_to_message_id: u.message.message_id, text: '⚠️ 봇 오류: ' + err.message }); } catch (_) {}
        }
      }
    });
  } finally { lock.releaseLock(); }
}
/* 1분 트리거 설치/해제 — 편집기에서 한 번 실행 */
function installTrigger() {
  uninstallTrigger();
  ScriptApp.newTrigger('pollUpdates').timeBased().everyMinutes(1).create();
  Logger.log('1분 폴링 트리거 설치 완료');
}
function uninstallTrigger() {
  ScriptApp.getProjectTriggers().forEach(function (t) { if (t.getHandlerFunction() === 'pollUpdates') ScriptApp.deleteTrigger(t); });
}

/* 웹훅 등록(예비 — 폴링을 쓰는 동안은 사용하지 않는다) */
function setWebhook() {
  const url = PROP.getProperty('WEBAPP_URL') + '?token=' + PROP.getProperty('SECRET');
  const r = tg('setWebhook', { url: url, allowed_updates: ['message'] });
  Logger.log(r.getContentText());
}
function removeWebhook() { Logger.log(tg('deleteWebhook', {}).getContentText()); }

/* 시트 기재만 시험(텔레그램 없이): 편집기에서 실행 → 로그 확인 */
function testApply() {
  const ss = SpreadsheetApp.openById(PROP.getProperty('SHEET_ID'));
  const fake = { date: Math.floor(Date.now() / 1000), text: '시험 기재', chat: { id: 0 }, message_id: 0 };
  applyEntry(ss, { date: '2026-09-26', name: '이아람', minutes: 30, kind: '연장', mult15: true }, fake, '시험', false);
  Logger.log('OK — 시트에서 확인 후 되돌리세요');
}
