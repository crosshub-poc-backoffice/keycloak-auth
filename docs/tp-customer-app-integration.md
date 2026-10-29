# TP 앱 ↔ 인증 서버(tp realm) 연동 가이드

TP 앱(React Native)이 고객 로그인을 인증 서버(Keycloak, `tp` realm)로 하고, 받은 access token 으로
제휴사 백오피스 BE 의 고객용 API 를 부르기 위한 값과 흐름. 2026-10-26 기준.

## 한눈에

| 항목 | 값 |
|---|---|
| issuer | `https://<인증서버>/realms/tp` (로컬: `http://localhost:8080/realms/tp`) |
| discovery | `<issuer>/.well-known/openid-configuration` — 아래 endpoint 들은 전부 여기서 읽을 수 있다 |
| client_id | `tp-customer-app` |
| client 종류 | **public** (secret 없음) + **PKCE S256 필수** |
| 허용 flow | Authorization Code 만. implicit·password(direct grant) 꺼짐 |
| redirect_uri | `travelpass://callback` (로그인 후·로그아웃 후 둘 다) |
| scope | `openid profile email` (필요하면 `offline_access`·`phone` 추가 가능) |
| access token 수명 | 5분 |
| refresh token 수명 | 마지막 사용 후 30일, 최초 로그인 후 최대 90일. 쓴 refresh 는 회전(새 refresh 발급, 옛것 1회까지만 재사용 허용) |
| 가입 | 로그인 화면에서 자가 가입. 이메일이 곧 아이디. 비번 8자 이상·숫자 포함 |
| 테스트 계정 | `test-customer@example.com` (비번은 인증 서버 운영자에게. 로컬은 `.env` 의 `TP_TEST_CUSTOMER_PASSWORD`) |

## 흐름

1. 앱이 PKCE `code_verifier`/`code_challenge` 를 만들고 시스템 브라우저(ASWebAuthenticationSession / Custom Tabs)로
   `<issuer>/protocol/openid-connect/auth?response_type=code&client_id=tp-customer-app&redirect_uri=travelpass://callback&scope=openid%20profile%20email&code_challenge=...&code_challenge_method=S256&state=...`
   를 연다. 로그인·가입 화면은 인증 서버가 그린다. 앱 안에 로그인 폼을 만들지 않는다.
2. 로그인이 끝나면 브라우저가 `travelpass://callback?code=...&state=...` 로 돌아온다.
3. 앱이 `<issuer>/protocol/openid-connect/token` 에 `grant_type=authorization_code&client_id=tp-customer-app&code=...&redirect_uri=travelpass://callback&code_verifier=...` 를 POST → `access_token`, `refresh_token`, `id_token`.
4. BE 호출: `Authorization: Bearer <access_token>`. **id_token 은 BE 에 보내지 않는다** (앱 안에서 "누구인지" 표시용).
5. access 가 만료되면(5분) `grant_type=refresh_token&client_id=tp-customer-app&refresh_token=...` 으로 갱신. 응답의 새 refresh 로 갈아 끼운다.
6. 로그아웃: 저장한 토큰을 지우고 `<issuer>/protocol/openid-connect/logout?id_token_hint=<id_token>&post_logout_redirect_uri=travelpass://callback` 을 브라우저로 연다 (인증 서버 세션까지 끝냄). 토큰만 지우면 다음 로그인 때 브라우저 세션으로 자동 로그인될 수 있다.

### react-native-app-auth 예
```ts
const config = {
  issuer: 'https://<인증서버>/realms/tp',
  clientId: 'tp-customer-app',
  redirectUrl: 'travelpass://callback',
  scopes: ['openid', 'profile', 'email'],
  usePKCE: true,            // 기본값 true — 끄지 말 것
  dangerouslyAllowInsecureHttpRequests: __DEV__, // 로컬 http 일 때만
}
const result = await authorize(config)         // access/refresh/id token
const fresh  = await refresh(config, { refreshToken: result.refreshToken })
await logout(config, { idToken: result.idToken, postLogoutRedirectUrl: 'travelpass://callback' })
```
Android 는 `AndroidManifest` 의 `appAuthRedirectScheme` 을 `travelpass`, iOS 는 URL scheme 에 `travelpass` 등록.
로컬 Android 에뮬레이터에서 `localhost` 는 `10.0.2.2` 로 바꿔 쓴다 (issuer 와 토큰의 `iss` 가 같아야 하므로 인증 서버 쪽 주소를 그 값으로 띄우거나, 실기기 + 내 PC IP 를 쓴다).

## 토큰에 들어 있는 것

access token (JWT, RS256) 의 주요 claim:

