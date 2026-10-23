#!/usr/bin/env bash
# 로컬 검수용 Keycloak 조작 (backoffice-admin-api service account로 Admin API 호출 — 비밀번호 입력 없음)
#   bash scripts/kc-test.sh add-role <username> <crosshub|affiliate|partner>     poc-backoffice client role 추가
#   bash scripts/kc-test.sh remove-role <username> <role>                         client role 제거
#   bash scripts/kc-test.sh roles <username>                                      현재 client role 보기
#   bash scripts/kc-test.sh logout <username>                                     그 유저의 Keycloak 세션 전부 종료(백채널 로그아웃 발생)
set -euo pipefail
cd "$(dirname "$0")/.."
CMD=${1:?사용: kc-test.sh <add-role|remove-role|roles|logout> <username> [role]}
USERNAME=${2:?username 필요}
set -a; source .env; set +a
KC=${KC_URL:-http://localhost:8080}; R=crosshub; CLIENT=poc-backoffice
TOKEN=$(curl -sf -X POST "$KC/realms/$R/protocol/openid-connect/token" \
  -d grant_type=client_credentials -d client_id=backoffice-admin-api -d client_secret="$BACKOFFICE_ADMIN_API_CLIENT_SECRET" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
H=(-H "Authorization: Bearer $TOKEN")
UID_=$(curl -sf "${H[@]}" "$KC/admin/realms/$R/users?username=$USERNAME&exact=true" | python3 -c "import sys,json;r=json.load(sys.stdin);print(r[0]['id'] if r else '')")
[ -n "$UID_" ] || { echo "❌ 유저 없음: $USERNAME"; exit 1; }
CID=$(curl -sf "${H[@]}" "$KC/admin/realms/$R/clients?clientId=$CLIENT" | python3 -c "import sys,json;print(json.load(sys.stdin)[0]['id'])")
case "$CMD" in
  roles)
    curl -sf "${H[@]}" "$KC/admin/realms/$R/users/$UID_/role-mappings/clients/$CID" | python3 -c "import sys,json;print('roles:', [r['name'] for r in json.load(sys.stdin)])" ;;
  add-role|remove-role)
    ROLE=${3:?role 필요}
    REP=$(curl -sf "${H[@]}" "$KC/admin/realms/$R/clients/$CID/roles/$ROLE")
    METHOD=$([ "$CMD" = add-role ] && echo POST || echo DELETE)
    code=$(curl -s -o /dev/null -w "%{http_code}" -X $METHOD "${H[@]}" -H "Content-Type: application/json" -d "[$REP]" \
      "$KC/admin/realms/$R/users/$UID_/role-mappings/clients/$CID")
    [ "$code" = "204" ] && echo "✅ $CMD $USERNAME $ROLE" || echo "❌ 실패 HTTP $code"
    curl -sf "${H[@]}" "$KC/admin/realms/$R/users/$UID_/role-mappings/clients/$CID" | python3 -c "import sys,json;print('now roles:', [r['name'] for r in json.load(sys.stdin)])" ;;
  logout)
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${H[@]}" "$KC/admin/realms/$R/users/$UID_/logout")
    [ "$code" = "204" ] && echo "✅ $USERNAME Keycloak 세션 종료 (백채널 로그아웃 전송됨)" || echo "❌ 실패 HTTP $code" ;;
  *) echo "모르는 명령: $CMD"; exit 1 ;;
esac
