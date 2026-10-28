# Keycloak 변경안 — realm `tp` / `tp-office`, TP 백오피스 연동

2026-10-27 결정. TP 백오피스(dev-office-front.travelpass.io.kr)의 Admin Management를 전부 훑어 권한 구조를 확인한 뒤,
파트너 백오피스와 같은 realm에서 계정을 공유하는 방향으로 정한 것.

진행: 2026-10-27 env·client 구조 확정(아래 "env"·"client 구조 확정 사항"), 파트너 백오피스 쪽 적용(realm rename·group·`-svc` 권한 축소·event)을 keycloak-auth·BE·FE에 반영.
TP 백오피스(`tp-office-admin-*`)는 아직 — 연동 시작할 때 realm JSON에 추가.

## 0. 레포·환경

| 레포 | 경로 | 역할 |
|---|---|---|
| `keycloak-auth` | `26.10.21 keycloak/keycloak-auth` | Keycloak 26.8.1 + Postgres(Docker). `realm/*.json` 자동 import. **realm 기준은 JSON** |
| 파트너 백오피스 BE | `26.10.21 keycloak/travelpass-backoffice-BE` | Spring. `docs/auth-architecture.md`에 현재 구조. JDK 17로 빌드 |
| 파트너 백오피스 FE | `26.10.21 keycloak/travelpass-backoffice-FE` | Next.js BFF. 세션은 Redis(`lib/server/auth/session-store.ts`) |
| TP 백오피스 | 로컬에 없음. dev: `https://dev-office-front.travelpass.io.kr` (Next.js, BFF 쿠키 `office.session-alive`) | 자체 로그인·자체 IAM 보유 |

커밋·PR에 AI 작성 표시(Co-Authored-By 등) 넣지 않음.

## 1. 지금 상태

### keycloak-auth (현재 realm 2개)

| realm | client | 종류 | 비고 |
|---|---|---|---|
| `crosshub` (직원) | `backoffice-web` | confidential + PKCE | 파트너 FE 로그인. full scope 끔, `backoffice-api` role scope mapping, audience mapper |
| `crosshub` | `backoffice-api` | 이름표(flow 전부 끔) | 파트너 BE aud. client role `crosshub` / `affiliate` / `partner` |
| `crosshub` | `backoffice-svc` | service account | manage-users + fine-grained(`backoffice-api`만 view·map-roles) |
| `idblock` (고객) | `tp-app` | public + PKCE | TP 앱 로그인. redirect `travelpass://callback`, 데모 `http://localhost:5173/*` |
| `idblock` | `backoffice-api` | 이름표 | 파트너 BE 고객용 API(`/api/customer/me`) aud. 고객은 role 없음 |

- group 없음, realm role은 기본값뿐.
- 파트너 BE: issuer 2개(`app.keycloak.staff-issuer` / `customer-issuer`) 검증기, `aud=backoffice-api` 검사, `resource_access.backoffice-api.roles` → 권한(`SecurityConfig`, `CallerService`).
- 파트너 BE의 Keycloak username = 백오피스 DB `User.loginId`(예: `test-crosshub`).

### TP 백오피스 Admin Management (2026-10-27 dev 기준)

- **권한 단위**: 메뉴(화면 경로) × 액션 6종. 비트값 목록 1·조회 2·등록 4·수정 8·삭제 16·승인 32 를 합친 정수로 저장.
  메뉴 82개(쿼리스트링 상태별로 따로 잡힘 — `/office/user/info?status=active` 와 `?status=suspended` 가 별개), 칸 492개.
- **Role 32개**, 관리자 1명당 Role 1개. "구분" 사용자/마스터/루트 — 마스터·루트는 Role 없이 전체 권한으로 보임(루트 1명 유영근, 마스터 7명).
- 사용자 그룹 화면은 있으나 등록 0개.
- 로그인은 자체 ID/PW(이메일). 브라우저에 토큰 없음(BFF).
- 관리자 17명(crosshub.kr 이메일 대부분), 개발자 8명이 `DEVELOPER_TEAM_CRU`.

Role 코드 (`tp-office-admin-api` client role로 그대로 옮긴다):

