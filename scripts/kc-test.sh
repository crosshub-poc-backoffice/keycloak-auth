#!/usr/bin/env bash
# 로컬 검수용 Keycloak 조작 (tp-office realm)
#   bash scripts/kc-test.sh set-group <username> <crosshub|affiliate|partner>     그룹을 이것 하나로 바꾼다 (= 파트너 백오피스 role 변경)
#   bash scripts/kc-test.sh roles <username>                                     그룹과, 그룹에서 오는 tp-office-partner-api role 보기
#   bash scripts/kc-test.sh logout <username>                                    그 유저의 Keycloak 세션 전부 종료(백채널 로그아웃 발생)
# roles·logout 은 tp-office-partner-svc(BE 와 같은 권한)로 부른다.
# set-group 은 svc 가 할 수 없는 일(그룹 이동)이라 .env 의 최초 관리자(KC_BOOTSTRAP_ADMIN_*)로 부른다 — 관리 콘솔에서 하는 것과 같다.
set -euo pipefail
cd "$(dirname "$0")/.."
CMD=${1:?사용: kc-test.sh <set-group|roles|logout> <username> [group]}
USERNAME=${2:?username 필요}
set -a; source .env; set +a
KC=${KC_URL:-http://localhost:8080}; R=tp-office; CLIENT=tp-office-partner-api   # 파트너 백오피스 role 이 붙는 BE 이름표 client
token() {
  if [ "$1" = admin ]; then
    curl -sf -X POST "$KC/realms/master/protocol/openid-connect/token" -d grant_type=password -d client_id=admin-cli \
      --data-urlencode username="$KC_BOOTSTRAP_ADMIN_USERNAME" --data-urlencode password="$KC_BOOTSTRAP_ADMIN_PASSWORD"
  else
    curl -sf -X POST "$KC/realms/$R/protocol/openid-connect/token" \
      -d grant_type=client_credentials -d client_id=tp-office-partner-svc -d client_secret="$TP_OFFICE_PARTNER_SVC_CLIENT_SECRET"
  fi | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])"
}
H=(-H "Authorization: Bearer $(token $([ "$CMD" = set-group ] && echo admin || echo svc))")
UID_=$(curl -sf "${H[@]}" "$KC/admin/realms/$R/users?username=$USERNAME&exact=true" | python3 -c "import sys,json;r=json.load(sys.stdin);print(r[0]['id'] if r else '')")
[ -n "$UID_" ] || { echo "❌ 유저 없음: $USERNAME"; exit 1; }
show() {
  CID=$(curl -sf "${H[@]}" "$KC/admin/realms/$R/clients?clientId=$CLIENT" | python3 -c "import sys,json;print(json.load(sys.stdin)[0]['id'])")
  curl -sf "${H[@]}" "$KC/admin/realms/$R/users/$UID_/groups" | python3 -c "import sys,json;print('groups:', [g['path'] for g in json.load(sys.stdin)])"
  curl -sf "${H[@]}" "$KC/admin/realms/$R/users/$UID_/role-mappings/clients/$CID/composite" | python3 -c "import sys,json;print('roles:', [r['name'] for r in json.load(sys.stdin)])"
}
case "$CMD" in
  roles) show ;;
  set-group)
    GROUP=${3:?group 필요 (crosshub|affiliate|partner)}
    GID=$(curl -sf "${H[@]}" "$KC/admin/realms/$R/group-by-path/$GROUP" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
    for old in $(curl -sf "${H[@]}" "$KC/admin/realms/$R/users/$UID_/groups" | python3 -c "import sys,json;print(' '.join(g['id'] for g in json.load(sys.stdin)))"); do
      [ "$old" = "$GID" ] || curl -sf -X DELETE "${H[@]}" "$KC/admin/realms/$R/users/$UID_/groups/$old"
    done
    code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${H[@]}" "$KC/admin/realms/$R/users/$UID_/groups/$GID")
    [ "$code" = "204" ] && echo "✅ $USERNAME → /$GROUP" || echo "❌ 실패 HTTP $code"
    show ;;
  logout)
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${H[@]}" "$KC/admin/realms/$R/users/$UID_/logout")
    [ "$code" = "204" ] && echo "✅ $USERNAME Keycloak 세션 종료 (백채널 로그아웃 전송됨)" || echo "❌ 실패 HTTP $code" ;;
  *) echo "모르는 명령: $CMD"; exit 1 ;;
esac
