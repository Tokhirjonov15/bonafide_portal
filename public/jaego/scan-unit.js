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
  var MAX_QTY = 9999;   // 입력 수량 상한 — 스캐너가 수량 칸에 바코드 숫자를 쳐 넣은 경우 막는다
  function unitCount(unit, qty, boxSize) {
    var q = Math.floor(Number(qty));
    if (!(q > 0) || q > MAX_QTY) return 0;
    if (unit === "box") return Number(boxSize) > 1 ? q * Number(boxSize) : 0;
    return q;
  }
  /* 마지막에 쓴 단위 저장 키 — 입고·출고를 따로 둔다(입고를 박스로 했다고 출고도 박스로 시작하면 위험) */
  function unitKey(mode, pid) { return "jaego_unit_" + (mode === "in" ? "in" : "out") + "_" + pid; }
  var api = { defaultUnit: defaultUnit, unitCount: unitCount, unitKey: unitKey, MAX_QTY: MAX_QTY };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.ScanUnit = api;
})(typeof window !== "undefined" ? window : this);
