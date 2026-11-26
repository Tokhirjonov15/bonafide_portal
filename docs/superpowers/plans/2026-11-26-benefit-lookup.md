# 급여정보 조회 (건강보험심사평가원 약가기준정보) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** 수정창 [조회]로 급여코드(제품코드 `mdsCd`)·품목명(`itmNm`)을 조회해 급여코드를 채운다.
**Architecture:** 순수 함수 `src/hira.js`(URL 만들기·XML 읽기, Node 테스트) → 서버 `/benefit/lookup` → 수정창 결과 팝업. 키 `HIRA_API_KEY` 는 서버에서만 사용, 화면·로그·응답에 나가지 않는다.
**Spec:** `docs/superpowers/specs/2026-11-26-prod-edit-sections-design.md` (범위 3·"조회 연동"), 사용자 승인: 급여코드 채움, 품목명·거래처·입고가·처방단가 자동 덮어쓰기 금지, 상한금액은 참고 표시, 삭제/변경코드 경고. 응답에 포장단위 없음(박스 크기 추천 불가).

## Global Constraints
- 호출: `GET https://apis.data.go.kr/B551182/dgamtCrtrInfoService1.2/getDgamtList` 변수 `serviceKey numOfRows pageNo mdsCd itmNm mnfEntpNm adtStaDd` (빈 값은 보내지 않음). 응답 항목: `mdsCd itmNm mnfEntpNm unit nomNm mxCprc payTpNm chgAfMdsCd adtStaDd injcPthNm spcGnlTpNm`.
- 인증키는 코드·테스트·문서·로그·응답 어디에도 쓰지 않는다. 테스트 자료는 `tests/fixtures/hira-getDgamtList.xml`(키 없음).
- 기존 항목 삭제 금지. 커밋 `feat:`/`fix:` 한 줄, AI 서명 줄 없음.

## Review Focus
- 키가 이미 URL 인코딩된 형태(`%2B` 등)여도 이중 인코딩되지 않는다.
- 결과 0건(`<items/>` 또는 items 없음)·1건·여러 건, 오류 응답(`resultCode` ≠ 00 / `OpenAPI_ServiceResponse`)을 구분한다.
- XML 엔티티(`&amp;` 등)와 빈 태그를 안전하게 읽는다.
- 서버 오류 메시지에 키가 섞여 나가지 않는다.

### Task 6: `src/hira.js` — URL 만들기·응답 읽기
**Files:** Create `src/hira.js`; Test `tests/server/hira.test.mjs`
**Interfaces (ESM):** `buildDgamtUrl({key, code, name, maker, rows, page}) -> string`; `parseDgamtXml(xml: string) -> {ok:boolean, resultCode:string, message:string, total:number, items:Item[]}` with `Item={code,name,maker,unit,spec,price,payType,changedCode,startDate,route,kind}`; `itemWarning(item) -> string`("" | "삭제된 코드입니다" | "변경 코드: G…")
- [ ] 실패 테스트(샘플 XML 파일 사용): 샘플 → `ok true, total 1, items[0]` 가 `code "G03900131", name "레스피렌정", maker "건일제약", unit "정", spec "1", price 0, payType "삭제", changedCode "G09900011", startDate "20050401", route "내복", kind "전문"`; `<items/>`·items 없음 → `ok true, total 0, items []`; `resultCode 30` 응답 → `ok false` + message; `OpenAPI_ServiceResponse`(`<returnReasonCode>30</returnReasonCode><returnAuthMsg>…`) → `ok false`; 여러 `<item>` 2건 → 2건 순서대로; `&amp;` 포함 제품명 → `&`; `buildDgamtUrl({key:"a+b/c=",itm…})` 에 `serviceKey=a%2Bb%2Fc%3D`, 이미 `a%2Bb%2Fc%3D` 를 줘도 같은 결과; 한글 `name:"피렌정"` 은 `itmNm=%ED%94%BC%EB%A0%8C%EC%A0%95`; 빈 값은 파라미터 생략; `rows` 기본 10, `page` 기본 1; `itemWarning`: payType "삭제" → "삭제된 코드입니다", changedCode 가 있고 code 와 다르면 "변경 코드: …", 둘 다면 둘 다, 정상이면 "".
- [ ] FAIL → 구현(정규식으로 `<item>` 블록과 태그 값을 읽는 최소 구현) → PASS → 커밋 `feat: 급여정보 조회 URL·응답 읽기 함수와 테스트`

### Task 7: 서버 `/benefit/lookup`
**Files:** Modify `src/index.js`
- [ ] `import { buildDgamtUrl, parseDgamtXml } from "./hira.js"`. `/benefit/lookup`: 키 없음 400(기존), `code`/`name`/`maker` 중 하나도 없으면 400 "조회할 급여코드나 품목명이 필요합니다."; `fetch(url,{signal:AbortSignal.timeout(10000)})` → 본문 텍스트 → `parseDgamtXml` → `ok` 면 `json({ok:true,total,items})` (items 최대 20), 아니면 502 `{error:"급여정보 조회 실패: "+message}`; fetch 예외도 502 로 메시지에 키·URL 을 넣지 않는다. 기존 501 응답은 제거.
- [ ] 검증: `cp src/index.js src/_chk.mjs; node --check src/_chk.mjs; rm` → ok, `node --test tests/` PASS → 커밋 `feat: 서버 급여정보 조회 연결`

### Task 8: 수정창 [조회] 결과 팝업
**Files:** Modify `public/jaego/index.html` (새 `#benefitOvl` 팝업, `benefitBtn` 핸들러), `public/jaego/product-codes.js` (+ `itemWarning` 같은 규칙), Test `tests/jaego/product-codes.test.js`
- [ ] 클라 `ProductCodes.benefitWarning(item)` 테스트(삭제/변경코드/정상)를 먼저 추가해 FAIL → 구현 → PASS.
- [ ] `benefitBtn`: `pPayCode` 가 있으면 `?code=`, 없으면 `pName` 으로 `?name=`; 로딩 표시; 결과 목록(품목명·제조사·규격/단위·급여구분·상한금액(참고)·경고) 팝업; [선택] → `pPayCode` 채움, `payType==="급여"` 면 `pPayType="급여"`; 품목명·거래처·입고가·처방단가는 건드리지 않음. 결과 0건·오류 메시지 안내. 팝업은 `esc()` 로 이스케이프.
- [ ] 검증: `node --test tests/` PASS + 화면 문법 검사 `ok` → 커밋 `feat: 수정창 급여정보 조회 결과 팝업`
