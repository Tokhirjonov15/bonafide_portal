import test from "node:test";
import assert from "node:assert/strict";
import { resetPlan } from "../../src/stock-reset.js";

test("resetPlan: 재고가 있는 묶음만, 그 수량·층·유통기한 그대로", () => {
  const r = resetPlan([
    { pid: "a", floor: "3층", expiry: "2027-01-01", qty: 5 },
    { pid: "a", floor: "4층", expiry: "", qty: 0 },
    { pid: "b", floor: "", expiry: "", qty: 12 },
  ]);
  assert.deepEqual(r, [
    { pid: "a", floor: "3층", expiry: "2027-01-01", qty: 5 },
    { pid: "b", floor: "", expiry: "", qty: 12 },
  ]);
});
test("resetPlan: 0 이하·숫자 아님·품목 없음은 뺀다(마이너스 재고는 건드리지 않음)", () => {
  assert.deepEqual(resetPlan([{ pid: "a", qty: -2 }, { pid: "a", qty: NaN }, { pid: "a", qty: null }, { qty: 3 }]), []);
});
test("resetPlan: 빈 입력", () => {
  assert.deepEqual(resetPlan([]), []);
  assert.deepEqual(resetPlan(null), []);
});
