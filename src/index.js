/* ============================================================
   반듯한정형외과 통합 포털 — API (재고관리)
   /api/* 요청만 여기서 처리하고, 나머지 주소는 public/ 의 파일을 그대로 보냅니다.

   설계 원칙
   1) 재고 수량은 저장하지 않는다. movements(입출고 기록)의 합으로 서버가 계산 → 감사 추적.
   2) 유통기한은 movements에 함께 기록한다 → 같은 품목도 들어온 날짜별로 관리(로트).
      출고할 때는 유통기한이 가장 빠른 것부터 자동으로 빠진다(FEFO).
   3) 표는 첫 요청 때 자동으로 만들어지고, 새 열도 자동으로 추가된다.
   ============================================================ */

/* PDF 발주서 생성용 (한글 폰트 임베드) */
import * as PDFLib from "./vendor/pdf-lib.min.js";
import fontkit from "./vendor/fontkit.umd.min.js";

let schemaReady = false;

const DDL = [
  `CREATE TABLE IF NOT EXISTS products (
     id TEXT PRIMARY KEY,
     name TEXT NOT NULL,
     cat  TEXT DEFAULT '',
     loc  TEXT DEFAULT '',
     unit TEXT DEFAULT '',
     bar  TEXT DEFAULT '',
     min_qty INTEGER DEFAULT 0,
     price INTEGER DEFAULT 0,
     vendor TEXT DEFAULT '',
     created_at INTEGER
   )`,
  `CREATE TABLE IF NOT EXISTS movements (
     id   TEXT PRIMARY KEY,
     pid  TEXT NOT NULL,
     type TEXT NOT NULL,
     qty  INTEGER NOT NULL,
     memo TEXT DEFAULT '',
     who  TEXT DEFAULT '',
     expiry TEXT DEFAULT '',
     lot  TEXT DEFAULT '',
     ts   INTEGER NOT NULL
   )`,
  `CREATE INDEX IF NOT EXISTS idx_mv_pid ON movements(pid)`,
  `CREATE INDEX IF NOT EXISTS idx_mv_ts  ON movements(ts)`,
  `CREATE INDEX IF NOT EXISTS idx_pr_bar ON products(bar)`,
  `CREATE TABLE IF NOT EXISTS tg_subs (
     chat_id TEXT PRIMARY KEY,
     name    TEXT DEFAULT '',
     added   INTEGER
   )`,
  `CREATE TABLE IF NOT EXISTS meta (
     key   TEXT PRIMARY KEY,
     value TEXT
   )`,
  `CREATE TABLE IF NOT EXISTS staff (
     id     TEXT PRIMARY KEY,
     name   TEXT DEFAULT '',
     active INTEGER DEFAULT 1
   )`
];

/* 이미 만들어진 표에 새 열을 붙인다(이미 있으면 오류가 나므로 조용히 넘어감) */
const MIGRATIONS = [
  `ALTER TABLE products  ADD COLUMN price  INTEGER DEFAULT 0`,
  `ALTER TABLE products  ADD COLUMN vendor TEXT DEFAULT ''`,
  `ALTER TABLE products  ADD COLUMN par_qty INTEGER DEFAULT 0`,
  `ALTER TABLE products  ADD COLUMN alt    TEXT DEFAULT ''`,
  `ALTER TABLE movements ADD COLUMN expiry TEXT DEFAULT ''`,
  `ALTER TABLE movements ADD COLUMN lot    TEXT DEFAULT ''`
];

async function ensureSchema(env) {
  if (schemaReady) return;
  for (const q of DDL) await env.DB.prepare(q).run();
  for (const q of MIGRATIONS) {
    try { await env.DB.prepare(q).run(); } catch (_) { /* 이미 있는 열 */ }
  }
  /* 직원 아이디 30개 자동 생성 (bd01 ~ bd30) — 이미 있으면 건너뜀 */
  const c = await env.DB.prepare(`SELECT COUNT(*) AS c FROM staff`).first();
  if (!c || !c.c) {
    const stmts = [];
    for (let i = 1; i <= 30; i++) {
      stmts.push(env.DB.prepare(`INSERT OR IGNORE INTO staff (id) VALUES (?)`)
        .bind("bd" + String(i).padStart(2, "0")));
    }
    for (let i = 0; i < stmts.length; i += 15) await env.DB.batch(stmts.slice(i, i + 15));
  }
  schemaReady = true;
}

/* ============================================================
   직원 로그인 — 아이디 30개 + 공용 비밀번호(STAFF_PW 시크릿)
   토큰: id.만료시각.서명(HMAC) — 서버에 세션 저장 불필요, 90일 유효
   ============================================================ */
