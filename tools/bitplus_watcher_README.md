# 비트플러스 접수 연동 — 설치 안내

`bitplus_watcher.ps1`(v3.5)은 세 채널을 합쳐 동선관리(Firebase `bitIntake`·`bitNote`)에 올립니다. 같은 스크립트를 접수 PC와 진료실 PC에 설치하며,
열려 있는 비트 창(접수 / 외래진료실)을 보고 스스로 무엇을 읽을지 정합니다.

> **v3.5 (2026-09-16) — DB 에이전트 우선.** 접수 PC 에 비트 DB 를 직접 읽는 에이전트(`bit_db_agent.ps1`, `bit_db_agent_README.md`)가 함께 돌면
> 캐스트(채널 ①)로는 `bitIntake` 에 쓰지 않습니다. 확인은 LAN 상태 포트(TCP 9001)로만 하므로 Firestore 비용이 없고, 이 PC(127.0.0.1)와 `bitplus_peers.txt` 의
> IP 중 하나라도 "OK" 로 답하면 정상으로 봅니다. 에이전트가 모두 응답이 없으면(꺼짐·DB 서버 불통) 지금까지처럼 캐스트로 직접 씁니다 → 접수 PC 3대가 그대로 예비 경로.
> 접수 캐스트는 에이전트에 맡긴 뒤 15초 후 문서에 `src=db` 가 있는지 1회 읽어 확인하고, 없으면 직접 씁니다(이중 안전). 인적정보(채널 ②)·처방(채널 ③)은 그대로 읽습니다.
> 로그: `DB 에이전트 정상(…) → 캐스트는 bitIntake 에 쓰지 않음` / `cast 접수 … → 생략 (15초 뒤 확인)` / `확인: … 에이전트가 전송함`.
> 설치: 접수 PC 에서 `bitplus_install.ps1 -Pc 접수1 -Agent -Priority 3 -Peers <다른 에이전트 PC IP들>` (아래 2단계). 진료실 PC 는 갱신하지 않아도 됩니다(캐스트를 받지 않으므로).
3. **외래진료실 창 — 처방 목록(진료실 PC, Win32, 2초)** — 의사가 '증상' 칸 **맨 아래**에 적는 약·주사 목록을 읽어 `bitNote/{날짜}_{차트번호}` 에 올립니다.
   - 규칙(2026-09-13 원내 표기 공지 반영): 감시 스크립트는 맨 아래에서 위로 올라가며 **처음 만나는 `med` 로 시작하는 줄부터 끝까지**를 원문 그대로 보냅니다(상한 20줄, `$RX_HEAD`).
     해석은 동선관리(`rxParse`)가 합니다 — `med` 줄 **아래에 `neuropathic pain` 줄이 있어야** 처방(약·주사 목록)이고, 없으면 특이사항 성격의 메모로 보고 슬립에 표시하지 않습니다.
     `med` 줄의 표시는 배지로: `@`=진료원장님 주사, `(prone)`/`(supine)`=준비 포지션, `g`=그린(진료 없이 주사만), `gp`=그린+(주사하면서 진료), `약처방o`/`약 x 예정`=약처방 있음/없음.
     표기 규칙이 바뀌면 웹(rxParse)만 고치면 되고 PC 재설치는 필요 없습니다. 같은 창의 주민번호 앞 7자리·성별도 함께 보내 카드가 없어도 슬립에 생년월일을 찍습니다.
   - 2번 연속 같은 값(입력 중 아님)일 때 전송, 의사가 고치면 다시 전송(문서 갱신). 창의 **차트번호 칸**으로 환자를 구분하므로 다른 환자로 바꾸면 그 환자 문서로 갑니다.
   - 동선관리: 카드에 `처방 N줄` 요약이 붙고, 메뉴 **[슬립 화면]** 또는 주소 `…/dongseon/?slip` (태블릿·별도 창, `&room=물리치료` 로 그 방 동선 환자만)에서
     위에 환자 정보, 아래에 목록을 크게 보여 줍니다. **[슬립 인쇄]** 는 폭 104mm·길이 자동 용지로 인쇄(숨김 iframe, 라벨과 같은 방식). [확인]은 모든 화면에 공유.
   - 같은 창의 **특이사항** 칸도 읽어 `memo` 로 보냅니다. 동선관리는 이를 환자 명단의 특이사항(영구 메모)에 없는 문장만 덧붙입니다 —
     의사가 진료 뒤(카드가 이미 내보내진 뒤)에 적어도 저장되어 **다음 내원 때 카드에 보입니다**. 슬립에는 인쇄하지 않습니다. 비트의 빈 표시 줄(`+`, `-`)은 무시.
   - 처방내역·슬립 표(C1TrueDBGrid)는 읽을 수 없으므로 물리치료 코드는 슬립에 나오지 않습니다.
   - 진료실 PC 설치는 접수 PC와 같습니다(`bitplus_install.ps1 -Pc 진료실1`). 전광판IP 등록은 필요 없고(캐스트는 접수 PC용), 방화벽 9000도 없어도 됩니다.
     pill 은 접수 창 **또는** 외래진료실 창이 열려 있으면 초록(`doctorOpen`).
