"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const html = fs.readFileSync(path.join(__dirname, "../../public/jaego/index.html"), "utf8");
const a = html.indexOf('<div class="ovl" id="outOvl">');
const b = html.indexOf('<div class="ovl" id="lotOvl">');
const modal = a >= 0 && b > a ? html.slice(a, b) : "";

test("스캔 팝업 구간을 찾았다", () => assert.ok(modal.length > 300));

/* 기존 요소는 그대로 */
for (const id of ["outTitle", "outProd", "outNow", "outUnitRow", "outUBox", "outUEa", "outBoxSz", "outStep2", "outQtyLabel", "outQty", "outHintTx", "outOk"]) {
  test(`스캔 팝업 기존 요소 유지: #${id}`, () => assert.ok(modal.includes(`id="${id}"`)));
}
/* 2단계 B: 박스 크기를 모르는 품목에서 처음 한 번 묻는 칸 */
for (const id of ["outBoxAsk", "outBoxN", "outBoxSug"]) {
  test(`박스 크기 묻기 요소: #${id}`, () => assert.ok(modal.includes(`id="${id}"`)));
}
test("추천 함수와 저장 본문 함수를 쓴다", () => {
  assert.ok(html.includes("ScanUnit.suggestBoxSizes("));
  assert.ok(html.includes("ProductCodes.updatePayload(prod,{ounit:"));
});
