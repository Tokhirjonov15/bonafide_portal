# 품목 수정창 개편 1단계 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** 수정창을 접이식 섹션으로 개편하고 처방단가·급여구분·급여코드·자체 코드·조회 버튼·lot 바코드 버튼을 추가한다(기존 항목 보존).
**Architecture:** 순수 함수(서버 `src/product-fields.js`, 클라 `public/jaego/product-codes.js`)를 Node 로 테스트하고, 서버는 열 추가·COALESCE 저장·상태 엔드포인트, 화면은 `<details>` 재배치.
**Tech Stack:** 바닐라 JS, Cloudflare Worker(D1), Node `node:test`
**Spec:** `docs/superpowers/specs/2026-11-26-prod-edit-sections-design.md`

## Global Constraints
- 기존 수정창 입력 id·로직·서버 열/API 동작 삭제·변경 금지(열 추가만). 커밋 메시지 `feat:`/`fix:`/`docs:` 한 줄, AI 서명 줄 없음.
- 새 DB 열: `rx_price INTEGER DEFAULT 0`, `pay_type TEXT DEFAULT ''`, `pay_code TEXT DEFAULT ''`, `own_code TEXT DEFAULT ''`, `benefit_info TEXT DEFAULT ''`.
- `/product` 응답/요청 키: `rxPrice, payType, payCode, ownCode`. 안 보내면(undefined) 기존 값 유지.

## Review Focus
- 구버전 화면(새 키 없이)이 `/product` 로 저장해도 새 열이 지워지지 않는다 (`normExtra` undefined→null 테스트).
- 급여구분에 이상한 값 → 빈 문자열; 처방단가 음수·글자 → 0.
- lot 번호에 공백·슬래시·한글 → Code128 안전 문자만 남기고, 비면 코드 없음.
- 수정창에서 기존 id 가 하나라도 사라지면 테스트 실패.

### Task 1: 서버 값 정규화 + 테스트
**Files:** Create `src/product-fields.js`; Test `tests/server/product-fields.test.mjs`
**Interfaces:** Produces (ESM export): `normPayType(v)->"급여"|"비급여"|"미정"|""`, `normExtra(body)->{rxPrice:number|null,payType:string|null,payCode:string|null,ownCode:string|null}` (키가 undefined 면 null)
- [ ] 실패 테스트: `normPayType("급여")==="급여"`, `("비급여")`, `("미정")`, `("xyz")===""`, `(undefined)===""`; `normExtra({})` 전부 null; `normExtra({rxPrice:"1200",payType:"급여",payCode:" A12 ",ownCode:"NB1"})` → `{rxPrice:1200,payType:"급여",payCode:"A12",ownCode:"NB1"}`; `normExtra({rxPrice:-5}).rxPrice===0`; `normExtra({rxPrice:"abc"}).rxPrice===0`; `normExtra({payType:"zzz"}).payType===""`
- [ ] `node --test tests/` → FAIL(모듈 없음) → 구현 → PASS → 커밋 `feat: 서버 품목 새 항목 값 정규화`

### Task 2: 클라 코드 문자열 함수 + 테스트
**Files:** Create `public/jaego/product-codes.js`; Test `tests/jaego/product-codes.test.js`
**Interfaces:** Produces (전역 `ProductCodes`/CJS): `ownCode(now:number)->string`("NB"+base36 대문자), `lotBarcode(base:string, lot:string)->string`(Code128 안전문자 `[A-Za-z0-9._-]` 만, base 또는 lot 이 비면 `""`)
- [ ] 실패 테스트: `ownCode(0)` 가 `/^NB[0-9A-Z]+$/`; `ownCode(1000)!==ownCode(2000)`; `lotBarcode("BF123","A-77")==="BF123-A-77"`; `lotBarcode("BF123","a b/7")==="BF123-ab7"`; `lotBarcode("BF123","")===""`; `lotBarcode("","L1")===""`; `lotBarcode("BF123","한글")===""`
- [ ] FAIL → 구현(`scan-unit.js` 와 같은 UMD 형태) → PASS → 커밋 `feat: 자체 코드·lot 바코드 문자열 함수`