1. **BITCast (TCP 9000)** — 비트의 대기표시기(전광판) 연동 채널. 비트 환경설정에 이 PC IP를 등록하면
   **모든 접수 PC**의 비트가 [환자접수]·[접수취소]·[호출] 이벤트를 이 PC로 보냅니다 (`2|이름|진료실|분|메모|담당의|이전방|접수번호|`).
   → 동선관리는 접수 이벤트를 **확인 없이 3층 대기실 카드로 자동 생성**하고, 접수취소면 아직 손대지 않은 카드를 자동 제거합니다.
   - 접수 수정·보류는 비트가 `접수취소 → 접수`를 연달아 보내므로 동선관리는 취소를 6초 기다렸다가 처리합니다(카드 유지).
     예약 환자는 `예약접수 → (3초 뒤) 접수취소 → 사전예약`으로 오므로, 취소 뒤에 환자가 살아 있다는 캐스트(사전예약·호출·수납대기 등)가 오면 취소를 해제하고 카드를 되살립니다.
   - 카드의 담당의는 비트 접수의 담당의를 그대로 씁니다(3층 대기실에 전담 진료의가 지정돼 있어도 덮어쓰지 않음).
   - **수납대기**(7)는 아직 원내 → 카드 그대로. **수납완료**(8) → 카드를 3층 수납으로 옮기고 **'비트 수납완료' 초록 표시**만 남긴다. 내보내기는 직원이 확인 후 [내보내기]
     (직원이 비트에서 수납완료를 잘못 누르는 일이 있어 2026-09-16 부터 자동 내보내기 중단). 추가 비용 미수납이면 알림.
   - 수납완료 뒤 **수납취소**(10)·수납대기(7)가 오면(잘못 계산 등) → 카드가 보드에 있으면 초록 표시만 해제, 이미 내보냈으면 완료 목록의 그 내원 기록을 다시 보드(3층 수납)로 복귀.
   - 카드의 `원내` 시간 옆에 **접수 시각**(비트 접수 시각, 없으면 동선관리 등록 시각)을 표시합니다.
2. **접수 창 인적정보 패널**(UIAutomation, 2초) — 조회된 환자의 차트번호·주민번호7·보험·메모를 캐시해 1의 이벤트에 붙입니다
   (캐스트 메시지에는 차트번호가 없음). 캐시가 없으면 이름만으로 카드가 먼저 생기고, 차트번호는 뒤에 자동 보충됩니다.
   조회된 인적정보는 `bitLookup/{날짜}_{차트번호}` 에도 기록되므로, 접수가 **다른 PC**에서 됐거나 스크립트가 **재시작**된 뒤라도
   어느 PC에서든 그 환자를 조회하면 동선관리가 이름으로(오늘 그 이름이 하나일 때만) 카드에 차트번호·생년월일을 채웁니다.
   접수 **뒤에** 인적정보가 조회되거나 [원외처방] 창의 특이사항이 열리면 그 내용도 같은 문서에 보충됩니다(카드 특이사항에 자동 추가).
   원외처방 특이사항은 진료 뒤(수납 무렵)에 입력되므로, 창이 열리면 패널에 그 환자가 떠 있지 않아도 차트번호로 오늘 문서를 찾아 바로 보충하고,
   카드가 이미 내보내진 뒤라도 환자 명단의 특이사항에는 남습니다(다음 내원 때 보임).
   캐스트 메시지의 접수메모는 비트가 **8자로 잘라** 보내므로(전광판 한계) 카드에 먼저 짧게 보이고, 접수 PC의 인적정보에서 전체 문장이 오면 통째로 바뀝니다.
