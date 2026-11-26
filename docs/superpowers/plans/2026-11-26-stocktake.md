# 재고 실사 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 층별 재고 실사 — 직원이 실제 수량을 세어 넣고, 관리자가 차이를 검토·확정하면 조정 입출고 기록이 남는다.

**Architecture:** 실사 세션을 D1 표 2개(`counts`, `count_lines`)에 저장. 계산·검증은 순수 모듈 `src/stocktake.js`, 서버 경로 `/count/*`는 `src/index.js`, 화면은 `public/jaego/index.html`에 팝업 하나(`#cntOvl`)로 추가. 재고는 기존처럼 입출고 기록으로만 바뀐다.

**Tech Stack:** Cloudflare Worker + D1, 바닐라 JS 단일 파일 화면, `node --test`

**Spec:** `docs/superpowers/specs/2026-11-26-stocktake-design.md`

## Global Constraints
- 재고 수량 열을 만들지 않는다. 조정은 `movements` 기록(메모 `실사 조정 (이름 · 전→후)`)으로만, 층은 그 실사의 층.
- 조정량 = `counted − sys_at_count` (`sys_at_count`는 서버가 입력 순간 계산, 화면 값 불신).
- 확정·취소는 관리자만(`staff.admin`), 시작·입력은 로그인한 누구나. 확정은 `open → done` 상태를 **먼저** 원자적으로 바꾸고(바뀐 행 0이면 거절) 그 뒤 기록을 넣는다. 실패하면 상태를 `open`으로 되돌린다.
- 줄어드는 조정은 `buildOutStatements`(FEFO)로, 늘어나는 조정은 유통기한 없는 입고로.
- 안 센 품목은 조정하지 않는다. 기본 블라인드(전산 수량 숨김, 시작 때 끌 수 있음), 관리자 검토 화면에서만 전산 수량 노출.
- 기존 기능은 지우지 않는다. 수량은 0 이상 정수, 상한 100000. 화면은 박스를 개수로 환산해 보낸다.
- 커밋 메시지는 `feat:`/`fix:`/`chore:`/`docs:` 한 줄, AI 서명 줄 금지(CLAUDE.md).

## Review Focus
- 같은 품목을 두 번 입력 → 마지막 값으로 덮어쓰고 조정은 한 번만
- 센 뒤 입고·출고가 생김 → 조정은 센 시점 기준(현재 재고가 맞게 됨)
- 확정 두 번(더블클릭·두 관리자) → 두 번째 거절, 조정 중복 없음
- 0 입력 → "없음 확인"으로 받아들여 차이 계산에 포함
- 닫힌(done/cancelled)·없는 실사나 다른 층 품목 입력 → 거절
- 직원 계정으로 확정·취소 → 403

---

### Task 1: 순수 모듈 `src/stocktake.js`

**Files:** Create `src/stocktake.js`, `tests/server/stocktake.test.mjs`

**Interfaces — Produces:**
- `normCountQty(v): number | null` — 문자열 포함, `^[0-9]+$`만 정수로, 100000 초과·빈 값·음수·소수·글자는 `null`
- `adjustment(counted: number, sysAtCount: number): number` — `counted - sysAtCount`
- `summarize(lines: {pid,counted,sysAtCount}[], excluded: string[]): {items:number, plus:number, minus:number}` — 제외 목록 뺀 뒤 차이 0은 세지 않음. `plus` = 늘어나는 개수 합, `minus` = 줄어드는 개수 합(양수)
- `buildReview(lines, products): {pid,name,unit,price,counted,sysAtCount,diff,amount,by,at}[]` — `products`는 `{id,name,unit,price}[]`, 차이 있는 줄(절댓값 큰 순)이 먼저, 그다음 차이 0, `amount = diff*price`. 상품 없으면 이름 `(삭제된 품목)`

