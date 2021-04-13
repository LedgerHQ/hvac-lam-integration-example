#!/usr/bin/env bash

set -eu

# shellcheck disable=SC2046
# we do actually want the word split to occur
export $(cat "$(dirname "${0}")"/env_files/*.env)
echo "$VAULT_DEV_ROOT_TOKEN_ID" | vault login - > /dev/null

CERT_FILE_NAMES=("lam.certificate" "lam_private.pem" "lam_public.pem")

ACTION="$1"
shift
if [ -n "${1:-}" ]; then
    CERT_FOLDER="${1}"
    shift
else
    CERT_FOLDER="$(dirname "${0}")/certs"
fi

CERT_FILES=()
for name in "${CERT_FILE_NAMES[@]}"; do
    CERT_FILES+=("${CERT_FOLDER}/${name}")
done

function encode_base64() {
    python -c "import base64;print(base64.b64encode(open('${1}', 'rb').read()).decode('ascii'))"
}

function check() {
    for file in "${CERT_FILES[@]}"; do
        if [ ! -f "${file}" ]; then
            echo "Missing file ${file}" >&2 && exit 1
        fi
    done
}

function upload() {
    check
    for file in "${CERT_FILES[@]}"; do
        echo -en "Uploading ${file}...";
        vault kv put \
	  secret/"${CERT_STORAGE_PATH}"/"$(basename "${file}")" \
	  binary="$(encode_base64 "${file}")";
        echo "done!"
    done
}

case "$ACTION" in
    check )
        check;;
    upload )
        upload;;
    * ) echo "Invalid action $ACTION" >&2 && exit 1;;
esac
