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
export $(cat "$(dirname "${0}")"/env_files/*.env | xargs)

echo "$VAULT_DEV_ROOT_TOKEN_ID" | vault login -

# shellcheck source=./hvac/hvac-certs.sh
. "$(dirname "${0}")"/hvac-certs.sh check

# enable userpass authentication and get accessor id
vault auth enable userpass

userpass_accessor_id=$(vault auth list -format=json| jq -r '."userpass/".accessor')

vault write auth/userpass/users/"${HASHICORP_USERPASS_NAME}" password="${HASHICORP_USERPASS_PWD}" policies="${HASHICORP_POLICY_NAME}" ttl="60m"

vault policy write "${HASHICORP_POLICY_NAME}" - <<EOF
# cat - <<EOF
# to list secret, the given path must be under secret/metadata
path "secret/metadata/${USER_STORAGE_PATH}/{{identity.entity.aliases.${userpass_accessor_id}.name}}" {
    capabilities = ["list"]
}

path "secret/data/${USER_STORAGE_PATH}/{{identity.entity.aliases.${userpass_accessor_id}.name}}/*" {
    capabilities = ["read", "create", "update"]
}

path "secret/data/${CERT_STORAGE_PATH}/*" {
    capabilities = ["read", "list"]
}
EOF

# shellcheck source=hvac/hvac-certs.sh
. "$(dirname "${0}")"/hvac-certs.sh upload
