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
| `PN PC PT` | 수납 완료 | `8 수납완료` → 동선관리가 카드를 3층 수납으로 옮기고 **'비트 수납완료' 초록 표시**. 내보내기는 직원이 확인 후 [내보내기] (직원이 비트에서 수납완료를 잘못 누르는 일이 있어 2026-09-16 자동 내보내기 중단) |
| 수납 완료 → 다시 접수/진료 완료 계열 | 수납 취소 | `10 수납취소` → 카드가 보드에 있으면 표시 해제, 이미 내보냈으면 완료 목록에서 카드 복귀 |
| `CN` | 접수 취소 | `command 3, cancelled=true` → 손대지 않은 카드는 6초 뒤 제거 |
| `WR NR HR TR FR PR CR` | 예약만(미도착) | 보내지 않음 (도착하면 같은 행이 `WN` 으로 바뀜) |
| `O* V*` | 입원 | 보내지 않음 |

문서 필드는 `bitplus_watcher.ps1` 과 같은 이름을 씁니다: `name mrn rrn7 doctor hourMin command commandName registered registeredAt cancelled seenAt lastSeenAt event eventAt` + DB 전용 `src='db' stt dep firstVisit nextResv`.
`rrn7` 은 주민번호 앞 7자리(`YYMMDD-S`)만 만들고, 뒷자리·전화·주소는 읽지 않습니다. 로그에는 차트번호만 남고 이름은 기록하지 않습니다.

## 동선관리 쪽 처리 (2026-09-17)

- `src='db'` 문서는 30분 TTL 없이 그날 문서 전부를 카드 대상으로 본다(상태는 에이전트가 계속 맞춰 줌). 화면을 늦게 열어도 그날 온 환자 전원이 카드와 `#번호`를 받아 통계에 잡힌다.
- 이미 `수납완료(8)` 인 환자(화면이 닫혀 있는 사이 왔다 간 환자)는 3층 수납에 '비트 수납완료' 초록 카드로 만들어지고, 직원이 [내보내기]로 정리한다.
- 여러 명을 한꺼번에 만들 때는 접수 시각(`hourMin`) 순으로 한 건씩 만들어 `#번호`가 도착 순서를 따른다.
- 그래도 아침에는 동선관리를 한 화면에 열어 두는 것이 가장 정확하다(번호가 실시간으로 붙고, 진료실 처방·슬립도 바로 보임).

## 새 접수 판정 (파트너 문서 6절과 동일)

- 상태 파일 `%LOCALAPPDATA%\bit_db_agent\state.json` = `{ date, seen: {접수번호: 상태}, sent: {접수번호: 마지막 command} }`.
- 상태가 접수 계열이고 `sent` 에 없으면 전송. **첫 폴링(시작 직후)은 보내지 않고 `sent` 에만 넣는다**(재시작 때 오늘 접수분 중복 방지). 같은 날 재시작하면 상태 파일을 그대로 이어 쓴다.
- 접수 시각이 `지금 + 5분` 보다 미래면 보류(사전 등록분) — 그 시각이 되면 보냄.
- 스냅샷의 예외(`-RecentMin`, 기본 30분): 시작 시점에 이미 접수돼 있어도 **최근 30분 안에 접수됐고 수납 전**이면 보낸다. 아침에 에이전트가 켜지기 전(PC 부팅 전) 접수된 환자가 빠지지 않도록(2026-09-17 아침 3명이 빠졌던 사례). 같은 문서 id 로 merge 되므로 이미 카드가 있으면 동선관리가 무시한다.
- 이미 보낸 접수의 상태가 바뀌면(수납대기·수납완료·수납취소·취소) 그 command 만 갱신. 취소 뒤 재접수는 `registered=true` 를 다시 세워 자동 생성 대상으로.
- 날짜가 바뀌면 상태 초기화.

## 어디에 설치하나 — 접수 PC 3대 (우선순위 + 자동 인계)

관리 PC(192.168.0.25)는 주 5일 8시간만 켜져 있어 병원 운영 시간(매일 12시간)을 덮지 못한다. 그래서 에이전트는 **접수 PC 에 함께 설치**한다(접수 PC 는 진료 중 항상 켜져 있고 비트 DB 서버에 닿는다).
- 여러 PC 의 에이전트가 모두 4초마다 DB 를 읽되, **우선순위(`-Priority`, 큰 수가 우선)가 가장 높은 정상 에이전트만 Firestore 에 쓴다.** 나머지는 대기하며 상태만 따라간다.
- 서로의 상태는 LAN 상태 포트 **TCP 9001** 로 확인한다(Firestore 비용 없음). 에이전트는 최근 30초 안에 DB 를 성공적으로 읽었을 때만 `OK <우선순위> <PC> <leader|standby>` 로 답하고, 아니면 `DOWN`.
- 전송 담당 PC 가 꺼지거나 DB 에 못 닿으면 다음 순위가 **4~8초 안에** 이어받는다(같은 DB 스냅샷을 보고 있으므로 빠진 접수 없음). 돌아오면 다시 담당이 된다.
- 같은 PC 의 감시 스크립트(`bitplus_watcher.ps1` v3.5)는 캐스트가 오면 9001 에 물어 보고, 정상인 에이전트가 있으면 `bitIntake` 에 쓰지 않는다. 에이전트가 모두 죽으면 캐스트로 직접 쓴다 → 예비 경로 유지.
- 관리 PC 의 에이전트는 `-Priority 0` 으로 두면 켜져 있는 동안 추가 예비가 되고, 꺼져도 아무 영향이 없다.
- **우선순위는 PC 마다 다르게** 준다(3·2·1). 같으면 PC 이름(`DB-접수1` < `DB-접수2`)이 앞선 쪽이 담당이 되지만, 의도가 드러나지 않으니 피할 것.
- 상태 응답의 5번째 칸에 **자기가 아는 동료 IP** 를 실어 보내므로, 설치 때 `-Peers` 를 빠뜨리거나 틀려도 서로 물어 보는 동안 목록이 채워진다(로그 `동료 목록에 추가`). 그래도 설치 명령의 `-Peers` 는 정확히 적는 것이 좋다 — 목록이 불완전한 동안 담당이 둘이 될 수 있다(2026-09-16 실제 사례: 세 PC 에 같은 `-Priority 3 -Peers` 를 넣어 접수1·접수2 가 동시에 전송).

