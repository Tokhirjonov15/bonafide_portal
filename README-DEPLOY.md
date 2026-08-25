# BONAFIDE 통합 포털 (bonafide-portal)

원내 통합 포털 — 재고관리 · 동선관리 · JS PACS를 한 곳에서 엽니다.

## 폴더 구조

```
bonafide_portal/
├── public/            ← 실제 서비스되는 파일 (여기 안의 내용만 웹에 공개됩니다)
│   ├── index.html     포털 (3개 선택 화면)
│   ├── jaego/         재고관리 (자체 개발 v0.2 — 클라우드)
│   ├── dongseon/      동선관리 (준비 중)
│   └── jspacs/        JS PACS 뷰어
├── src/index.js       API (/api/* — 재고 데이터 처리)
├── wrangler.jsonc     Cloudflare 배포 설정 (D1 연결 포함)
├── DEMO-START.bat     로컬 데모 실행 (python 필요)
└── README-DEPLOY.md
```

## 데이터베이스 (D1)

재고 데이터는 Cloudflare D1 `bonafide-db`에 저장됩니다. 표(products·movements)는
첫 요청 때 자동으로 생성되므로 수동 SQL 실행이 필요 없습니다.

**재고 수량은 저장하지 않습니다** — 입출고 기록의 합계로 서버가 계산합니다(감사 추적).

### 로그인 (구글 계정) — Cloudflare Access

직원은 **구글 계정으로 로그인**합니다. 별도 회원가입·비밀번호가 없고, 코드도 필요 없습니다.
Cloudflare Zero Trust의 Access가 신원을 확인한 뒤 Worker에 이메일을 전달하고,
앱은 그 계정을 입출고 담당자로 자동 기록합니다.

**설정 순서 (관리자 1회):**

1. Cloudflare 대시보드 → **Zero Trust** (처음이면 팀 이름 지정 + Free 요금제 선택)
2. **Settings → Authentication → Login methods → Add new → Google** → 저장
   (기본 제공 방식이라 별도 구글 개발자 설정 없이 바로 사용 가능)
3. **Access → Applications → Add an application → Self-hosted**
   - Application name: `BONAFIDE 통합 포털`
   - Domain: `bonafide-portal.seoulgijibae.workers.dev`
4. **Policy**: Action `Allow`, Include → **Emails** 에 직원 구글 계정을 넣거나,
   회사 도메인을 쓰면 **Emails ending in** `@도메인` 으로 한 번에 허용
   ※ 반드시 **본인 계정을 먼저** 넣으세요(잠김 방지)
5. 저장 → 이후 사이트 접속 시 구글 로그인 화면이 먼저 뜹니다

로그아웃 주소: `/cdn-cgi/access/logout`

### 임시 암호 보호 (Access를 켜기 전에만)

Worker → **Settings → Variables and Secrets → Add** 에 `APP_KEY` 를 등록하면
그 암호를 입력한 사람만 재고 데이터를 쓸 수 있습니다.
Access를 켠 뒤에는 무시되므로 그대로 두거나 삭제해도 됩니다.

### API 엔드포인트

| 주소 | 용도 |
|---|---|
| `GET /api/state` | 품목 목록(재고 포함) + 최근 기록 300건 |
| `POST /api/product` | 품목 추가·수정 |
| `POST /api/product/delete` | 품목 삭제 |
| `POST /api/movement` | 입고·출고 등록 |
| `POST /api/import` | CSV 일괄 가져오기 |
| `GET /api/backup` · `POST /api/restore` | 전체 백업·복원 |

`public/` 밖의 파일(설정·문서)은 웹에 공개되지 않습니다.

## Cloudflare 배포

새 Cloudflare 대시보드에는 "Pages" 생성 메뉴가 없고 **Workers**로 통합되었습니다.
정적 사이트도 Workers로 배포하며, 설정은 `wrangler.jsonc`가 담당합니다.

**처음 연결할 때 (1회):**

1. **Workers & Pages → Create application → Workers → Import a repository**
2. 저장소 `Tokhirjonov15/bonafide_portal` 선택
3. 설정:
   - Project name: `bonafide-portal`
   - Build command: **비워둠**
   - Deploy command: `npx wrangler deploy`
4. **Deploy** → `https://bonafide-portal.<계정>.workers.dev` 발급

**그 다음부터:** VS Code에서 Commit → Sync Changes 하면 자동으로 재배포됩니다.

## 로컬에서 확인

`DEMO-START.bat` → `http://localhost:8080/` — 포털과 JS PACS 확인용입니다.
**재고관리는 API가 필요하므로 로컬 데모에서는 동작하지 않습니다.**
재고관리는 실제 주소(`bonafide-portal.seoulgijibae.workers.dev/jaego/`)에서 확인하거나,
`npx wrangler dev` 로 API까지 함께 띄워서 확인하세요.

## 다음 단계

- [x] D1 데이터베이스 연결 — 재고 데이터를 모든 기기가 공유
- [ ] Cloudflare Access + 구글 로그인 켜기
- [ ] 관리자/직원 역할 구분 (users 표 — 로그인 이메일 기준)
- [x] 스캔 모드 (입고/출고) · 유통기한(로트) · 단가 · 거래처
- [ ] 기존 재고 앱 데이터 CSV로 가져오기
- [ ] 발주(주문) 관리 · 소비량 통계

### CSV 열 순서 (10열)

`품목명, 카테고리, 보관위치, 단위, 바코드, 최소수량, 현재수량, 단가, 거래처, 유통기한`
- [ ] 직원 로그인 (통합 계정)
- [ ] 동선관리 구축 (타 지점 시스템 검토 후)
