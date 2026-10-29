# keycloak-auth — 인증 서버 (Keycloak)

크로스허브 서비스들의 로그인을 맡는 인증 서버. Keycloak 26.8.1 + 전용 Postgres를 Docker로 띄우고,
`realm/` 아래 JSON 두 개(백오피스 `tp-office`, 고객 `tp`)를 자동 import한다. **realm 설정의 기준은 이 JSON** — 콘솔에서 바꿨으면 export해서 반영한다.

여기에는 인증만 둔다. 업무 데이터·로직은 각 리소스 서버(제휴사 백오피스 BE 등)에 있고,
리소스 서버가 이 서버에 기대는 건 토큰 서명 확인용 공개키(JWKS)뿐이다.
구조 설명: 제휴사 백오피스 BE 레포 `docs/auth-architecture.md`.

| 쓰는 쪽 | realm | client | 비고 |
|---|---|---|---|
| 제휴사 백오피스 FE (Next.js, BFF) | `tp-office` | `tp-office-merchant-web` (confidential) | 크로스허브·연맹·업체 로그인 |
| 제휴사 백오피스 BE (Spring) | `tp-office` | `tp-office-merchant-api` (이름표, 로그인 불가) | 리소스 서버. 토큰 `aud`·role 이 이 이름으로 들어온다. 계정 발급 때만 `tp-office-merchant-svc`로 관리 API 호출 |
| TP 앱 (React Native, 아직 없음) / 브라우저 데모 `demo/tp-web` | `tp` | `tp-customer-app` (public, PKCE) | 고객 로그인·자가 가입. 연동 가이드: `docs/tp-customer-app-integration.md` |
| 제휴사 백오피스 BE — 고객용 API (`GET /api/customer/me`) | `tp` | `tp-office-merchant-api` (이름표) | 고객 토큰의 `aud`. 고객은 role 없음 |

## 실행
```bash
cp .env.example .env          # 값 채우기 (secret은 FE .env와 같은 값)
docker compose up -d --wait   # http://localhost:8080  (관리 콘솔: /admin, 계정은 .env의 KC_BOOTSTRAP_ADMIN_*). --wait 는 realm import 까지 기다린다
bash scripts/reset-password.sh test-partner 'Temp-1234!'   # 테스트 유저 임시 비번 (JSON엔 비번이 없음)
```
처음 한 번 켜 두면 Docker Desktop과 같이 뜬다. BE DB·FE Redis 등 로컬 컨테이너 전체는 BE 레포 `docs/local-infra.md`. 리소스 서버(BE)는 기동할 때 여기서 공개키를 받아오므로 **Keycloak을 먼저 띄운다.**

**2026-10-29 이름 변경을 받을 때**: client `tp-office-partner-*`→`tp-office-merchant-*`, `tp-app`→`tp-customer-app`, 그룹 `/crosshub`·`/affiliate`·`/partner`·`/tp-office` → `/merchant-crosshub`·`/merchant-affiliate`·`/merchant-partner`·`/app-office`. `.env` 의 `TP_OFFICE_PARTNER_*` 를 `TP_OFFICE_MERCHANT_*` 로 바꾸고 `docker compose down -v` 후 up, 비번 다시 넣기. BE·FE `.env` 의 client 이름도 같이.

**옛 realm(`crosshub`·`idblock`)으로 떠 있던 로컬에서 옮길 때**: realm 이름이 바뀌어 `--import-realm` 이 새 realm 을 만들기만 하고 옛 realm 은 남는다. 테스트 유저뿐이라 `docker compose down -v` 후 다시 up 하고 비번을 다시 넣는다.
`.env` 는 `.env.example` 대로 `BACKCHANNEL_LOGOUT_URL` → `TP_OFFICE_MERCHANT_WEB_BACKCHANNEL_LOGOUT_URL`, `IDBLOCK_TEST_CUSTOMER_PASSWORD` → `TP_TEST_CUSTOMER_PASSWORD` 로 이름을 바꾸고 `TP_OFFICE_MERCHANT_WEB_URL` 을 추가한다.
BE·FE `.env` 의 issuer 도 같이 바꾼다 (`…/realms/tp-office`, `…/realms/tp`).

이 레포는 원래 제휴사 백오피스 BE 레포의 `infra/keycloak/`에 있던 것을 옮긴 것이다(히스토리 포함).
compose 프로젝트 이름을 `keycloak`으로 고정해 두어 그때의 컨테이너·볼륨(Keycloak DB)을 그대로 쓴다.

