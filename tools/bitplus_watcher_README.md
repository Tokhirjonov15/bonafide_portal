# 비트플러스 접수 연동 — 설치 안내

접수 PC에서 `bitplus_watcher.ps1`이 비트플러스 **접수 창의 인적정보 패널**을 2초마다 읽어
동선관리(Firebase `bitIntake`)에 올립니다. 동선관리 보드 위에 **비트 접수 대기** 줄이 나타나고,
직원이 **[접수]**를 눌러야 환자 카드가 만들어집니다. 자동으로 만들지 않습니다.

- 비트플러스에는 아무것도 입력·클릭하지 않습니다 (읽기만).
- 읽는 항목: 차트번호, 이름, 생년월일+성별(주민번호 앞 7자리만), 전진료실/담당의, 전진료일, 다음예약일,
  가입자성명·관계(가족관계), 최초내원일, 보험유형, 초/재진, 접수메모(당일·연속).
- 읽지 않는 항목: 주민번호 뒷자리, 전화번호, 주소, 이메일.
- 설치 프로그램 없음. Windows 10/11 기본 PowerShell만 사용. 비용 없음.

## 1. 동선관리에 bitbot 계정 만들기 (한 번만, admin 계정으로)

동선관리 → 계정 관리 → **계정 추가**: 아이디 `bitbot`, 권한 `직원`, 비밀번호는 8자 이상 (영문+숫자).
이 비밀번호를 아래 3단계의 `.secret` 파일에 적습니다. 세 PC 모두 같은 계정을 씁니다.

## 2. 파일 복사 (각 접수 PC)

```
C:\bitplus\bitplus_watcher.ps1
```
(레포 `tools/bitplus_watcher.ps1` 그대로 복사)

## 3. 비밀번호 파일

메모장으로 `C:\bitplus\bitplus_watcher.secret` 을 만들고 **첫 줄에 bitbot 비밀번호만** 적고 저장.
(확장자가 `.secret.txt` 가 되지 않도록 "모든 파일"로 저장)

## 4. 테스트 실행 (창이 보이는 상태)

비트플러스 접수 창을 연 뒤 PowerShell에서:
```
powershell -ExecutionPolicy Bypass -File C:\bitplus\bitplus_watcher.ps1 -Pc 접수1
```
`Firebase 로그인 성공` 이 뜨고, 비트에서 환자를 조회하면 `전송: 2026-09-08_28235 ...` 줄이 찍힙니다.
동선관리 상단에 `비트 접수1 ●` (초록) 이 보이고, 보드 위에 **비트 접수 대기** 줄에 환자가 나타나면 성공.
PC 이름(`-Pc`)은 PC마다 다르게: `접수1`, `접수2`, `접수3`.

## 5. 자동 시작 등록 (로그온 시, 창 숨김)

PowerShell(관리자 아님, 그 PC의 접수 계정으로) 에서 한 줄:
```
schtasks /Create /TN "BitPlusWatcher" /SC ONLOGON /TR "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\bitplus\bitplus_watcher.ps1 -Pc 접수1" /F
```
- 지금 바로 시작: `schtasks /Run /TN BitPlusWatcher`
- 중지: `schtasks /End /TN BitPlusWatcher`
- 삭제: `schtasks /Delete /TN BitPlusWatcher /F`

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

## 동선관리 쪽 동작 요약

- `bitIntake/{날짜_차트번호}` 문서 하나 = 그날 그 환자. 같은 환자를 여러 번 조회해도 문서는 하나(갱신만).
- [접수] → 정보가 채워진 접수 창 → 동선 선택 후 저장 → 문서 `status: 접수`. [무시] → `status: 무시`.
- 가족관계(가입자성명·관계, 본인 제외)와 최초내원일·전진료일·다음예약일·당일메모는 저장 시 환자 기록(`p.bit`)에 함께 보관.
