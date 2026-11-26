/* 품목 새 항목(처방단가·급여구분·급여코드·자체 코드) 값 정리 — 순수 함수 (2026-11-26)
   키를 안 보내면(undefined) null → 저장 때 COALESCE 로 기존 값을 유지한다(구버전 화면이 값을 지우지 않게). */
const str = (v) => (v == null ? "" : String(v).trim());

export function normPayType(v) {
  const t = str(v);
  return t === "급여" || t === "비급여" || t === "미정" ? t : "";
}

export function normExtra(body) {
  const b = body || {};
  const money = (v) => { const x = parseInt(v, 10); return Number.isFinite(x) && x > 0 ? x : 0; };
  return {
    rxPrice: b.rxPrice === undefined ? null : money(b.rxPrice),
    payType: b.payType === undefined ? null : normPayType(b.payType),
    payCode: b.payCode === undefined ? null : str(b.payCode),
    ownCode: b.ownCode === undefined ? null : str(b.ownCode),
  };
}