- 명단과 이름이 다르거나 병록번호가 충돌하면 자동 생성하지 않고 보드 위 **비트 접수 대기** 줄에 남깁니다(직원 확인).
- 카드는 **[환자접수]가 눌렸을 때만** 생깁니다. 인적정보 조회·특이사항 입력·예약 등록/변경은 캐스트가 없어 아무 일도 하지 않습니다
  (예약 캐스트라도 시각이 30분 넘게 미래면 '미도착'으로 기록만).
- **동명이인**: 캐스트에는 차트번호가 없어 이름으로 인적정보 캐시를 맞춥니다. 같은 이름의 다른 차트번호가 15분 안에 함께 조회됐으면
  차트번호를 붙이지 않고 카드에 '동명이인 확인' 알림을 띄웁니다(직원이 [수정]에서 입력). 한 번 보낸 차트번호는 다른 환자 조회로 바뀌지 않습니다.

## 0. 비트 환경설정 — 전광판IP 등록 (한 번만, 비트 관리자)

비트 메인 메뉴 → **환경설정** → 상단 **기타사항** 버튼 → 아래쪽 **전광판IP 세팅**:
- **전광판 IP**: 감시 PC의 IP (예 `192.168.0.25`) → 저장(디스켓)
- **전광판IP 세팅** 목록: 구분 `접수BitCast`, IP `192.168.0.25` → **저장** (목록에 `IP | 192.168.0.25` 행이 생김)
- 이 설정은 DB에 저장되어 모든 접수 PC에 적용됩니다. 비트는 접수 창을 다시 열지 않아도 바로 보냅니다.
- 감시 PC의 Windows 방화벽에서 `powershell.exe`의 **TCP 9000 인바운드**가 막히면 다른 PC의 이벤트가 안 옵니다(첫 실행 때 허용).

- 비트플러스에는 아무것도 입력·클릭하지 않습니다 (읽기만).
- 읽는 항목: 차트번호, 이름, 생년월일+성별(주민번호 앞 7자리만), 전진료실/담당의, 전진료일, 다음예약일,
  가입자성명·관계(가족관계), 최초내원일, 보험유형, 초/재진, 접수메모(당일·연속).
- 읽지 않는 항목: 주민번호 뒷자리, 전화번호, 주소, 이메일.
- 설치 프로그램 없음. Windows 10/11 기본 PowerShell만 사용. 비용 없음.

## 1. 동선관리에 bitbot 계정 만들기 (한 번만, admin 계정으로)

동선관리 → 계정 관리 → **계정 추가**: 아이디 `bitbot`, 권한 `직원`, 비밀번호는 8자 이상 (영문+숫자).
이 비밀번호를 아래 3단계의 `.secret` 파일에 적습니다. 세 PC 모두 같은 계정을 씁니다.

## 2. 접수 PC마다 설치 (관리자 PowerShell, 1회)

`tools/bitplus_watcher.ps1` 과 `tools/bitplus_install.ps1` 을 같은 폴더(USB 등)에 두고, 그 접수 PC의 **관리자 PowerShell**에서:
```
powershell -ExecutionPolicy Bypass -File bitplus_install.ps1 -Pc 접수1
```
설치 스크립트가 순서대로: `C:\bitplus` 복사 → bitbot 비밀번호 입력(.secret, 현재 사용자만 읽기) → 방화벽 TCP 9000 허용(관리자일 때) →
로그온 자동 시작 작업(`BitPlusWatcher`, 실행 시간 제한 없음·죽으면 1분 뒤 재시작) 등록 → 지금 시작 → **이 PC의 IP를 출력**합니다.
PC 이름(`-Pc`)은 PC마다 다르게: `접수1`, `접수2`, `접수3`.
- 관리자가 아니어도 작업 등록·시작은 됩니다(방화벽만 건너뜀). 처음 실행 때 Windows 방화벽 창이 뜨면 **허용**.
- 작업 등록이 막힌 PC에서는 시작 프로그램 폴더의 `BitPlusWatcher.vbs` 로 대체 등록됩니다.
- 접수 PC는 부팅 후 **로그온**이 되어야 시작됩니다(비트도 마찬가지). 자동 로그온이 아니면 아침에 로그온만 하면 됩니다.