| 코드 | 이름 | 설명 |
|---|---|---|
| OFFICE_VIEWER | 백오피스 뷰어 | 거의 전 메뉴 목록·조회 |
| DEVELOPER_TEAM_CRU | 트래블패스 개발팀_CRU권한 | 거의 전 메뉴 목록·조회·등록·수정 (IAM 메뉴 포함 — 이관 때 제거) |
| MEMBER_VIEWER | 회원 조회 | 회원 목록·상세·변경/조치 이력·기기 조회 |
| MEMBER_OPERATOR | 회원 일반 운영 | 회원 이용 제한·해제 등 상태 관리 |
| MEMBER_SECURITY | 회원 보안 관리 | PIN 초기화·로그인 수단·기기 해제 |
| CS_VIEWER | 고객지원 조회 | 문의·거래이의 조회 |
| CS_OPERATOR | 고객문의 처리 | 문의 답변·담당자·상태 관리 |
| DISPUTE_OPERATOR | 거래이의 처리 | 거래이의 조회·상태 관리 |
| CS_CONTENT_EDITOR | 공지·FAQ 관리 | 고객 공지·FAQ 등록·수정 |
| POLICY_MANAGER | 정책 문서 관리 | 정책 초안·버전·발행 관리 |
| KYC_VIEWER | KYC 조회 | 심사·검증·신원·이벤트·통계 조회 |
| KYC_REVIEWER | KYC 심사 | 심사 승인·반려·재시도 |
| KYC_CONTROLLER | KYC 검증 관리 | Case·신원 검증 철회 |
| KYC_POLICY_ADMIN | KYC 정책 관리 | 정책 조회·신규 버전 등록 |
| CARD_VIEWER | 카드 정보 조회 | 카드사·발행사·상품·실물카드 조회 |
| CARD_PRODUCT_ADMIN | 카드 기준정보·상품 관리 | 카드사·발행사·상품 등록·수정 |
| CARD_INVENTORY_ADMIN | 카드 재고 관리 | 카드번호 파일 적재·재고 관리 |
| CARD_PICKUP_ADMIN | 픽업 장소 관리 | 수령 장소 등록·수정·활성 관리 |
| FIN_VIEWER | 월렛·거래 조회 | 월렛·잔액·거래·동기화 상태 조회 |
| WALLET_CONFIG_ADMIN | 월렛 기준정보 관리 | 앱 안내 한도·비카드 자산·분류 관리 |
| PAYMENT_VIEWER | 충전 내역 조회 | 충전 요청·승인·실패·반영 상태 조회 |
| PG_LOG_VIEWER | PG 연동 이력 조회 | PG 요청·응답·통신/처리 오류 조회 |
| PG_ADMIN | PG 기준정보 관리 | PG사 정보·수수료·정산 통화·활성 설정 |
| TRAVEL_VIEWER | 여행 콘텐츠 조회 | 장소·코스·가이드·이벤트·여행지·카테고리 조회 |
| TRAVEL_CONTENT_ADMIN | 여행 콘텐츠 관리 | 관광 콘텐츠 및 기준정보 등록·수정 |
| PARTNER_VIEWER | 제휴 서비스 조회 | 제휴사 계약·주문·신청·웹훅 조회 |
| PARTNER_OPERATOR | 제휴 서비스 운영 | 필수 조회 + 확인된 운영 처리 (현재 중지 상태) |
| BOARD_USER | 내부 게시판 이용 | 업무 공지 조회·게시글/자료 등록 |
| BOARD_MANAGER | 내부 게시판 관리 | 공지·게시글·자료·게시판 설정 관리 |
| ADMIN_VIEWER | 관리자 현황 조회 | 계정·접속·활동 이력 조회 |
| ADMIN_ACCOUNT_MANAGER | 관리자 계정 관리 | 관리자 계정·그룹·상태 관리 |
| IAM_ADMIN | 접근 권한 관리 | Role 생성·수정·배정·해제 (유일하게 삭제 권한) |

확인된 문제:
1. `DEVELOPER_TEAM_CRU`에 `/office/iam/role`·`/office/iam/admin-role` 등록·수정 권한이 있어 스스로 권한 상승 가능.
2. Dashboard, Bank Partners, OIDC Clients(IDBlock·V-Pay), Notifications, Audit & Security 메뉴는 권한 매트릭스에 항목이 없음.
3. 리소스가 화면 경로라 TP 백오피스 BE가 API 수준에서 이 매트릭스를 검사하는지 미확인.

## 2. 설계

### 이름 규칙

- realm: `tp`(고객), `tp-office`(백오피스 쓰는 사람 전부). "idblock"은 블록체인 기술명이라 realm 이름에서 뺌.
- client: `tp-office-{admin|partner}-{web|api|svc}` + `tp-app`. admin = TP 백오피스, partner = 파트너 백오피스.
  web = 로그인 받는 FE, api = BE 이름표(aud), svc = 서버 간 호출용 service account.
