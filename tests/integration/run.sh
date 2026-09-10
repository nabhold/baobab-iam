#!/usr/bin/env bash
# tests/integration/run.sh
#
# Verification suite for ADR-0002 Section 48 ("Required Verification").
# Runs from the CI runner (or a developer's host) against an already
# bootstrapped Keycloak stack — it does not exec into the container, so it
# only needs curl/jq/bash on the caller's side.
#
# Requires:
#   KC_URL                             (default: http://localhost:8080)
#   KEYCLOAK_ADMIN / KEYCLOAK_ADMIN_PASSWORD (default: admin / admin123)
#   BOOTSTRAP_WORKLOAD_CLIENT_SECRET   the same value bootstrap.sh was run with
set -euo pipefail

KC_URL=${KC_URL:-http://localhost:8080}
KC_ADMIN=${KEYCLOAK_ADMIN:-admin}
KC_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin123}
WORKLOAD_SECRET=${BOOTSTRAP_WORKLOAD_CLIENT_SECRET:?BOOTSTRAP_WORKLOAD_CLIENT_SECRET must be set to the value bootstrap.sh was run with}
REALM=baobab
EXPECTED_ISSUER="$KC_URL/realms/$REALM"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

jwt_payload() {
  local segment
  segment=$(echo "$1" | cut -d '.' -f2 | tr '_-' '/+')
  case $(( ${#segment} % 4 )) in
    2) segment="${segment}==" ;;
    3) segment="${segment}=" ;;
  esac
  echo "$segment" | base64 -d 2>/dev/null
}

get_admin_token() {
  curl -sf --max-time 30 -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=$KC_ADMIN" \
    -d "password=$KC_ADMIN_PASSWORD" \
    -d "grant_type=password" | jq -r '.access_token'
}

echo "== 1. Deterministic realm bootstrap =="
REALM_INFO=$(curl -sf --max-time 30 "$KC_URL/realms/$REALM" || echo "")
if [ -n "$REALM_INFO" ] && [ "$(echo "$REALM_INFO" | jq -r '.realm')" = "$REALM" ]; then
  pass "realm '$REALM' is provisioned and reachable"
else
  fail "realm '$REALM' is not reachable at $KC_URL/realms/$REALM"
fi

echo "== 2. OIDC discovery =="
DISCOVERY=$(curl -sf --max-time 30 "$KC_URL/realms/$REALM/.well-known/openid-configuration")
ISSUER=$(echo "$DISCOVERY" | jq -r '.issuer')
JWKS_URI=$(echo "$DISCOVERY" | jq -r '.jwks_uri')
TOKEN_ENDPOINT=$(echo "$DISCOVERY" | jq -r '.token_endpoint')
if [ "$ISSUER" = "$EXPECTED_ISSUER" ]; then
  pass "discovery document issuer matches $EXPECTED_ISSUER"
else
  fail "discovery issuer '$ISSUER' != expected '$EXPECTED_ISSUER'"
fi
if [ -n "$JWKS_URI" ] && [ "$JWKS_URI" != "null" ]; then
  pass "discovery document advertises a jwks_uri"
else
  fail "discovery document is missing jwks_uri"
fi

echo "== 3. JWKS retrieval =="
JWKS=$(curl -sf --max-time 30 "$JWKS_URI")
KEY_COUNT=$(echo "$JWKS" | jq '.keys | length')
if [ "$KEY_COUNT" -gt 0 ]; then
  pass "JWKS endpoint returned $KEY_COUNT signing key(s)"
else
  fail "JWKS endpoint returned no keys"
fi

echo "== 4. Workload client-credentials grant + actor_type/scope claims =="
# baobab-trade-workload, not baobab-trade: baobab-trade.json (bearerOnly,
# no service account) and baobab-trade-workload.json used to share the
# same clientId "baobab-trade" before this suite caught it — Keycloak had
# two client resources answering to one clientId, so which one a token
# request actually resolved to was undefined. Fixed by giving every
# workload client its own distinct clientId (config/clients/*-workload.json).
TOKEN_RESPONSE=$(curl -s --max-time 30 -X POST "$TOKEN_ENDPOINT" \
  -d "client_id=baobab-trade-workload" \
  -d "client_secret=$WORKLOAD_SECRET" \
  -d "grant_type=client_credentials")
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
if [ -n "$ACCESS_TOKEN" ]; then
  pass "workload client 'baobab-trade-workload' obtained an access token via client_credentials"
  PAYLOAD=$(jwt_payload "$ACCESS_TOKEN")
  ACTOR_TYPE=$(echo "$PAYLOAD" | jq -r '.actor_type // empty')
  SCOPE=$(echo "$PAYLOAD" | jq -r '.scope // empty')
  TOKEN_ISS=$(echo "$PAYLOAD" | jq -r '.iss // empty')
  if [ "$ACTOR_TYPE" = "workload" ]; then
    pass "token carries actor_type=workload (ADR-0006 token profile)"
  else
    fail "token actor_type claim is '$ACTOR_TYPE', expected 'workload'"
  fi
  if [[ "$SCOPE" == *"context:resolve"* ]]; then
    pass "token scope includes context:resolve (required by baobab-cp's authorize() middleware)"
  else
    fail "token scope '$SCOPE' does not include context:resolve"
  fi
  if [ "$TOKEN_ISS" = "$EXPECTED_ISSUER" ]; then
    pass "token issuer matches realm issuer"
  else
    fail "token issuer '$TOKEN_ISS' != expected '$EXPECTED_ISSUER'"
  fi
else
  fail "workload client 'baobab-trade-workload' did not receive an access token: $TOKEN_RESPONSE"
fi

echo "== 5. Wrong-client-secret rejection =="
# Deliberately uses baobab-cms-workload, not baobab-trade-workload: the
# realm has bruteForceProtected=true with a 60s minimumQuickLoginWaitSeconds,
# and a service account is a user under the hood — one deliberately-wrong
# attempt against baobab-trade-workload here would trip its "quick retry"
# penalty and cause test 8's later, legitimate check to be falsely
# rejected. baobab-cms-workload is otherwise unused in this suite, so it
# absorbs the deliberate failure without poisoning a client checked
# elsewhere.
BAD_RESPONSE=$(curl -s --max-time 30 -o /dev/null -w "%{http_code}" -X POST "$TOKEN_ENDPOINT" \
  -d "client_id=baobab-cms-workload" \
  -d "client_secret=definitely-not-the-secret" \
  -d "grant_type=client_credentials")
if [ "$BAD_RESPONSE" = "401" ]; then
  pass "wrong client secret is rejected (401)"
else
  fail "wrong client secret returned HTTP $BAD_RESPONSE, expected 401"
fi

echo "== 6. Unknown-client rejection =="
UNKNOWN_RESPONSE=$(curl -s --max-time 30 -o /dev/null -w "%{http_code}" -X POST "$TOKEN_ENDPOINT" \
  -d "client_id=does-not-exist" \
  -d "client_secret=irrelevant" \
  -d "grant_type=client_credentials")
if [ "$UNKNOWN_RESPONSE" = "401" ]; then
  pass "unknown client_id is rejected (401)"
else
  fail "unknown client_id returned HTTP $UNKNOWN_RESPONSE, expected 401"
fi

echo "== 7. PKCE S256 configured on public browser clients =="
ADMIN_TOKEN=$(get_admin_token)
for CLIENT_ID in zuribeans-web thamani-web; do
  CLIENT_JSON=$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KC_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID" | jq '.[0]')
  PKCE_METHOD=$(echo "$CLIENT_JSON" | jq -r '.attributes["pkce.code.challenge.method"] // empty')
  PUBLIC=$(echo "$CLIENT_JSON" | jq -r '.publicClient')
  IMPLICIT=$(echo "$CLIENT_JSON" | jq -r '.implicitFlowEnabled')
  if [ "$PKCE_METHOD" = "S256" ] && [ "$PUBLIC" = "true" ] && [ "$IMPLICIT" = "false" ]; then
    pass "$CLIENT_ID requires PKCE S256, is public, and implicit flow is disabled"
  else
    fail "$CLIENT_ID PKCE/public/implicit config is wrong (pkce=$PKCE_METHOD public=$PUBLIC implicit=$IMPLICIT)"
  fi
  DEFAULT_SCOPES=$(echo "$CLIENT_JSON" | jq -r '.defaultClientScopes | join(",")')
  if [[ "$DEFAULT_SCOPES" == *"actor-type-human"* ]]; then
    pass "$CLIENT_ID has the actor-type-human default scope attached"
  else
    fail "$CLIENT_ID is missing the actor-type-human default scope (scopes: $DEFAULT_SCOPES)"
  fi
done

echo "== 8. Independent workload client revocation =="
ERP_CLIENT_UUID=$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients?clientId=baobab-erp-workload" | jq -r '.[0].id')
curl -sf --max-time 30 -X PUT -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  "$KC_URL/admin/realms/$REALM/clients/$ERP_CLIENT_UUID" \
  -d '{"enabled": false}' > /dev/null
ERP_TOKEN_RESPONSE=$(curl -s --max-time 30 -o /dev/null -w "%{http_code}" -X POST "$TOKEN_ENDPOINT" \
  -d "client_id=baobab-erp-workload" \
  -d "client_secret=$WORKLOAD_SECRET" \
  -d "grant_type=client_credentials")
if [ "$ERP_TOKEN_RESPONSE" != "200" ]; then
  pass "disabling 'baobab-erp-workload' independently revokes its ability to obtain tokens (HTTP $ERP_TOKEN_RESPONSE)"
else
  fail "'baobab-erp-workload' still obtained a token after being disabled"
fi
TRADE_TOKEN_RESPONSE=$(curl -s --max-time 30 -o /dev/null -w "%{http_code}" -X POST "$TOKEN_ENDPOINT" \
  -d "client_id=baobab-trade-workload" \
  -d "client_secret=$WORKLOAD_SECRET" \
  -d "grant_type=client_credentials")
if [ "$TRADE_TOKEN_RESPONSE" = "200" ]; then
  pass "revoking 'baobab-erp-workload' did not affect unrelated workload 'baobab-trade-workload' (independent revocation, ADR-0007)"
else
  fail "'baobab-trade-workload' unexpectedly lost access after an unrelated client was disabled (HTTP $TRADE_TOKEN_RESPONSE)"
fi
# Restore state for idempotent re-runs.
curl -sf --max-time 30 -X PUT -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  "$KC_URL/admin/realms/$REALM/clients/$ERP_CLIENT_UUID" \
  -d '{"enabled": true}' > /dev/null

echo ""
echo "== Summary: $PASS passed, $FAIL failed =="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
