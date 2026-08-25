/* ============================================================
   BONAFIDE 통합 포털 — API (재고관리)
   /api/* 요청만 여기서 처리하고, 나머지 주소는 public/ 의 파일을 그대로 보냅니다.

   설계 원칙
   1) 재고 수량은 저장하지 않는다. movements(입출고 기록)의 합으로 서버가 계산 → 감사 추적.
   2) 유통기한은 movements에 함께 기록한다 → 같은 품목도 들어온 날짜별로 관리(로트).
      출고할 때는 유통기한이 가장 빠른 것부터 자동으로 빠진다(FEFO).
   3) 표는 첫 요청 때 자동으로 만들어지고, 새 열도 자동으로 추가된다.
   ============================================================ */

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
  `CREATE INDEX IF NOT EXISTS idx_pr_bar ON products(bar)`
];

/* 이미 만들어진 표에 새 열을 붙인다(이미 있으면 오류가 나므로 조용히 넘어감) */
const MIGRATIONS = [
  `ALTER TABLE products  ADD COLUMN price  INTEGER DEFAULT 0`,
  `ALTER TABLE products  ADD COLUMN vendor TEXT DEFAULT ''`,
  `ALTER TABLE movements ADD COLUMN expiry TEXT DEFAULT ''`,
  `ALTER TABLE movements ADD COLUMN lot    TEXT DEFAULT ''`
];