- 변경 전후 대응: `crosshub`→`tp-office`, `idblock`→`tp`, `backoffice-web`→`tp-office-partner-web`, `backoffice-api`→`tp-office-partner-api`, `backoffice-svc`→`tp-office-partner-svc`.

### Realm 2개

| realm | displayName | 누구 | 가입 | issuer |
|---|---|---|---|---|
| `tp-office` | TP Office | 크로스허브 직원, 연맹(affiliate), 제휴 업체(partner) | 관리자 발급 | `/realms/tp-office` |
| `tp` | TravelPass | TP 앱 일반 사용자 (나중에 외부 서비스 "TP로 로그인" 제공) | 자가 가입·소셜 | `/realms/tp` |

한 realm에 두 백오피스를 두는 이유: 크로스허브 직원은 파트너 백오피스(`crosshub` role)와 TP 백오피스를 같은 사람이 쓴다. 계정 하나, SSO, 퇴사 처리 한 번.
realm 정책(잠금·비번·토큰 수명)은 지금 `crosshub`/`idblock` 값 그대로 가져간다.

### `tp-office` realm — client 6개

| client | 종류 | 용도 |
|---|---|---|
| `tp-office-admin-web` | confidential + PKCE(S256), standard flow만 | TP 백오피스 FE 로그인. redirect `${TP_OFFICE_ADMIN_WEB_URL}/*` — 환경마다 주소 하나(Keycloak은 호스트 자리 와일드카드 `https://*-office-front…`를 지원하지 않는다), 백채널 로그아웃 → TP 백오피스 FE. full scope 끔, `tp-office-admin-api` role만 scope mapping, audience mapper `aud=tp-office-admin-api` |
| `tp-office-admin-api` | 이름표 (flow 전부 끔) | TP 백오피스 BE. client role = 위 32개 + `OFFICE_MASTER` |
| `tp-office-admin-svc` | service account | TP 백오피스 BE가 관리자 등록·Role 배정·Role 생성·강제 로그아웃할 때. realm-management `query-users`·`query-groups`·`query-clients`·`view-events` + Admin Permissions로 Groups `/tp-office` 멤버 관리(`view`·`view-members`·`manage-members`·`manage-membership`) + `/crosshub` `manage-membership`(직원을 파트너 백오피스에 넣고 빼기), Clients/Roles 는 **`tp-office-admin-api`에만** view·manage·map-roles (manage = client role 생성·수정·삭제). `manage-users` 전체 권한은 주지 않음 |
| `tp-office-partner-web` | confidential + PKCE | 파트너 FE 로그인 (지금 `backoffice-web`, 설정 그대로) |
| `tp-office-partner-api` | 이름표 | 파트너 BE. client role `crosshub` / `affiliate` / `partner` (지금 `backoffice-api`) |
| `tp-office-partner-svc` | service account | 파트너 BE 계정 발급·조회. **적용됨.** realm-management `query-users`·`query-groups`·`query-clients` + Admin Permissions V2로 Groups `/affiliate`·`/partner` 에만 `view`·`view-members`·`manage-members`·`manage-membership`, **`/crosshub` 는 `view`·`view-members`(조회만)** — 아래 "② 관리 주체는 한 곳", Clients `tp-office-partner-api` 에 `view`. `manage-users`·map-roles 없음. 권한은 role 직접 배정이 아니라 **어느 그룹에 넣느냐**로 결정(그룹 role 매핑) |

각 BE는 자기 이름표가 `aud`에 있는지와 `resource_access.<자기 api>.roles`만 본다. 토큰에 상대편 role은 실리지 않는다.

### `tp-office` realm — group (소속)

| group | role 매핑 | 의미 |
|---|---|---|
| `/crosshub` | `tp-office-partner-api:crosshub` | 크로스허브 직원의 파트너 백오피스 출입 |
| `/tp-office` (TP 연동 때 추가) | `tp-office-admin-api:OFFICE_VIEWER` | TP 백오피스 출입. 필요한 직원만 |
| `/affiliate` | `tp-office-partner-api:affiliate` | 연맹. 파트너 백오피스만 |
| `/partner` | `tp-office-partner-api:partner` | 업체. 파트너 백오피스만 |

크로스허브 직원에 대해 2026-10-28 에 정한 것은 두 가지이고, 서로 별개다.

