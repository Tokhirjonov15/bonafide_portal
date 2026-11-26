/* 재고 실사 — 순수 함수 (2026-11-26)
   조정량 = 실제 수량 − 센 순간의 전산 재고. 센 뒤에 생긴 입출고는 이미 현재 재고와 실제 수량 양쪽에 반영돼 있으므로 센 시점 기준 차이만 조정하면 현재 재고가 맞게 된다. */
export const MAX_COUNT = 100000;

export function normCountQty(v) {
  const t = v == null ? "" : String(v).trim();
  if (!/^[0-9]+$/.test(t)) return null;
  const n = parseInt(t, 10);
  return n > MAX_COUNT ? null : n;
}

export function adjustment(counted, sysAtCount) {
  return Number(counted) - Number(sysAtCount);
}

/* 확정으로 실제 조정될 품목 수와 늘어나는/줄어드는 개수 (차이 0·제외한 줄은 세지 않음) */
export function summarize(lines, excluded) {
  const ex = new Set(Array.isArray(excluded) ? excluded.map(String) : []);
  let items = 0, plus = 0, minus = 0;
  for (const l of Array.isArray(lines) ? lines : []) {
    if (ex.has(String(l.pid))) continue;
    const d = adjustment(l.counted, l.sysAtCount);
    if (!d) continue;
    items++;
    if (d > 0) plus += d; else minus += -d;
  }
  return { items, plus, minus };
}

/* 검토 표: 차이 있는 줄(절댓값 큰 순) 먼저, 그다음 차이 0. products = [{id,name,unit,price}] */
export function buildReview(lines, products) {
  const byId = new Map((Array.isArray(products) ? products : []).map((p) => [String(p.id), p]));
  const rows = (Array.isArray(lines) ? lines : []).map((l) => {
    const p = byId.get(String(l.pid));
    const diff = adjustment(l.counted, l.sysAtCount);
    const price = p ? Number(p.price) || 0 : 0;
    return { pid: String(l.pid), name: p ? p.name : "(삭제된 품목)", unit: p ? p.unit || "" : "", price, counted: l.counted, sysAtCount: l.sysAtCount, diff, amount: diff * price, by: l.by || "", at: l.at || 0 };
  });
  const nz = rows.filter((r) => r.diff !== 0).sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff));
  return [...nz, ...rows.filter((r) => r.diff === 0)];
}

/* 줄어드는 조정의 유통기한 묶음 차감 계획 (FEFO) — lots 는 유통기한 오름차순 [{expiry,qty}]. 모자라는 만큼은 기한 없는 재고에서 뺀다 */
export function planOut(lots, qty) {
  const out = [];
  let remain = Number(qty) || 0;
  for (const b of Array.isArray(lots) ? lots : []) {
    if (remain <= 0) break;
    const q = Number(b && b.qty) || 0;
    if (q <= 0) continue;
    const take = Math.min(remain, q);
    out.push({ expiry: String(b.expiry || ""), qty: take });
    remain -= take;
  }
  if (remain > 0) out.push({ expiry: "", qty: remain });
  return out;
}

/* 한 품목의 그 층 재고 합 — groups = [{f: 기록의 층('' 가능), q: 합계}]. 층이 빈 기록은 품목 위치의 층(locFloor)으로 본다(attachFloors 와 같은 규칙) */
export function floorTotal(groups, floor, locFloor) {
  let s = 0;
  for (const g of Array.isArray(groups) ? groups : []) if ((g.f || locFloor) === floor) s += Number(g.q) || 0;
  return s;
}
