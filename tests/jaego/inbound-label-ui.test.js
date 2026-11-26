"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const html = fs.readFileSync(path.join(__dirname, "../../public/jaego/index.html"), "utf8");

/* 스캔 화면: 이번 입고 목록 + 출력 버튼 */
for (const id of ["inbLbl", "inbList", "inbBtn", "inbUndo", "inbOvl", "inbRows", "inbOk", "inbCancel"]) {
  test(`입고 라벨 목록 요소: #${id}`, () => assert.ok(html.includes(`id="${id}"`)));
}
test("확인 팝업 문구", () => assert.ok(html.includes("출력하시겠습니까?")));
test("순수 함수 스크립트를 불러온다", () => assert.ok(html.includes('src="inbound-labels.js"')));
test("목록은 순수 함수로 계산한다", () => assert.ok(html.includes("InboundLabels.pendingInboundLabels(")));
test("출력 기준 시각은 계정별로 저장한다", () => assert.ok(html.includes("jaego_lbl_mark_")));
test("확인을 눌러야만 출력 창을 연다 (목록에서 바로 열지 않음)", () => {
  const i = html.indexOf("window.inbConfirm");
  assert.ok(i > 0);
  assert.ok(html.slice(i, i + 1500).includes("printBarLabels("));
  const j = html.indexOf("function renderInbLabels");
  assert.ok(j > 0);
  const k = html.indexOf("function inbSum", j);
  assert.ok(k > j);
  assert.ok(!html.slice(j, k).includes("printBarLabels("));
});
test("목록에서 부르면 인쇄 창은 장수 칸 대신 총 장수만 보여준다 (기존 호출은 그대로)", () => {
  assert.ok(html.includes("perItem"));
  assert.ok(html.includes('id="lc"'));   // 기존 장수 칸 유지
  assert.ok(html.includes("printBarLabels([{bar, name:$(\"pName\").value.trim()||\"\"}]);"));
});
test("기존 [오늘 품목 라벨] 유지", () => assert.ok(html.includes('id="todayLabelBtn"') || html.includes("todayLabelBtn")));
