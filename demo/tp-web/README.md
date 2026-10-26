# demo/tp-web — TP 앱 대신 브라우저로 보는 고객 로그인 데모

HTML 한 장. 라이브러리 없이 OIDC Authorization Code + PKCE 를 그대로 구현해, "고객이 `idblock` realm 에 로그인해서
받은 access token 으로 제휴사 백오피스 BE 의 고객용 API 를 부른다" 를 눈으로 확인한다. client 는 앱과 같은 `tp-app`.

## 띄우기
1. 인증 서버: 이 레포 루트에서 `docker compose up -d` (realm `idblock` 의 `tp-app` 에 `http://localhost:5173/*` 가 들어 있다)
2. BE: `CORS_ALLOWED_ORIGINS` 에 `http://localhost:5173` 포함해서 기동 (`.env` 또는 환경변수)
3. 이 폴더에서
   ```bash
   python3 -m http.server 5173
   ```
   → http://localhost:5173 (포트가 다르면 realm 의 redirect/webOrigins 도 맞춰야 한다)

## 보여주는 것
- **로그인 / 가입**: 인증 서버 화면으로 갔다 돌아온다. 테스트 고객 `test-customer@example.com` 또는 "등록"으로 새 고객
- **토큰**: `iss`(idblock) · `aud`(backoffice-api) · `azp`(tp-app) · `sub` · role 없음 을 디코드해서 표시
- **GET /api/customer/me** → 200, 토큰의 고객 정보
- **GET /api/v1/products**(직원용) → 403. 고객 토큰으로 직원 API 를 못 부른다는 증명
- **refresh** 로 갱신(회전), **로그아웃**(인증 서버 세션까지 종료)

## 실제 앱과 다른 점
- 토큰을 sessionStorage 에 둔다. 앱은 secure storage.
- redirect 가 `http://localhost:5173/`. 앱은 `travelpass://callback`. 운영 realm 에서는 localhost redirect 를 뺀다.
