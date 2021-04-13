#!/usr/bin/env bash

set -eu


# shellcheck disable=SC2046
# we do actually want the word split to occur
export $(cat "$(dirname "${0}")"/env_files/*.env | xargs)

echo "${VAULT_DEV_ROOT_TOKEN_ID}" | vault login - > /dev/null

ACTION="$1"
shift
if [ -n "${1:-}" ]; then
    BACKUP_PATH="${1}"
    shift
else
    BACKUP_PATH="$(dirname "${0}")/users_backup"
fi

function backup() {
    mkdir -p "${BACKUP_PATH}"

    for USER_CLAIM in $(vault kv list -format=json secret/"${USER_STORAGE_PATH:?storage path is not defined}" | jq -r .[]);
    do
        echo -en "Backing up API users for ${USER_CLAIM} ... "

        USER_CLAIM_PATH="${BACKUP_PATH}/${USER_CLAIM}"
        mkdir -p "${USER_CLAIM_PATH}"
        ALL_DATA=""
        for USER_ID in $(vault kv list -format=json secret/"${USER_STORAGE_PATH}"/"${USER_CLAIM}" | jq -r .[]);
        do
            USER_DATA=$(vault kv get -format=json secret/"${USER_STORAGE_PATH}"/"${USER_CLAIM}"/"${USER_ID}" | jq -c -M .data.data);
            ALL_DATA="${ALL_DATA} {\"${USER_ID}\": ${USER_DATA}}"
        done;

        echo "${ALL_DATA}" | jq -s -c -M 'reduce .[] as $item ({}; . * $item)' > "${USER_CLAIM_PATH}"/.user_store

        echo "done!"
    done
}

function upload() {
    if [ -f "${BACKUP_PATH}" ]; then
        upload_for_user "${BACKUP_PATH}" "${1}"
    elif [ ! -d "${BACKUP_PATH}" ]; then
        echo "could not find backup folder; aborting..."
        exit
    else
        for USER_BACKUP_PATH in "${BACKUP_PATH}"/*;
        do
            USER_STORE_PATH="${USER_BACKUP_PATH}/.user_store"
            USER_CLAIM="$(basename "${USER_BACKUP_PATH}")"
            upload_for_user "${USER_STORE_PATH}" "${USER_CLAIM}"
        done
    fi
}

function upload_for_user() {
    USER_STORE_PATH="${1}"
    USER_CLAIM="${2}"
    echo -en "Uploading API users for ${USER_CLAIM} ... "

    ALL_DATA="$(cat "${USER_STORE_PATH}")"
    for USER_ID in $(echo "${ALL_DATA}" | jq -r 'keys | .[]');
    do
        echo "${ALL_DATA}" | jq -c -M ."${USER_ID}" | vault kv put "secret/${USER_STORAGE_PATH}/${USER_CLAIM}/${USER_ID}" - > /dev/null
    done

    echo "done!"
}

case "$ACTION" in
    upload )
        upload "$@";;
    backup )
        backup;;
    * ) echo "Invalid action $ACTION" >&2 && exit 1;;
esac