async function ensureSchema(env) {
  if (schemaReady) return;
  for (const q of DDL) await env.DB.prepare(q).run();
  for (const q of MIGRATIONS) {
    try { await env.DB.prepare(q).run(); } catch (_) { /* 이미 있는 열 */ }
  }
  schemaReady = true;
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
           p.min_qty AS min, p.price, p.vendor,
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

/* 출고 시 유통기한이 빠른 로트부터 차감(FEFO). 기록 문장 배열을 만들어 준다. */
async function buildOutStatements(env, pid, qty, memo, who) {
  const { results } = await env.DB.prepare(`
    SELECT expiry, SUM(CASE WHEN type='in' THEN qty ELSE -qty END) AS qty
    FROM movements
    WHERE pid = ? AND expiry <> ''
    GROUP BY expiry HAVING qty > 0
    ORDER BY expiry
  `).bind(pid).all();

  const stmts = [];
  let remain = qty;
  for (const b of (results || [])) {
    if (remain <= 0) break;
    const take = Math.min(remain, b.qty);
    stmts.push(env.DB.prepare(
      `INSERT INTO movements (id,pid,type,qty,memo,who,expiry,lot,ts) VALUES (?,?,'out',?,?,?,?,'',?)`
    ).bind(uid(), pid, take, memo, who, b.expiry, Date.now()));
    remain -= take;
  }
  if (remain > 0) {
    stmts.push(env.DB.prepare(
      `INSERT INTO movements (id,pid,type,qty,memo,who,expiry,lot,ts) VALUES (?,?,'out',?,?,?,'','',?)`
    ).bind(uid(), pid, remain, memo, who, Date.now()));
  }
  return stmts;
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
      `SELECT id, name, unit FROM products WHERE bar = ? LIMIT 1`
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

async function currentStock(env, pid) {
  const row = await env.DB.prepare(`
    SELECT COALESCE(SUM(CASE WHEN type='in' THEN qty ELSE -qty END),0) AS stock
    FROM movements WHERE pid = ?
  `).bind(pid).first();
  return row ? row.stock : 0;
}

/* ---------- 라우팅 ---------- */
async function handleApi(request, env, url) {
  await ensureSchema(env);
  const path = url.pathname.replace(/^\/api/, "") || "/";
  const method = request.method;
  const body = method === "POST" ? await request.json().catch(() => ({})) : {};
  const me = authUser(request);
  /* 담당자: 로그인 계정(공용 계정)으로 기록. 로그인 전 단계에서는 입력값을 쓴다. */
  const actor = me ? me.email : s(body.who);

  /* 현황 + 로트 + 최근 기록 */
  if (path === "/state" && method === "GET") {
    const [products, lots, movements] = await Promise.all([
      listProducts(env), listLots(env), listMovements(env)
    ]);
    return json({ products, lots, movements, me, serverTime: Date.now() });
  }

  /* 품목 추가 / 수정 */
  if (path === "/product" && method === "POST") {
    const name = s(body.name);
    if (!name) return json({ error: "품목명이 필요합니다." }, 400);

    if (body.id) {
      await env.DB.prepare(
        `UPDATE products SET name=?, cat=?, loc=?, unit=?, bar=?, min_qty=?, price=?, vendor=? WHERE id=?`
      ).bind(name, s(body.cat), s(body.loc), s(body.unit), s(body.bar),
             n(body.min), n(body.price), s(body.vendor), s(body.id)).run();
      return json({ ok: true, id: body.id });
    }

    const id = uid();
    const stmts = [
      env.DB.prepare(
        `INSERT INTO products (id,name,cat,loc,unit,bar,min_qty,price,vendor,created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?)`
      ).bind(id, name, s(body.cat), s(body.loc), s(body.unit), s(body.bar),
             n(body.min), n(body.price), s(body.vendor), Date.now())
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

    if (type === "in") {
      await env.DB.prepare(
        `INSERT INTO movements (id,pid,type,qty,memo,who,expiry,lot,ts) VALUES (?,?,'in',?,?,?,?,?,?)`
      ).bind(uid(), pid, qty, s(body.memo), actor, normDate(body.expiry), s(body.lot), Date.now()).run();
    } else {
      const stmts = await buildOutStatements(env, pid, qty, s(body.memo), actor);
      await env.DB.batch(stmts);
    }
    return json({ ok: true, stock: await currentStock(env, pid) });
  }

  /* 스캐너 전용: 바코드 하나로 입고/출고 */
  if (path === "/scan" && method === "POST") {
    const raw = s(body.bar);
    const mode = body.mode === "out" ? "out" : "in";
    const qty = Math.max(1, n(body.qty) || 1);
    if (!raw) return json({ error: "바코드가 비어 있습니다." }, 400);

    const p = await findByBarcode(env, raw);
    if (!p) return json({ notFound: true, bar: raw, gs1: parseGs1(raw) });

    if (mode === "in") {
      const g = parseGs1(raw);
      const expiry = normDate(body.expiry) || g.expiry;
      await env.DB.prepare(
        `INSERT INTO movements (id,pid,type,qty,memo,who,expiry,lot,ts) VALUES (?,?,'in',?,?,?,?,?,?)`
      ).bind(uid(), p.id, qty, "스캔 입고", actor, expiry, g.lot, Date.now()).run();
    } else {
      const stmts = await buildOutStatements(env, p.id, qty, "스캔 출고", actor);
      await env.DB.batch(stmts);
    }
    return json({ ok: true, product: p, mode, qty, stock: await currentStock(env, p.id) });
  }

  /* CSV 일괄 가져오기
     열: 품목명,카테고리,보관위치,단위,바코드,최소수량,현재수량,단가,거래처,유통기한 */
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
        `INSERT INTO products (id,name,cat,loc,unit,bar,min_qty,price,vendor,created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?)`
      ).bind(id, name, s(r[1]), s(r[2]), s(r[3]), s(r[4]), n(r[5]), n(r[7]), s(r[8]), Date.now()));
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
        `INSERT INTO products (id,name,cat,loc,unit,bar,min_qty,price,vendor,created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?)`
      ).bind(s(p.id) || uid(), s(p.name), s(p.cat), s(p.loc), s(p.unit), s(p.bar),
             n(p.min_qty ?? p.min), n(p.price), s(p.vendor), n(p.created_at) || Date.now()));
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

  return json({ error: "알 수 없는 요청: " + path }, 404);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (!url.pathname.startsWith("/api/")) {
      return env.ASSETS.fetch(request);
    }

    /* 접근 제어: Access(구글 로그인) 우선, 없으면 APP_KEY, 둘 다 없으면 개방 */
    if (!authUser(request) && env.APP_KEY && request.headers.get("x-app-key") !== env.APP_KEY) {
      return json({ error: "unauthorized" }, 401);
    }

    try {
      return await handleApi(request, env, url);
    } catch (err) {
      return json({ error: "서버 오류: " + (err && err.message ? err.message : String(err)) }, 500);
    }
  }
};
