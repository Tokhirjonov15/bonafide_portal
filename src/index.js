/* ============================================================
   BONAFIDE 통합 포털 — API (재고관리)
   /api/* 요청만 여기서 처리하고, 나머지 주소는 public/ 의 파일을 그대로 보냅니다.

   설계 원칙
   1) 재고 수량은 저장하지 않는다. movements(입출고 기록)의 합으로 서버가 계산 → 감사 추적.
   2) 표(테이블)는 첫 요청 때 자동으로 만들어진다 → 수동 SQL 실행 불필요.
   3) APP_KEY 환경변수를 설정하면 그 암호를 아는 직원만 쓸 수 있다(미설정 시 개방).
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
     created_at INTEGER
   )`,
  `CREATE TABLE IF NOT EXISTS movements (
     id   TEXT PRIMARY KEY,
     pid  TEXT NOT NULL,
     type TEXT NOT NULL,
     qty  INTEGER NOT NULL,
     memo TEXT DEFAULT '',
     who  TEXT DEFAULT '',
     ts   INTEGER NOT NULL
   )`,
  `CREATE INDEX IF NOT EXISTS idx_mv_pid ON movements(pid)`,
  `CREATE INDEX IF NOT EXISTS idx_mv_ts  ON movements(ts)`,
  `CREATE INDEX IF NOT EXISTS idx_pr_bar ON products(bar)`
];

async function ensureSchema(env) {
  if (schemaReady) return;
  for (const q of DDL) await env.DB.prepare(q).run();
  schemaReady = true;
}

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
  });

const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
const s = (v) => (v == null ? "" : String(v).trim());
const n = (v) => { const x = parseInt(v, 10); return Number.isFinite(x) ? x : 0; };

/* ---------- 재고 현황: 품목 + 계산된 재고 ---------- */
async function listProducts(env) {
  const { results } = await env.DB.prepare(`
    SELECT p.id, p.name, p.cat, p.loc, p.unit, p.bar,
           p.min_qty AS min,
           COALESCE(SUM(CASE WHEN m.type='in' THEN m.qty ELSE -m.qty END), 0) AS stock
    FROM products p
    LEFT JOIN movements m ON m.pid = p.id
    GROUP BY p.id
    ORDER BY p.name COLLATE NOCASE
  `).all();
  return results || [];
}

async function listMovements(env, limit = 300) {
  const { results } = await env.DB.prepare(`
    SELECT m.id, m.pid, m.type, m.qty, m.memo, m.who, m.ts, p.name AS pname
    FROM movements m
    LEFT JOIN products p ON p.id = m.pid
    ORDER BY m.ts DESC
    LIMIT ?
  `).bind(limit).all();
  return results || [];
}