- [ ] **Step 1: 실패하는 테스트** — `normCountQty("12")===12`, `("0")===0`, `("-1")/("1.5")/("1e3")/("")/(null)/("100001")===null`; `adjustment(5,3)===2`, `(0,4)===-4`; `summarize` 에 `[{pid:"a",counted:5,sysAtCount:3},{pid:"b",counted:1,sysAtCount:4},{pid:"c",counted:2,sysAtCount:2}]`, `excluded:[]` → `{items:2,plus:2,minus:3}`, `excluded:["b"]` → `{items:1,plus:2,minus:0}`; `buildReview` 정렬(큰 차이 먼저, 0 차이 뒤)·`amount`·삭제된 품목
- [ ] **Step 2:** `node --test tests/server/stocktake.test.mjs` → 모듈 없음으로 FAIL
- [ ] **Step 3:** 위 시그니처대로 구현(순수, 의존성 없음)
- [ ] **Step 4:** 같은 명령 → PASS, 전체 `node --test tests/` 통과
- [ ] **Step 5:** `git add src/stocktake.js tests/server/stocktake.test.mjs && git commit -m "feat: 재고 실사 계산 함수"`

### Task 2: 서버 표와 `/count/*` 경로

**Files:** Modify `src/index.js` (마이그레이션 목록, `/product/floor-stock` 앞에 경로 추가, `import { ... } from "./stocktake.js"`)

**Interfaces — Consumes:** Task 1 함수, 기존 `floorOfLoc`, `FLOORS`, `buildOutStatements(env,pid,qty,memo,who,floor)`, `uid()`, `actor`, `staff`.
**Produces (JSON):**
- `POST /count/start {floor,kind,name,blind}` → `{ok,id,existing}` — `floor`는 `FLOORS` 중 하나(아니면 400), `kind`는 `''|'약품'|'물품'`, 같은 층·구분의 `open` 실사가 있으면 그것을 돌려줌
- `GET /count/list` → `{counts:[{id,name,floor,kind,status,blind,createdBy,createdAt,finishedAt,counted}]}` 최신순 50건
- `GET /count/get?id=&review=1` → `{count, targets:[{pid,name,bar,unit,boxSize,sys?}], lines:[{pid,counted,sysAtCount?,by,at}]}` — `sys`·`sysAtCount`는 `blind`가 0이거나 (`review=1`이고 관리자)일 때만. targets = 비숨김 품목 중 그 층 재고>0 이거나 `floorOfLoc(loc)`가 그 층, `kind` 지정 시 같은 구분만
- `POST /count/line {id,pid,qty}` → `{ok}` — `normCountQty` null이면 400, 실사 없음/`open` 아님 404·409, 품목 없음 404, `(id,pid)` upsert, `sys_at_count`는 서버가 그 층의 그 품목 재고로 계산(기록의 층, 비어 있으면 품목 위치의 층)
- `POST /count/finish {id,excluded}` (관리자) → `{ok,adjusted,plus,minus}`; `POST /count/cancel {id}` (관리자) → `{ok}` (`open`만)

- [ ] **Step 1:** `CREATE TABLE IF NOT EXISTS counts (id TEXT PRIMARY KEY, name, floor, kind, status, blind INTEGER, created_by, created_at INTEGER, finished_by, finished_at INTEGER, note)` 와 `count_lines (count_id, pid, counted INTEGER, sys_at_count INTEGER, counted_by, counted_at INTEGER, PRIMARY KEY (count_id, pid))` 를 기존 마이그레이션 목록에 추가
- [ ] **Step 2:** 헬퍼 `floorStockOf(env, pid, floor)`(기록 합, 층 비어 있으면 위치 층으로 보정) 구현 후 `start/list/get/line` 구현
- [ ] **Step 3:** `finish`: 관리자 확인 → 상태 `open→done` UPDATE 후 `meta.changes` 0이면 409 → 줄별 `adjustment`≠0 (제외 목록 뺌)마다 입고 INSERT 또는 `buildOutStatements`, 메모 `실사 조정 (${count.name} · ${sys}→${counted})` → `DB.batch`; 예외 시 상태를 `open`으로 되돌리고 500. `cancel` 구현
- [ ] **Step 4:** 로컬 서버(wrangler dev, 8787)에서 E2E 스크립트(scratchpad) — 시작→같은 층 재시작 existing→두 번 입력(덮어쓰기)→센 뒤 입고 후 확정 시 조정이 센 시점 기준→finish 두 번째 409→직원 토큰 403→닫힌 실사 입력 409→취소 후 재고 불변→blind에서 `sys` 숨김. 결과 전부 기대와 같을 때까지 수정
- [ ] **Step 5:** `node --test tests/` 통과 후 `git commit -m "feat: 재고 실사 서버 — 표와 /count 경로"`

