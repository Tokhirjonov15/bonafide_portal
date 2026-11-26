# 2단계 A — 대체 품목별 "달라지는 값" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans.

**Goal:** 수정창의 대체 품목 블록에서 본 품목과 다른 값(입고가·처방단가·박스당 개수·급여 구분·급여코드·자체 코드)만 적으면 되게 한다. 비워 두면 저장할 때 본 품목 값을 복사한다.
**Architecture:** 순수 함수 `ProductCodes.resolveAltValues` / `updatePayload`(Node 테스트) → `renderAltStock` 에 접이식 "달라지는 값" 추가 → `saveFloorAndAltStock` 이 새 대체 품목 생성·기존 대체 품목 수정에 반영. 서버 변경 없음(1단계의 `/product` 가 새 항목을 이미 받음).
**Spec:** 사용자 승인(2단계): 변경되는 규격은 대체 품목으로 등록, 달라지는 요소만 기입. 박스당 개수는 품목마다 고정.

## Global Constraints
- 기존 항목·동작 삭제 금지(층별 재고 칸 id `pAs_<j>_<i>`, `renderAltStock`, 저장 흐름 유지). 서버 `/product` 수정은 보낸 값으로 덮어쓰므로 수정 요청은 **기존 항목을 모두 담아** 보낸다.
- 비운 칸 = 본 품목 값 복사. 잘못된 숫자·급여 구분 = 본 품목 값. 입력 `0` 은 명시한 0.
- 커밋 `feat:`/`fix:` 한 줄, AI 서명 줄 없음.

## Review Focus
- 기존 대체 품목을 수정할 때 바코드·최소/적정 수량·거래처 등 안 보이는 항목이 지워지지 않는다 (`updatePayload` 테스트).
- 값 칸을 안 건드린 저장이 불필요한 수정 요청을 만들지 않는다.
- 본 품목에 값이 없을 때(0/빈칸) 복사해도 0/빈칸.

### Task 9: 순수 함수 + 테스트
**Files:** Modify `public/jaego/product-codes.js`; Test `tests/jaego/product-codes.test.js`
**Interfaces:** `ProductCodes.resolveAltValues(parent, input) -> {price,rxPrice,ounit:number, payType,payCode,ownCode:string}`; `ProductCodes.updatePayload(p, over) -> object`(`/product` 수정 본문: id,name,cat,loc,unit,bar,min,par,alt,price,vendor,ounit,ogrp,rx,kind,rxPrice,payType,payCode,ownCode)
- [ ] 실패 테스트 → 구현 → PASS → 커밋 `feat: 대체 품목 달라지는 값 정리 함수와 테스트`

### Task 10: 수정창 화면
**Files:** Modify `public/jaego/index.html` (`renderAltStock`, `saveFloorAndAltStock`); Test `tests/jaego/prod-edit-ids.test.js`
- [ ] 정적 테스트(`pAv_${j}_price` 등 입력 id·"달라지는 값" 문구) 실패 확인 → `renderAltStock` 의 대체 품목 블록마다 접이식 "달라지는 값"(입고가·처방단가·박스당 개수·급여 구분·급여코드·자체 코드, 칸 안 placeholder 는 본 품목 값) 추가 → `saveFloorAndAltStock`: 값 입력이 있거나 재고가 있으면 대체 품목 생성(생성 본문에 해결된 값 포함), 이미 있으면 값이 바뀐 경우에만 `/product` 로 `updatePayload(sub, 해결된 값)` 수정 → 테스트·문법 PASS → 커밋 `feat: 수정창 대체 품목에 달라지는 값 입력`
