# crosshub Keycloak (poc-backoffice 로그인)

(BE 레포 `infra/keycloak/`) Keycloak 26.8.1 + Postgres를 Docker로 띄우고, `realm/crosshub-realm.json`을 자동 import한다.
**realm 설정의 기준은 이 JSON** — 콘솔에서 바꿨으면 export해서 이 파일에 반영한다.

## 실행
```bash
cp .env.example .env          # 값 채우기 (secret은 FE .env와 같은 값)
docker compose up -d          # http://localhost:8080  (관리 콘솔: /admin, 계정은 .env의 KC_ADMIN_*)
bash scripts/reset-password.sh test-partner 'Temp-1234!'   # 테스트 유저 임시 비번 (JSON엔 비번이 없음)
```

## realm 구성 (`realm/crosshub-realm.json`)
| 항목 | 값 |
|---|---|
| realm | `crosshub` — 자가 가입 OFF, 5회 실패 잠금(최대 15분), 비번 8자+·숫자·특수문자·아이디 금지·최근 3개 재사용 금지 |
| `poc-backoffice` | 백오피스 로그인 client. confidential + PKCE(S256), redirect `http://localhost:3000/*` |
| `backoffice-admin-api` | 계정 발급용 service account. realm-management `manage-users`, `view-clients` |
| client role | `crosshub` / `affiliate` / `partner` (서비스 DB `User.role`과 같은 이름) |
| 테스트 유저 | `test-crosshub` / `test-federation` / `test-partner` (DB `User.loginId`와 같은 값) |

secret은 JSON에 `${POC_BACKOFFICE_CLIENT_SECRET}`처럼 자리표시로만 있고, 실제 값은 `.env`로 넣는다.
서명키·비번 해시는 JSON에 없다 → import 때 Keycloak이 새로 만든다.

## realm 바꾸는 법
1. 콘솔에서 바꾸거나 JSON을 직접 수정
2. 콘솔에서 바꿨다면 export:
   `docker compose exec keycloak /opt/keycloak/bin/kc.sh export --realm crosshub --users same_file --file /tmp/r.json && docker compose cp keycloak:/tmp/r.json ./r.json`
   → secret·`KeyProvider`·`credentials` 지우고 `realm/crosshub-realm.json`에 반영
3. 이미 있는 realm은 `--import-realm`이 덮어쓰지 않는다. 새로 적용하려면 `docker compose down -v` 후 다시 up (Keycloak DB 초기화)

## 주의
- `.env`, `crosshub-realm.export-original.json` 등 원본 export는 git 금지 (`.gitignore`에 있음)
- 운영 전: `start-dev` → `start` + `KC_HOSTNAME` 고정, HTTPS, 환경별 secret 분리, admin 2FA