## 백오피스 realm `tp-office` (`realm/tp-office-realm.json`)
백오피스를 쓰는 사람 전부(크로스허브 직원·연맹·업체). merchant 백오피스(상품·제휴사)와 app 백오피스(앱 운영: 회원·KYC·카드·월렛)가 이 realm 을 같이 쓴다 — 설계: `docs/tp-office-realm-plan.md`.
app 백오피스 쪽 client·출입 role·그룹은 **Keycloak 쪽 설정까지 들어가 있다**(2026-10-29). app 백오피스 FE·BE 가 아직 Keycloak 에 붙지 않아 주소·secret 은 `.env` 의 로컬 임시값이다.

| 항목 | 값 |
|---|---|
| realm | `tp-office` (TP Office) — Admin Permissions(fine-grained V2) ON, 자가 가입 OFF, 5회 실패 잠금(최대 15분), 비번 8자+·숫자·특수문자·아이디 금지·최근 3개 재사용 금지. 로그인 event·admin event ON(보존 30일) |
| `tp-office-merchant-web` | 백오피스 로그인 client(FE). confidential + PKCE(S256), redirect·webOrigins 는 `.env` 의 `TP_OFFICE_MERCHANT_WEB_URL` 로 만들어진다(로컬 `http://localhost:3000`), 백채널 로그아웃 → `TP_OFFICE_MERCHANT_WEB_BACKCHANNEL_LOGOUT_URL`. audience mapper 로 access token `aud` 에 `tp-office-merchant-api` 추가, scope mapping 으로 `tp-office-merchant-api` role 을 토큰에 담는다 (full scope 꺼짐) |
| `tp-office-merchant-api` | BE(리소스 서버) 이름표. bearer-only, 모든 flow 끔 — 토큰을 발급받지 못한다. client role 이 여기 붙고, BE 는 `aud` 에 이 이름이 있는지로 "우리 토큰인가"를 본다 |
| `tp-office-merchant-svc` | 계정 발급용 service account. realm-management `query-users`·`query-groups`·`query-clients` 만 있고, fine-grained 권한으로 **`/merchant-crosshub`·`/merchant-affiliate`·`/merchant-partner` 그룹과 그 멤버만** 보고 관리한다(조회·비번 초기화·활성 토글·로그아웃·삭제). 계정 생성은 이 그룹에 넣을 때만 된다. 그룹 밖 사용자는 조회조차 안 되고(403), 그룹 이동·role 직접 부여·그룹 생성도 403 |
| group | `/merchant-crosshub` · `/merchant-affiliate` · `/merchant-partner`. 각 그룹에 같은 이름의 `tp-office-merchant-api` client role 이 매핑돼 있다 — **role 은 사용자에게 직접 붙이지 않고 어느 그룹에 넣느냐로 정한다** |
| `tp-office-app-web` | app 백오피스 로그인 client(FE). merchant-web 과 같은 틀(confidential + PKCE, full scope 끔, audience mapper `aud=tp-office-app-api`, scope mapping 으로 `tp-office-app-api` role 만). 주소는 `TP_OFFICE_APP_WEB_URL`, 백채널 로그아웃은 `TP_OFFICE_APP_WEB_BACKCHANNEL_LOGOUT_URL` |
| `tp-office-app-api` | app 백오피스 BE 이름표. client role 은 출입용 `app-office` 하나. **세부 권한(Role 32개·메뉴×액션 매트릭스)은 Keycloak 에 두지 않고 app 백오피스 DB 가 토큰 `sub` 로 정한다** — 인증·출입은 Keycloak, 세부 인가는 앱 |
| `tp-office-app-svc` | app 백오피스 BE 의 관리자 등록·중지·비번 초기화·강제 로그아웃용 service account. realm-management `query-users`·`query-groups`·`query-clients`·`view-events` + fine-grained: `/app-office` 멤버만 관리(조회·생성·비번 초기화·활성 토글·로그아웃·삭제·다른 그룹에 넣고 빼기), `/merchant-crosshub` 에 넣고 빼기(= 직원에게 merchant 출입 주기). role 직접 부여(map-roles)는 없다 |
| group `/app-office` | app 백오피스 출입(`/merchant-crosshub` 와 별개, 필요한 직원만). `tp-office-app-api:app-office` 매핑. merchant-svc 는 이 그룹을 볼 수 없다 |
| client role | `tp-office-merchant-api` 의 `crosshub` / `affiliate` / `partner` (백오피스 DB `User.role`과 같은 이름). 토큰에는 `resource_access.tp-office-merchant-api.roles` 로 들어온다 |
| 테스트 유저 | `test-crosshub`(/merchant-crosshub) / `test-federation`(/merchant-affiliate) / `test-partner`(/merchant-partner) (백오피스 DB `User.loginId`와 같은 값) |

