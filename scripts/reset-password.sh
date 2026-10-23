#!/usr/bin/env bash
# Keycloak 유저 비번을 임시 비번으로 초기화 (+ 잠금 해제). 첫 로그인 때 새 비번 설정을 강제한다.
# 사용: bash scripts/reset-password.sh test-partner 'Temp-1234!'
# backoffice-admin-api(service account)로 Admin API를 부른다 — 백오피스 "비번 초기화"와 같은 경로.
set -euo pipefail
cd "$(dirname "$0")/.."
USERNAME=${1:?사용: reset-password.sh <username> <임시비번>}
TEMP=${2:?임시 비번 (8자 이상, 숫자·특수문자 포함)}
set -a; source .env; set +a
KC=${KC_URL:-http://localhost:8080}; R=crosshub
TOKEN=$(curl -sf -X POST "$KC/realms/$R/protocol/openid-connect/token" \
  -d grant_type=client_credentials -d client_id=backoffice-admin-api -d client_secret="$BACKOFFICE_ADMIN_API_CLIENT_SECRET" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
ID=$(curl -sf -H "Authorization: Bearer $TOKEN" "$KC/admin/realms/$R/users?username=$USERNAME&exact=true" \
  | python3 -c "import sys,json;r=json.load(sys.stdin);print(r[0]['id'] if r else '')")
[ -n "$ID" ] || { echo "유저 없음: $USERNAME"; exit 1; }
curl -s -o /dev/null -X DELETE -H "Authorization: Bearer $TOKEN" "$KC/admin/realms/$R/attack-detection/brute-force/users/$ID" || true
BODY=$(python3 -c "import json,sys;print(json.dumps({'type':'password','value':sys.argv[1],'temporary':True}))" "$TEMP")
code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$BODY" "$KC/admin/realms/$R/users/$ID/reset-password")
[ "$code" = "204" ] && echo "✅ $USERNAME 임시 비번 설정 완료 (첫 로그인 때 변경)" || echo "❌ 실패 HTTP $code (비번 정책: 8자+, 숫자·특수문자)"