### Task 3: 화면 `#cntOvl`

**Files:** Modify `public/jaego/index.html` (도구 줄 버튼, 팝업 마크업, 스크립트), Create `tests/jaego/stocktake-ui.test.js`

**Interfaces — Consumes:** Task 2 경로, 기존 `API.call`, `PRODUCTS`, `ME`, `boxSizeOf(p)`, `esc`, `refresh(true)`, `ScanUnit.unitCount`.
**Produces:** `window.cntOpen()`(목록), `cntStart()`, `cntEnter(id)`, `cntPick(pid)`, `cntSave()`, `cntReview()`, `cntFinish()`, `cntCancel()`, `cntClose()`; 요소 id `cntBtn, cntOvl, cntList, cntNew, cntFloor, cntKind, cntBlind, cntWork, cntScan, cntCand, cntQty, cntUnit, cntRows, cntProg, cntTodo, cntReview, cntFinish`.

- [ ] **Step 1: 정적 테스트(RED)** — 위 id 전부 존재, `/count/start`·`/count/line`·`/count/finish` 문자열, 확정 확인 문구(`조정`·`확정`), 관리자 아닐 때 검토·확정 버튼 숨김 로직(`ME.admin`), 기존 `selectAllVisible`·`bulkResetStock`(없으면 `bulkHide`) 유지
- [ ] **Step 2:** 마크업·스타일: 도구 줄 `[재고 실사]` 버튼, 팝업 3화면(목록/세기/검토) 전환
- [ ] **Step 3:** 세기 화면 — 입력칸에서 Enter로 바코드(`PRODUCTS`의 `bar`, 대체 품목 포함) 또는 이름 검색, 후보 최대 8개, 선택하면 단위(박스 크기 있으면 박스 기본)+수량 입력, `cntSave`는 개수로 환산해 `/count/line`(저장 중 버튼 잠금), 진행 `센 n / 대상 N`, 안 센 목록 접기
- [ ] **Step 4:** 검토 화면(관리자) — `GET /count/get?review=1` → `buildReview` 모양 표(브라우저에는 같은 계산을 인라인, 순수 모듈은 `src/`라 화면이 못 씀 → 표 계산은 화면 인라인), 줄별 "조정 제외" 체크, 요약(조정 n개·늘어나는 x·줄어드는 y), 확정 `confirm()` 후 `/count/finish`, 성공 시 `refresh(true)`
- [ ] **Step 5:** 스크립트 구문 검사(`new Function`) + 전체 테스트 통과 후 `git commit -m "feat: 재고 실사 화면"`

### Task 4: 마무리

- [ ] **Step 1:** 로컬 E2E 재실행(Task 2 Step 4) + 화면 파일 서빙 200 확인
- [ ] **Step 2:** 전체 테스트, `git push`, `develop` 대상 PR 생성(본문: 설명·범위·확인·한계·PR #10 충돌 가능성, AI 서명 없음)
- [ ] **Step 3:** 최종 독립 검토(Agent, 코드 전체) 후 지적 사항 수정

## Self-Review
- 스펙 커버: 시작(Task2/3)·세기·블라인드·진행 현황·검토·제외·확정·취소·조정 기록·FEFO·중복 확정 방지·권한 — 모두 위 Task에 있음. 모듈의 `buildReview`·`summarize`는 서버 확정(`summarize`)과 검토 API 응답 정렬에 쓰고 화면 표는 인라인 계산(스펙 "순수 함수 모듈 + 화면은 한 파일" 제약에 맞춤).
- 로트별 실사·일정·오프라인은 비목표라 제외.