| claim | 값 | 비고 |
|---|---|---|
| `iss` | `<issuer>` | BE 는 이 값이 자기가 믿는 issuer 목록에 있는지 본다 |
| `aud` | `tp-office-merchant-api` | BE 이름표. 이게 없으면 BE 가 401 |
| `azp` | `tp-customer-app` | 토큰을 받아간 client |
| `sub` | 고객의 고유 ID (UUID) | BE 가 고객을 식별하는 키. 이메일은 바뀔 수 있으니 이걸 쓴다 |
| `email`, `email_verified`, `name`, `preferred_username` | 프로필 | `preferred_username` 은 이메일과 같다 |
| `exp`, `iat` | 만료·발급 시각 | |

고객 토큰에는 **역할(role)이 없다**. 직원 realm 과 달리 `resource_access` 가 비어 있고, BE 는 issuer 가 고객 realm 이면
"본인 데이터만" 규칙으로 처리한다. 직원 전용 API 는 고객 토큰으로 못 부른다 (issuer 가 다름).

## 보관

- access·refresh·id token 은 **secure storage** (iOS Keychain / Android Keystore. `react-native-keychain` 등). AsyncStorage 금지.
- 앱에 client secret·API 키를 넣지 않는다. `tp-customer-app` 은 public client 라 애초에 secret 이 없다.
- 앱은 자체 세션을 두지 않는다. "로그인돼 있나" = "유효한 refresh 가 있나".

## 앱 없이 먼저 보기
이 레포 `demo/tp-web/` 이 같은 `tp-customer-app` client 로 브라우저에서 로그인→토큰→BE 호출을 보여준다. 앱 구현 전에 흐름을 확인하거나, 앱 쪽 문제인지 인증 서버 쪽 문제인지 가를 때 쓴다.

## 로컬에서 띄우기

```bash
git clone <keycloak-auth 레포>
cd keycloak-auth && cp .env.example .env   # 값 채우기 (TP_TEST_CUSTOMER_PASSWORD 포함)
docker compose up -d                       # http://localhost:8080
open http://localhost:8080/realms/tp/.well-known/openid-configuration
```
관리 콘솔 `http://localhost:8080/admin` (계정은 `.env` 의 `KC_BOOTSTRAP_ADMIN_*`) → realm `tp` 에서 가입한 고객·세션을 볼 수 있다.

## BE 고객용 API (`Authorization: Bearer <access_token>`)

| 메서드·경로 | 하는 일 | 비고 |
|---|---|---|
| `GET /api/customer/me` | 토큰의 고객 정보(sub·email·name) | |
| `GET /api/customer/products` | 노출중 상품 목록 (id·name·partnerName·currency·priceFrom·confirmType) | |
| `GET /api/customer/bookings` | 내 예약 | 이용일 최근 순 |
| `POST /api/customer/bookings` | 예약 신청 `{productId, nationality, useDate, people, amount, phone?, priceBreakdown?, idempotencyKey}` | 즉시확정 상품은 정원 안이면 바로 `confirmed`(결제 행 생성), 견적형은 `pending`. 정원 초과 `409 full`, 상품 없음/숨김 `404 productNotFound` |
| `GET /api/customer/bookings/{id}` | 내 예약 상세 | 남의 예약은 404 |
| `POST /api/customer/bookings/{id}/decision` | 견적 수락/거절 `{decision: accepted\|declined}` | `quoted` 상태에서만 (`409 notQuoted`) |
| `POST /api/customer/bookings/{id}/cancel` | 취소 | `pending`→`withdrawn`, `confirmed`→`canceled`+취소 수수료(`cancelFee`). 그 외 `409 notCancelable` |
| `GET /api/customer/inquiries` | 내 문의 (대화 스레드 포함) | |
| `POST /api/customer/inquiries` | 문의 접수 `{productId, language: en\|zh\|ja\|vi, question, idempotencyKey}` | |
| `GET /api/customer/inquiries/{id}` | 내 문의 상세 | |

- `idempotencyKey`: 앱이 "신청 1건"마다 한 번 만들어(UUID) 재시도에도 같은 값을 보낸다. 같은 키가 다시 오면 새로 만들지 않고 기존 것을 돌려준다.
- 고객 식별은 토큰 `sub`. 예약·문의 행의 `customerId` 에 저장되고 조회는 항상 "내 것"만.
- 에러는 `{code}` 본문 (예: `{"code":"full"}`). 401 = 토큰 없음/만료, 403 = 직원 토큰 등 고객 토큰이 아님.

## 아직 없는 것 (순서대로 붙일 예정)

- ~~BE 고객용 API~~ → 있음. 아래 표.
- **소셜 로그인**(Google·Apple 등). 인증 서버에 Identity Provider 로 추가하면 앱 코드 변경 없이 로그인 화면에 버튼이 생긴다. 각 제공자의 client 등록이 필요.
- **이메일 인증·비번 재설정 메일**. SMTP 가 붙어야 동작한다. 지금은 가입 즉시 로그인 가능, 비번 찾기 버튼은 있지만 메일이 안 간다.
- **운영 주소·HTTPS**. 위 값의 `<인증서버>` 는 운영 주소가 정해지면 바뀐다. 앱은 issuer 하나만 설정으로 빼 두면 된다.
