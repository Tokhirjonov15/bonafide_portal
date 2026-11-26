"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const html = fs.readFileSync(path.join(__dirname, "../../public/jaego/index.html"), "utf8");
const a = html.indexOf('<div class="ovl" id="prodOvl">');
const b = html.indexOf('<div class="ovl" id="mvOvl">');
const modal = a >= 0 && b > a ? html.slice(a, b) : "";
const has = (id) => modal.includes(`id="${id}"`);

/* 원칙: 기존 수정창 항목은 하나도 지우지 않는다 */
const EXISTING = ["prodTitle", "pName", "pCat", "catList", "pRx", "locList", "pKind", "pUnit", "pMin", "pPar", "pPrice",
  "pVendor", "venList", "pAlt", "pFloorWrap", "pFloors", "pAltStock", "pOunit", "pOgrp", "pBar", "barGenBtn", "barPrintBtn",
  "pInitWrap", "pInit", "pExp", "prodDel", "prodHide", "prodCancel", "prodSave"];
const NEW = ["pRxPrice", "pPayType", "pPayCode", "pOwnCode", "ownGenBtn", "benefitBtn", "lotBarBtn"];

test("수정창 구간을 찾았다", () => assert.ok(modal.length > 500));

for (const id of EXISTING) test(`기존 항목 유지: #${id}`, () => assert.ok(has(id), `#${id} 가 수정창에서 사라졌습니다`));
for (const id of NEW) test(`새 항목 추가: #${id}`, () => assert.ok(has(id), `#${id} 가 없습니다`));

test("접이식 섹션 5개", () => assert.equal((modal.match(/<details class="sec/g) || []).length, 5));

/* 검토 반영: 열 때마다 섹션 상태를 다시 정한다 (접어 둔 채 남지 않게), 기존 기능이 있는 섹션은 늘 펼친다 */
const a2 = html.indexOf("window.openProd=function(id){");
const b2 = html.indexOf('$("addBtn").onclick', a2);
const openProd = a2 >= 0 && b2 > a2 ? html.slice(a2, b2) : "";
test("openProd 함수를 찾았다", () => assert.ok(openProd.length > 300));
for (const id of ["secBasic", "pFloorWrap", "secPrice", "secBar"]) {
  test(`열 때마다 #${id} 를 펼친다`, () => assert.ok(openProd.includes(`setSecOpen("${id}", true)`)));
}
test("새 코드 섹션만 값이 있을 때 펼친다", () => assert.ok(openProd.includes("setSecOpen(\"secCode\", !!")));

/* 급여정보 조회 결과 팝업 */
for (const id of ["benefitOvl", "benefitQuery", "benefitList", "benefitClose"]) {
  test(`조회 결과 팝업 요소: #${id}`, () => assert.ok(html.includes(`id="${id}"`)));
}
test("조회 팝업은 수정창보다 뒤에 있어 위에 겹친다", () => assert.ok(html.indexOf('id="benefitOvl"') > html.indexOf('id="prodOvl"')));

/* 검토 반영: 조회 팝업에서 검색어를 고칠 수 있고, 조회 중 다른 품목을 열면 결과를 버린다 */
for (const id of ["benefitQ", "benefitGo"]) test(`조회 팝업 검색 요소: #${id}`, () => assert.ok(html.includes(`id="${id}"`)));
test("조회 결과를 늦게 받아도 품목이 바뀌었으면 버린다", () => assert.ok(html.includes("BENEFIT_SEQ")));
test("조회 결과 행에 적용 시작일을 보여 준다", () => assert.ok(html.includes("it.startDate")));

test("조회 중 안내: 응답에 10~20초 걸릴 수 있음을 알린다", () => assert.ok(html.includes("10~20초")));
