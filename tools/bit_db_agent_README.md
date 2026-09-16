# 비트 DB 접수 연동 (`bit_db_agent.ps1`) — 설치·운영 안내

비트(Dr.BIT / 비트플러스)의 SQL Server 에서 **읽기 전용 계정으로 접수 상태를 4초마다 SELECT** 해 동선관리 `bitIntake` 문서로 올립니다.
캐스트(전광판 TCP 9000) + 접수 창 화면 읽기(`bitplus_watcher.ps1` 채널 ①②)를 대체하는 방식이며, 파트너 병원 문서(`기술문서_유차트_접수데이터_수집.md`)의 방법을 우리 환경에 맞춘 것입니다.
진료실 처방 목록(채널 ③, 외래진료실 창 → `bitNote`)은 이 스크립트가 다루지 않으므로 진료실 PC 의 `bitplus_watcher.ps1` 은 그대로 둡니다.

## 왜 DB 방식인가

| | 캐스트 + 화면 읽기(현행) | DB 읽기(이 스크립트) |
|---|---|---|
| 차트번호 | 캐스트에 없음 → 이름으로 인적정보 캐시 매칭(동명이인 문제) | 행에 바로 있음 |
| 접수 취소·수정 | `취소→접수` 쌍을 6초 유예로 추정 | 상태 코드 변화로 확정 |
| 예약 환자 도착 | 캐스트 순서 해석에 의존 | `WR → WN` 전환 + 도착 시각 갱신 |
| 설치 위치 | 접수 PC 3대 + 전광판 IP 등록 + 방화벽 9000 | 관리 PC 1대(192.168.0.25), 서버에 설치 없음 |
| 비트 업데이트 | 화면 라벨이 바뀌면 멈춤 | 테이블 구조는 수년째 동일 |

## 환경 (2026-09-16 확인)

- DB 서버 `192.168.0.250`, SQL Server 2019, 기본 인스턴스, TCP 1433, 혼합 모드. 데이터베이스 `drbitpack`.
- 읽기 전용 로그인 `dongseon_ro` (db_datareader + INSERT/UPDATE/DELETE/EXECUTE DENY). `tools/bit_db_check.ps1 -TestLogin` 으로 쓰기 거부 확인 가능.
- 테이블·컬럼은 파트너 문서와 같고, `DtlMst` 만 이름 컬럼이 `DtlCodNam` (파트너: `DtlNam`). 접수 상태 코드(COMSTT) 36개도 동일.
- `OcmNum` 은 char(10) **앞 공백** 패딩(`'    182357'`) → 숫자만 남겨 문서 id `{날짜}_ocm182357` 로 만든다(캐스트 채널과 같은 id → 같은 문서에 merge).
- 하루 80~100행. 4초마다 전체를 `NOLOCK` + `READ UNCOMMITTED` + `LOCK_TIMEOUT 3000` 으로 읽으므로 비트에 영향 없음. 연결은 폴링마다 열고 닫음.

## 상태 코드 → 동선관리 command

| `OcmComStt` | 뜻 | 보내는 것 |
|---|---|---|
| `WN NN WC WT SN SC ST` | 접수·대기 | `command 2 접수`, 첫 진입 때 `registered=true` → 동선관리가 3층 대기실 카드 자동 생성 |
| `HN HC HT` | 보류 | `13 보류` |
| `TN FN TC FC TT` | 진료 완료(수납 대기) | `7 수납대기` (뒤늦게 카드를 만들면 3층 수납에서 시작) |
| `PN PC PT` | 수납 완료 | `8 수납완료` → 동선관리가 카드를 3층 수납 경유로 내보냄 |
| 수납 완료 → 다시 접수/진료 완료 계열 | 수납 취소 | `10 수납취소` → 완료 목록에서 카드 복귀 |
| `CN` | 접수 취소 | `command 3, cancelled=true` → 손대지 않은 카드는 6초 뒤 제거 |
| `WR NR HR TR FR PR CR` | 예약만(미도착) | 보내지 않음 (도착하면 같은 행이 `WN` 으로 바뀜) |
| `O* V*` | 입원 | 보내지 않음 |

문서 필드는 `bitplus_watcher.ps1` 과 같은 이름을 씁니다: `name mrn rrn7 doctor hourMin command commandName registered registeredAt cancelled seenAt lastSeenAt event eventAt` + DB 전용 `src='db' stt dep firstVisit nextResv`.
`rrn7` 은 주민번호 앞 7자리(`YYMMDD-S`)만 만들고, 뒷자리·전화·주소는 읽지 않습니다. 로그에는 차트번호만 남고 이름은 기록하지 않습니다.

