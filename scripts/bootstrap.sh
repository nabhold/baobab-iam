#!/usr/bin/env bash
# bootstrap.sh – idempotent realm and client provisioning
set -euo pipefail

KC_ADMIN=${KEYCLOAK_ADMIN:-admin}
KC_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin123}
KC_URL=${KC_URL:-http://localhost:8080}

# Wait for Keycloak to be ready
echo "Waiting for Keycloak at $KC_URL ..."
until curl -s -o /dev/null -w "%{http_code}" "$KC_URL/health/ready" | grep -q "200"; do
  sleep 2
done

# Login as admin
/opt/keycloak/bin/kcadm.sh config credentials --server "$KC_URL" --realm master --user "$KC_ADMIN" --password "$KC_ADMIN_PASSWORD"

# Import realm if not exists
REALM_EXISTS=$(/opt/keycloak/bin/kcadm.sh get realms/baobab > /dev/null 2>&1 && echo "yes" || echo "no")
if [ "$REALM_EXISTS" = "no" ]; then
  echo "Creating realm 'baobab'..."
  /opt/keycloak/bin/kcadm.sh create realms -f /opt/keycloak/config/realm/baobab-realm.json
else
  echo "Realm 'baobab' already exists. Skipping creation."
fi

# Import clients
for client_file in /opt/keycloak/config/clients/*.json; do
  if [ -f "$client_file" ]; then
    CLIENT_ID=$(jq -r '.clientId' "$client_file")
    echo "Importing client '$CLIENT_ID' ..."
    /opt/keycloak/bin/kcadm.sh create clients -r baobab -f "$client_file" || echo "Client '$CLIENT_ID' may already exist; skipping."
  fi
done

echo "Bootstrap completed."