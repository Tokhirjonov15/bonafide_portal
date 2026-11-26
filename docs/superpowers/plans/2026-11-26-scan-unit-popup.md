# 스캔 입고·출고 단위/수량 한 팝업 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 스캔 팝업(`#outOvl`)에서 단위(박스/개수) 선택과 수량 입력을 한 화면에서 끝낸다.

**Architecture:** 단위·수량 계산은 순수 함수 파일(`scan-unit.js`)로 분리해 Node 로 테스트하고, `index.html` 은 그 함수를 불러 팝업의 1단계(단위 선택)와 2단계(수량)를 한 화면으로 합친다. 서버·기록 방식은 그대로.

**Tech Stack:** 바닐라 JS 단일 HTML, Node `node:test`

**Spec:** `docs/superpowers/specs/2026-11-26-scan-unit-popup-design.md`

## Global Constraints

- 수정 범위는 `public/jaego/` 와 `tests/jaego/` 뿐. `src/index.js`(서버) 변경 금지.
- 서버로 보내는 값은 기존과 동일: 입고 박스 `{qty:박스수, unit:"box"}`, 입고 개수 `{qty:개수, unit:"ea"}`, 출고 `{qty:개수}`.
- 박스 크기가 없는(`bs<=1`) 품목은 단위 버튼 없이 개수만.
- 마지막 단위 기억 키: `localStorage` `jaego_unit_<product.id>`, 값 `"box"` 또는 `"ea"`. 기본값은 입고=`box`, 출고=`ea`.
- 커밋 메시지는 `feat:`/`fix:`/`chore:`/`docs:` 한 줄 요약, AI 서명 줄 없음(CLAUDE.md).

## Review Focus

- 수량이 0·음수·빈칸·소수 → 확인 불가(수량 칸에 포커스), 소수는 내림 (`unitCount` 테스트).
- 마지막 단위가 `box` 였는데 지금은 박스 크기가 없는 품목 → `ea` (`defaultUnit` 테스트).
- 저장된 단위 값이 이상한 글자(`"xyz"`, null) → 기본값으로 (`defaultUnit` 테스트).
- 박스 크기가 1 또는 0 → 박스 선택 불가, 개수만 (`defaultUnit`/`unitCount` 테스트).
- 출고에서 환산 개수가 재고보다 많음 → 기존 경고·확인창 유지 (화면 확인 항목).

---

### Task 1: 단위 순수 함수와 테스트

**Files:**
- Create: `public/jaego/scan-unit.js`
- Test: `tests/jaego/scan-unit.test.js`

**Interfaces:**
- Produces (브라우저 전역 `ScanUnit`, Node `module.exports`):
  - `defaultUnit(mode: "in"|"out", boxSize: number, lastUnit: string|null) -> "box"|"ea"`
  - `unitCount(unit: "box"|"ea", qty: any, boxSize: number) -> number` — 개수로 환산한 정수, 잘못된 값은 0

- [ ] **Step 1: Write the failing tests** in `tests/jaego/scan-unit.test.js` (`node:test`, `require("../../public/jaego/scan-unit.js")`), 테스트 이름과 단언:
  - `박스 크기가 없으면 늘 개수` : `defaultUnit("in",0,"box")==="ea"`, `defaultUnit("in",1,null)==="ea"`
  - `처음 쓰는 품목은 입고=박스, 출고=개수` : `defaultUnit("in",10,null)==="box"`, `defaultUnit("out",10,null)==="ea"`
  - `마지막에 쓴 단위를 따른다` : `defaultUnit("in",10,"ea")==="ea"`, `defaultUnit("out",10,"box")==="box"`
  - `이상한 저장값은 기본값으로` : `defaultUnit("in",10,"xyz")==="box"`, `defaultUnit("out",10,"")==="ea"`
  - `박스 단위는 박스 수 × 박스 크기` : `unitCount("box",3,10)===30`
  - `개수 단위는 그대로` : `unitCount("ea",7,10)===7`
  - `소수는 내림` : `unitCount("ea",2.9,10)===2`, `unitCount("box","3.5",10)===30`
  - `0·음수·빈칸·글자는 0` : `unitCount("ea",0,10)`, `(-2)`, `("")`, `("abc")` 모두 `0`
  - `박스 크기가 없는데 박스를 요청하면 0` : `unitCount("box",3,0)===0`
