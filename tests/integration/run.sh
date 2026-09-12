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
#
# Section 9 also fetches nabhold/shared's workload-registry.yaml (pinned in
# contracts.lock.yaml) over the network and needs yq in addition to
# curl/jq/bash -- this happens here, not in scripts/bootstrap.sh, because
# the Keycloak container bootstrap.sh runs in deliberately has neither curl
# nor yq (see Dockerfile's tools-build stage comment: curl was removed for
# unfixed ubi9 CVEs, and nothing else in the image needed it back).
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
  AUDIENCE=$(echo "$PAYLOAD" | jq -r 'if (.aud | type) == "array" then .aud | join(",") else (.aud // empty) end')
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
  if [[ ",$AUDIENCE," == *",baobab-control-plane,"* ]]; then
    pass "token carries aud=baobab-control-plane (ADR-0007 §§24-25, required by baobab-cp's go-oidc audience check)"
  else
    fail "token aud claim is '$AUDIENCE', expected to include 'baobab-control-plane'"
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

echo "== 9. Workload registry consistency (ADR-0007 §42-44) =="
LOCK_SHA=$(yq -o=json '.' contracts.lock.yaml | jq -r '.contracts[0].sha')
REGISTRY_YAML=$(curl -sf --max-time 30 "https://raw.githubusercontent.com/nabhold/shared/$LOCK_SHA/contracts/identity/v1/workload-registry.yaml" || echo "")
if [ -z "$REGISTRY_YAML" ]; then
  fail "could not fetch nabhold/shared's workload-registry.yaml at pinned commit $LOCK_SHA (contracts.lock.yaml)"
