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

/* 2B 검토 반영 */
test("추천 함수를 쓰고, 박스 크기는 좁은 저장 경로로만 저장한다 (오래된 데이터로 통째 덮어쓰기 금지)", () => {
  assert.ok(html.includes("ScanUnit.suggestBoxSizes("));
  assert.ok(html.includes('"/product/fields",{id:'));
  assert.ok(!html.includes("ProductCodes.updatePayload("));
});
test("저장을 기다리는 동안 다시 누르거나 닫아도 이중 입고되지 않는다 (진행 중 표시)", () => {
  assert.ok(html.includes("o.busy=true"));
  assert.ok(html.includes("OUT!==o"));
  assert.ok(html.includes("OUT&&OUT.busy"));   // 저장 중에는 닫지 않는다
});
test("박스 크기 저장이 발주 올림 단위에도 쓰인다고 알려 준다", () => assert.ok(modal.includes("발주 수량도")));
test("스캐너가 숫자 칸에 바코드를 쳐 넣고 Enter 한 것은 걸러 낸다", () => assert.ok(html.includes("ScanUnit.looksLikeScan(")));
