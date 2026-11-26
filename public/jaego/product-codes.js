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
  /* 대체 품목의 "달라지는 값" 정리: 비운 칸은 본 품목 값을 따른다(저장할 때 복사). 잘못된 숫자·급여 구분도 본 품목 값. 입력한 0 은 명시한 값 */
  function resolveAltValues(parent, input) {
    var P = parent || {}, I = input || {};
    function txt(v) { return String(v == null ? "" : v).trim(); }
    function num(v, fallback) {
      var s = txt(v);
      if (s === "") return fallback;
      var x = parseInt(s, 10);
      return isFinite(x) && x >= 0 ? x : fallback;
    }
    var pt = txt(I.payType);
    return {
      price: num(I.price, P.price || 0),
      rxPrice: num(I.rxPrice, P.rxPrice || 0),
      ounit: num(I.ounit, P.ounit || 0),
      payType: pt === "급여" || pt === "비급여" || pt === "미정" ? pt : (P.payType || ""),
      payCode: txt(I.payCode) || P.payCode || "",
      ownCode: txt(I.ownCode) || P.ownCode || ""
    };
  }
  /* /product 수정 요청 본문 — 서버 수정은 보낸 값으로 덮어쓰므로 기존 항목을 모두 담고 바꿀 값만 덮어쓴다 */
  function updatePayload(p, over) {
    var q = p || {};
    var base = {
      id: q.id, name: q.name, cat: q.cat || "", loc: q.loc || "", unit: q.unit || "", bar: q.bar || "",
      min: q.min || 0, par: q.par || 0, alt: q.alt || "", price: q.price || 0, vendor: q.vendor || "",
      ounit: q.ounit || 0, ogrp: q.ogrp || "", rx: q.rx || "", kind: q.kind || "",
      rxPrice: q.rxPrice || 0, payType: q.payType || "", payCode: q.payCode || "", ownCode: q.ownCode || ""
    };
    var o = over || {};
    Object.keys(o).forEach(function (k) { base[k] = o[k]; });
    return base;
  }
  var api = { ownCode: ownCode, lotBarcode: lotBarcode, benefitQueryKind: benefitQueryKind, resolveAltValues: resolveAltValues, updatePayload: updatePayload };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.ProductCodes = api;
})(typeof window !== "undefined" ? window : this);
