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

/* 2단계 B: 박스 크기를 모르는 품목 — 이름·단위 글자에서 박스당 개수 추천 */
const { suggestBoxSizes } = require("../../public/jaego/scan-unit.js");

test("추천: 품목명의 /50A, 10V, 50백 같은 표기에서 박스당 개수", () => {
  assert.deepEqual(suggestBoxSizes("케로라주 1ml 50A"), [50]);
  assert.deepEqual(suggestBoxSizes("대한염산리도카인 20ml/10V"), [10]);
  assert.deepEqual(suggestBoxSizes("대한멸균생리식염수 100ml 50백"), [50]);
  assert.deepEqual(suggestBoxSizes("헤파뮨 1ml/10PFS"), [10]);
});

test("추천: 박스/EA 표기와 단위 칸의 '10=1통' 형식", () => {
  assert.deepEqual(suggestBoxSizes("박씨그리프주 1박스/10EA"), [10]);
  assert.deepEqual(suggestBoxSizes("거즈", "10=1통"), [10]);
});

test("추천: 1개짜리·표기 없음·너무 큰 값은 제외", () => {
  assert.deepEqual(suggestBoxSizes("시노비안 3ml/1관[PF]"), []);
  assert.deepEqual(suggestBoxSizes("거즈"), []);
  assert.deepEqual(suggestBoxSizes("거즈", "1=1개"), []);
  assert.deepEqual(suggestBoxSizes("이상한 5000A"), []);
  assert.deepEqual(suggestBoxSizes(null, null), []);
});

test("추천: 여러 개면 나온 순서대로, 중복 없이 최대 3개", () => {
  assert.deepEqual(suggestBoxSizes("가 50A 나 10V 다 50A"), [50, 10]);
  assert.deepEqual(suggestBoxSizes("5A 10V 20T 30EA"), [5, 10, 20]);
});

test("추천: 봉합사·보호대 규격 숫자(NB324 C25, GIPS123)는 개수로 보지 않는다", () => {
  assert.deepEqual(suggestBoxSizes("NYLON 3/0 NB324 C25"), []);
  assert.deepEqual(suggestBoxSizes("GIPS123 Long Leg 소(S) 장하지"), []);
  assert.deepEqual(suggestBoxSizes("KNEE BRACE(MCL)22 S"), []);
});

test("추천: 거즈의 8P(8겹)는 개수가 아니다", () => {
  assert.deepEqual(suggestBoxSizes("접은거즈 4*4*8P"), []);
  assert.deepEqual(suggestBoxSizes("헤파뮨 1ml/10PFS"), [10]);
});
