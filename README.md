# idblock-auth — 인증 서버 (Keycloak)

크로스허브 서비스들의 로그인을 맡는 인증 서버. Keycloak 26.8.1 + 전용 Postgres를 Docker로 띄우고,
`realm/` 아래 JSON 두 개(직원 `crosshub`, 고객 `idblock`)를 자동 import한다. **realm 설정의 기준은 이 JSON** — 콘솔에서 바꿨으면 export해서 반영한다.

여기에는 인증만 둔다. 업무 데이터·로직은 각 리소스 서버(제휴사 백오피스 BE 등)에 있고,
리소스 서버가 이 서버에 기대는 건 토큰 서명 확인용 공개키(JWKS)뿐이다.
구조 설명: 제휴사 백오피스 BE 레포 `docs/auth-architecture.md`.

| 쓰는 쪽 | realm | client | 비고 |
|---|---|---|---|
| 제휴사 백오피스 FE (Next.js, BFF) | `crosshub` | `poc-backoffice` (confidential) | 직원 로그인 |
| 제휴사 백오피스 BE (Spring) | `crosshub` | `backoffice-api` (이름표, 로그인 불가) | 리소스 서버. 토큰 `aud`·직원 role 이 이 이름으로 들어온다. 계정 발급 때만 `backoffice-admin-api`로 관리 API 호출 |
| TP 앱 (React Native, 아직 없음) / 브라우저 데모 `demo/tp-web` | `idblock` | `tp-app` (public, PKCE) | 고객 로그인·자가 가입. 연동 가이드: `docs/tp-app-integration.md` |
| 제휴사 백오피스 BE — 고객용 API (`GET /api/customer/me`) | `idblock` | `backoffice-api` (이름표) | 고객 토큰의 `aud`. 고객은 role 없음 |

## 실행
```bash
cp .env.example .env          # 값 채우기 (secret은 FE .env와 같은 값)
docker compose up -d          # http://localhost:8080  (관리 콘솔: /admin, 계정은 .env의 KC_ADMIN_*)
bash scripts/reset-password.sh test-partner 'Temp-1234!'   # 테스트 유저 임시 비번 (JSON엔 비번이 없음)
```
처음 한 번 켜 두면 Docker Desktop과 같이 뜬다. 리소스 서버(BE)는 기동할 때 여기서 공개키를 받아오므로 **Keycloak을 먼저 띄운다.**

이 레포는 원래 제휴사 백오피스 BE 레포의 `infra/keycloak/`에 있던 것을 옮긴 것이다(히스토리 포함).
compose 프로젝트 이름을 `keycloak`으로 고정해 두어 그때의 컨테이너·볼륨(Keycloak DB)을 그대로 쓴다.

## 직원 realm `crosshub` (`realm/crosshub-realm.json`)
| 항목 | 값 |
|---|---|
| realm | `crosshub` — Admin Permissions(fine-grained) ON, 자가 가입 OFF, 5회 실패 잠금(최대 15분), 비번 8자+·숫자·특수문자·아이디 금지·최근 3개 재사용 금지 |
| `poc-backoffice` | 백오피스 로그인 client(FE). confidential + PKCE(S256), redirect `http://localhost:3000/*`, 백채널 로그아웃 → FE `/api/auth/keycloak/backchannel-logout`. audience mapper 로 access token `aud` 에 `backoffice-api` 추가, scope mapping 으로 `backoffice-api` role 을 토큰에 담는다 (full scope 꺼짐) |
| `backoffice-api` | BE(리소스 서버) 이름표. bearer-only, 모든 flow 끔 — 토큰을 발급받지 못한다. 직원 client role 이 여기 붙고, BE 는 `aud` 에 이 이름이 있는지로 "우리 토큰인가"를 본다 |
| `backoffice-admin-api` | 계정 발급용 service account. realm-management `manage-users` + `query-clients`, 그리고 fine-grained 권한으로 **`backoffice-api`에만** view·map-roles (다른 client 는 403) |
| client role | `backoffice-api` 의 `crosshub` / `affiliate` / `partner` (백오피스 DB `User.role`과 같은 이름). 토큰에는 `resource_access.backoffice-api.roles` 로 들어온다 |
| 테스트 유저 | `test-crosshub` / `test-federation` / `test-partner` (백오피스 DB `User.loginId`와 같은 값) |

