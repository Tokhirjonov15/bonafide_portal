"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const html = fs.readFileSync(path.join(__dirname, "../../public/jaego/index.html"), "utf8");
const a = html.indexOf('id="cntOvl"');
const modal = a >= 0 ? html.slice(a, a + 6000) : "";

for (const id of ["cntBtn", "cntOvl", "cntList", "cntNew", "cntFloor", "cntKind", "cntBlind", "cntWork", "cntScan", "cntCand", "cntQty", "cntUnit", "cntRows", "cntProg", "cntTodo", "cntReview", "cntFinish"]) {
  test(`실사 요소: #${id}`, () => assert.ok(html.includes(`id="${id}"`)));
}
test("팝업 마크업이 있다", () => assert.ok(modal.length > 800));
test("서버 경로를 모두 부른다", () => {
  for (const p of ["/count/list", "/count/start", "/count/get", "/count/line", "/count/finish", "/count/cancel"]) assert.ok(html.includes(p), p);
});
test("확정 전 확인 문구와 조정 요약", () => {
  const i = html.indexOf("window.cntFinish");
  assert.ok(i > 0);
  const s = html.slice(i, i + 1500);
  assert.ok(s.includes("confirm("));
  assert.ok(s.includes("조정"));
  assert.ok(s.includes("excluded"));
});
test("검토·확정·취소는 관리자에게만", () => {
  const i = html.indexOf("window.cntReview");
  assert.ok(i > 0 && html.slice(i, i + 400).includes("ME.admin"));
  assert.ok(html.includes("cntAdminSync"));
});
test("수량은 0도 받고, 박스는 개수로 환산해 보낸다", () => {
  const i = html.indexOf("window.cntSave");
  const s = html.slice(i, i + 1600);
  assert.ok(s.includes("[0-9]+"));
  assert.ok(s.includes("boxSizeOf("));
  assert.ok(s.includes("busy"));   // 저장 중 이중 클릭 방지
});
test("실사 팝업이 열려 있으면 스캐너 입력이 가로채지 않는다", () => {
  assert.ok((html.match(/\$\("cntOvl"\)\.classList\.contains\("show"\)/g) || []).length >= 2);
});
test("기존 기능 유지", () => {
  for (const k of ["selectAllVisible", "bulkHide", "bulkDelete", "openMv", "openHidden"]) assert.ok(html.includes(k), k);
});

/* 독립 검토 반영 */
test("실사를 빠르게 바꿔도 마지막 요청만 반영한다 (요청 순번)", () => {
  const i = html.indexOf("window.cntEnter=async function");
  const s = html.slice(i, i + 700);
  assert.ok(s.includes("++CNT.seq") && s.includes("seq!==CNT.seq"));
});
test("id 는 인라인 onclick 문자열이 아니라 data-id 로 넘긴다", () => {
  assert.ok(!html.includes("cntEnter('${"));
  assert.ok(!html.includes("cntPick('${"));
  assert.ok(!html.includes("cntExclude('${"));
  assert.ok(html.includes("this.dataset.id"));
});
test("스캔 칸이 서버 스캔과 같은 바코드 규칙(GS1·끝 13자리)을 쓴다", () => {
  assert.ok(html.includes("function cntBarKeys"));
  assert.ok(html.includes('startsWith("01")') && html.includes("slice(-13)"));
});
test("대상 밖 품목은 확인을 받고 검토 표에 표시한다", () => {
  assert.ok(html.includes("대상이 아닙니다"));
  assert.ok(html.includes("(대상 외)"));
});
test("수량 칸에 스캐너 입력을 걸러낸다", () => {
  const i = html.indexOf('$("cntQty").addEventListener("keydown"');
  assert.ok(i > 0 && html.slice(i, i + 700).includes("ScanUnit.looksLikeScan"));
});
test("확정은 검토 시점(asOf)을 보내고, 저장은 응답으로 한 줄만 갱신한다", () => {
  assert.ok(html.includes("asOf:Math.max(0"));
  const i = html.indexOf("window.cntSave");
  assert.ok(html.slice(i, i + 1800).includes("r.line"));
});
