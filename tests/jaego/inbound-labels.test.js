"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { pendingInboundLabels } = require("../../public/jaego/inbound-labels.js");

const ME = "nurse1";
let n = 0;
const mv = (o) => ({ id: "m" + ++n, pid: "p1", pname: "거즈", type: "in", qty: 10, memo: "스캔 입고", who: ME, ts: 2000, ...o });
const run = (movements, extra) => pendingInboundLabels({ movements, meId: ME, since: 1000, ...extra });

test("본인이 스캔 입고한 기록은 목록에 들어간다", () => {
  const r = run([mv({ qty: 4 })]);
  assert.equal(r.length, 1);
  assert.equal(r[0].pid, "p1");
  assert.equal(r[0].name, "거즈");
  assert.equal(r[0].qty, 4);
});

test("스캔 입고가 아닌 입고(+버튼 등)는 제외한다", () => {
  assert.deepEqual(run([mv({ memo: "" }), mv({ memo: "재고 조정" })]), []);
});

test("출고 기록은 제외한다", () => {
  assert.deepEqual(run([mv({ type: "out", memo: "스캔 출고" })]), []);
});

test("다른 사람이 입고한 기록은 제외한다", () => {
  assert.deepEqual(run([mv({ who: "other" })]), []);
});

test("출력 기준 시각 이전(같은 시각 포함) 기록은 제외한다", () => {
  assert.deepEqual(run([mv({ ts: 1000 }), mv({ ts: 999 })]), []);
});

test("같은 품목의 여러 입고는 한 줄로 합산한다", () => {
  const r = run([mv({ qty: 3, ts: 2000 }), mv({ qty: 2, ts: 3000 })]);
  assert.equal(r.length, 1);
  assert.equal(r[0].qty, 5);
  assert.equal(r[0].copies, 5);
});

test("취소된 입고는 제외하고, 취소 기록 자체도 목록에 넣지 않는다", () => {
  const orig = mv({ id: "orig" });
  const cancel = mv({ type: "out", memo: "취소:orig" });
  assert.deepEqual(run([orig, cancel]), []);
});

test("박스 입고는 메모의 박스 수가 라벨 장수 기본값이다", () => {
  const r = run([mv({ qty: 30, memo: "스캔 입고 3박스(1박스=10개)" })]);
  assert.equal(r[0].qty, 30);
  assert.equal(r[0].copies, 3);
});

test("서로 다른 품목은 따로 나온다", () => {
  const r = run([mv({ pid: "p1" }), mv({ pid: "p2", pname: "주사기" })]);
  assert.deepEqual(r.map((x) => x.pid).sort(), ["p1", "p2"]);
});

test("포함된 기록 중 가장 늦은 시각을 돌려준다(출력 기준 갱신용)", () => {
  const r = run([mv({ ts: 2000 }), mv({ pid: "p2", ts: 5000 })]);
  assert.equal(Math.max(...r.map((x) => x.lastTs)), 5000);
});
