/* 품목 코드 문자열 만들기 (순수 함수 — 브라우저와 Node 테스트 양쪽에서 쓴다) */
(function (root) {
  "use strict";
  /* 비급여 자체 코드: NB + 시각(36진수 대문자) — 겹치지 않는다 */
  function ownCode(now) {
    return "NB" + Math.max(0, Math.floor(Number(now) || 0)).toString(36).toUpperCase();
  }
  /* lot 바코드: 품목 바코드-lot. Code128 에서 안전한 글자([A-Za-z0-9._-])만 남기고, 품목 바코드나 lot 이 비면 "" */
  function lotBarcode(base, lot) {
    var b = String(base == null ? "" : base).trim();
    var l = String(lot == null ? "" : lot).replace(/[^A-Za-z0-9._-]/g, "");
    return b && l ? b + "-" + l : "";
  }
  /* 급여정보 조회 검색어 종류: 영문 1자 + 숫자 8자리(예: G03900131)면 제품코드, 아니면 품목명 */
  function benefitQueryKind(q) {
    var s = String(q == null ? "" : q).trim();
    if (!s) return "";
    return /^[A-Za-z][0-9]{8}$/.test(s) ? "code" : "name";
  }
  var api = { ownCode: ownCode, lotBarcode: lotBarcode, benefitQueryKind: benefitQueryKind };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.ProductCodes = api;
})(typeof window !== "undefined" ? window : this);