### Task 3: 서버 연결
**Files:** Modify `src/index.js` (MIGRATIONS 끝, `listProducts`, `/product` POST 의 UPDATE·INSERT, 새 `GET /benefit/status`, `GET /benefit/lookup`)
- [ ] `normExtra`/`normPayType` 를 `import` 하고: MIGRATIONS 에 새 열 5개 추가(`alt_of` 줄 끝에 쉼표); UPDATE 에 `rx_price=COALESCE(?,rx_price), pay_type=COALESCE(?,pay_type), pay_code=COALESCE(?,pay_code), own_code=COALESCE(?,own_code)`; INSERT 에 같은 열(없으면 0/'' ); `listProducts` SELECT 에 `COALESCE(p.rx_price,0) AS rxPrice, COALESCE(p.pay_type,'') AS payType, COALESCE(p.pay_code,'') AS payCode, COALESCE(p.own_code,'') AS ownCode`; `/benefit/status` → `{ok:true,enabled:!!env.HIRA_API_KEY}`; `/benefit/lookup` → 키 없으면 `{error:"급여정보 API 인증이 설정되지 않았습니다."}` 400, 있으면 `{error:"급여정보 조회 연동 준비 중입니다."}` 501.
- [ ] 검증: `cp src/index.js $TEMP/x.mjs` 후 `node --check` 통과, `git diff src/index.js` 로 기존 줄이 삭제되지 않았음(추가·COALESCE 확장만) 확인 → 커밋 `feat: 품목 새 항목 저장·급여 조회 상태 엔드포인트`

### Task 4: 수정창 HTML 개편 + 기존 id 보존 테스트
**Files:** Modify `public/jaego/index.html` (`#prodOvl` 마크업, CSS); Test `tests/jaego/prod-edit-ids.test.js`
- [ ] 실패 테스트: index.html 에서 `<div class="ovl" id="prodOvl">` ~ `<div class="ovl" id="mvOvl">` 구간을 잘라 아래 id 전부 존재 확인 — 기존: `prodTitle pName pCat catList pRx locList pKind pUnit pMin pPar pPrice pVendor venList pAlt pFloorWrap pFloors pAltStock pOunit pOgrp pBar barGenBtn barPrintBtn pInitWrap pInit pExp prodDel prodHide prodCancel prodSave`; 새: `pRxPrice pPayType pPayCode pOwnCode ownGenBtn benefitBtn lotBarBtn`. (새 id 때문에 FAIL)
- [ ] 마크업을 `<details class="sec">` 5개로 재배치(Spec 범위 1·2), `pFloorWrap` 은 ② 의 `<details>` 자체에 둬서 기존 `display` 토글 유지, 팝업에 폭 확대 클래스, `단가` 라벨 → "입고가 (원)" → 테스트 PASS → 커밋 `feat: 품목 수정창을 접이식 섹션으로 재배치 (기존 항목 유지)`

### Task 5: 화면 로직 연결
**Files:** Modify `public/jaego/index.html` (`openProd`, `prodSave` payload, 새 버튼 핸들러, `<script src="product-codes.js">`)
- [ ] `openProd`: 새 값 채우기(`p.rxPrice/payType/payCode/ownCode`), 값 있는 섹션 열기, `lotBarBtn` 은 약품(`kindOf(p)==="약품"` 또는 `pKind` 값)일 때만 표시, `benefitBtn` 은 `/benefit/status` 결과(한 번 캐시)에 따라 활성/비활성+툴팁. `prodSave`: payload 에 `rxPrice,payType,payCode,ownCode` 추가. `ownGenBtn`: 값이 있으면 확인 후 `ProductCodes.ownCode(Date.now())`. `lotBarBtn`: lot 번호 입력 → `ProductCodes.lotBarcode(pBar,lot)` → `printBarLabels([{bar,name,copies:1}])`(코드가 비면 안내). `benefitBtn`: `API.call("/benefit/lookup?code="+…)` 오류 메시지 alert.
- [ ] 검증: `node --test tests/` 전부 PASS, 메인 `<script>` 문법 검사 `ok`, 커밋 `feat: 수정창 새 항목·자체 코드·lot 바코드·급여 조회 버튼 연결`
