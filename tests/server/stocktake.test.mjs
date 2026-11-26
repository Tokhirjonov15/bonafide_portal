import test from "node:test";
import assert from "node:assert/strict";
import { normCountQty, adjustment, summarize, buildReview } from "../../src/stocktake.js";

test("normCountQty: 0 이상 정수만, 글자·소수·음수·너무 큰 값은 null", () => {
  assert.equal(normCountQty("12"), 12);
  assert.equal(normCountQty(7), 7);
  assert.equal(normCountQty("0"), 0);
  for (const bad of ["-1", "1.5", "1e3", "", null, undefined, "abc", "100001"]) assert.equal(normCountQty(bad), null, String(bad));
});
test("adjustment: 실제 − 센 순간 전산", () => {
  assert.equal(adjustment(5, 3), 2);
  assert.equal(adjustment(0, 4), -4);
  assert.equal(adjustment(2, 2), 0);
});
const lines = [{ pid: "a", counted: 5, sysAtCount: 3 }, { pid: "b", counted: 1, sysAtCount: 4 }, { pid: "c", counted: 2, sysAtCount: 2 }];
test("summarize: 차이 있는 줄만, 제외 목록은 뺀다", () => {
  assert.deepEqual(summarize(lines, []), { items: 2, plus: 2, minus: 3 });
  assert.deepEqual(summarize(lines, ["b"]), { items: 1, plus: 2, minus: 0 });
  assert.deepEqual(summarize([], null), { items: 0, plus: 0, minus: 0 });
});
test("buildReview: 큰 차이 먼저, 차이 0은 뒤, 금액·삭제된 품목", () => {
  const products = [{ id: "a", name: "A", unit: "개", price: 100 }, { id: "b", name: "B", unit: "개", price: 10 }, { id: "c", name: "C", unit: "개", price: 5 }];
  const r = buildReview([...lines, { pid: "z", counted: 1, sysAtCount: 0, by: "x", at: 1 }], products);
  assert.deepEqual(r.map((x) => x.pid), ["b", "a", "z", "c"]);
  assert.equal(r[1].diff, 2);
  assert.equal(r[1].amount, 200);
  assert.equal(r[0].amount, -30);
  assert.equal(r[2].name, "(삭제된 품목)");
  assert.equal(r[3].diff, 0);
});

import { planOut } from "../../src/stocktake.js";
test("planOut: 유통기한 빠른 묶음부터 차감, 모자라면 기한 없음으로", () => {
  const lots = [{ expiry: "2027-01-01", qty: 3 }, { expiry: "2027-06-01", qty: 5 }];
  assert.deepEqual(planOut(lots, 2), [{ expiry: "2027-01-01", qty: 2 }]);
  assert.deepEqual(planOut(lots, 6), [{ expiry: "2027-01-01", qty: 3 }, { expiry: "2027-06-01", qty: 3 }]);
  assert.deepEqual(planOut(lots, 10), [{ expiry: "2027-01-01", qty: 3 }, { expiry: "2027-06-01", qty: 5 }, { expiry: "", qty: 2 }]);
  assert.deepEqual(planOut([], 4), [{ expiry: "", qty: 4 }]);
  assert.deepEqual(planOut(null, 0), []);
  assert.deepEqual(planOut([{ expiry: "2027-01-01", qty: 0 }, { expiry: "2027-02-01", qty: -2 }], 1), [{ expiry: "", qty: 1 }]);
});
