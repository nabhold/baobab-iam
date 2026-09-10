#!/usr/bin/env bash
# bootstrap.sh – idempotent realm and client provisioning
set -euo pipefail

KC_ADMIN=${KEYCLOAK_ADMIN:-admin}
KC_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin123}
KC_URL=${KC_URL:-http://localhost:8080}

# kcadm.sh persists its login session to $HOME/.keycloak/kcadm.config by
# default. The runtime container has no /etc/passwd entry for its non-root
# UID, so $HOME resolves to empty/"/" — which that UID cannot write to
# ("Failed to create config file: /.keycloak/kcadm.config"). Rather than
# depend on which directories under /opt/keycloak happen to be writable by
# that UID, point the config file at a fresh file under /tmp, which is
# writable by any UID regardless of image specifics.
KCADM_CONFIG=$(mktemp)
kcadm() {
  /opt/keycloak/bin/kcadm.sh "$@" --config "$KCADM_CONFIG"
}

# Wait for Keycloak to be ready, then log in as admin.
#
# This retries kcadm's own login rather than curl-polling a health
# endpoint: kcadm.sh is a bundled Java CLI with its own HTTP client, so it
# needs no extra runtime dependency, and a successful login both confirms
# readiness and completes the login step in one loop. (An earlier version
# of this script used curl for the wait loop, which required installing
# curl into the image — removed after a vulnerability scan flagged
# multiple HIGH-severity CVEs in the ubi9-provided curl/libcurl package
# with no fixed version yet available upstream; kcadm.sh has no such
# exposure since it ships with Keycloak itself.)
echo "Waiting for Keycloak at $KC_URL ..."
READY=0
for _ in $(seq 1 60); do
  if kcadm config credentials --server "$KC_URL" --realm master --user "$KC_ADMIN" --password "$KC_ADMIN_PASSWORD"; then
    READY=1
    break
  fi
  sleep 5
done
if [ "$READY" -ne 1 ]; then
  echo "Keycloak admin login did not succeed within 5 minutes; giving up." >&2
  exit 1
fi

# Import realm if not exists
REALM_EXISTS=$(kcadm get realms/baobab > /dev/null 2>&1 && echo "yes" || echo "no")
if [ "$REALM_EXISTS" = "no" ]; then
  echo "Creating realm 'baobab'..."
  kcadm create realms -f /opt/keycloak/config/realm/baobab-realm.json
else
  echo "Realm 'baobab' already exists. Skipping creation."
fi

# Import client scopes (custom scopes required by ADR-0006's token profile,
# e.g. actor-type-human, actor-type-workload, context:resolve). These must
# exist before any client references them in defaultClientScopes.
for scope_file in /opt/keycloak/config/scopes/*.json; do
  if [ -f "$scope_file" ]; then
    SCOPE_NAME=$(jq -r '.name' "$scope_file")
    echo "Creating client scope '$SCOPE_NAME' ..."
    kcadm create client-scopes -r baobab -f "$scope_file" || echo "Client scope '$SCOPE_NAME' may already exist; skipping."
  fi
done

# Import workload clients (service accounts).
#
# BOOTSTRAP_WORKLOAD_CLIENT_SECRET, when set, seeds every workload client
# with the same deterministic secret at creation time. This exists ONLY to
# make local development and CI integration testing (tests/integration/)
# reproducible without a Keycloak admin round-trip per client. Production
# secrets SHALL be injected by the platform secret-management boundary per
# ADR-0002 Section 25 and SHALL NOT use this variable.
for client_file in /opt/keycloak/config/clients/*-workload.json; do
  if [ -f "$client_file" ]; then
    CLIENT_ID=$(jq -r '.clientId' "$client_file")
    echo "Creating workload client '$CLIENT_ID' ..."
    if [ -n "${BOOTSTRAP_WORKLOAD_CLIENT_SECRET:-}" ]; then
      TMP_FILE=$(mktemp)
      jq --arg secret "$BOOTSTRAP_WORKLOAD_CLIENT_SECRET" '. + {secret: $secret}' "$client_file" > "$TMP_FILE"
      kcadm create clients -r baobab -f "$TMP_FILE" || echo "Client '$CLIENT_ID' may already exist; skipping."
      rm -f "$TMP_FILE"
    else
      kcadm create clients -r baobab -f "$client_file" || echo "Client '$CLIENT_ID' may already exist; skipping."
    fi
  fi
done

# Import remaining (non-workload) clients. Workload files are excluded here
# since the loop above already imports them — matching them again against
# the broad *.json glob previously caused a redundant, silently-swallowed
# second create attempt per workload client.
for client_file in /opt/keycloak/config/clients/*.json; do
  case "$client_file" in
    *-workload.json) continue ;;
  esac
  if [ -f "$client_file" ]; then
    CLIENT_ID=$(jq -r '.clientId' "$client_file")
    echo "Importing client '$CLIENT_ID' ..."
    kcadm create clients -r baobab -f "$client_file" || echo "Client '$CLIENT_ID' may already exist; skipping."
  fi
done

rm -f "$KCADM_CONFIG"
echo "Bootstrap completed."