else
  REGISTRY_JSON=$(echo "$REGISTRY_YAML" | yq -o=json '.')
  REGISTRY_IDS=$(echo "$REGISTRY_JSON" | jq -r '.workloads | keys[]')
  # config/clients/*-workload.json's *filenames* all end in "-workload", but
  # the clientId inside doesn't always (thamani-backend/zuribeans-backend
  # never had the clientId collision the other four did -- see
  # gate-iam-0-discovery.md §4.9 -- so they were never renamed to match
  # their filename). Look up by clientId content below, never by filename.
  LOCAL_CLIENT_IDS=""
  DRIFT=0
  for CLIENT_FILE in config/clients/*-workload.json; do
    CLIENT_ID=$(jq -r '.clientId' "$CLIENT_FILE")
    LOCAL_CLIENT_IDS=$(printf '%s\n%s' "$LOCAL_CLIENT_IDS" "$CLIENT_ID")
    if ! echo "$REGISTRY_IDS" | grep -qx "$CLIENT_ID"; then
      fail "workload client '$CLIENT_ID' ($CLIENT_FILE) is not registered in nabhold/shared's workload registry (ADR-0007 §44: an orphaned IAM client is a security defect)"
      DRIFT=1
      continue
    fi
    ALLOWED_SCOPES=$(echo "$REGISTRY_JSON" | jq -r --arg id "$CLIENT_ID" '.workloads[$id].allowed_scopes[]')
    # Only the ADR-0007-specific custom scope is checked against the
    # registry's allowlist -- built-in Keycloak default scopes (openid,
    # profile, roles, ...) aren't part of what this registry governs.
    for SCOPE in $(jq -r '.defaultClientScopes[] | select(. == "context:resolve")' "$CLIENT_FILE"); do
      if ! echo "$ALLOWED_SCOPES" | grep -qx "$SCOPE"; then
        fail "workload client '$CLIENT_ID' grants scope '$SCOPE', which is not in its workload-registry.yaml allowed_scopes"
        DRIFT=1
      fi
    done
  done
  if [ "$DRIFT" -eq 0 ]; then
    pass "every config/clients/*-workload.json client is registered, with scopes within its registry allowlist"
  fi
  ACTIVE_WITHOUT_CLIENT=0
  for ID in $(echo "$REGISTRY_JSON" | jq -r '.workloads | to_entries[] | select(.value.status == "ACTIVE") | .key'); do
    if ! echo "$LOCAL_CLIENT_IDS" | grep -qx "$ID"; then
      fail "workload registry lists ACTIVE workload '$ID' but no config/clients/*.json declares that clientId"
      ACTIVE_WITHOUT_CLIENT=1
    fi
  done
  if [ "$ACTIVE_WITHOUT_CLIENT" -eq 0 ]; then
    pass "every ACTIVE workload in the registry has a matching config/clients/*.json clientId"
  fi
fi

echo "== 10. Cross-workload identity isolation (ADR-0007 §102 impersonation checks) =="
PULSE_TOKEN_RESPONSE=$(curl -s --max-time 30 -X POST "$TOKEN_ENDPOINT" \
  -d "client_id=baobab-pulse-workload" \
  -d "client_secret=$WORKLOAD_SECRET" \
  -d "grant_type=client_credentials")
PULSE_ACCESS_TOKEN=$(echo "$PULSE_TOKEN_RESPONSE" | jq -r '.access_token // empty')
if [ -n "$PULSE_ACCESS_TOKEN" ] && [ -n "${ACCESS_TOKEN:-}" ]; then
  PULSE_PAYLOAD=$(jwt_payload "$PULSE_ACCESS_TOKEN")
  TRADE_AZP=$(echo "$PAYLOAD" | jq -r '.azp // empty')
  PULSE_AZP=$(echo "$PULSE_PAYLOAD" | jq -r '.azp // empty')
  TRADE_SUB=$(echo "$PAYLOAD" | jq -r '.sub // empty')
  PULSE_SUB=$(echo "$PULSE_PAYLOAD" | jq -r '.sub // empty')
  if [ "$TRADE_AZP" = "baobab-trade-workload" ] && [ "$PULSE_AZP" = "baobab-pulse-workload" ]; then
    pass "each workload's token carries its own azp (no cross-workload identity leakage)"
  else
    fail "azp does not exclusively identify its own client (trade azp='$TRADE_AZP', pulse azp='$PULSE_AZP')"
  fi
  if [ -n "$TRADE_SUB" ] && [ "$TRADE_SUB" != "$PULSE_SUB" ]; then
    pass "baobab-trade-workload and baobab-pulse-workload resolve to distinct subjects"
  else
    fail "baobab-trade-workload and baobab-pulse-workload unexpectedly share a subject ('$TRADE_SUB'), which would let one impersonate the other"
  fi
else
  fail "could not obtain both trade and pulse workload tokens for the cross-workload isolation check"
fi
# ADR-0007 §102's "development credential rejected in production" isolation
# case is NOT covered above: this realm has no environment-separated
# workload clients yet (every workload-registry.yaml entry is
# environment: production) -- that's Gate IAM-2's environment-separation
# work (see README.md's Status section), not something Gate IAM-4 can test
# against real infrastructure until it exists.

echo "== 11. Workforce admin client separation (Gate IAM-5, ADR-0009 §9-10) =="
ADMIN_TOKEN=$(get_admin_token)
for CLIENT_ID in baobab-control-plane-admin baobab-cms-admin baobab-trade-admin; do
  CLIENT_JSON=$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KC_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID" | jq '.[0]')
  if [ "$CLIENT_JSON" = "null" ] || [ -z "$CLIENT_JSON" ]; then
    fail "$CLIENT_ID is not provisioned"
    continue
  fi
  STANDARD_FLOW=$(echo "$CLIENT_JSON" | jq -r '.standardFlowEnabled')
  BEARER_ONLY=$(echo "$CLIENT_JSON" | jq -r '.bearerOnly')
  PKCE_METHOD=$(echo "$CLIENT_JSON" | jq -r '.attributes["pkce.code.challenge.method"] // empty')
  if [ "$STANDARD_FLOW" = "true" ] && [ "$BEARER_ONLY" = "false" ] && [ "$PKCE_METHOD" = "S256" ]; then
    pass "$CLIENT_ID is a distinct SSO login client (standardFlow, not bearer-only, PKCE S256)"
  else
    fail "$CLIENT_ID login config is wrong (standardFlow=$STANDARD_FLOW bearerOnly=$BEARER_ONLY pkce=$PKCE_METHOD)"
  fi
  DEFAULT_SCOPES=$(echo "$CLIENT_JSON" | jq -r '.defaultClientScopes | join(",")')
  if [[ "$DEFAULT_SCOPES" == *"actor-type-human"* ]]; then
    pass "$CLIENT_ID has the actor-type-human default scope attached"
  else
    fail "$CLIENT_ID is missing the actor-type-human default scope (scopes: $DEFAULT_SCOPES)"
  fi
done
# ADR-0009 §10: each admin client is a distinct registration from the
# engine's own bearer-only resource-server client (baobab-control-plane,
# baobab-cms, baobab-trade) -- confirming they're separate clientIds, not
# that one was reused, since §9 explicitly prohibits a universal admin
# client covering multiple systems.
ENGINE_CLIENT_COUNT=$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients?clientId=baobab-control-plane" | jq 'length')
if [ "$ENGINE_CLIENT_COUNT" = "1" ]; then
  pass "baobab-control-plane (engine) and baobab-control-plane-admin (workforce) remain distinct client registrations"
else
  fail "expected exactly one baobab-control-plane client alongside the new admin client, found $ENGINE_CLIENT_COUNT"
fi

echo "== 12. Workforce role namespace least privilege (ADR-0009 §13, §87-88, §102-103) =="
for ROLE in "iam:security-admin" "iam:helpdesk" "cp:platform-admin" "cp:tenant-admin" "trade:operator" "cms:editor" "cms:publisher"; do
  # ":" is a valid unencoded path-segment character per RFC 3986 pchar, so
  # the role name needs no percent-encoding here.
  ROLE_JSON=$(curl -s --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KC_URL/admin/realms/$REALM/roles/$ROLE")
  ROLE_NAME=$(echo "$ROLE_JSON" | jq -r '.name // empty')
  if [ "$ROLE_NAME" = "$ROLE" ]; then
    pass "realm role '$ROLE' is provisioned"
  else
    fail "realm role '$ROLE' is not provisioned"
  fi
done
DEFAULT_REALM_ROLE_NAMES=$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/roles/default-roles-$REALM/composites" | jq -r '[.[].name] | join(",")')
if [[ "$DEFAULT_REALM_ROLE_NAMES" != *"iam:"* ]] && [[ "$DEFAULT_REALM_ROLE_NAMES" != *"cp:"* ]] && [[ "$DEFAULT_REALM_ROLE_NAMES" != *"trade:"* ]] && [[ "$DEFAULT_REALM_ROLE_NAMES" != *"cms:"* ]]; then
  pass "no workforce admin role is granted by default to a new user (ADR-0009 §13 least privilege, §87-88 no privileged JIT)"
else
  fail "a workforce admin role is unexpectedly part of default-roles-$REALM: $DEFAULT_REALM_ROLE_NAMES"
fi

echo "== 13. Zuribeans B2B: Organizations feature (Gate IAM-6, ADR-0010 §5-9) =="
REALM_ORG_ENABLED=$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM" | jq -r '.organizationsEnabled')
if [ "$REALM_ORG_ENABLED" = "true" ]; then
  pass "realm '$REALM' has the Organizations feature enabled (organizationsEnabled=true)"
else
  fail "realm '$REALM' does not have organizationsEnabled=true (got '$REALM_ORG_ENABLED')"
fi
ORG_SCOPE_JSON=$(curl -s --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/client-scopes" | jq '[.[] | select(.name == "organization")][0]')
ORG_SCOPE_MAPPER=$(echo "$ORG_SCOPE_JSON" | jq -r '.protocolMappers[0].protocolMapper // empty')
if [ "$ORG_SCOPE_MAPPER" = "oidc-organization-membership-mapper" ]; then
  pass "the 'organization' client scope exists with Keycloak's organization-membership mapper"
else
  fail "the 'organization' client scope is missing or lacks the organization-membership mapper (found '$ORG_SCOPE_MAPPER')"
fi
ZURIBEANS_OPTIONAL_SCOPES=$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients?clientId=zuribeans-web" | jq -r '.[0].optionalClientScopes | join(",")')
if [[ "$ZURIBEANS_OPTIONAL_SCOPES" == *"organization"* ]]; then
  pass "zuribeans-web can request the 'organization' scope (ADR-0010 §35 explicit buyer-context selection)"
else
  fail "zuribeans-web is missing the 'organization' optional scope (scopes: $ZURIBEANS_OPTIONAL_SCOPES)"
fi
# End-to-end smoke test: the feature is not just configured but functional
# against a real Keycloak instance. Idempotent: the test organization is
# deleted at the end regardless of outcome so re-runs don't accumulate state
# or collide on the unique alias.
ORG_ALIAS="gate-iam-6-smoketest"
curl -s --max-time 30 -X DELETE -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/organizations/$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" "$KC_URL/admin/realms/$REALM/organizations?search=$ORG_ALIAS&exact=true" | jq -r '.[0].id // empty')" > /dev/null 2>&1 || true
ORG_CREATE_RESPONSE=$(curl -s --max-time 30 -o /tmp/org-create-response.txt -w "%{http_code}" -X POST \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  "$KC_URL/admin/realms/$REALM/organizations" \
  -d "{\"name\":\"Gate IAM-6 Smoke Test\",\"alias\":\"$ORG_ALIAS\",\"domains\":[{\"name\":\"gate-iam-6-smoketest.example.invalid\"}]}")
if [ "$ORG_CREATE_RESPONSE" = "201" ]; then
  pass "creating a real Organization via the Admin API succeeds end-to-end"
else
  fail "creating a real Organization via the Admin API failed (HTTP $ORG_CREATE_RESPONSE): $(cat /tmp/org-create-response.txt)"
fi
ORG_ID=$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/organizations?search=$ORG_ALIAS&exact=true" | jq -r '.[0].id // empty')
if [ -n "$ORG_ID" ]; then
  curl -s --max-time 30 -X DELETE -H "Authorization: Bearer $ADMIN_TOKEN" \
    "$KC_URL/admin/realms/$REALM/organizations/$ORG_ID" > /dev/null
fi
rm -f /tmp/org-create-response.txt

echo "== 14. ERP workforce SSO client (Gate IAM-10, ADR-0014 §6-9, §115) =="
ERP_ADMIN_JSON=$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients?clientId=baobab-erp-admin" | jq '.[0]')
if [ "$ERP_ADMIN_JSON" = "null" ] || [ -z "$ERP_ADMIN_JSON" ]; then
  fail "baobab-erp-admin is not provisioned"
else
  STANDARD_FLOW=$(echo "$ERP_ADMIN_JSON" | jq -r '.standardFlowEnabled')
  BEARER_ONLY=$(echo "$ERP_ADMIN_JSON" | jq -r '.bearerOnly')
  if [ "$STANDARD_FLOW" = "true" ] && [ "$BEARER_ONLY" = "false" ]; then
    pass "baobab-erp-admin is a distinct SSO login client (standardFlow, not bearer-only)"
  else
    fail "baobab-erp-admin login config is wrong (standardFlow=$STANDARD_FLOW bearerOnly=$BEARER_ONLY)"
  fi
  DEFAULT_SCOPES=$(echo "$ERP_ADMIN_JSON" | jq -r '.defaultClientScopes | join(",")')
  if [[ "$DEFAULT_SCOPES" == *"actor-type-human"* ]]; then
    pass "baobab-erp-admin has the actor-type-human default scope attached"
  else
    fail "baobab-erp-admin is missing the actor-type-human default scope (scopes: $DEFAULT_SCOPES)"
  fi
  # Deliberately different from baobab-trade-admin/baobab-cms-admin: verified
  # directly against org.idempiere.ui.sso.oidc's source (idempiere/idempiere)
  # that iDempiere's built-in OIDC plugin never sends a code_challenge, so
  # requiring PKCE here would break every real login attempt.
  PKCE_METHOD=$(echo "$ERP_ADMIN_JSON" | jq -r '.attributes["pkce.code.challenge.method"] // empty')
  if [ -z "$PKCE_METHOD" ]; then
    pass "baobab-erp-admin has no PKCE requirement (iDempiere's OIDC plugin does not support it)"
  else
    fail "baobab-erp-admin unexpectedly requires PKCE ($PKCE_METHOD), which iDempiere's stock OIDC plugin cannot satisfy"
  fi
fi
ERP_ENGINE_CLIENT_COUNT=$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients?clientId=baobab-erp" | jq 'length')
if [ "$ERP_ENGINE_CLIENT_COUNT" = "1" ]; then
  pass "baobab-erp (engine) and baobab-erp-admin (workforce) remain distinct client registrations"
else
  fail "expected exactly one baobab-erp client alongside baobab-erp-admin, found $ERP_ENGINE_CLIENT_COUNT"
fi
ERP_WORKLOAD_SCOPES=$(curl -sf --max-time 30 -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$KC_URL/admin/realms/$REALM/clients?clientId=baobab-erp-workload" | jq -r '.[0].defaultClientScopes | join(",")')
if [[ "$ERP_WORKLOAD_SCOPES" == *"erp:integrate"* ]]; then
  pass "baobab-erp-workload carries the erp:integrate scope (ADR-0014 §111)"
else
  fail "baobab-erp-workload is missing the erp:integrate scope (scopes: $ERP_WORKLOAD_SCOPES)"
fi
ERP_INTEGRATE_TOKEN_RESPONSE=$(curl -s --max-time 30 -X POST \
  "$KC_URL/realms/$REALM/protocol/openid-connect/token" \
  -d "client_id=baobab-erp-workload" \
  -d "client_secret=$WORKLOAD_SECRET" \
  -d "grant_type=client_credentials" \
  -d "scope=erp:integrate")
ERP_INTEGRATE_ACCESS_TOKEN=$(echo "$ERP_INTEGRATE_TOKEN_RESPONSE" | jq -r '.access_token // empty')
if [ -n "$ERP_INTEGRATE_ACCESS_TOKEN" ]; then
  ERP_INTEGRATE_AUD=$(jwt_payload "$ERP_INTEGRATE_ACCESS_TOKEN" | jq -r 'if (.aud | type) == "array" then .aud[] else .aud end' | tr '\n' ',')
  if [[ "$ERP_INTEGRATE_AUD" == *"baobab-erp"* ]]; then
    pass "a baobab-erp-workload token requesting erp:integrate carries aud=baobab-erp"
  else
    fail "a baobab-erp-workload token requesting erp:integrate has aud='$ERP_INTEGRATE_AUD', expected it to include baobab-erp"
  fi
else
  fail "could not obtain a baobab-erp-workload token with the erp:integrate scope"
fi

echo ""
echo "== Summary: $PASS passed, $FAIL failed =="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
