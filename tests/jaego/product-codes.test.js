"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { ownCode, lotBarcode } = require("../../public/jaego/product-codes.js");

test("자체 코드는 NB 로 시작하는 대문자·숫자", () => {
  assert.match(ownCode(0), /^NB[0-9A-Z]+$/);
  assert.match(ownCode(1764000000000), /^NB[0-9A-Z]+$/);
});

test("시각이 다르면 자체 코드도 다르다", () => {
  assert.notEqual(ownCode(1000), ownCode(2000));
});

test("lot 바코드는 품목 바코드-lot", () => {
  assert.equal(lotBarcode("BF123", "A-77"), "BF123-A-77");
});

test("lot 의 공백·슬래시는 지운다", () => {
  assert.equal(lotBarcode("BF123", "a b/7"), "BF123-ab7");
});

test("lot 이 비거나 쓸 수 없는 글자뿐이면 코드 없음", () => {
  assert.equal(lotBarcode("BF123", ""), "");
  assert.equal(lotBarcode("BF123", "한글"), "");
});

test("품목 바코드가 비면 코드 없음", () => {
  assert.equal(lotBarcode("", "L1"), "");
});

const { benefitQueryKind } = require("../../public/jaego/product-codes.js");
test("급여코드 모양(영문 1자 + 숫자 8자리)이면 code, 아니면 name", () => {
  assert.equal(benefitQueryKind("G03900131"), "code");
  assert.equal(benefitQueryKind(" g03900131 "), "code");
  assert.equal(benefitQueryKind("피렌정"), "name");
  assert.equal(benefitQueryKind("G0390013"), "name");
  assert.equal(benefitQueryKind(""), "");
  assert.equal(benefitQueryKind(null), "");
});

/* 2단계 A: 대체 품목 달라지는 값 (검토 반영: 코드는 복사하지 않고, 숫자는 숫자만) */
const { resolveAltValues } = require("../../public/jaego/product-codes.js");
const parent = { price: 1000, rxPrice: 1500, ounit: 20, payType: "급여", payCode: "G03900131", ownCode: "NB1" };

test("대체 품목: 비운 칸은 본 품목의 값(입고가·처방단가·박스당 개수·급여 구분)을 따른다", () => {
  const r = resolveAltValues(parent, {});
  assert.deepEqual([r.price, r.rxPrice, r.ounit, r.payType], [1000, 1500, 20, "급여"]);
});

test("대체 품목: 급여코드·자체 코드는 식별자라서 본 품목 것을 복사하지 않는다", () => {
  const r = resolveAltValues(parent, {});
  assert.equal(r.payCode, ""); assert.equal(r.ownCode, "");
  assert.equal(resolveAltValues(parent, { payCode: "X1", ownCode: "NB9" }).payCode, "X1");
});

test("대체 품목: 적은 값은 그 값을 쓴다 (0 도 명시한 값)", () => {
  const r = resolveAltValues(parent, { price: "800", rxPrice: "0", ounit: "25", payType: "비급여" });
  assert.deepEqual([r.price, r.rxPrice, r.ounit, r.payType], [800, 0, 25, "비급여"]);
});

test("대체 품목: 음수·글자·소수·지수 표기·이상한 급여 구분은 본 품목 값", () => {
  for (const bad of ["-5", "abc", "12.5", "1e3", "1,000"]) assert.equal(resolveAltValues(parent, { price: bad }).price, 1000, bad);
  assert.equal(resolveAltValues(parent, { payType: "zzz" }).payType, "급여");
});

test("대체 품목: 본 품목에 값이 없으면 0·빈칸", () => {
  assert.deepEqual(resolveAltValues({}, {}), { price: 0, rxPrice: 0, ounit: 0, payType: "", payCode: "", ownCode: "" });
  assert.deepEqual(resolveAltValues(null, null), { price: 0, rxPrice: 0, ounit: 0, payType: "", payCode: "", ownCode: "" });
});
