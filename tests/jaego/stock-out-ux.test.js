"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const html = fs.readFileSync(path.join(__dirname, "../../public/jaego/index.html"), "utf8");
const fn = (name, len) => { const i = html.indexOf(name); assert.ok(i >= 0, name + " 없음"); return html.slice(i, i + len); };

/* 1. 재고현황 출고: 박스 크기를 알면 박스가 기본 */
test("출고·입고 모두 박스 크기가 있으면 박스로 시작한다", () => {
  const s = fn("window.openMv=function", 1800);
  assert.ok(s.includes('setMvUnit(bs>1?"box":"ea")'));
  assert.ok(!s.includes('type==="in"?"box":"ea"'));
});
test("수량 칸에 커서(기존 동작 유지)", () => assert.ok(fn("window.openMv=function", 3200).includes('$("mvQty").focus()')));

/* 2. 본 품목/대체 품목 구분 */
test("입출고 창에 본 품목·대체 품목 표시 칸", () => {
  assert.ok(html.includes('id="mvKind"'));
  const s = fn("window.openMv=function", 3200);
  assert.ok(s.includes("mvKind"));
  assert.ok(s.includes("대체 품목"));
});
test("대체 품목 바코드 칸과 저장", () => {
  assert.ok(html.includes("pAv_${j}_bar"));
  const s = fn("async function saveFloorAndAltStock", 4500);
  assert.ok(s.includes("_bar"));
  assert.ok(s.includes("이미 다른 품목"));   // 화면에서도 중복을 먼저 확인
});
test("대체 품목 줄에 바코드를 보여 준다", () => assert.ok(fn("function altRowsHtml", 900).includes("x.bar")));
test("스캔 팝업도 대체 품목이면 표시", () => assert.ok(fn("OUT={bar, mode, product:p", 1400).includes("대체 품목")));

/* 3. 재고 초기화 */
test("선택 도구에 [재고 초기화] 버튼", () => {
  const a = html.indexOf('id="bulkTools"'), b = html.indexOf("</span>", a);
  assert.ok(html.slice(a, b + 400).includes("bulkResetStock()"));
});
test("재고 초기화는 관리자만, 확인 입력 후 서버 경로 호출", () => {
  const s = fn("window.bulkResetStock=async function", 1800);
  assert.ok(s.includes("ME.admin"));
  assert.ok(s.includes("/product/reset-stock"));
  assert.ok(s.includes("prompt("));
  assert.ok(s.includes("대체 품목"));
});
test("기존 선택 기능 유지", () => {
  for (const k of ["selectAllVisible", "selectSec", "selClear", "bulkHide", "bulkDelete", "bulkSet"]) assert.ok(html.includes(k), k);
});
