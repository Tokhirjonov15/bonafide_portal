# 품목 수정창 개편 1단계 — 접이식 섹션 + 새 항목 (짧은 설계, 승인됨)

대상: `public/jaego/index.html`, 새 `public/jaego/product-codes.js`, 서버 `src/index.js` + 새 `src/product-fields.js`

## 원칙 (사용자 지시)
**기존 항목·동작을 삭제하지 않는다. 있는 것을 고치고 배치만 바꾼다.** 기존 입력 요소 id, `prodSave`/`saveFloorAndAltStock`/`openProd` 로직, 서버 `/product` 동작, 층별 재고 조정(차이만큼 입출고 기록)은 그대로. 서버는 열 **추가만**.

## 목적
수정창은 품목 기본 정보 · 층별 재고 조정 · 입고가/병원 처방단가 · 급여 코드(급여면 조회, 약품이면 급여정보 불러오기) · 비급여 자체 코드 · 약품 lot 바코드를 한곳에서 다룬다. 지금은 한 줄로 늘어선 15개 칸이라 구분이 안 된다.

## 1단계 범위
1. 한 화면 **접이식 섹션**(`<details>`): ① 기본 정보(열림) ② 층별 재고 조정(수정 시 열림) ③ 가격·발주 ④ 코드 ⑤ 바코드. 값이 있는 섹션은 열린 채로 시작. 컴퓨터에서는 팝업 폭 확대(640px).
2. **새 항목**: 처방단가(`pRxPrice`), 급여구분(`pPayType`: 급여/비급여/미정), 급여코드(`pPayCode`), 자체 코드(`pOwnCode`, [자동 생성] `ownGenBtn`). 기존 `단가`는 라벨만 "입고가 (원)"로, id `pPrice`·열 `price` 그대로.
3. **급여 조회 버튼**(`benefitBtn`): 서버 `GET /api/benefit/status` → `{enabled}`. 환경변수 `HIRA_API_KEY` 가 없으면 비활성("API 인증 설정 후 사용"). 있으면 활성화되고, 눌렀을 때 `GET /api/benefit/lookup?code=` 는 이번엔 `501 연동 준비 중`(실제 조회는 2단계 이후).
4. **약품 lot 바코드 버튼**(`lotBarBtn`, 약품일 때만): lot 번호를 물어 `품목 바코드-lot` 코드로 라벨을 출력. 스캐너가 이 코드를 알아보는 서버 처리는 범위 밖.
5. 서버: `products` 에 열 추가 `rx_price INTEGER`, `pay_type TEXT`, `pay_code TEXT`, `own_code TEXT`, `benefit_info TEXT`(API 결과 보관용, 이번엔 미사용). `/product` 저장은 새 항목을 `COALESCE`(안 보내면 기존 값 유지)로 처리해 구버전 화면이 값을 지우지 않게 한다. 목록 응답에 `rxPrice, payType, payCode, ownCode` 추가.

## 비범위 (2단계)
대체 품목별 "달라지는 값" 입력, 박스 크기 처음 한 번 묻기, 실제 급여정보 조회, lot 바코드 스캔 인식.

## 테스트
- Node: `src/product-fields.js`(서버 값 정규화), `public/jaego/product-codes.js`(자체 코드·lot 바코드 문자열), **수정창 HTML 에 기존 입력 id 가 모두 남아 있는지** 정적 검사.
- 화면은 localhost 에서 확인(서버 없음 → 목업).