| | ① 무슨 권한을 받나 (출입증) | ② 누가 계정을 바꾸나 (관리 주체) |
|---|---|---|
| 정한 것 | TP 권한은 `/crosshub` 가 아니라 별도 최상위 그룹 `/tp-office` 로 준다 | 크로스허브 직원 계정의 생성·비번·중지는 한 곳(콘솔 → TP 연동 후 `tp-office-admin-svc`)에서만 한다 |
| 막는 것 | 파트너 백오피스만 쓰는 직원이 TP 권한까지 받는 것 | 파트너 백오피스가 같은 계정의 TP 백오피스 쪽까지 바꾸는 것 |
| 상태 (2026-10-28) | realm 에 `/tp-office` 빈 그룹 추가됨(role 없음). TP 연동 때 `OFFICE_VIEWER` 매핑 | **적용됨** — realm(svc `/crosshub` 조회만) + 파트너 BE·FE 같이 |

①만 하고 ②를 안 하면, 출입증은 나뉘어 있어도 계정(아이디·비번·켜짐 여부)은 하나라서 아래 문제가 그대로 남는다.

#### ① TP 권한은 별도 그룹 `/tp-office`
처음엔 `/crosshub` 하나에 두 role(`tp-office-partner-api:crosshub` + `tp-office-admin-api:OFFICE_VIEWER`)을 걸어, 넣으면 두 백오피스에 다 들어가게 했다. 직원마다 필요한 백오피스가 다를 수 있어 분리한다.
- 하위 그룹(`/crosshub/tp-office`)이 아니라 최상위 그룹 `/tp-office` 로 둔다 — Keycloak 하위 그룹은 부모 그룹 role 을 물려받아, TP 직원이 파트너 출입증까지 무조건 받게 된다.
- TP 세부 권한(32개 Role·`OFFICE_MASTER`)은 그룹이 아니라 사람마다 `tp-office-admin-api` role 로 붙인다(아래 "Role").
- `OFFICE_VIEWER`의 내용(어느 메뉴까지 조회)은 TP 백오피스 매트릭스 그대로 — Keycloak 도입 범위 밖. 참고(권고만): 지금 64개 메뉴 조회(회원 상세·KYC 신원·월렛 잔액 포함)라 넓다.

#### ② 크로스허브 직원 계정의 관리 주체는 한 곳 (적용됨 2026-10-28 — Keycloak 26.8.1 실측 근거)
이전에는 `-partner-svc` 가 `/crosshub` 를 관리하고 파트너 BE 가 크로스허브 계정을 발급·비번 초기화·비활성했다. 그대로 두고 TP 백오피스가 같은 realm 에 붙으면 크로스허브 직원은 **Keycloak 계정 하나로 두 백오피스에 로그인**하므로, 파트너 쪽 작업이 TP 쪽에 그대로 번진다. 예 (김OO = 크로스허브 직원이자 TP 백오피스 관리자):

| 파트너 백오피스에서 | Keycloak 에서 일어나는 일 | TP 백오피스 결과 |
|---|---|---|
| 김OO **비활성화** | 파트너 BE 가 `-partner-svc` 로 `enabled=false` + 세션 종료 → Keycloak 계정 자체가 꺼짐 | 김OO 은 **TP 백오피스에도 로그인 못 함** (파트너 출입만 끊으려던 것) |
| 김OO **비번 초기화** | 파트너 BE 가 계정 비번을 임시 비번으로 바꾸고, 그 임시 비번을 초기화한 크로스허브 직원 화면에 보여 줌 | **TP 백오피스 비번도 바뀜**. 김OO 이 TP 마스터면, 파트너 쪽 직원이 TP 마스터 비번을 알게 되는 셈 → TP 백오피스 마스터 권한 탈취 |
| 김OO **삭제**(발급 롤백 등) | `-partner-svc` 가 `/crosshub` 멤버 삭제 가능 | TP 관리자 계정이 통째로 사라짐 |

원인: Admin Permissions V2 의 그룹 `manage-members` 는 **사용자 단위**로 판단한다 — 그 그룹 멤버면 다른 그룹(`/tp-office`)에 같이 있어도 비번 초기화·비활성·삭제·이메일 변경이 된다(실측). 그래서 ① 처럼 그룹을 나눠도 `-partner-svc` 가 `/crosshub` 를 관리하는 한 막히지 않는다.

