/* 재고 초기화 계획 — 순수 함수 (2026-11-26)
   cells = [{pid, floor, expiry, qty}] (품목·층·유통기한별 현재 재고). 0 초과인 묶음만, 같은 층·같은 유통기한으로 그 수량만큼 출고하면 재고·층별·유통기한 묶음이 함께 0이 된다.
   마이너스 묶음은 건드리지 않는다. */
export function resetPlan(cells) {
  const out = [];
  for (const c of Array.isArray(cells) ? cells : []) {
    const qty = Number(c && c.qty);
    if (c && c.pid && Number.isFinite(qty) && qty > 0) out.push({ pid: String(c.pid), floor: String(c.floor || ""), expiry: String(c.expiry || ""), qty });
  }
  return out;
}