secret은 JSON에 `${TP_OFFICE_MERCHANT_WEB_CLIENT_SECRET}`처럼 자리표시로만 있고, 실제 값은 `.env`로 넣는다.
서명키·비번 해시는 JSON에 없다 → import 때 Keycloak이 새로 만든다.

## 고객 realm `tp` (`realm/tp-realm.json`)
| 항목 | 값 |
|---|---|
| realm | `tp` (TravelPass) — 자가 가입 ON(이메일 = 아이디), 비번 재설정 ON(메일은 SMTP 붙여야 감), 잠금 정책은 tp-office 와 같음, 비번 8자+·숫자. 언어 ko/en/ja |
| 토큰 | access 5분, refresh(SSO 세션) idle 30일·max 90일, refresh 회전(1회 재사용 허용) |
| `tp-customer-app` | TP 앱 로그인 client. **public + PKCE(S256)**, Authorization Code 만, redirect `travelpass://callback` (+ 데모용 `http://localhost:5173/*`, webOrigins 도 — 운영 realm 에서는 뺀다). audience mapper 로 access token `aud` 에 `tp-office-merchant-api` |
| `tp-office-merchant-api` | BE 이름표(bearer-only). tp-office 의 같은 이름 client 와 짝 — BE 는 두 realm 토큰 모두 `aud=tp-office-merchant-api` 로 본다. 고객은 role 없음 |
| 테스트 고객 | `test-customer@example.com`, 비번은 `.env` 의 `TP_TEST_CUSTOMER_PASSWORD` (import 때 들어감) |

관리 API 용 service account 는 없다. 고객은 스스로 가입하므로 BE 가 계정을 만들어 줄 일이 없다.
나중에 "TP 로 로그인" 을 외부에 제공하는 쪽도 이 realm 이다 (외부 서비스 = 이 realm 의 client 추가).

예정: 소셜 로그인(Identity Provider 추가), SMTP, 운영 주소·HTTPS.

## realm 바꾸는 법
1. 콘솔에서 바꾸거나 JSON을 직접 수정
2. 콘솔에서 바꿨다면 export:
   `docker compose exec keycloak /opt/keycloak/bin/kc.sh export --realm tp-office --users same_file --file /tmp/r.json && docker compose cp keycloak:/tmp/r.json ./r.json`
   → secret·`KeyProvider`·`credentials` 지우고 해당 realm JSON 에 반영 (`--realm tp` 이면 `realm/tp-realm.json`)
3. 이미 있는 realm은 `--import-realm`이 덮어쓰지 않는다. 새로 적용하려면 `docker compose down -v` 후 다시 up (Keycloak DB 초기화 — tp-office 테스트 유저 비번은 `scripts/reset-password.sh` 로 다시 넣는다).
   **새 realm 파일을 추가한 것뿐이면** `docker compose up -d --force-recreate keycloak` 으로 충분하다 (있는 realm 은 건드리지 않고 새 realm 만 import)
4. JSON 만 고쳤을 때 검증: 다른 프로젝트 이름·포트로 임시 인스턴스를 띄워 import 가 되는지 본다.
   `docker compose -p kc-verify -f docker-compose.yml -f <ports 를 18080 으로 바꾼 override> up -d` → 확인 → `docker compose -p kc-verify down -v`

## 브라우저 데모 (`demo/tp-web/`)
TP 앱이 생기기 전에 "고객이 tp realm 으로 로그인 → BE 고객용 API 호출" 을 보여주는 HTML 한 장. `python3 -m http.server 5173` 으로 띄운다.
BE 는 `CORS_ALLOWED_ORIGINS` 에 `http://localhost:5173` 을 넣고 기동. 자세한 건 `demo/tp-web/README.md`.

## 스크립트 (`scripts/`)
- `reset-password.sh <아이디> '<임시비번>'` — tp-office 테스트 유저 임시 비번 설정
- `kc-test.sh` — tp-office 로컬 검수용 (그룹 바꾸기 = role 변경, 그룹·role 조회, 강제 로그아웃)
- `tp-office-merchant-svc` 로 동작한다(BE 와 같은 권한). 단 `kc-test.sh set-group` 은 svc 에 없는 권한이라 최초 관리자로 부른다. `tp` 고객은 관리 콘솔에서 본다

## 주의
- `.env`, `tp-office-realm.export-original.json` 등 원본 export는 git 금지 (`.gitignore`에 있음)
- 권한(fine-grained) realm 결정 방식이 UNANIMOUS 라, 같은 그룹·scope 에 permission 을 둘로 걸면 서로 막는다. 두 svc 가 같이 쓰는 `/merchant-crosshub` 넣고 빼기는 한 permission 에 두 svc 를 같이 둔다
- 운영 전: `start-dev` → `start` + `KC_HOSTNAME` 고정, HTTPS, 환경별 secret 분리, admin 2FA