적용한 것 — **realm·파트너 BE·파트너 FE 를 한꺼번에 배포해야 한다** (svc 권한만 줄이면 예전 파트너 BE 의 크로스허브 발급·초기화·토글이 403 으로 깨진다):
- `tp-office-partner-svc`: `/crosshub` 는 `view`·`view-members` 만(조회만). 실측: 비번 초기화·비활성·로그아웃·삭제·생성·이메일 변경 모두 403.
- 파트너 BE: 크로스허브 계정은 발급하지 않고 첫 로그인 때 DB 에 자동 등록(토큰 role 이 `crosshub` 하나일 때), 비번 초기화는 거절, 비활성은 파트너 DB 만 바꾼다(파트너 출입만 끊김).
- 파트너 FE: 발급 창에서 크로스허브 제외, 크로스허브 행 비번 초기화 버튼 숨김.
- 직원 계정 생성·비번·중지: 지금은 관리 콘솔, TP 연동 후에는 `tp-office-admin-svc`(TP 백오피스).
- `tp-office-admin-svc` 범위(연동 때 실측으로 확인): `/tp-office` 멤버 관리 + `/crosshub` `manage-membership`. 업체·연맹(`/affiliate`·`/partner`)은 조회도 못 한다.
- `/tp-office` 가 아닌 사용자에게 `tp-office-admin-api` role 이 붙지 않는 건 그룹 role 매핑 + `-svc` 의 map-role 금지로 강제.
- svc 가 사용자 그룹 목록을 조회하면 자기가 볼 수 있는 그룹만 나온다(다른 그룹 소속은 숨겨짐) — BE 가 이 목록으로 "우리 계정인가"를 판단하면 안 된다.
- 관리 콘솔 직접 변경은 남는다 → 콘솔 계정 소수 제한 + admin event ON.

### Role

- `tp-office-admin-api`: 32개 코드 그대로 + `OFFICE_MASTER`(32개를 전부 포함하는 composite). BE에 "마스터면 통과" 예외 코드 없이 토큰에 다 실린다.
- **Role 코드의 원본은 Keycloak.** 코드·이름·설명은 client role(name·description). TP 백오피스 DB에는 Role 테이블을 두지 않고, 매트릭스 테이블이 `role_code` 문자열로 Keycloak role을 가리킨다.
  - Role 관리 화면 "등록·수정·상태" → BE가 `-svc`로 client role 생성·수정(`-svc`의 fine-grained manage 권한). 생성 때 `OFFICE_MASTER` composite에도 추가, 삭제 때 제거. 중지 상태는 role attribute `status=inactive`(토큰에는 실리되 BE가 무시).
  - Role 삭제 → BE가 Keycloak role 삭제 + 매트릭스 행 삭제. 콘솔에서 직접 지운 경우 매트릭스 행은 고아가 되지만 토큰에 코드가 안 실리므로 권한 효과는 없다.
  - **불일치 감지**: Role 관리 목록은 Keycloak role 목록 ∪ 매트릭스 `role_code`를 합쳐 그린다. Keycloak에만 있으면 "매트릭스 미설정", 매트릭스에만 있으면 "Keycloak에서 삭제됨" 표시 + 매트릭스 행 삭제/Keycloak 재생성 버튼. 토큰에 매트릭스에 없는 코드가 오면 BE가 경고 로그.
- Role → 메뉴×액션 매트릭스(492칸)는 **TP 백오피스 DB에 남긴다**. 토큰엔 Role 코드만. (메뉴 추가 때마다 Keycloak을 건드리지 않기 위해. Authorization Services는 쓰지 않음)
- `tp-office-partner-api`: `crosshub` / `affiliate` / `partner` 그대로.

### 사용자 마스터 — Keycloak이 유일한 원본

두 백오피스 모두 자기 DB에 사용자(관리자) 테이블을 **두지 않는다**. 직원 수십 명 규모라 Admin API 직접 조회로 충분하다.

| 동작 | 처리 |
|---|---|
| 사용자 목록·상세 (양쪽 백오피스) | `-svc`로 Admin API 조회. 파트너는 `/affiliate`·`/partner`·`/crosshub` 멤버, TP 백오피스는 `/tp-office` 멤버. `enabled`·group·role·마지막 로그인(`attributes` 또는 event)을 그때그때 읽는다 |
| 계정 생성 | 업체·연맹 = 파트너 BE. 크로스허브 직원 = 콘솔(TP 연동 후 TP 백오피스)이 만들고 파트너 BE 는 첫 로그인 때 자동 등록만. username = email. 같은 username 이 이미 있으면 **지우지 않고 거절**(2026-10-28 — 그룹·DB 만으로는 누가 만든 계정인지 알 수 없다). TP 쪽은 이메일로 먼저 조회 → 있으면 group만 추가 |
| 중지 | `enabled=false` + 강제 로그아웃. 상대편 백오피스도 다음 조회 때 `enabled`로 바로 보인다 |
| 사용자별 앱 데이터 (담당자 지정, 개인 설정 등) | 각 BE DB에 **`sub`(Keycloak user id)를 키로** 저장. 이름·이메일은 저장하지 않고 표시 때 Keycloak에서 읽거나 토큰에서 꺼낸다 |
| 파트너 BE의 기존 `User` 테이블 (`loginId`·`role`) | `sub` 키의 "업체 범위" 테이블로 축소. `role`은 토큰에서, `loginId`는 username(=email)로 대체. `db-ownership-plan.md`와 함께 진행 |