async function hmacSig(env, text) {
  const keyData = new TextEncoder().encode("bandeut-staff:" + (env.STAFF_PW || ""));
  const key = await crypto.subtle.importKey("raw", keyData, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(text));
  return btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
/* 최고관리자 계정 — 비밀번호는 ADMIN_PW 시크릿으로 별도 관리 */
const ADMIN_ID = "bd01";

/* 세션 30분 — 단, 작업(POST)할 때마다 새 토큰이 발급되어 연장된다.
   즉 계속 일하는 직원은 로그아웃되지 않고, 방치된 기기만 30분 뒤 잠긴다. */
const SESSION_MS = 30 * 60 * 1000;
async function makeStaffToken(env, id) {
  const body = id + "." + (Date.now() + SESSION_MS);
  return body + "." + await hmacSig(env, body);
}
async function staffFromRequest(env, request) {
  const tok = request.headers.get("x-staff-token") || "";
  const parts = tok.split(".");
  if (parts.length !== 3) return null;
  const [id, exp, sig] = parts;
  if (!/^\d+$/.test(exp) || +exp < Date.now()) return null;
  if (sig !== await hmacSig(env, id + "." + exp)) return null;
  const row = await env.DB.prepare(`SELECT id, name FROM staff WHERE id=? AND active=1`).bind(id).first();
  return row ? { id: row.id, name: row.name || "", admin: row.id === ADMIN_ID } : null;
}

/* Cloudflare Access(구글 로그인)로 들어온 사용자 */
function authUser(request) {
  const email = (request.headers.get("cf-access-authenticated-user-email") || "").trim();
  return email ? { email, name: email.split("@")[0] } : null;
}

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
  });

const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
const s = (v) => (v == null ? "" : String(v).trim());
const n = (v) => { const x = parseInt(v, 10); return Number.isFinite(x) ? x : 0; };
/* 유통기한 정규화: 20260930 / 2026-09-30 / 260930 → 2026-09-30 */
function normDate(v) {
  let t = s(v).replace(/[^0-9]/g, "");
  if (!t) return "";
  if (t.length === 6) t = "20" + t;
  if (t.length !== 8) return "";
  const y = t.slice(0, 4), m = t.slice(4, 6), d = t.slice(6, 8);
  if (+m < 1 || +m > 12 || +d < 1 || +d > 31) return "";
  return `${y}-${m}-${d}`;
}

/* ---------- 조회 ---------- */
async function listProducts(env) {
  const { results } = await env.DB.prepare(`
    SELECT p.id, p.name, p.cat, p.loc, p.unit, p.bar,
           p.min_qty AS min, p.par_qty AS par, p.alt, p.price, p.vendor,
           COALESCE(SUM(CASE WHEN m.type='in' THEN m.qty ELSE -m.qty END), 0) AS stock
    FROM products p
    LEFT JOIN movements m ON m.pid = p.id
    GROUP BY p.id
    ORDER BY p.name COLLATE NOCASE
  `).all();
  return results || [];
}

/* 남아 있는 로트(유통기한별 재고) */
async function listLots(env) {
  const { results } = await env.DB.prepare(`
    SELECT pid, expiry,
           SUM(CASE WHEN type='in' THEN qty ELSE -qty END) AS qty
    FROM movements
    WHERE expiry <> ''
    GROUP BY pid, expiry
    HAVING qty > 0
    ORDER BY expiry
  `).all();
  return results || [];
}

/* 로트 보정: 유통기한 없이 기록된 출고(예: 재고 0에서 강제 출고)도
   기한이 빠른 로트부터 소진된 것으로 간주해, 로트 합계가 실제 재고를
   넘지 않도록 맞춘다. (표시·알림용 — 원본 기록은 바꾸지 않음) */
function adjustLots(products, lots) {
  const stockMap = {};
  for (const p of products) stockMap[p.id] = Math.max(0, p.stock || 0);
  const byPid = {};
  for (const l of lots) (byPid[l.pid] = byPid[l.pid] || []).push({ ...l });
  const out = [];
  for (const pid in byPid) {
    const group = byPid[pid];                       // SQL에서 expiry 오름차순
    const total = group.reduce((s, l) => s + l.qty, 0);
    let deficit = total - (stockMap[pid] ?? 0);
    for (const l of group) {
      if (deficit > 0) {
        const cut = Math.min(deficit, l.qty);
        l.qty -= cut; deficit -= cut;
      }
      if (l.qty > 0) out.push(l);
    }
  }
  out.sort((a, b) => (a.expiry < b.expiry ? -1 : a.expiry > b.expiry ? 1 : 0));
  return out;
}

async function listMovements(env, limit = 300) {
  const { results } = await env.DB.prepare(`
    SELECT m.id, m.pid, m.type, m.qty, m.memo, m.who, m.expiry, m.lot, m.ts, p.name AS pname
    FROM movements m
    LEFT JOIN products p ON p.id = m.pid
    ORDER BY m.ts DESC
    LIMIT ?
  `).bind(limit).all();
  return results || [];
}

/* 출고 시 유통기한이 빠른 로트부터 차감(FEFO).
   기록 문장 배열과 함께 "어느 묶음에서 꺼냈는지"(took)도 돌려준다 —
   화면에서 직원에게 실제로 꺼낼 묶음을 안내하기 위함. */
async function buildOutStatements(env, pid, qty, memo, who) {
  const { results } = await env.DB.prepare(`
    SELECT expiry, SUM(CASE WHEN type='in' THEN qty ELSE -qty END) AS qty
    FROM movements
    WHERE pid = ? AND expiry <> ''
    GROUP BY expiry HAVING qty > 0
    ORDER BY expiry
  `).bind(pid).all();

  const stmts = [], took = [];
  let remain = qty;
  for (const b of (results || [])) {
    if (remain <= 0) break;
    const take = Math.min(remain, b.qty);
    stmts.push(env.DB.prepare(
      `INSERT INTO movements (id,pid,type,qty,memo,who,expiry,lot,ts) VALUES (?,?,'out',?,?,?,?,'',?)`
    ).bind(uid(), pid, take, memo, who, b.expiry, Date.now()));
    took.push({ expiry: b.expiry, qty: take });
    remain -= take;
  }
  if (remain > 0) {
    stmts.push(env.DB.prepare(
      `INSERT INTO movements (id,pid,type,qty,memo,who,expiry,lot,ts) VALUES (?,?,'out',?,?,?,'','',?)`
    ).bind(uid(), pid, remain, memo, who, Date.now()));
    took.push({ expiry: "", qty: remain });
  }
  return { stmts, took };
}

