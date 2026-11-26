/* 품목 새 항목(처방단가·급여구분·급여코드·자체 코드) 값 정리 — 순수 함수 (2026-11-26)
   키를 안 보내면(undefined) null → 저장 때 COALESCE 로 기존 값을 유지한다(구버전 화면이 값을 지우지 않게). */
const str = (v) => (v == null ? "" : String(v).trim());

export function normPayType(v) {
  const t = str(v);
  return t === "급여" || t === "비급여" || t === "미정" ? t : "";
}

/* 좁은 저장 경로(POST /product/fields)가 바꿀 수 있는 항목 → DB 열. 이 밖의 항목은 이 경로로 바꿀 수 없다 */
export const FIELD_COLUMNS = { ounit: "order_unit", price: "price", rxPrice: "rx_price", payType: "pay_type", payCode: "pay_code", ownCode: "own_code" };

/* 보낸 항목만 정리해 돌려준다(안 보낸 항목은 키 자체가 없음). 숫자는 정수만(글자·"1e3" 같은 것은 빼고) 음수는 0, 너무 큰 값은 뺀다 */
export function normFields(body) {
  const b = body || {};
  const out = {};
  const num = (v, max) => {
    const t = str(v);
    if (!/^-?[0-9]+$/.test(t)) return undefined;
    const x = parseInt(t, 10);
    return x > max ? undefined : Math.max(0, x);
  };
  const put = (k, v) => { if (v !== undefined) out[k] = v; };
  if (b.ounit !== undefined) put("ounit", num(b.ounit, 100000));
  if (b.price !== undefined) put("price", num(b.price, 100000000));
  if (b.rxPrice !== undefined) put("rxPrice", num(b.rxPrice, 100000000));
  if (b.payType !== undefined) put("payType", normPayType(b.payType));
  if (b.payCode !== undefined) put("payCode", str(b.payCode).slice(0, 60));
  if (b.ownCode !== undefined) put("ownCode", str(b.ownCode).slice(0, 60));
  return out;
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