### 권한 변경 즉시 반영

access 토큰 수명(5분) 동안 옛 권한이 살아 있는 걸 막기 위해, **Role 배정·해제·계정 중지 때 BE가 `-svc`로 해당 사용자 강제 로그아웃** (`POST /admin/realms/tp-office/users/{id}/logout`). 백채널 로그아웃이 두 백오피스 FE에 가서 BFF 세션이 지워지고, 사용자는 다시 로그인한다(양쪽 다 끊기는 건 수용). 자기 자신을 바꿀 때도 같다.

### 로그인 이력·감사

| 항목 | 소스 |
|---|---|
| 로그인 성공·실패, 로그아웃 | Keycloak realm event ON(보존 30일). TP 백오피스 "로그내역"·"최종 접속내역"은 BFF 콜백에서 자기 DB에 기록(sub·시각·IP·UA) — 파트너 FE가 이미 하는 방식. Keycloak event는 보조(실패 시도 등) |
| 접근/활동 로그 | 앱 레벨. 변경 없음 (주체만 `sub`로) |
| 관리자 권한 변경 (대시보드 알림) | BE가 `-svc`로 배정·해제할 때 자기 DB에 기록(누가·누구에게·무엇을). 콘솔 직접 변경은 Keycloak admin event ON으로 남기고 `view-events`로 읽어 같은 화면에 합친다 |

### MFA

적용 안 함. 지금처럼 비밀번호만(Keycloak 기본값인 "사용자가 원하면 OTP 켜기"는 그대로 둠). 필요해지면 그때 결정.

### 토큰 모양

```json
// tp-office-admin-web 으로 로그인한 직원
"iss": "https://<auth>/realms/tp-office",
"aud": "tp-office-admin-api",
"resource_access": { "tp-office-admin-api": { "roles": ["OFFICE_VIEWER", "KYC_REVIEWER"] } }

// tp-office-partner-web 으로 로그인한 같은 직원
"iss": "https://<auth>/realms/tp-office",
"aud": "tp-office-partner-api",
"resource_access": { "tp-office-partner-api": { "roles": ["crosshub"] } }
```

### `tp` realm

| client | 종류 | 용도 |
|---|---|---|
| `tp-app` | public + PKCE | TP 앱 로그인 (그대로) |
| `tp-office-partner-api` | 이름표 | 파트너 BE 고객용 API(`/api/customer/me`) aud. 지금 `backoffice-api` |
| `tp-office-admin-api` | 이름표 | TP 백오피스 BE가 앱 사용자 요청을 직접 받을 때만 추가 |

고객은 role 없음. `tp-app` audience mapper에는 앱이 실제로 부르는 BE 이름표를 넣는다.

### TP 백오피스에서 바뀌는 것

| 기능 | 지금 | 후 |
|---|---|---|
| 로그인 | 자체 ID/PW | `tp-office-admin-web` → Keycloak (BFF. 파트너 FE `session-store.ts` 패턴) |
| 사용자 관리 (목록·등록·중지·Excel) | 오피스 DB | DB 테이블 제거. `tp-office-admin-svc`로 Admin API 조회·생성(이메일 있으면 group만)·`enabled=false`+강제 로그아웃 |
| 관리자 Role 배정·해제 | 오피스 DB | `tp-office-admin-svc`로 client role map/unmap + 강제 로그아웃. 이력은 오피스 DB에 기록 + Keycloak admin event |
| Role 관리 (코드·이름·상태) | 오피스 DB | Keycloak client role이 원본. 화면은 `-svc`로 생성·수정·삭제 |
| Role 관리 (매트릭스) | 오피스 DB | DB 그대로, `role_code`로 참조 |
| 사용자 그룹 (0개) | 오피스 DB | 메뉴 제거 (소속은 Keycloak group) |
| 구분 사용자/마스터/루트 | DB 컬럼 | 사용자 = Role 있는 사람, 마스터 = `OFFICE_MASTER`, 루트 = `OFFICE_MASTER` + Keycloak 관리 콘솔 계정 |
| 로그내역·최종 접속내역 | 자체 로그인에서 기록 | BFF 콜백에서 기록. Keycloak event 보조 |
| BE 인가 | 미확인 | issuer `tp-office` + `aud=tp-office-admin-api` 검사 → `resource_access.tp-office-admin-api.roles` → 매트릭스 비트 판정(Role별 캐시) |

