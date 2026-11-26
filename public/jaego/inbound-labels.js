/* 스캔 입고 라벨 목록 계산 (순수 함수 — 브라우저와 Node 테스트 양쪽에서 쓴다)
   서버 입고 기록(MOVEMENTS)에서 "내가 스캔 화면으로 입고했고, 마지막 출력 이후이며, 취소되지 않은" 것을 품목별로 합산한다. */
(function (root) {
  "use strict";
  function pendingInboundLabels(opt) {
    var movements = opt.movements || [], meId = opt.meId, since = opt.since || 0;
    var cancelled = {};
    movements.forEach(function (m) {
      var memo = String(m.memo || "");
      if (memo.indexOf("취소:") === 0) cancelled[memo.slice(3)] = true;
    });
    var byPid = {}, order = [];
    movements.forEach(function (m) {
      var memo = String(m.memo || "");
      if (m.type !== "in" || memo.indexOf("스캔 입고") !== 0) return;
      if (m.who !== meId || !(m.ts > since) || cancelled[m.id]) return;
      var bm = /(\d+)\s*박스/.exec(memo);
      var copies = bm ? parseInt(bm[1], 10) : m.qty;
      var row = byPid[m.pid];
      if (!row) { row = byPid[m.pid] = { pid: m.pid, name: m.pname || "", qty: 0, copies: 0, lastTs: 0 }; order.push(m.pid); }
      row.qty += m.qty; row.copies += copies; if (m.ts > row.lastTs) row.lastTs = m.ts;
    });
    return order.map(function (pid) { return byPid[pid]; });
  }
  var api = { pendingInboundLabels: pendingInboundLabels };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.InboundLabels = api;
})(typeof window !== "undefined" ? window : this);