## 3. 비트 전광판IP 등록 (0번 항목) — 세 PC의 IP를 모두 목록에 추가

세 접수 PC 모두가 모든 캐스트를 받으므로 한 대가 꺼져 있어도 나머지가 처리합니다. 같은 문서에 세 번 써도(merge) 동선관리는 한 번만 카드를 만듭니다.
접수 PC의 IP는 **고정**(또는 공유기 예약)이어야 합니다. 테스트에 썼던 다른 PC IP는 목록에서 삭제하세요.

## 4. 확인

- 로그: `%LOCALAPPDATA%\bitplus_watcher\watcher.log` 에 `Firebase 로그인 성공`, `BITCast 수신 대기: TCP 9000`
- 비트에서 [환자접수] → 로그에 `전송: 2026-09-09_ocm193429 접수 (… 차트번호 있음)` → 동선관리 3층 대기실에 카드(2~3초)
- 동선관리 상단 pill: `비트 접수1 ●` 초록
- 중지: `Stop-ScheduledTask BitPlusWatcher` · 다시 시작: `Start-ScheduledTask BitPlusWatcher` · 삭제: `Unregister-ScheduledTask BitPlusWatcher -Confirm:$false`

## 6. 로그 / 상태

- 로그: `%LOCALAPPDATA%\bitplus_watcher\watcher.log` (환자 이름은 기록하지 않음, 차트번호만)
- 동선관리 상단 pill: 초록 = 정상(접수 창 또는 외래진료실 창이 열림), 노랑 = 비트 창이 하나도 안 열림(스크립트는 살아 있음 — 이 PC 에서 외래진료실을 열면 바로 초록), 회색 = 신호 없음(스크립트 꺼짐·PC 꺼짐).
  하트비트: 창이 열린 PC 는 5분마다, 창이 없는 PC 는 30분마다(v3.3), 창이 열리고 닫히는 순간은 즉시. 회색 판정은 각각 12분 30초 / 35분 뒤.
  v3.4 부터 하트비트는 `bitStatus/_all` 한 문서(PC 이름별 필드)에 모아 쓰고, 동선관리는 이 문서를 5분마다 한 번 읽는다(실시간 구독 없음 → 읽기 = 화면당 하루 300회). 구버전 PC 의 개별 문서는 60분마다 합쳐 읽는다.
  병원 전 PC(약 20대)에 설치해도 되는 이유: 어느 PC 에서든 의사가 외래진료실 '증상' 칸에 처방을 적으면 슬립으로 가야 하기 때문. 놀고 있는 PC 는 하루 48번만 쓴다.
- **Firestore 읽기 한도(무료 Spark 50,000/일)**: 읽기는 "바뀐 문서 × 듣고 있는 화면 수"로 센다. 2026-09-14 에 하트비트(6대×1분)와 화면 10개로 한도를 넘어 16:00(태평양 자정)까지 새 연결이 모두 거부됐다.
  대응: 하트비트 300초(v3.2), 대기화면(TV)·슬립 태블릿은 접수·하트비트·처방 컬렉션을 듣지 않음(동선관리). 그래도 하루 4~5만 회에 가까우므로 **Blaze(종량제) 전환 권장** — 이 규모에서 월 2~5달러.

## 7. 자주 있는 문제

