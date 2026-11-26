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