### env (2026-10-27 확정)

| 레포 | 변수 | 값(로컬) | 비고 |
|---|---|---|---|
| keycloak-auth | `KC_DB_PASSWORD`, `KC_BOOTSTRAP_ADMIN_USERNAME/PASSWORD` | | 그대로 |
| keycloak-auth | `TP_OFFICE_PARTNER_WEB_CLIENT_SECRET`, `TP_OFFICE_PARTNER_SVC_CLIENT_SECRET` | | 그대로 |
| keycloak-auth | `TP_OFFICE_PARTNER_WEB_URL` | `http://localhost:3000` | 새로. redirect·webOrigins·로그아웃 후 이동 주소 |
| keycloak-auth | `TP_OFFICE_PARTNER_WEB_BACKCHANNEL_LOGOUT_URL` | `http://host.docker.internal:3000/api/auth/keycloak/backchannel-logout` | ← `BACKCHANNEL_LOGOUT_URL` |
| keycloak-auth | `TP_TEST_CUSTOMER_PASSWORD` | | ← `IDBLOCK_TEST_CUSTOMER_PASSWORD` |
| keycloak-auth (admin 연동 때) | `TP_OFFICE_ADMIN_WEB_CLIENT_SECRET`, `TP_OFFICE_ADMIN_SVC_CLIENT_SECRET`, `TP_OFFICE_ADMIN_WEB_URL`, `TP_OFFICE_ADMIN_WEB_BACKCHANNEL_LOGOUT_URL` | | 이름만 확정 |
| BE·FE | `KEYCLOAK_OFFICE_ISSUER_URI` | `http://localhost:8080/realms/tp-office` | ← `KEYCLOAK_STAFF_ISSUER_URI` (업체·연맹도 있어 staff 아님) |
| BE | `KEYCLOAK_CUSTOMER_ISSUER_URI` | `http://localhost:8080/realms/tp` | 이름 그대로, 값만 |
| BE·FE | `KEYCLOAK_AUDIENCE`, `KEYCLOAK_SVC_CLIENT_ID`, `KEYCLOAK_CLIENT_ID` | `tp-office-partner-*` | 그대로 |

### client 구조 확정 사항 (2026-10-27)

- 위 "Realm 2개"·"client 6개"·"group"·"Role" 그대로 확정.
- `tp-office-admin-*` 3개와 그룹 `/tp-office`(`tp-office-admin-api:OFFICE_VIEWER` 매핑)는 TP 백오피스 연동 때 realm JSON에 추가 (지금은 secret·주소가 없음).
- `-svc` 그룹 권한은 실제 Keycloak 26.8.1에서 확인한 조합: Groups `view`(그룹 경로로 생성할 때 필요)·`view-members`·`manage-members`·`manage-membership`. 이걸로 그룹 멤버 조회·비번 초기화·활성 토글·로그아웃·삭제·"그룹에 넣으며 생성"이 되고, 그룹 밖 사용자 조회·그룹 없이 생성·그룹 이동·role 직접 부여·realm-admin 부여·그룹 생성은 403.
  - 2026-10-28 실측: `/crosshub` 를 `view`·`view-members` 만으로 줄이면 비번 초기화·비활성·로그아웃·삭제·생성·이메일 변경 모두 403. 2026-10-28 이렇게 바꿈. `/affiliate`·`/partner` 는 위 조합 그대로.
  - 그룹 이동(파트너 ↔ 크로스허브)은 `-svc`가 못 한다. 지금 파트너 BE에 role 변경 기능이 없어 문제없음. 필요해지면 Groups `manage-membership-of-members` 추가를 검토.
- username=email·`loginId`→`sub`는 이번 범위 밖 (`db-ownership-plan.md`와 같이).

## 3. 결정한 것 / 남은 것

