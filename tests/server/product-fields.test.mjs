import test from "node:test";
import assert from "node:assert/strict";
import { normPayType, normExtra } from "../../src/product-fields.js";

test("급여구분은 급여·비급여·미정만 받고 나머지는 빈 문자열", () => {
  assert.equal(normPayType("급여"), "급여");
  assert.equal(normPayType("비급여"), "비급여");
  assert.equal(normPayType("미정"), "미정");
  assert.equal(normPayType("xyz"), "");
  assert.equal(normPayType(undefined), "");
});

test("안 보낸 키는 null (저장 때 기존 값 유지)", () => {
  assert.deepEqual(normExtra({}), { rxPrice: null, payType: null, payCode: null, ownCode: null });
});

test("값이 있으면 정리해서 돌려준다", () => {
  assert.deepEqual(
    normExtra({ rxPrice: "1200", payType: "급여", payCode: " A12 ", ownCode: "NB1" }),
    { rxPrice: 1200, payType: "급여", payCode: "A12", ownCode: "NB1" });
});

test("처방단가가 음수·글자면 0", () => {
  assert.equal(normExtra({ rxPrice: -5 }).rxPrice, 0);
  assert.equal(normExtra({ rxPrice: "abc" }).rxPrice, 0);
});

test("이상한 급여구분은 빈 문자열(지움)", () => {
  assert.equal(normExtra({ payType: "zzz" }).payType, "");
});