## 설치 (접수 PC 마다 1회, 관리자 PowerShell)

`tools/bitplus_watcher.ps1`·`tools/bit_db_agent.ps1`·`tools/bitplus_install.ps1` 을 같은 폴더(USB 등)에 두고, 다른 두 에이전트 PC 의 IP 를 `-Peers` 로 넘긴다:
```
powershell -ExecutionPolicy Bypass -File bitplus_install.ps1 -Pc 접수1 -Agent -Priority 3 -Peers 192.168.0.44,192.168.0.57
powershell -ExecutionPolicy Bypass -File bitplus_install.ps1 -Pc 접수2 -Agent -Priority 2 -Peers 192.168.0.16,192.168.0.57
powershell -ExecutionPolicy Bypass -File bitplus_install.ps1 -Pc 접수3 -Agent -Priority 1 -Peers 192.168.0.16,192.168.0.44
```
(IP 는 동선관리 pill 의 각 PC 항목에서 확인. 2026-09-16 기준 접수1=192.168.0.16, 접수2=192.168.0.44, 접수3=192.168.0.57.)
설치 스크립트가: 감시 스크립트 갱신 → (있으면 그대로) bitbot 비밀번호 → `bitplus_peers.txt` 저장 → 에이전트 복사 → **`dongseon_ro` 비밀번호 입력**(`bit_db_agent.sql.secret`) → 방화벽 9000·9001 → 작업 `BitPlusWatcher`·`BitDbAgent` 등록·시작.
에이전트는 bitbot 비밀번호를 감시 스크립트의 `bitplus_watcher.secret` 에서 같이 읽는다.

확인:
- 동선관리 상단 pill 에 `DB-접수1`·`DB-접수2`·`DB-접수3` 이 초록. 툴팁의 `leader` 가 하나만 `true`.
- 에이전트 로그 `%LOCALAPPDATA%\bit_db_agent\agent.log`: 담당 PC 는 `전송: …`, 나머지는 `→ 대기(standby): DB-접수1@192.168.0.16(우선순위 3) 가 전송 담당`.
- 감시 로그 `%LOCALAPPDATA%\bitplus_watcher\watcher.log`: `DB 에이전트 정상(…) → 캐스트는 bitIntake 에 쓰지 않음`, 접수 때 `cast 접수 … → 생략 (15초 뒤 확인)` 다음 `확인: … 에이전트가 전송함`.
- 전송 담당 PC 를 꺼 보면 다른 PC 로그에 몇 초 안에 `→ 전송 담당(leader)` 가 찍힌다.

## 시험용 옵션

- `-DryRun` — Firestore 에 쓰지 않고 로그만. `-Cycles N` — N번 조회 뒤 종료. `-SendExistingOnStart` — 시작 스냅샷을 보내지 않는 대신 전부 보냄. `-StateDir <폴더>` — 상태·로그 위치.
- `-HealthPort`(기본 9001)·`-PeerPort`(시험용: 한 PC 에서 두 인스턴스를 다른 포트로 띄워 우선순위를 시험할 때) · `-PollSec`, `-LeadMin`, `-HeartbeatSec`, `-Pc`.

## 남은 일

- 캐스트 채널과 며칠 병행한 뒤 접수 PC 의 `bitplus_watcher.ps1` 채널 ①② 를 끄고(전광판 IP 목록에서 접수 PC 제거) 진료실 PC 만 남긴다.
- 접수메모(당일·연속)·특이사항이 DB 어느 컬럼에 있는지 확인(`OcmCstCmt/OcmSpcCmt` 는 비어 있음, `PbsRefCmt` 는 대부분 채워져 있어 용도 확인 필요). 확인되면 `memoToday/memoCont` 도 보낼 수 있다.
- 진료실 처방(슬립)은 `EmrInf`(약 256만 행) 에 있을 가능성이 큼 → 구조 확인 뒤 채널 ③ 도 DB 로 옮길 수 있음.
