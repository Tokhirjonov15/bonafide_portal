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
  /* 박스 크기를 모르는 품목: 품목명·단위 글자에서 박스당 개수를 찾아 추천한다
     (예: "케로라주 1ml 50A" → 50, "1박스/10EA" → 10, 단위 칸 "10=1통" → 10). 2 이상 1000 이하만, 나온 순서대로 중복 없이 최대 3개.
     숫자 앞이 글자·숫자면 건너뛴다(예: 봉합사 "NB324 C25" 의 324 는 규격이지 개수가 아님) */
  function suggestBoxSizes(name, unit) {
    var out = [];
    function add(n) { n = parseInt(n, 10); if (n >= 2 && n <= 1000 && out.indexOf(n) < 0 && out.length < 3) out.push(n); }
    var u = /^\s*(\d+)\s*=\s*1/.exec(String(unit == null ? "" : unit));
    if (u) add(u[1]);
    var re = /(?:^|[^A-Za-z0-9])(\d+)\s*(?:EA|ea|PFS|PF|A|V|T|C|정|캡슐|병|관|백|입|매|개)(?![A-Za-z])/g;
    var s = String(name == null ? "" : name), m;
    while ((m = re.exec(s))) add(m[1]);
    return out;
  }
  /* 바코드 스캐너는 키보드처럼 글자를 아주 빠르게(글자 사이 수 ms) 치고 Enter 를 보낸다. 사람은 글자 사이가 100ms 안팎.
     stamps = 최근 글자 입력 시각(ms) 목록. 4글자 이상이고 평균 간격이 40ms 미만이면 스캐너 입력으로 본다 */
  function looksLikeScan(stamps) {
    if (!stamps || stamps.length < 4) return false;
    var n = stamps.length;
    return (stamps[n - 1] - stamps[0]) / (n - 1) < 40;
  }
  var api = { defaultUnit: defaultUnit, unitCount: unitCount, unitKey: unitKey, suggestBoxSizes: suggestBoxSizes, looksLikeScan: looksLikeScan, MAX_QTY: MAX_QTY };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.ScanUnit = api;
})(typeof window !== "undefined" ? window : this);