/* 바코드로 품목 찾기: 전체 일치 → GS1(01+GTIN14) → 끝 13자리 */
async function findByBarcode(env, raw) {
  const code = s(raw);
  if (!code) return null;
  const tryCodes = [code];
  if (code.length > 16 && code.startsWith("01")) {
    const gtin = code.slice(2, 16);
    tryCodes.push(gtin, gtin.replace(/^0+/, ""));
  }
  if (code.length >= 13) tryCodes.push(code.slice(-13));
  for (const c of tryCodes) {
    const row = await env.DB.prepare(
      `SELECT id, name, unit, loc FROM products WHERE bar = ? LIMIT 1`
    ).bind(c).first();
    if (row) return row;
  }
  return null;
}

/* GS1-128에서 유통기한(AI 17)·로트(AI 10) 뽑기 */
function parseGs1(raw) {
  const code = s(raw);
  const out = { expiry: "", lot: "" };
  if (code.length <= 16 || !code.startsWith("01")) return out;
  const rest = code.slice(16);
  const mExp = rest.match(/17(\d{6})/);
  if (mExp) out.expiry = normDate(mExp[1]);
  const mLot = rest.match(/10([0-9A-Za-z]{1,20})$/);
  if (mLot) out.lot = mLot[1];
  return out;
}

/* ============================================================
   발주 → 텔레그램 알림
   매주 수요일 아침(크론) 또는 발주 화면의 [지금 보내기] 버튼으로,
   주문시점 이하로 떨어진 품목을 거래처별 문안으로 만들어 보냅니다.
   필요 설정(Worker Secrets): TELEGRAM_TOKEN, TELEGRAM_CHAT
   ============================================================ */
function orderMessageText(vendor, items, dateStr) {
  const lines = items.map((p) => {
    let l = `- ${p.name}`;
    if (p.unit) l += ` (${p.unit})`;
    l += ` : ${p.need}개`;
    if (p.alt) l += `  ※대체가능: ${p.alt}`;
    return l;
  });
  return `[반듯한정형외과 발주] ${dateStr}\n거래처: ${vendor || "미지정"}\n` +
         lines.join("\n") +
         "\n\n품절이거나 대체품 발송이 필요한 경우 회신 부탁드립니다.";
}

async function buildOrders(env) {
  const products = await listProducts(env);
  const items = products
    .filter((p) => (p.par || 0) > 0 || (p.min || 0) > 0)
    .filter((p) => p.stock <= (p.min || 0))
    .map((p) => ({ ...p, need: Math.max(1, (p.par || 0) - p.stock) }));
  const byVendor = {};
  for (const p of items) {
    const v = p.vendor || "미지정";
    (byVendor[v] = byVendor[v] || []).push(p);
  }
  return byVendor;
}

async function tgApi(env, method, payload) {
  const res = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_TOKEN}/${method}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
  return await res.json().catch(() => ({}));
}

async function tgSendTo(env, chatId, text) {
  const out = await tgApi(env, "sendMessage", { chat_id: chatId, text });
  return !!out.ok;
}

/* /start 보낸 사람을 구독자로 등록 (getUpdates 폴링 — 15분마다 크론 + 발주 전송 직전)
   TELEGRAM_JOIN 비밀값을 설정하면 "/start 코드" 처럼 코드를 입력한 사람만 등록됩니다. */
async function pollTelegram(env) {
  if (!env.TELEGRAM_TOKEN) return;
  const last = await env.DB.prepare(`SELECT value FROM meta WHERE key='tg_offset'`).first();
  const offset = last ? parseInt(last.value, 10) + 1 : 0;
  const out = await tgApi(env, "getUpdates", { offset, timeout: 0, allowed_updates: ["message"] });
  if (!out.ok || !Array.isArray(out.result) || !out.result.length) return;

  let maxId = offset - 1;
  for (const u of out.result) {
    maxId = Math.max(maxId, u.update_id);
    const msg = u.message;
    if (!msg || !msg.text || !msg.chat) continue;
    const chatId = String(msg.chat.id);
    const text = msg.text.trim();
    const name = [msg.chat.first_name, msg.chat.last_name, msg.chat.title]
      .filter(Boolean).join(" ") || (msg.chat.username || "");

    if (text.startsWith("/start")) {
      if (env.TELEGRAM_JOIN && !text.includes(env.TELEGRAM_JOIN)) {
        await tgSendTo(env, chatId,
          "구독하려면 코드를 함께 보내주세요.\n예) /start 코드\n(코드는 관리자에게 문의)");
        continue;
      }
      await env.DB.prepare(
        `INSERT OR REPLACE INTO tg_subs (chat_id, name, added) VALUES (?,?,?)`
      ).bind(chatId, name, Date.now()).run();
      await tgSendTo(env, chatId,
        "✅ 반듯한정형외과 발주 알림 구독 완료!\n매주 수요일 오전 9시에 발주 문안이 전송됩니다.\n구독 해지: /stop");
    } else if (text.startsWith("/stop")) {
      await env.DB.prepare(`DELETE FROM tg_subs WHERE chat_id=?`).bind(chatId).run();
      await tgSendTo(env, chatId, "구독이 해지되었습니다. 다시 받으려면 /start");
    }
  }
  await env.DB.prepare(
    `INSERT OR REPLACE INTO meta (key, value) VALUES ('tg_offset', ?)`
  ).bind(String(maxId)).run();
}

