# idblock-auth — 인증 서버 (Keycloak)

크로스허브 서비스들의 로그인을 맡는 인증 서버. Keycloak 26.8.1 + 전용 Postgres를 Docker로 띄우고,
`realm/` 아래 JSON을 자동 import한다. **realm 설정의 기준은 이 JSON** — 콘솔에서 바꿨으면 export해서 반영한다.

여기에는 인증만 둔다. 업무 데이터·로직은 각 리소스 서버(제휴사 백오피스 BE 등)에 있고,
리소스 서버가 이 서버에 기대는 건 토큰 서명 확인용 공개키(JWKS)뿐이다.
구조 설명: 제휴사 백오피스 BE 레포 `docs/auth-architecture.md`.

| 쓰는 쪽 | realm | client | 비고 |
|---|---|---|---|
| 제휴사 백오피스 FE (Next.js, BFF) | `crosshub` | `poc-backoffice` (confidential) | 직원 로그인 |
| 제휴사 백오피스 BE (Spring) | `crosshub` | — (리소스 서버, 토큰 검증만) | 계정 발급 때만 `backoffice-admin-api`로 관리 API 호출 |
| TP 앱 (React Native) | 고객 realm (만들 것) | `tp-app` (public, PKCE) | 고객 로그인·자가 가입 |

## 실행
```bash
cp .env.example .env          # 값 채우기 (secret은 FE .env와 같은 값)
docker compose up -d          # http://localhost:8080  (관리 콘솔: /admin, 계정은 .env의 KC_ADMIN_*)
bash scripts/reset-password.sh test-partner 'Temp-1234!'   # 테스트 유저 임시 비번 (JSON엔 비번이 없음)
```
처음 한 번 켜 두면 Docker Desktop과 같이 뜬다. 리소스 서버(BE)는 기동할 때 여기서 공개키를 받아오므로 **Keycloak을 먼저 띄운다.**

이 레포는 원래 제휴사 백오피스 BE 레포의 `infra/keycloak/`에 있던 것을 옮긴 것이다(히스토리 포함).
compose 프로젝트 이름을 `keycloak`으로 고정해 두어 그때의 컨테이너·볼륨(Keycloak DB)을 그대로 쓴다.

## realm 구성 (`realm/crosshub-realm.json`)
| 항목 | 값 |
|---|---|
| realm | `crosshub` — Admin Permissions(fine-grained) ON, 자가 가입 OFF, 5회 실패 잠금(최대 15분), 비번 8자+·숫자·특수문자·아이디 금지·최근 3개 재사용 금지 |
| `poc-backoffice` | 백오피스 로그인 client. confidential + PKCE(S256), redirect `http://localhost:3000/*`, 백채널 로그아웃 → FE `/api/auth/keycloak/backchannel-logout` |
| `backoffice-admin-api` | 계정 발급용 service account. realm-management `manage-users` + `query-clients`, 그리고 fine-grained 권한으로 **`poc-backoffice`에만** view·map-roles (다른 client는 조회 불가) |
| client role | `crosshub` / `affiliate` / `partner` (백오피스 DB `User.role`과 같은 이름) |
| 테스트 유저 | `test-crosshub` / `test-federation` / `test-partner` (백오피스 DB `User.loginId`와 같은 값) |

secret은 JSON에 `${POC_BACKOFFICE_CLIENT_SECRET}`처럼 자리표시로만 있고, 실제 값은 `.env`로 넣는다.
서명키·비번 해시는 JSON에 없다 → import 때 Keycloak이 새로 만든다.

예정: BE 이름표용 client `backoffice-api`(직원 role·aud를 여기로 옮김), 고객 realm + `tp-app` client, 연동 가이드.

## realm 바꾸는 법
1. 콘솔에서 바꾸거나 JSON을 직접 수정
2. 콘솔에서 바꿨다면 export:
   `docker compose exec keycloak /opt/keycloak/bin/kc.sh export --realm crosshub --users same_file --file /tmp/r.json && docker compose cp keycloak:/tmp/r.json ./r.json`
   → secret·`KeyProvider`·`credentials` 지우고 `realm/crosshub-realm.json`에 반영
3. 이미 있는 realm은 `--import-realm`이 덮어쓰지 않는다. 새로 적용하려면 `docker compose down -v` 후 다시 up (Keycloak DB 초기화)

## 스크립트 (`scripts/`)
- `reset-password.sh <아이디> '<임시비번>'` — 테스트 유저 임시 비번 설정
- `kc-test.sh` — 로컬 검수용 (역할 추가·제거·조회, 강제 로그아웃)

## 주의
- `.env`, `crosshub-realm.export-original.json` 등 원본 export는 git 금지 (`.gitignore`에 있음)
- 운영 전: `start-dev` → `start` + `KC_HOSTNAME` 고정, HTTPS, 환경별 secret 분리, admin 2FA
