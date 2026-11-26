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
