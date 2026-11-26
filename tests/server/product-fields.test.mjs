import test from "node:test";
import assert from "node:assert/strict";
import { normPayType, normExtra, normFields, FIELD_COLUMNS } from "../../src/product-fields.js";

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

/* 좁은 저장 경로 /product/fields — 보낸 항목만, 허용된 것만 (오래된 화면 데이터로 다른 항목을 덮어쓰지 않게) */
test("normFields: 보낸 항목만 돌려준다", () => {
  assert.deepEqual(normFields({ id: "x", ounit: "50" }), { ounit: 50 });
  assert.deepEqual(normFields({}), {});
  assert.deepEqual(normFields(null), {});
});

test("normFields: 허용되지 않은 항목(이름·최소·적정 수량 등)은 무시", () => {
  assert.deepEqual(normFields({ name: "X", min: 5, par: 7, ounit: 10 }), { ounit: 10 });
});

test("normFields: 숫자는 정리 — 글자는 빼고 음수는 0", () => {
  assert.deepEqual(normFields({ ounit: "abc" }), {});
  assert.equal(normFields({ price: -5 }).price, 0);
  assert.equal(normFields({ rxPrice: "1500" }).rxPrice, 1500);
  assert.equal(normFields({ ounit: "1e3" }).ounit, undefined);
});

test("normFields: 급여 구분·코드 정리", () => {
  assert.equal(normFields({ payType: "zzz" }).payType, "");
  assert.equal(normFields({ payType: "비급여" }).payType, "비급여");
  assert.equal(normFields({ payCode: " G1 " }).payCode, "G1");
  assert.equal(normFields({ ownCode: "x".repeat(200) }).ownCode.length, 60);
});

test("FIELD_COLUMNS: 허용 항목과 DB 열 이름", () => {
  assert.deepEqual(FIELD_COLUMNS, { ounit: "order_unit", price: "price", rxPrice: "rx_price", payType: "pay_type", payCode: "pay_code", ownCode: "own_code", bar: "bar" });
});

test("normFields: 바코드는 보낸 때만, 앞뒤 공백 제거·60자 제한, 빈 값은 비움", () => {
  assert.deepEqual(normFields({ bar: "  ABC-1 " }), { bar: "ABC-1" });
  assert.deepEqual(normFields({ bar: "" }), { bar: "" });
  assert.equal(normFields({ bar: "x".repeat(100) }).bar.length, 60);
  assert.deepEqual(normFields({ price: 5 }), { price: 5 });
});