secret은 JSON에 `${POC_BACKOFFICE_CLIENT_SECRET}`처럼 자리표시로만 있고, 실제 값은 `.env`로 넣는다.
서명키·비번 해시는 JSON에 없다 → import 때 Keycloak이 새로 만든다.

## 고객 realm `idblock` (`realm/idblock-realm.json`)
| 항목 | 값 |
|---|---|
| realm | `idblock` — 자가 가입 ON(이메일 = 아이디), 비번 재설정 ON(메일은 SMTP 붙여야 감), 잠금 정책은 crosshub 와 같음, 비번 8자+·숫자. 언어 ko/en/ja |
| 토큰 | access 5분, refresh(SSO 세션) idle 30일·max 90일, refresh 회전(1회 재사용 허용) |
| `tp-app` | TP 앱 로그인 client. **public + PKCE(S256)**, Authorization Code 만, redirect `travelpass://callback` (+ 데모용 `http://localhost:5173/*`, webOrigins 도 — 운영 realm 에서는 뺀다). audience mapper 로 access token `aud` 에 `backoffice-api` |
| `backoffice-api` | BE 이름표(bearer-only). crosshub 의 같은 이름 client 와 짝 — BE 는 두 realm 토큰 모두 `aud=backoffice-api` 로 본다. 고객은 role 없음 |
| 테스트 고객 | `test-customer@example.com`, 비번은 `.env` 의 `IDBLOCK_TEST_CUSTOMER_PASSWORD` (import 때 들어감) |

관리 API 용 service account 는 없다. 고객은 스스로 가입하므로 BE 가 계정을 만들어 줄 일이 없다.
나중에 "idblock 으로 로그인" 을 외부에 제공하는 쪽도 이 realm 이다 (외부 서비스 = 이 realm 의 client 추가).

예정: 소셜 로그인(Identity Provider 추가), SMTP, 운영 주소·HTTPS.

## realm 바꾸는 법
1. 콘솔에서 바꾸거나 JSON을 직접 수정
2. 콘솔에서 바꿨다면 export:
   `docker compose exec keycloak /opt/keycloak/bin/kc.sh export --realm crosshub --users same_file --file /tmp/r.json && docker compose cp keycloak:/tmp/r.json ./r.json`
   → secret·`KeyProvider`·`credentials` 지우고 해당 realm JSON 에 반영 (`--realm idblock` 이면 `realm/idblock-realm.json`)
3. 이미 있는 realm은 `--import-realm`이 덮어쓰지 않는다. 새로 적용하려면 `docker compose down -v` 후 다시 up (Keycloak DB 초기화 — crosshub 테스트 유저 비번은 `scripts/reset-password.sh` 로 다시 넣는다).
   **새 realm 파일을 추가한 것뿐이면** `docker compose up -d --force-recreate keycloak` 으로 충분하다 (있는 realm 은 건드리지 않고 새 realm 만 import)
4. JSON 만 고쳤을 때 검증: 다른 프로젝트 이름·포트로 임시 인스턴스를 띄워 import 가 되는지 본다.
   `docker compose -p kc-verify -f docker-compose.yml -f <ports 를 18080 으로 바꾼 override> up -d` → 확인 → `docker compose -p kc-verify down -v`

## 브라우저 데모 (`demo/tp-web/`)
TP 앱이 생기기 전에 "고객이 idblock 으로 로그인 → BE 고객용 API 호출" 을 보여주는 HTML 한 장. `python3 -m http.server 5173` 으로 띄운다.
BE 는 `CORS_ALLOWED_ORIGINS` 에 `http://localhost:5173` 을 넣고 기동. 자세한 건 `demo/tp-web/README.md`.

## 스크립트 (`scripts/`)
- `reset-password.sh <아이디> '<임시비번>'` — crosshub 테스트 유저 임시 비번 설정
- `kc-test.sh` — crosshub 로컬 검수용 (역할 추가·제거·조회, 강제 로그아웃)
- 둘 다 `crosshub` realm 의 `backoffice-admin-api` 로 동작한다. `idblock` 고객은 관리 콘솔에서 본다

## 주의
- `.env`, `crosshub-realm.export-original.json` 등 원본 export는 git 금지 (`.gitignore`에 있음)
- 운영 전: `start-dev` → `start` + `KC_HOSTNAME` 고정, HTTPS, 환경별 secret 분리, admin 2FA