## 새 접수 판정 (파트너 문서 6절과 동일)

- 상태 파일 `%LOCALAPPDATA%\bit_db_agent\state.json` = `{ date, seen: {접수번호: 상태}, sent: {접수번호: 마지막 command} }`.
- 상태가 접수 계열이고 `sent` 에 없으면 전송. **첫 폴링(시작 직후)은 보내지 않고 `sent` 에만 넣는다**(재시작 때 오늘 접수분 중복 방지). 같은 날 재시작하면 상태 파일을 그대로 이어 쓴다.
- 접수 시각이 `지금 + 5분` 보다 미래면 보류(사전 등록분) — 그 시각이 되면 보냄.
- 이미 보낸 접수의 상태가 바뀌면(수납대기·수납완료·수납취소·취소) 그 command 만 갱신. 취소 뒤 재접수는 `registered=true` 를 다시 세워 자동 생성 대상으로.
- 날짜가 바뀌면 상태 초기화.

## 설치 (관리 PC 192.168.0.25, 1회)

1. `tools/bit_db_agent.ps1` 을 `C:\dongseon_agent\` 로 복사.
2. 같은 폴더에 비밀번호 파일 두 개(첫 줄만):
   - `bit_db_agent.sql.secret` — `dongseon_ro` 비밀번호
   - `bit_db_agent.secret` — 동선관리 `bitbot` 계정 비밀번호 (`bitplus_watcher.secret` 과 같은 값)
   ```
   icacls C:\dongseon_agent\*.secret /inheritance:r /grant:r "%USERNAME%:M"
   ```
3. 먼저 **전송 없이** 하루 돌려 본다:
   ```
   powershell -ExecutionPolicy Bypass -File C:\dongseon_agent\bit_db_agent.ps1 -DryRun
   ```
   로그 `%LOCALAPPDATA%\bit_db_agent\agent.log` 에 `DRY 전송: 2026-…_ocm194430 접수 (이름 3자, 차트번호 있음, WN, 접수 14:06)` 줄이 비트 접수 뒤 4초 안에 찍히는지, 캐스트 채널의 `bitIntake` 문서 id 와 같은지 확인.
4. 실전 (캐스트 채널과 **병행** — 같은 문서에 merge 되므로 카드는 하나만 생긴다):
   ```
   powershell -ExecutionPolicy Bypass -File C:\dongseon_agent\bit_db_agent.ps1
   ```
   로그온 자동 시작은 `bitplus_install.ps1` 과 같은 방식의 예약 작업으로 등록(작업 이름 `BitDbAgent`, 실행 시간 제한 없음, 실패 시 1분 뒤 재시작):
   ```
   $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -WindowStyle Hidden -File C:\dongseon_agent\bit_db_agent.ps1'
   $t = New-ScheduledTaskTrigger -AtLogOn
   $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
   Register-ScheduledTask -TaskName BitDbAgent -Action $a -Trigger $t -Settings $s -Force
   Start-ScheduledTask BitDbAgent
   ```
5. 동선관리 상단 pill 에 `비트 DB ●` 가 초록으로 보이면 정상(하트비트 `bitStatus/_all.DB`, `bitOpen` = DB 연결 상태). 5분마다 갱신.

## 시험용 옵션

- `-Cycles 1 -SendExistingOnStart -DryRun -StateDir <임시폴더>` — 오늘 접수분 전체를 한 번 판정해 보고 종료(위 dry-run 확인용).
- `-PollSec`, `-LeadMin`, `-HeartbeatSec`, `-Pc` 로 주기·이름 조정.

## 남은 일

- 캐스트 채널과 며칠 병행한 뒤 접수 PC 의 `bitplus_watcher.ps1` 채널 ①② 를 끄고(전광판 IP 목록에서 접수 PC 제거) 진료실 PC 만 남긴다.
- 접수메모(당일·연속)·특이사항이 DB 어느 컬럼에 있는지 확인(`OcmCstCmt/OcmSpcCmt` 는 비어 있음, `PbsRefCmt` 는 대부분 채워져 있어 용도 확인 필요). 확인되면 `memoToday/memoCont` 도 보낼 수 있다.
- 진료실 처방(슬립)은 `EmrInf`(약 256만 행) 에 있을 가능성이 큼 → 구조 확인 뒤 채널 ③ 도 DB 로 옮길 수 있음.
