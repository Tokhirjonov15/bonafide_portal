# BONAFIDE 통합 포털 (bonafide-portal)

원내 통합 포털 — 재고관리 · 동선관리 · JS PACS를 한 곳에서 엽니다.

## 폴더 구조

```
bonafide_portal/
├── public/            ← 실제 서비스되는 파일 (여기 안의 내용만 웹에 공개됩니다)
│   ├── index.html     포털 (3개 선택 화면)
│   ├── jaego/         재고관리 (자체 개발 v0.1)
│   ├── dongseon/      동선관리 (준비 중)
│   └── jspacs/        JS PACS 뷰어
├── wrangler.jsonc     Cloudflare 배포 설정
├── DEMO-START.bat     로컬 데모 실행 (python 필요)
└── README-DEPLOY.md
```

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

`DEMO-START.bat` 실행 → `http://localhost:8080/`
(폴더 선택 등 브라우저 기능이 정상 동작하려면 파일 직접 열기보다 이 방법을 권장)

## 다음 단계

- [ ] D1 데이터베이스 연결 — 재고 데이터를 모든 기기가 공유
- [ ] 직원 로그인 (통합 계정)
- [ ] 동선관리 구축 (타 지점 시스템 검토 후)
