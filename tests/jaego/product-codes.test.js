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

/* 2단계 A: 대체 품목 달라지는 값 */
const { resolveAltValues, updatePayload } = require("../../public/jaego/product-codes.js");
const parent = { price: 1000, rxPrice: 1500, ounit: 20, payType: "급여", payCode: "G03900131", ownCode: "" };

test("대체 품목: 비운 칸은 본 품목 값을 따른다", () => {
  assert.deepEqual(resolveAltValues(parent, {}), { price: 1000, rxPrice: 1500, ounit: 20, payType: "급여", payCode: "G03900131", ownCode: "" });
  assert.deepEqual(resolveAltValues(parent, { price: "", ounit: " ", payCode: "" }).price, 1000);
});

test("대체 품목: 적은 값은 그 값을 쓴다 (0 도 명시한 값)", () => {
  const r = resolveAltValues(parent, { price: "800", rxPrice: "0", ounit: "25", payType: "비급여", payCode: "X1", ownCode: "NB9" });
  assert.deepEqual(r, { price: 800, rxPrice: 0, ounit: 25, payType: "비급여", payCode: "X1", ownCode: "NB9" });
});

test("대체 품목: 음수·글자·이상한 급여 구분은 본 품목 값", () => {
  const r = resolveAltValues(parent, { price: "-5", ounit: "abc", payType: "zzz" });
  assert.equal(r.price, 1000); assert.equal(r.ounit, 20); assert.equal(r.payType, "급여");
});

test("대체 품목: 본 품목에 값이 없으면 0·빈칸", () => {
  assert.deepEqual(resolveAltValues({}, {}), { price: 0, rxPrice: 0, ounit: 0, payType: "", payCode: "", ownCode: "" });
  assert.deepEqual(resolveAltValues(null, null), { price: 0, rxPrice: 0, ounit: 0, payType: "", payCode: "", ownCode: "" });
});

test("수정 본문: 화면에 없는 기존 항목(바코드·최소·적정·거래처 등)을 그대로 담고 바꿀 값만 덮어쓴다", () => {
  const sub = { id: "s1", name: "거즈 B사", cat: "소모품", loc: "3층", unit: "개", bar: "BF1", min: 5, par: 20, alt: "", price: 900, vendor: "메디풀", ounit: 10, ogrp: "g", rx: "gz1", kind: "물품", rxPrice: 1200, payType: "급여", payCode: "A", ownCode: "" };
  const p = updatePayload(sub, { price: 800, ounit: 25 });
  assert.equal(p.id, "s1"); assert.equal(p.bar, "BF1"); assert.equal(p.min, 5); assert.equal(p.par, 20);
  assert.equal(p.vendor, "메디풀"); assert.equal(p.rx, "gz1"); assert.equal(p.kind, "물품"); assert.equal(p.ogrp, "g");
  assert.equal(p.price, 800); assert.equal(p.ounit, 25); assert.equal(p.rxPrice, 1200);
});

test("수정 본문: 없는 항목은 0·빈칸으로 채운다", () => {
  const p = updatePayload({ id: "s2", name: "X" }, {});
  assert.equal(p.price, 0); assert.equal(p.bar, ""); assert.equal(p.rxPrice, 0); assert.equal(p.payType, "");
});