| 증상 | 원인 / 조치 |
|---|---|
| `비밀번호 파일이 없습니다` | 3단계 파일 이름·위치 확인 (`.secret.txt` 아님) |
| `Firebase 로그인 실패 … INVALID_LOGIN_CREDENTIALS` | bitbot 비밀번호 틀림 또는 계정 미생성 |
| pill 이 노랑 | 비트플러스 접수 창이 닫혀 있음 — 접수 메뉴를 다시 열면 됨 |
| pill 이 회색 | 스크립트가 꺼짐 — `Start-ScheduledTask BitPlusWatcher` 또는 PC 재로그온 |
| 환자가 대기 줄에 안 뜸 | 이미 보드에 있는 환자는 안 뜸 / 30분 지난 조회는 자동 제거 / 로그의 `전송:` 줄 확인 |
| 비트 업데이트 후 안 읽힘 | 인적정보 라벨 이름이 바뀐 경우 — `bitplus_probe.ps1` 로 다시 확인 후 스크립트의 `$LABELS` 수정 |
| 슬립에 수진자명·생년월일이 없음 (상태 로그에 `주민앞자리 없음`) | v3(09-13) 스크립트의 버그 — 환자를 부르기 전(빈 창)에 핸들을 외워 이름·주민 칸을 못 읽었음. **v3.1 이상으로 갱신**: 그 PC에서 `bitplus_install.ps1 -Pc 진료실1` 을 다시 실행(비밀번호 파일은 그대로 두고 스크립트만 바꿔 재시작). 갱신 전까지는 동선관리가 접수 창 조회 기록(bitLookup)으로 이름·생년월일을 채움 |
| 동선관리에 "Quota exceeded" / 보드가 비어서 열림 | Firestore 일일 읽기 한도 초과(무료 플랜). 열려 있는 화면은 새로고침하지 말 것(기존 연결은 유지됨). 16:00 KST 에 초기화. 근본 대책은 Blaze 전환 + 이 문서 6장의 읽기 줄이기 |
| 스크립트 갱신 방법 | 새 `bitplus_watcher.ps1` 을 같은 폴더에 두고 설치 명령을 그대로 다시 실행 — 동선관리 상단 pill 의 `ver` 가 바뀌면 완료 |

## 8. 보안 설정 (꼭 해두기)

### 8-1. 비밀번호 파일 접근 제한 (각 접수 PC, 한 번)
`.secret` 파일을 현재 Windows 사용자만 읽을 수 있게 합니다. PowerShell에서:
```
icacls "C:\bitplus\bitplus_watcher.secret" /inheritance:r /grant:r "%USERNAME%:M"
```
(경로는 실제 위치로. 관리자·SYSTEM 외 다른 계정은 읽지 못함. 설치 스크립트가 자동으로 해 주며, 같은 폴더의 `bitplus_watcher.token`(세션 토큰)도 같은 권한으로 저장됨 — 재시작 때 비밀번호 로그인 없이 이어가기 위한 파일)

