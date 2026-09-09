# 비트플러스 접수 연동 — 설치 안내

`bitplus_watcher.ps1`(v2)은 두 채널을 합쳐 동선관리(Firebase `bitIntake`)에 올립니다.
1. **BITCast (TCP 9000)** — 비트의 대기표시기(전광판) 연동 채널. 비트 환경설정에 이 PC IP를 등록하면
   **모든 접수 PC**의 비트가 [환자접수]·[접수취소]·[호출] 이벤트를 이 PC로 보냅니다 (`2|이름|진료실|분|메모|담당의|이전방|접수번호|`).
   → 동선관리는 접수 이벤트를 **확인 없이 3층 대기실 카드로 자동 생성**하고, 접수취소면 아직 손대지 않은 카드를 자동 제거합니다.
   - 접수 수정·보류는 비트가 `접수취소 → 접수`를 연달아 보내므로 동선관리는 취소를 6초 기다렸다가 처리합니다(카드 유지).
   - **수납대기**(7)는 아직 원내 → 카드 그대로. **수납완료**(8) → 카드를 3층 수납 경유로 자동 내보내기(내원 기록 보관). 추가 비용 미수납이면 알림만.
   - 카드의 `원내` 시간 옆에 **접수 시각**(비트 접수 시각, 없으면 동선관리 등록 시각)을 표시합니다.
2. **접수 창 인적정보 패널**(UIAutomation, 2초) — 조회된 환자의 차트번호·주민번호7·보험·메모를 캐시해 1의 이벤트에 붙입니다
   (캐스트 메시지에는 차트번호가 없음). 캐시가 없으면 이름만으로 카드가 먼저 생기고, 차트번호는 뒤에 자동 보충됩니다.
- 명단과 이름이 다르거나 병록번호가 충돌하면 자동 생성하지 않고 보드 위 **비트 접수 대기** 줄에 남깁니다(직원 확인).

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
설치 스크립트가 순서대로: `C:\bitplus` 복사 → bitbot 비밀번호 입력(.secret, 현재 사용자만 읽기) → 방화벽 TCP 9000 허용 →
로그온 자동 시작 작업(`BitPlusWatcher`) 등록 → 지금 시작 → **이 PC의 IP를 출력**합니다.
PC 이름(`-Pc`)은 PC마다 다르게: `접수1`, `접수2`, `접수3`.

## 3. 비트 전광판IP 등록 (0번 항목) — 세 PC의 IP를 모두 목록에 추가

세 접수 PC 모두가 모든 캐스트를 받으므로 한 대가 꺼져 있어도 나머지가 처리합니다. 같은 문서에 세 번 써도(merge) 동선관리는 한 번만 카드를 만듭니다.
접수 PC의 IP는 **고정**(또는 공유기 예약)이어야 합니다. 테스트에 썼던 다른 PC IP는 목록에서 삭제하세요.

## 4. 확인

- 로그: `%LOCALAPPDATA%\bitplus_watcher\watcher.log` 에 `Firebase 로그인 성공`, `BITCast 수신 대기: TCP 9000`
- 비트에서 [환자접수] → 로그에 `전송: 2026-09-09_ocm193429 접수 (… 차트번호 있음)` → 동선관리 3층 대기실에 카드(2~3초)
- 동선관리 상단 pill: `비트 접수1 ●` 초록
- 중지: `schtasks /End /TN BitPlusWatcher` · 삭제: `schtasks /Delete /TN BitPlusWatcher /F`

## 6. 로그 / 상태

- 로그: `%LOCALAPPDATA%\bitplus_watcher\watcher.log` (환자 이름은 기록하지 않음, 차트번호만)
- 동선관리 상단 pill: 초록 = 정상, 노랑 = 비트 접수 창이 닫힘, 회색 = 90초 이상 신호 없음(스크립트 꺼짐·PC 꺼짐)

## 7. 자주 있는 문제

| 증상 | 원인 / 조치 |
|---|---|
| `비밀번호 파일이 없습니다` | 3단계 파일 이름·위치 확인 (`.secret.txt` 아님) |
| `Firebase 로그인 실패 … INVALID_LOGIN_CREDENTIALS` | bitbot 비밀번호 틀림 또는 계정 미생성 |
| pill 이 노랑 | 비트플러스 접수 창이 닫혀 있음 — 접수 메뉴를 다시 열면 됨 |
| pill 이 회색 | 스크립트가 꺼짐 — `schtasks /Run /TN BitPlusWatcher` 또는 PC 재로그온 |
| 환자가 대기 줄에 안 뜸 | 이미 보드에 있는 환자는 안 뜸 / 30분 지난 조회는 자동 제거 / 로그의 `전송:` 줄 확인 |
| 비트 업데이트 후 안 읽힘 | 인적정보 라벨 이름이 바뀐 경우 — `bitplus_probe.ps1` 로 다시 확인 후 스크립트의 `$LABELS` 수정 |

## 8. 보안 설정 (꼭 해두기)

### 8-1. 비밀번호 파일 접근 제한 (각 접수 PC, 한 번)
`.secret` 파일을 현재 Windows 사용자만 읽을 수 있게 합니다. PowerShell에서:
```
icacls "C:\bitplus\bitplus_watcher.secret" /inheritance:r /grant:r "%USERNAME%:R"
```
(경로는 실제 위치로. 관리자·SYSTEM 외 다른 계정은 읽지 못함)

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
    // 그 외(환자·설정 등): 로그인한 직원만 (기존과 동일)
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

### 8-3. 자동 정리
동선관리가 로그인 시 7일 지난 `bitIntake` 문서를 자동 삭제합니다(하루 1회). 로그 파일에는 차트번호만 남고 이름·메모는 기록되지 않습니다.

### 8-4. 남는 위험 (알고 있어야 할 것)
- 동선관리 계정(snu01~30)이 공통 비밀번호인 동안은 누구든 그 비밀번호로 환자 정보를 볼 수 있습니다. 개인별 비밀번호로 바꾸는 것을 권장합니다.
- 접수 PC 자체가 악성코드에 감염되면 `.secret`도 노출될 수 있습니다. bitbot은 '직원' 권한이므로 설정 변경·삭제는 못 하지만 환자 정보 읽기는 가능합니다. 의심되면 동선관리에서 bitbot 비밀번호를 바꾸면 즉시 차단됩니다.
- 비트플러스 업데이트로 화면 구성이 바뀌면 읽기가 멈춥니다(잘못 읽지는 않음). pill 이 회색/노랑이 아닌데 환자가 안 뜨면 `bitplus_probe.ps1` 로 라벨을 다시 확인하세요.

## 동선관리 쪽 동작 요약

- `bitIntake/{날짜_차트번호}` 문서 하나 = 그날 그 환자. 같은 환자를 여러 번 조회해도 문서는 하나(갱신만).
- 자동 생성 → 문서 `status: 자동접수` (여러 화면이 열려 있어도 트랜잭션으로 하나만 만듦). [접수] → 정보가 채워진 접수 창 → 동선 선택 후 저장 → `status: 접수`. [무시] → `status: 무시`.
- 가족관계(가입자성명·관계, 본인 제외)와 최초내원일·전진료일·다음예약일·당일메모는 저장 시 환자 기록(`p.bit`)에 함께 보관.