- [ ] **Step 2: Run** `node --test tests/jaego/` — Expected: FAIL (`Cannot find module '../../public/jaego/scan-unit.js'`)
- [ ] **Step 3: Implement** `defaultUnit`, `unitCount` in `public/jaego/scan-unit.js` — 브라우저/Node 양쪽에서 쓰는 즉시실행 함수 형태는 `public/jaego/inbound-labels.js` 와 같게.
- [ ] **Step 4: Run** `node --test tests/jaego/` — Expected: 모든 테스트 PASS (`inbound-labels` 포함)
- [ ] **Step 5: Commit**
```bash
git add public/jaego/scan-unit.js tests/jaego/scan-unit.test.js
git commit -m "feat: 스캔 단위·수량 환산 함수와 테스트"
```

---

### Task 2: 스캔 팝업을 한 화면으로 합치기

**Files:**
- Modify: `public/jaego/index.html` — 팝업 마크업 `#outOvl`(약 652-671줄), JS `scanOutAsk`·`outPick`·`outCount`·`outHint`·`outGo`(약 2124-2165줄), `<script src>` 추가(`inbound-labels.js` 와 같은 자리 근처, 메인 `<script>` 앞)

**Interfaces:**
- Consumes: `ScanUnit.defaultUnit(mode, boxSize, lastUnit)`, `ScanUnit.unitCount(unit, qty, boxSize)` (Task 1)
- Produces: 없음 (화면 동작만)

- [ ] **Step 1: 팝업 마크업 변경** — `#outStep1`(단위 질문)과 `#outStep2`(수량)를 한 블록으로: 단위 선택 버튼 2개(`박스 (1박스=N개)` / `개수`, 선택된 쪽에 `on` 클래스)와 수량 칸·힌트를 같이 보이게 한다. `bs<=1` 이면 단위 버튼 줄은 숨긴다. [확인] 버튼은 항상 보인다. 기존 id(`outQty`, `outHintTx`, `outOk` 등)는 가능한 한 유지.
- [ ] **Step 2: `scanOutAsk` 변경** — 팝업을 열 때 `OUT.unit = ScanUnit.defaultUnit(mode, bs, localStorage 의 jaego_unit_<id>)` 로 정하고(저장소 접근은 `try/catch`), 수량 칸을 `1` 로 두고 포커스·선택한다. 단위 질문 단계(`outStep1`)로 가는 분기는 제거.
- [ ] **Step 3: 단위 버튼 동작** — `outPick(u)` 를 "단위만 바꾸고 수량 칸에 포커스" 로 바꾼다(화면 전환 없음). 수량 라벨(`박스 수 (1박스=N개)`/`개수`)과 힌트를 갱신.
- [ ] **Step 4: 환산을 `ScanUnit.unitCount` 로** — `outCount()` 가 `ScanUnit.unitCount(OUT.unit, $("outQty").value, OUT.bs)` 를 돌려주게 하고, `outHint`·`outGo` 의 기존 메시지·재고 초과 확인창·서버 전달 값(Global Constraints)은 그대로 둔다. 수량이 0 이면 `outGo` 는 수량 칸에 포커스만.
- [ ] **Step 5: 마지막 단위 기억** — `outGo` 성공 직전, 박스 크기가 있는 품목이면 `localStorage.setItem("jaego_unit_"+OUT.product.id, OUT.unit)` (`try/catch`).
- [ ] **Step 6: Enter/Esc** — 기존 `#outOvl` 키 처리는 "수량 칸이 보이면 Enter=확인" 이므로 항상 수량이 보이는 새 구조에서도 동작해야 한다(조건 `outStep2` 의존 제거).
- [ ] **Step 7: 검증** — `node --test tests/jaego/` 전부 PASS. 문법: `node -e "const h=require('fs').readFileSync('public/jaego/index.html','utf8');const m=[...h.matchAll(/<script>([\s\S]*?)<\/script>/g)].pop()[1];new Function(m);console.log('ok')"` → `ok`.
- [ ] **Step 8: localhost 확인** — PowerShell 정적 서버(포트 8765, `public/` 루트)로 `/jaego/index.html` 을 열고 콘솔에서 `OUT` 대신 `scanOutAsk` 가 호출하는 `/scan` 을 `API.call=async()=>({ok:true,lookup:true,product:{id:"t",name:"테스트",unit:"개",loc:"10층"},stock:47,boxSize:10})` 로 대체한 뒤 `scanOutAsk("X","in")`, `scanOutAsk("X","out")` 를 호출: ① 단위 버튼과 수량 칸이 한 화면 ② 박스 선택 후 수량 3 → 힌트 `= 30개 입고 → 재고 77` ③ 개수로 바꾸면 힌트·라벨 갱신 ④ `boxSize:0` 로 바꾸면 단위 버튼 없음 ⑤ Esc 로 닫힘.
- [ ] **Step 9: Commit**
```bash
git add public/jaego/index.html
git commit -m "feat: 스캔 입고·출고 팝업에서 단위 선택과 수량을 한 화면으로"
```
