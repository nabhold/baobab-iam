#!/usr/bin/env bash
# test.sh – smoke test for baobab-iam
set -euo pipefail

KC_URL=${KC_URL:-http://localhost:8080}
REALM="baobab"

echo "Testing OIDC discovery..."
curl -fsSL "$KC_URL/realms/$REALM/.well-known/openid-configuration" > /dev/null

echo "Testing JWKS endpoint..."
curl -fsSL "$KC_URL/realms/$REALM/protocol/openid-connect/certs" > /dev/null

echo "Testing health endpoint..."
curl -fsSL "$KC_URL/health/ready" | grep -q "UP"

echo "Testing token issuance for a workload client (baobab-trade)..."
# We need to obtain a token using client credentials.
# This requires that the client secret is set; we can read it from .env.
# For simplicity in CI, we assume the secret is available.
CLIENT_ID="baobab-trade"
CLIENT_SECRET=${BAOBAB_TRADE_SECRET:-}
if [ -z "$CLIENT_SECRET" ]; then
  echo "WARNING: BAOBAB_TRADE_SECRET not set, skipping token test."
else
  TOKEN=$(curl -s -X POST "$KC_URL/realms/$REALM/protocol/openid-connect/token" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "grant_type=client_credentials" | jq -r '.access_token')
  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "Failed to obtain token"
    exit 1
  fi
  echo "Token obtained successfully."
fi

echo "All tests passed."