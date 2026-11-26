"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { defaultUnit, unitCount } = require("../../public/jaego/scan-unit.js");

test("박스 크기가 없으면 늘 개수", () => {
  assert.equal(defaultUnit("in", 0, "box"), "ea");
  assert.equal(defaultUnit("in", 1, null), "ea");
});

test("처음 쓰는 품목은 입고=박스, 출고=개수", () => {
  assert.equal(defaultUnit("in", 10, null), "box");
  assert.equal(defaultUnit("out", 10, null), "ea");
});

test("마지막에 쓴 단위를 따른다", () => {
  assert.equal(defaultUnit("in", 10, "ea"), "ea");
  assert.equal(defaultUnit("out", 10, "box"), "box");
});

test("이상한 저장값은 기본값으로", () => {
  assert.equal(defaultUnit("in", 10, "xyz"), "box");
  assert.equal(defaultUnit("out", 10, ""), "ea");
});

test("박스 단위는 박스 수 × 박스 크기", () => {
  assert.equal(unitCount("box", 3, 10), 30);
});

test("개수 단위는 그대로", () => {
  assert.equal(unitCount("ea", 7, 10), 7);
});

test("소수는 내림", () => {
  assert.equal(unitCount("ea", 2.9, 10), 2);
  assert.equal(unitCount("box", "3.5", 10), 30);
});

test("0·음수·빈칸·글자는 0", () => {
  assert.equal(unitCount("ea", 0, 10), 0);
  assert.equal(unitCount("ea", -2, 10), 0);
  assert.equal(unitCount("ea", "", 10), 0);
  assert.equal(unitCount("ea", "abc", 10), 0);
});

test("박스 크기가 없는데 박스를 요청하면 0", () => {
  assert.equal(unitCount("box", 3, 0), 0);
});

/* 검토 반영: 스캐너가 수량 칸에 바코드 숫자를 쳐 넣는 사고 방지 */
test("수량이 9999 를 넘으면 0 (바코드 숫자가 수량 칸에 들어간 경우)", () => {
  assert.equal(unitCount("ea", 9999, 10), 9999);
  assert.equal(unitCount("ea", 10000, 10), 0);
  assert.equal(unitCount("box", "8801234567890", 10), 0);
});

test("마지막 단위 저장 키는 입고·출고를 따로 둔다", () => {
  const { unitKey } = require("../../public/jaego/scan-unit.js");
  assert.equal(unitKey("in", "p1"), "jaego_unit_in_p1");
  assert.equal(unitKey("out", "p1"), "jaego_unit_out_p1");
  assert.equal(unitKey("anything", "p1"), "jaego_unit_out_p1");
});