결정:
- **username = 이메일** (`tp-office` realm 전체). 파트너 BE의 사용자 매칭은 `sub` 기준으로 변경, 테스트 유저 `test-crosshub` 등도 이메일 형식으로.
- **사용자 마스터 = Keycloak 단일 원본**, 양쪽 BE는 캐시 없이 Admin API 조회 (위 "사용자 마스터" 절).
- **Role 코드 원본 = Keycloak client role**, 매트릭스만 오피스 DB (위 "Role" 절).
- ~~`/crosshub`에 `OFFICE_VIEWER` 기본 부여~~ → **2026-10-28 변경: 최상위 그룹 `/tp-office` 에 따로**, 필요한 직원만.
- **크로스허브 직원 계정 관리는 한 곳** (콘솔 → TP 연동 후 `tp-office-admin-svc`). `tp-office-partner-svc` 는 `/crosshub` 조회만 — 2026-10-28 적용(realm·파트너 BE·FE 같이, 위 "② 관리 주체는 한 곳"). `/tp-office` 분리(①)와는 별개 항목.
- **권한 변경·중지 시 강제 로그아웃**으로 즉시 반영.
- **MFA 적용 안 함.**
- **`/tp-office` 외 사용자에 admin role 금지는 Keycloak Admin Permissions로 강제** (`-svc` 는 map-role 금지, role 은 그룹에서만). 콘솔 변경만 admin event로 추적.

남은 것:
1. **TP 앱 백엔드가 어느 BE인지** — `tp` realm의 이름표 client와 `tp-app` audience가 여기에 달림.
2. ~~파트너 백오피스가 운영 중인지~~ → Keycloak은 로컬 docker에만 있음. 한 번에 바꾸고 로컬은 `down -v` (2026-10-27).
3. **기존 관리자 17명 이관** — `tp-office` realm 사용자 생성(username=email) + `/tp-office`(파트너 백오피스도 쓰면 `/crosshub` 도) + 현재 관리자 Role 테이블대로 role map(마스터·루트 → `OFFICE_MASTER`). 비번은 임시 발급 후 첫 로그인 변경. `DEVELOPER_TEAM_CRU`의 IAM 메뉴 권한·`OFFICE_VIEWER` 범위는 TP 백오피스 BE에 전달만(매트릭스 영역).
   - 확인 필요: DORI·TOKI·유영근(qcitycoin) — gmail 계정에 휴대폰이 `010-4274-5822`로 동일. 테스트 계정이면 이관 제외.

## 4. 작업 순서

0. ~~크로스허브 계정 관리 한 곳으로~~ → 2026-10-28 적용(keycloak-auth·파트너 BE·파트너 FE 같이 머지). TP 작업은 이게 배포된 뒤에 시작한다 (위 "② 관리 주체는 한 곳").
1. **keycloak-auth**
   - `realm/crosshub-realm.json` → `realm/tp-office-realm.json`: realm 이름·displayName, client 3개 rename, `tp-office-admin-*` 3개 추가, group 3개 + role 매핑, `tp-office-admin-api` role 33개(`OFFICE_MASTER` composite), `tp-office-admin-svc` fine-grained 권한, realm event·admin event ON, 테스트 유저 username을 이메일로
   - `realm/idblock-realm.json` → `realm/tp-realm.json`: realm 이름, `backoffice-api` → `tp-office-partner-api`, `tp-app` audience mapper
   - `.env.example`(secret 자리표시 이름), `scripts/reset-password.sh`·`kc-test.sh`(realm·client 이름), `demo/tp-web`, `docs/tp-app-integration.md`, README
   - 검증: 임시 인스턴스(`-p kc-verify`, 포트 18080)로 import 확인 → 로컬은 `docker compose down -v` 후 up
2. **파트너 BE/FE**: `staff-issuer`·`customer-issuer`, aud 값, client ID·secret 환경변수, 테스트 코드의 `backoffice-api` 문자열, 사용자 매칭 `loginId`→`sub`, 계정 발급을 "이메일 조회 → 있으면 group 추가" 분기로, `docs/auth-architecture.md`
3. **TP 백오피스 BE**: issuer·aud 검증, Role 코드 → 매트릭스 판정(Role별 캐시), 관리자 테이블·Role 테이블 제거, 사용자·Role 관리 API를 `tp-office-admin-svc` 호출로 교체(생성·중지·배정·Role CRUD·강제 로그아웃), 권한 변경 이력 기록
4. **TP 백오피스 FE**: 로그인을 BFF로(콜백에서 로그인 이력 기록, 백채널 로그아웃 엔드포인트), 사용자 관리·관리자 Role·Role 관리 화면을 새 BE API로, 사용자 그룹 메뉴 제거
5. dev 이관(관리자 17명) → 검증 → 운영
