/* 스캔 입고·출고 단위/수량 계산 (순수 함수 — 브라우저와 Node 테스트 양쪽에서 쓴다) */
(function (root) {
  "use strict";
  /* 처음 선택되는 단위: 박스 크기가 없으면 개수, 있으면 마지막에 쓴 단위, 없으면 입고=박스·출고=개수 */
  function defaultUnit(mode, boxSize, lastUnit) {
    if (!(Number(boxSize) > 1)) return "ea";
    if (lastUnit === "box" || lastUnit === "ea") return lastUnit;
    return mode === "in" ? "box" : "ea";
  }
  /* 개수로 환산한 정수. 0·음수·빈칸·글자는 0, 소수는 내림, 박스 크기가 없는데 박스면 0 */
  function unitCount(unit, qty, boxSize) {
    var q = Math.floor(Number(qty));
    if (!(q > 0)) return 0;
    if (unit === "box") return Number(boxSize) > 1 ? q * Number(boxSize) : 0;
    return q;
  }
  var api = { defaultUnit: defaultUnit, unitCount: unitCount };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.ScanUnit = api;
})(typeof window !== "undefined" ? window : this);