### 8-2. Firestore 규칙 — bitbot만 접수 문서를 쓰고, 직원은 처리 표시만
Firebase 콘솔 → Firestore Database → 규칙 → 아래로 교체 → 게시.
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // 비트 접수 대기: 쓰기는 bitbot 계정만, 직원은 status/handledBy/handledAt/patientId 만 변경·삭제 가능
    match /bitIntake/{doc} {
      allow read: if request.auth != null;
      allow create, update: if request.auth != null && request.auth.token.email == 'uc8feac453b1a01cc028b072a@bonafide.app';
      allow update: if request.auth != null
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status','handledBy','handledAt','patientId']);
      allow delete: if request.auth != null;
    }
    // 접수 PC 하트비트: bitbot만 쓰기
    match /bitStatus/{pc} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.token.email == 'uc8feac453b1a01cc028b072a@bonafide.app';
    }
    // 접수 창 조회 기록(차트번호 없는 캐스트 카드를 이름으로 보완): bitbot만 쓰기, 직원은 읽기·삭제(7일 정리)
    match /bitLookup/{doc} {
      allow read: if request.auth != null;
      allow create, update: if request.auth != null && request.auth.token.email == 'uc8feac453b1a01cc028b072a@bonafide.app';
      allow delete: if request.auth != null;
    }
    // 진료실 처방 목록(슬립): 쓰기는 bitbot, 직원은 확인 표시(ack/ackBy/ackAt)만 변경·삭제 가능
    match /bitNote/{doc} {
      allow read: if request.auth != null;
      allow create, update: if request.auth != null && request.auth.token.email == 'uc8feac453b1a01cc028b072a@bonafide.app';
      allow update: if request.auth != null
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['ack','ackBy','ackAt']);
      allow delete: if request.auth != null;
    }
    // 물리치료센터 예약리스트(Google Sheet, tools/sheet_bookings.gs): 쓰기는 sheetbot 만, 직원은 읽기
    match /bookings/{day} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.token.email == '<sheetbot 이메일>';
    }
    // 비트 진료 예약 하루치(tools/bit_db_agent.ps1 → bitResv/{날짜}, _summary): 쓰기는 bitbot 만, 직원은 읽기·삭제(7일 정리)
    match /bitResv/{day} {
      allow read: if request.auth != null;
      allow create, update: if request.auth != null && request.auth.token.email == 'uc8feac453b1a01cc028b072a@bonafide.app';
      allow delete: if request.auth != null;
    }
    // 계정 명단(acl/main: members·adminEmails·superEmails): 읽기는 로그인한 직원, 쓰기는 관리자·최고관리자만.
    // 직원이 스스로 관리자로 올리거나 다른 계정을 지우는 것을 막는다 (2026-09-21 — 그 전엔 누구나 쓸 수 있었음)
    match /acl/{doc} {
      allow read: if request.auth != null;
      allow write: if request.auth != null
        && (request.auth.token.email in resource.data.adminEmails
            || request.auth.token.email in resource.data.superEmails);
    }
    // 그 외(환자·설정 등): 로그인한 직원만.
    // ※ 여기서 봇 컬렉션과 acl 을 반드시 제외해야 한다 — Firestore 는 겹치는 match 중 하나라도 허용하면 허용이므로,
    //    /{document=**} 로 두면 위의 bitbot/sheetbot/관리자 제한이 모두 무력화된다(2026-09-14 확인).
    match /{collection}/{document=**} {
      allow read, write: if request.auth != null
        && !(collection in ['bitIntake','bitStatus','bitLookup','bitNote','bookings','bitResv','acl']);
    }
  }
}
```

### 8-3. 자동 정리
동선관리가 로그인 시 7일 지난 `bitIntake`·`bitNote` 문서를 자동 삭제합니다(하루 1회). 로그 파일에는 차트번호만 남고 이름·메모·처방 내용은 기록되지 않습니다.

### 8-4. 남는 위험 (알고 있어야 할 것)
- 동선관리 계정(snu01~30)이 공통 비밀번호인 동안은 누구든 그 비밀번호로 환자 정보를 볼 수 있습니다. 개인별 비밀번호로 바꾸는 것을 권장합니다.
- 접수 PC 자체가 악성코드에 감염되면 `.secret`도 노출될 수 있습니다. bitbot은 '직원' 권한이므로 설정 변경·삭제는 못 하지만 환자 정보 읽기는 가능합니다. 의심되면 동선관리에서 bitbot 비밀번호를 바꾸면 즉시 차단됩니다.
- 비트플러스 업데이트로 화면 구성이 바뀌면 읽기가 멈춥니다(잘못 읽지는 않음). pill 이 회색/노랑이 아닌데 환자가 안 뜨면 `bitplus_probe.ps1` 로 라벨을 다시 확인하세요.

## 동선관리 쪽 동작 요약

- `bitIntake/{날짜_차트번호}` 문서 하나 = 그날 그 환자. 같은 환자를 여러 번 조회해도 문서는 하나(갱신만).
- 자동 생성 → 문서 `status: 자동접수` (여러 화면이 열려 있어도 트랜잭션으로 하나만 만듦). [접수] → 정보가 채워진 접수 창 → 동선 선택 후 저장 → `status: 접수`. [무시] → `status: 무시`.
- 가족관계(가입자성명·관계, 본인 제외)와 최초내원일·전진료일·다음예약일·당일메모는 저장 시 환자 기록(`p.bit`)에 함께 보관.