async function sendOrders(env) {
  if (!env.TELEGRAM_TOKEN) {
    return { sent: 0, error: "텔레그램이 설정되지 않았습니다 (TELEGRAM_TOKEN)." };
  }
  await pollTelegram(env);   // 방금 /start 한 사람도 포함되도록

  const subs = (await env.DB.prepare(`SELECT chat_id FROM tg_subs`).all()).results || [];
  if (!subs.length) {
    return { sent: 0, error: "구독자가 없습니다. 봇에게 /start 를 보내 구독하세요." };
  }

  const byVendor = await buildOrders(env);
  const vendors = Object.keys(byVendor);
  const d = new Date(Date.now() + 9 * 3600 * 1000); // KST
  const days = ["일", "월", "화", "수", "목", "금", "토"];
  const dateStr = `${d.getUTCMonth() + 1}/${d.getUTCDate()}(${days[d.getUTCDay()]})`;

  const texts = vendors.length
    ? vendors.map((v) => orderMessageText(v, byVendor[v], dateStr))
    : [`[반듯한정형외과 발주] ${dateStr}\n오늘 발주할 품목이 없습니다 🎉`];

  for (const sub of subs) {
    for (const t of texts) await tgSendTo(env, sub.chat_id, t);
  }
  return { sent: texts.length * subs.length, vendors: vendors.length, subscribers: subs.length };
}

/* ============================================================
   유통기한 알림 (매일 오전 9시 KST 크론)
   재고가 남아 있는 로트 중 D-30 / D-7 / 오늘 만료를 텔레그램으로 알립니다.
   정확히 그 날짜에만 알리므로 같은 로트가 매일 반복 알림되지 않습니다.
   ============================================================ */
function kstToday() {
  const d = new Date(Date.now() + 9 * 3600 * 1000);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}
function expiryDaysLeft(expiry) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(expiry || "");
  if (!m) return null;
  const t = Date.UTC(+m[1], +m[2] - 1, +m[3]);
  return Math.round((t - kstToday()) / 86400000);
}

async function sendExpiryAlerts(env) {
  if (!env.TELEGRAM_TOKEN) return { sent: 0, error: "텔레그램이 설정되지 않았습니다 (TELEGRAM_TOKEN)." };
  await pollTelegram(env);
  const subs = (await env.DB.prepare(`SELECT chat_id FROM tg_subs`).all()).results || [];
  if (!subs.length) return { sent: 0, error: "구독자가 없습니다. 봇에게 /start 를 보내 구독하세요." };

  const [lotsRaw, products] = await Promise.all([listLots(env), listProducts(env)]);
  const lots = adjustLots(products, lotsRaw);
  const pmap = {};
  for (const p of products) pmap[p.id] = p;

  const buckets = { 0: [], 7: [], 30: [] };
  for (const l of lots) {
    const p = pmap[l.pid];
    if (!p) continue;
    const dd = expiryDaysLeft(l.expiry);
    if (dd === 0 || dd === 7 || dd === 30) {
      buckets[dd].push(`- ${p.name}${p.unit ? ` (${p.unit})` : ""} : ${l.qty}개 · ${l.expiry}${p.loc ? ` · ${p.loc}` : ""}`);
    }
  }
  if (!buckets[0].length && !buckets[7].length && !buckets[30].length) {
    return { sent: 0, vendors: 0, note: "오늘 알릴 유통기한 항목이 없습니다." };
  }

  const d = new Date(Date.now() + 9 * 3600 * 1000);
  const days = ["일", "월", "화", "수", "목", "금", "토"];
  let text = `⏰ [반듯한정형외과 유통기한 알림] ${d.getUTCMonth() + 1}/${d.getUTCDate()}(${days[d.getUTCDay()]})\n`;
  if (buckets[0].length)  text += `\n🔴 오늘 만료 — 즉시 사용 또는 폐기:\n${buckets[0].join("\n")}\n`;
  if (buckets[7].length)  text += `\n🟠 7일 남음 — 우선 사용:\n${buckets[7].join("\n")}\n`;
  if (buckets[30].length) text += `\n🟡 30일 남음:\n${buckets[30].join("\n")}\n`;

  let ok = 0;
  for (const sub of subs) { if (await tgSendTo(env, sub.chat_id, text.trim())) ok++; }
  return { sent: ok, subscribers: subs.length,
           items: buckets[0].length + buckets[7].length + buckets[30].length };
}

/* ============================================================
   발주서 PDF 생성 + 회사 이메일 자동 전송 (매주 수요일 크론)
   필요 시크릿: RESEND_KEY (resend.com API 키), ORDER_EMAIL (받는 회사 메일)
   ============================================================ */
let FONT_CACHE = null;
async function loadKoreanFont(env) {
  if (FONT_CACHE) return FONT_CACHE;
  const res = await env.ASSETS.fetch("https://assets.local/fonts/NotoSansKR-Regular.otf");
  if (!res.ok) throw new Error("한글 폰트 파일을 찾을 수 없습니다.");
  FONT_CACHE = await res.arrayBuffer();
  return FONT_CACHE;
}

