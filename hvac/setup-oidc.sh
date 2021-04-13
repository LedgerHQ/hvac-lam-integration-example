#!/usr/bin/env bash

set -eu


check_installed() {
  if [ -z "${1}" ]; then
    echo "nothing to check; aborting"
    return 1
  fi;
  echo "checking ${1} installation"
  if command -v "${1}"; then
    echo "program ${1} found"
  else
    echo "${1} is not installed ; aborting script"
    return 1
  fi;
}

check_installed jq
test $? -eq 0 || exit

check_installed python
test $? -eq 0 || exit

check_installed vault
test $? -eq 0 || exit

# shellcheck disable=SC2046
# we do actually want the word split to occur
export $(cat $(dirname "${0}")/env_files/*.env | xargs)

echo "${VAULT_DEV_ROOT_TOKEN_ID}" | vault login -

# shellcheck source=hvac/hvac-certs.sh
. "$(dirname "${0}")"/hvac-certs.sh check

# enable OIDC authentication and get accessor id
vault auth enable oidc
oidc_accessor_id=$(vault auth list -format=json| jq -r '."oidc/".accessor')


# Create a default role associated with OIDC-authenticated user
# this role is tied to a policy.
#
# The user_claim="email" parameter means that authenticated users
# are identified by their email on the hashicorp vault.
#
# The oidc_scopes="email,profile" are the claims associated with the user asked by the
# hashicorp vault to the OIDC provider.
vault write auth/oidc/role/"${HASHICORP_OIDC_ROLE}" \
allowed_redirect_uris="http://localhost:8250/oidc/callback,http://localhost:8200/oidc/callback" \
policies="${HASHICORP_POLICY_NAME}" \
user_claim="email" \
ttl="60m" role_type="oidc" \
oidc_scopes="email,profile"

# Write OIDC configuration
vault write auth/oidc/config default_role="${HASHICORP_OIDC_ROLE}" \
oidc_discovery_url="${OIDC_DISCOVERY_URL}" \
oidc_client_id="${OIDC_CLIENT_ID}" \
oidc_client_secret="${OIDC_CLIENT_SECRET}" \
oidc_scope="oidc,email"

vault policy write "${HASHICORP_POLICY_NAME}" - <<EOF
# cat - <<EOF
# to list secret, the given path must be under secret/metadata
path "secret/metadata/${USER_STORAGE_PATH}/{{identity.entity.aliases.${oidc_accessor_id}.name}}/*" {
    capabilities = ["list"]
}

path "secret/data/${USER_STORAGE_PATH}/{{identity.entity.aliases.${oidc_accessor_id}.name}}/*" {
    capabilities = ["read", "create", "update"]
}

path "secret/data/${CERT_STORAGE_PATH}/*" {
    capabilities = ["read", "list"]
}
EOF

# shellcheck source=./hvac/hvac-certs.sh
. "$(dirname "${0}")"/hvac-certs.sh upload