/* ---------- 라우팅 ---------- */
async function handleApi(request, env, url) {
  await ensureSchema(env);
  const path = url.pathname.replace(/^\/api/, "") || "/";
  const method = request.method;
  const body = method === "POST" ? await request.json().catch(() => ({})) : {};

  /* 현황 + 최근 기록 */
  if (path === "/state" && method === "GET") {
    const [products, movements] = await Promise.all([listProducts(env), listMovements(env)]);
    return json({ products, movements, serverTime: Date.now() });
  }

  /* 품목 추가 / 수정 */
  if (path === "/product" && method === "POST") {
    const name = s(body.name);
    if (!name) return json({ error: "품목명이 필요합니다." }, 400);

    if (body.id) {
      await env.DB.prepare(
        `UPDATE products SET name=?, cat=?, loc=?, unit=?, bar=?, min_qty=? WHERE id=?`
      ).bind(name, s(body.cat), s(body.loc), s(body.unit), s(body.bar), n(body.min), s(body.id)).run();
      return json({ ok: true, id: body.id });
    }

    const id = uid();
    const stmts = [
      env.DB.prepare(
        `INSERT INTO products (id,name,cat,loc,unit,bar,min_qty,created_at) VALUES (?,?,?,?,?,?,?,?)`
      ).bind(id, name, s(body.cat), s(body.loc), s(body.unit), s(body.bar), n(body.min), Date.now())
    ];
    const init = n(body.init);
    if (init > 0) {
      stmts.push(env.DB.prepare(
        `INSERT INTO movements (id,pid,type,qty,memo,who,ts) VALUES (?,?,'in',?,?,?,?)`
      ).bind(uid(), id, init, "초기 수량", s(body.who), Date.now()));
    }
    await env.DB.batch(stmts);
    return json({ ok: true, id });
  }

  /* 품목 삭제 (기록도 함께) */
  if (path === "/product/delete" && method === "POST") {
    const id = s(body.id);
    if (!id) return json({ error: "id가 필요합니다." }, 400);
    await env.DB.batch([
      env.DB.prepare(`DELETE FROM movements WHERE pid=?`).bind(id),
      env.DB.prepare(`DELETE FROM products  WHERE id=?`).bind(id)
    ]);
    return json({ ok: true });
  }

  /* 입출고 */
  if (path === "/movement" && method === "POST") {
    const pid = s(body.pid);
    const type = body.type === "out" ? "out" : "in";
    const qty = n(body.qty);
    if (!pid || qty <= 0) return json({ error: "품목과 수량을 확인하세요." }, 400);
    await env.DB.prepare(
      `INSERT INTO movements (id,pid,type,qty,memo,who,ts) VALUES (?,?,?,?,?,?,?)`
    ).bind(uid(), pid, type, qty, s(body.memo), s(body.who), Date.now()).run();
    return json({ ok: true });
  }

  /* CSV 일괄 가져오기 — rows: [[품목명,카테고리,위치,단위,바코드,최소수량,현재수량], ...] */
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
        `INSERT INTO products (id,name,cat,loc,unit,bar,min_qty,created_at) VALUES (?,?,?,?,?,?,?,?)`
      ).bind(id, name, s(r[1]), s(r[2]), s(r[3]), s(r[4]), n(r[5]), Date.now()));
      const qty = n(r[6]);
      if (qty > 0) {
        stmts.push(env.DB.prepare(
          `INSERT INTO movements (id,pid,type,qty,memo,who,ts) VALUES (?,?,'in',?,?,?,?)`
        ).bind(uid(), id, qty, "CSV 가져오기", "", Date.now()));
      }
      added++;
    }
    for (let i = 0; i < stmts.length; i += 40) await env.DB.batch(stmts.slice(i, i + 40));
    return json({ ok: true, added, skipped });
  }

  /* 전체 백업 */
  if (path === "/backup" && method === "GET") {
    const [p, m] = await Promise.all([
      env.DB.prepare(`SELECT * FROM products`).all(),
      env.DB.prepare(`SELECT * FROM movements ORDER BY ts`).all()
    ]);
    return json({ products: p.results || [], movements: m.results || [], at: Date.now() });
  }

  /* 백업 복원 — 전체 교체 */
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
        `INSERT INTO products (id,name,cat,loc,unit,bar,min_qty,created_at) VALUES (?,?,?,?,?,?,?,?)`
      ).bind(s(p.id) || uid(), s(p.name), s(p.cat), s(p.loc), s(p.unit), s(p.bar),
             n(p.min_qty ?? p.min), n(p.created_at) || Date.now()));
    }
    for (const m of movements) {
      stmts.push(env.DB.prepare(
        `INSERT INTO movements (id,pid,type,qty,memo,who,ts) VALUES (?,?,?,?,?,?,?)`
      ).bind(s(m.id) || uid(), s(m.pid), m.type === "out" ? "out" : "in",
             n(m.qty), s(m.memo), s(m.who), n(m.ts) || Date.now()));
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

    /* 암호 보호: APP_KEY를 설정한 경우에만 검사 */
    if (env.APP_KEY && request.headers.get("x-app-key") !== env.APP_KEY) {
      return json({ error: "unauthorized" }, 401);
    }

    try {
      return await handleApi(request, env, url);
    } catch (err) {
      return json({ error: "서버 오류: " + (err && err.message ? err.message : String(err)) }, 500);
    }
  }
};