async function buildOrderPdf(env, vendor, items, dateStr) {
  const { PDFDocument, rgb } = PDFLib;
  const doc = await PDFDocument.create();
  doc.registerFontkit(fontkit);
  const font = await doc.embedFont(await loadKoreanFont(env), { subset: true });

  const W = 595.28, H = 841.89, L = 40, R = W - 40;
  const col = { idx: L, name: L + 28, alt: L + 300, unit: L + 425, qty: R - 34 };
  const ink = rgb(0.1, 0.14, 0.2), gray = rgb(0.44, 0.5, 0.57), lineC = rgb(0.78, 0.82, 0.86);

  const fit = (t, maxW, size) => {
    t = String(t || "");
    if (font.widthOfTextAtSize(t, size) <= maxW) return t;
    while (t && font.widthOfTextAtSize(t + "…", size) > maxW) t = t.slice(0, -1);
    return t + "…";
  };

  let page, y;
  const newPage = () => {
    page = doc.addPage([W, H]); y = H - 52;
    page.drawText("반듯한정형외과 발주서", { x: L, y, size: 16, font, color: ink }); y -= 20;
    page.drawText(`발주일: ${dateStr}    거래처: ${vendor}    총 ${items.length}품목`,
      { x: L, y, size: 10, font, color: gray }); y -= 20;
    page.drawText("#", { x: col.idx, y, size: 9, font, color: gray });
    page.drawText("품목", { x: col.name, y, size: 9, font, color: gray });
    page.drawText("대체품목", { x: col.alt, y, size: 9, font, color: gray });
    page.drawText("규격", { x: col.unit, y, size: 9, font, color: gray });
    page.drawText("갯수", { x: col.qty, y, size: 9, font, color: gray });
    y -= 6;
    page.drawLine({ start: { x: L, y }, end: { x: R, y }, thickness: 0.8, color: lineC });
    y -= 14;
  };
  newPage();

  items.forEach((p, i) => {
    if (y < 80) newPage();
    page.drawText(String(i + 1), { x: col.idx, y, size: 9.5, font, color: gray });
    page.drawText(fit(p.name, col.alt - col.name - 8, 9.5), { x: col.name, y, size: 9.5, font, color: ink });
    page.drawText(fit(p.alt, col.unit - col.alt - 8, 9), { x: col.alt, y, size: 9, font, color: gray });
    page.drawText(fit(p.unit, col.qty - col.unit - 8, 9), { x: col.unit, y, size: 9, font, color: gray });
    page.drawText(String(p.need), { x: col.qty, y, size: 10.5, font, color: ink });
    y -= 16;
  });

  y -= 10;
  if (y < 70) newPage();
  page.drawText("· 품절이거나 대체품 발송이 필요한 경우 회신 부탁드립니다.", { x: L, y, size: 8.5, font, color: gray });
  y -= 13;
  page.drawText("· 거래명세서는 제품에 동봉해 주세요.", { x: L, y, size: 8.5, font, color: gray });

  return await doc.save();
}

function bytesToB64(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  }
  return btoa(s);
}

async function sendOrderEmail(env) {
  if (!env.RESEND_KEY || !env.ORDER_EMAIL) {
    return { sent: 0, error: "이메일이 설정되지 않았습니다 (RESEND_KEY / ORDER_EMAIL 시크릿 필요)." };
  }
  const byVendor = await buildOrders(env);
  const vendors = Object.keys(byVendor).sort((a, b) => a.localeCompare(b, "ko"));

  const d = new Date(Date.now() + 9 * 3600 * 1000);
  const days = ["일", "월", "화", "수", "목", "금", "토"];
  const dateStr = `${d.getUTCFullYear()}.${d.getUTCMonth() + 1}.${d.getUTCDate()}(${days[d.getUTCDay()]})`;
  const ymd = `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, "0")}${String(d.getUTCDate()).padStart(2, "0")}`;

  const attachments = [];
  for (const v of vendors) {
    const bytes = await buildOrderPdf(env, v, byVendor[v], dateStr);
    attachments.push({ filename: `발주서_${v}_${ymd}.pdf`, content: bytesToB64(bytes) });
  }

  const listHtml = vendors.length
    ? `<ul>${vendors.map(v => `<li><b>${v}</b> — ${byVendor[v].length}품목</li>`).join("")}</ul>
       <p>첨부된 PDF를 확인 후 각 거래처(카톡)로 전달해 주세요.</p>`
    : `<p>오늘 발주할 품목이 없습니다 🎉</p>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${env.RESEND_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({
      from: "반듯한정형외과 재고 <onboarding@resend.dev>",
      to: [env.ORDER_EMAIL],
      subject: `[반듯한정형외과] 발주서 ${dateStr}` + (vendors.length ? ` — 거래처 ${vendors.length}곳` : " — 발주 없음"),
      html: `<h2>반듯한정형외과 발주서 · ${dateStr}</h2>${listHtml}
             <p style="color:#888;font-size:12px">재고 시스템에서 자동 발송된 메일입니다.</p>`,
      attachments
    })
  });
  const out = await res.json().catch(() => ({}));
  if (!res.ok) return { sent: 0, error: "이메일 전송 실패: " + (out.message || res.status) };
  return { sent: 1, vendors: vendors.length };
}

async function currentStock(env, pid) {
  const row = await env.DB.prepare(`
    SELECT COALESCE(SUM(CASE WHEN type='in' THEN qty ELSE -qty END),0) AS stock
    FROM movements WHERE pid = ?
  `).bind(pid).first();
  return row ? row.stock : 0;
}

/* ---------- 라우팅 ---------- */
async function handleApi(request, env, url, ident) {
  const path = url.pathname.replace(/^\/api/, "") || "/";
  const method = request.method;
  const body = method === "POST" ? await request.json().catch(() => ({})) : {};
  const staff = ident && ident.staff;
  const access = ident && ident.me;
  /* 화면 표시용 신원 (직원이면 아이디, 관리자면 이메일) */
  const me = staff ? { email: (staff.name ? `${staff.id} (${staff.name})` : staff.id) + (staff.admin ? " 👑" : ""),
                       staff: true, admin: !!staff.admin }
                   : access;
  /* 담당자 기록: 직원 아이디 > 구글 계정 > 직접 입력 */
  const actor = staff ? staff.id : (access ? access.email : s(body.who));

  /* 현황 + 로트 + 최근 기록 */
  if (path === "/state" && method === "GET") {
    const [products, lotsRaw, movements] = await Promise.all([
      listProducts(env), listLots(env), listMovements(env)
    ]);
    return json({ products, lots: adjustLots(products, lotsRaw), movements, me, serverTime: Date.now() });
  }

  /* 품목 추가 / 수정 */
  if (path === "/product" && method === "POST") {
    const name = s(body.name);
    if (!name) return json({ error: "품목명이 필요합니다." }, 400);

    if (body.id) {
      await env.DB.prepare(
        `UPDATE products SET name=?, cat=?, loc=?, unit=?, bar=?, min_qty=?, par_qty=?, alt=?, price=?, vendor=? WHERE id=?`
      ).bind(name, s(body.cat), s(body.loc), s(body.unit), s(body.bar),
             n(body.min), n(body.par), s(body.alt), n(body.price), s(body.vendor), s(body.id)).run();
      return json({ ok: true, id: body.id });
    }

    const id = uid();
    const stmts = [
      env.DB.prepare(
        `INSERT INTO products (id,name,cat,loc,unit,bar,min_qty,par_qty,alt,price,vendor,created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`
      ).bind(id, name, s(body.cat), s(body.loc), s(body.unit), s(body.bar),
             n(body.min), n(body.par), s(body.alt), n(body.price), s(body.vendor), Date.now())
    ];
    const init = n(body.init);
    if (init > 0) {
      stmts.push(env.DB.prepare(
        `INSERT INTO movements (id,pid,type,qty,memo,who,expiry,lot,ts) VALUES (?,?,'in',?,?,?,?,'',?)`
      ).bind(uid(), id, init, "초기 수량", actor, normDate(body.expiry), Date.now()));
    }
    await env.DB.batch(stmts);
    return json({ ok: true, id });
  }

  /* 품목 삭제 */
  if (path === "/product/delete" && method === "POST") {
    const id = s(body.id);
    if (!id) return json({ error: "id가 필요합니다." }, 400);
    await env.DB.batch([
      env.DB.prepare(`DELETE FROM movements WHERE pid=?`).bind(id),
      env.DB.prepare(`DELETE FROM products  WHERE id=?`).bind(id)
    ]);
    return json({ ok: true });
  }

  /* 입출고 (화면에서 직접 입력) */
  if (path === "/movement" && method === "POST") {
    const pid = s(body.pid);
    const type = body.type === "out" ? "out" : "in";
    const qty = n(body.qty);
    if (!pid || qty <= 0) return json({ error: "품목과 수량을 확인하세요." }, 400);

    let took = [];
    if (type === "in") {
      await env.DB.prepare(
        `INSERT INTO movements (id,pid,type,qty,memo,who,expiry,lot,ts) VALUES (?,?,'in',?,?,?,?,?,?)`
      ).bind(uid(), pid, qty, s(body.memo), actor, normDate(body.expiry), s(body.lot), Date.now()).run();
    } else {
      const r = await buildOutStatements(env, pid, qty, s(body.memo), actor);
      await env.DB.batch(r.stmts);
      took = r.took;
    }
    return json({ ok: true, took, stock: await currentStock(env, pid) });
  }

  /* 스캐너 전용: 바코드 하나로 입고/출고 */
  if (path === "/scan" && method === "POST") {
    const raw = s(body.bar);
    const mode = body.mode === "out" ? "out" : "in";
    const qty = Math.max(1, n(body.qty) || 1);
    if (!raw) return json({ error: "바코드가 비어 있습니다." }, 400);

    const p = await findByBarcode(env, raw);
    if (!p) return json({ notFound: true, bar: raw, gs1: parseGs1(raw) });

    /* 스캔 화면에서 선택한 보관위치: 품목에 위치가 비어 있으면 자동 저장 */
    const locSel = s(body.loc);
    if (locSel && !(p.loc || "").trim()) {
      await env.DB.prepare(`UPDATE products SET loc=? WHERE id=?`).bind(locSel, p.id).run();
      p.loc = locSel;
    }

    let took = [];
    if (mode === "in") {
      const g = parseGs1(raw);
      const expiry = normDate(body.expiry) || g.expiry;
      await env.DB.prepare(
        `INSERT INTO movements (id,pid,type,qty,memo,who,expiry,lot,ts) VALUES (?,?,'in',?,?,?,?,?,?)`
      ).bind(uid(), p.id, qty, "스캔 입고", actor, expiry, g.lot, Date.now()).run();
    } else {
      const r = await buildOutStatements(env, p.id, qty, "스캔 출고", actor);
      await env.DB.batch(r.stmts);
      took = r.took;
    }
    return json({ ok: true, product: p, mode, qty, took, stock: await currentStock(env, p.id) });
  }

  /* CSV 일괄 가져오기
     열: 품목명,카테고리,보관위치,단위,바코드,최소수량(주문시점),현재수량,단가,거래처,유통기한,필요수량,대체품목 */
  if (path === "/import" && method === "POST") {
    const rows = Array.isArray(body.rows) ? body.rows : [];
    const existing = new Set((await listProducts(env)).map((p) => p.name));
    let added = 0, skipped = 0;
    const stmts = [];
    for (const r of rows) {
      const name = s(r[0]);
      if (!name || existing.has(name)) { skipped++; continue; }
      existing.add(name);
      const id = uid();
      stmts.push(env.DB.prepare(
        `INSERT INTO products (id,name,cat,loc,unit,bar,min_qty,par_qty,alt,price,vendor,created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`
      ).bind(id, name, s(r[1]), s(r[2]), s(r[3]), s(r[4]), n(r[5]), n(r[10]), s(r[11]), n(r[7]), s(r[8]), Date.now()));
      const qty = n(r[6]);
      if (qty > 0) {
        stmts.push(env.DB.prepare(
          `INSERT INTO movements (id,pid,type,qty,memo,who,expiry,lot,ts) VALUES (?,?,'in',?,?,?,?,'',?)`
        ).bind(uid(), id, qty, "CSV 가져오기", actor, normDate(r[9]), Date.now()));
      }
      added++;
    }
    for (let i = 0; i < stmts.length; i += 40) await env.DB.batch(stmts.slice(i, i + 40));
    return json({ ok: true, added, skipped });
  }

  /* 백업 / 복원 */
  if (path === "/backup" && method === "GET") {
    const [p, m] = await Promise.all([
      env.DB.prepare(`SELECT * FROM products`).all(),
      env.DB.prepare(`SELECT * FROM movements ORDER BY ts`).all()
    ]);
    return json({ products: p.results || [], movements: m.results || [], at: Date.now() });
  }

  if (path === "/restore" && method === "POST") {
    const products = Array.isArray(body.products) ? body.products : null;
    const movements = Array.isArray(body.movements) ? body.movements : null;
    if (!products || !movements) return json({ error: "백업 형식이 다릅니다." }, 400);

    const stmts = [
      env.DB.prepare(`DELETE FROM movements`),
      env.DB.prepare(`DELETE FROM products`)
    ];
    for (const p of products) {
      stmts.push(env.DB.prepare(
        `INSERT INTO products (id,name,cat,loc,unit,bar,min_qty,par_qty,alt,price,vendor,created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`
      ).bind(s(p.id) || uid(), s(p.name), s(p.cat), s(p.loc), s(p.unit), s(p.bar),
             n(p.min_qty ?? p.min), n(p.par_qty ?? p.par), s(p.alt),
             n(p.price), s(p.vendor), n(p.created_at) || Date.now()));
    }
    for (const m of movements) {
      stmts.push(env.DB.prepare(
        `INSERT INTO movements (id,pid,type,qty,memo,who,expiry,lot,ts) VALUES (?,?,?,?,?,?,?,?,?)`
      ).bind(s(m.id) || uid(), s(m.pid), m.type === "out" ? "out" : "in",
             n(m.qty), s(m.memo), s(m.who), normDate(m.expiry), s(m.lot), n(m.ts) || Date.now()));
    }
    for (let i = 0; i < stmts.length; i += 40) await env.DB.batch(stmts.slice(i, i + 40));
    return json({ ok: true, products: products.length, movements: movements.length });
  }

  /* 통계: 최근 12개월 월별 입출고·지출 + 출고 TOP + 거래처별 이번달 입고금액 */
  if (path === "/stats" && method === "GET") {
    const cutoff = Date.now() - 370 * 86400000;
    const [monthly, top, vmonth] = await Promise.all([
      env.DB.prepare(`
        SELECT strftime('%Y-%m', datetime(m.ts/1000,'unixepoch')) AS ym,
               SUM(CASE WHEN m.type='in'  THEN m.qty ELSE 0 END) AS in_qty,
               SUM(CASE WHEN m.type='out' THEN m.qty ELSE 0 END) AS out_qty,
               SUM(CASE WHEN m.type='in'  THEN m.qty * COALESCE(p.price,0) ELSE 0 END) AS in_cost
        FROM movements m LEFT JOIN products p ON p.id = m.pid
        WHERE m.ts >= ?
        GROUP BY ym ORDER BY ym
      `).bind(cutoff).all(),
      env.DB.prepare(`
        SELECT p.name, p.unit, SUM(m.qty) AS q
        FROM movements m JOIN products p ON p.id = m.pid
        WHERE m.type='out' AND m.ts >= ?
        GROUP BY p.id ORDER BY q DESC LIMIT 15
      `).bind(cutoff).all(),
      env.DB.prepare(`
        SELECT m.ts, m.qty, m.memo, p.name, p.unit,
               COALESCE(p.price,0) AS price,
               COALESCE(NULLIF(p.vendor,''),'미지정') AS vendor
        FROM movements m JOIN products p ON p.id = m.pid
        WHERE m.type='in' AND m.ts >= ?
        ORDER BY m.ts DESC LIMIT 2000
      `).bind(cutoff).all()
    ]);
    return json({
      monthly: monthly.results || [],
      top: top.results || [],
      ins: vmonth.results || []
    });
  }

  /* 발주 문안을 텔레그램으로 지금 보내기 (수동 실행·테스트용) */
  if (path === "/order/send" && method === "POST") {
    const r = await sendOrders(env);
    if (r.error) return json({ error: r.error }, 400);
    return json({ ok: true, ...r });
  }

  /* 발주서 PDF를 회사 이메일로 지금 보내기 (수동 실행·테스트용) */
  if (path === "/order/email" && method === "POST") {
    const r = await sendOrderEmail(env);
    if (r.error) return json({ error: r.error }, 400);
    return json({ ok: true, ...r });
  }

  /* 유통기한 알림 지금 보내기 (테스트용) */
  if (path === "/expiry/send" && method === "POST") {
    const r = await sendExpiryAlerts(env);
    if (r.error) return json({ error: r.error }, 400);
    return json({ ok: true, ...r });
  }

  /* ---- 최고관리자 전용: 직원 아이디 관리 ---- */
  if (path.startsWith("/staff/")) {
    if (!staff || !staff.admin) return json({ error: "관리자만 사용할 수 있습니다." }, 403);

    if (path === "/staff/list" && method === "GET") {
      const { results } = await env.DB.prepare(
        `SELECT id, name, active FROM staff ORDER BY id`).all();
      return json({ staff: results || [] });
    }
    if (path === "/staff/add" && method === "POST") {
      const id = s(body.id).toLowerCase();
      if (!/^[a-z0-9]{2,16}$/.test(id))
        return json({ error: "아이디는 영문 소문자·숫자 2~16자로 만들어 주세요." }, 400);
      const dup = await env.DB.prepare(`SELECT id FROM staff WHERE id=?`).bind(id).first();
      if (dup) return json({ error: "이미 있는 아이디입니다: " + id }, 400);
      await env.DB.prepare(`INSERT INTO staff (id, name, active) VALUES (?,?,1)`)
        .bind(id, s(body.name)).run();
      return json({ ok: true, id });
    }
    if (path === "/staff/update" && method === "POST") {
      const id = s(body.id).toLowerCase();
      const active = body.active ? 1 : 0;
      if (id === ADMIN_ID && !active)
        return json({ error: "관리자 계정은 중지할 수 없습니다." }, 400);
      await env.DB.prepare(`UPDATE staff SET name=?, active=? WHERE id=?`)
        .bind(s(body.name), active, id).run();
      return json({ ok: true });
    }
  }

  return json({ error: "알 수 없는 요청: " + path }, 404);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (!url.pathname.startsWith("/api/")) {
      return env.ASSETS.fetch(request);
    }

    try {
      await ensureSchema(env);

      /* ---- 로그인: 인증 없이 접근 가능한 유일한 곳 ---- */
      if (url.pathname === "/api/auth/login" && request.method === "POST") {
        const b = await request.json().catch(() => ({}));
        if (!env.STAFF_PW || !env.STAFF_PW.trim()) {
          return json({ error: "관리자가 아직 비밀번호(STAFF_PW)를 설정하지 않았습니다." }, 500);
        }
        const id = s(b.id).toLowerCase();
        const row = await env.DB.prepare(`SELECT id FROM staff WHERE id=? AND active=1`).bind(id).first();
        /* 최고관리자(bd01)는 ADMIN_PW, 일반 직원은 공용 STAFF_PW로 확인 */
        const expected = (id === ADMIN_ID)
          ? (env.ADMIN_PW || env.STAFF_PW).trim()
          : env.STAFF_PW.trim();
        if (!row || s(b.pw) !== expected) {
          return json({ error: "아이디 또는 비밀번호가 올바르지 않습니다." }, 403);
        }
        return json({ ok: true, id, token: await makeStaffToken(env, id) });
      }

      /* ---- 신원 확인: 직원 토큰 → 구글(Access) → (없으면 로그인 요구) ---- */
      const staff = await staffFromRequest(env, request);
      const me = staff ? null : authUser(request);
      if (!staff && !me) {
        return json({ error: "로그인이 필요합니다.", needLogin: true }, 401);
      }

      const resp = await handleApi(request, env, url, { staff, me });
      /* 작업 요청(POST)마다 세션 30분 연장 — 새 토큰을 헤더로 내려준다.
         (배경 자동 새로고침 GET은 연장하지 않음 → 방치된 기기는 만료됨) */
      if (staff && request.method === "POST") {
        const r2 = new Response(resp.body, resp);
        r2.headers.set("x-staff-refresh", await makeStaffToken(env, staff.id));
        return r2;
      }
      return resp;
    } catch (err) {
      return json({ error: "서버 오류: " + (err && err.message ? err.message : String(err)) }, 500);
    }
  },

  /* 크론 3개:
     - 15분마다: /start·/stop 메시지 확인(구독 등록)
     - 매일 오전 9시(KST): 유통기한 알림 (D-30 / D-7 / 당일)
     - 매주 수요일 오전 9시(KST): 발주 문안 전송 */
  async scheduled(event, env, ctx) {
    await ensureSchema(env);
    if (event.cron === "0 0 * * 3") {
      ctx.waitUntil(sendOrders(env).catch(() => {}));
      ctx.waitUntil(sendOrderEmail(env).catch(() => {}));
    } else if (event.cron === "0 0 * * *") {
      ctx.waitUntil(sendExpiryAlerts(env).catch(() => {}));
    } else {
      ctx.waitUntil(pollTelegram(env).catch(() => {}));
    }
  }
};
