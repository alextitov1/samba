#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${IMAGE:-samba-container:test}"
NETWORK="samba-test-${RANDOM}"
SERVER="samba-server-${RANDOM}"
CLIENT="samba-client-${RANDOM}"
VOLUME="samba-data-${RANDOM}"
CUSTOM_SERVER="samba-custom-${RANDOM}"
CUSTOM_VOLUME="samba-custom-data-${RANDOM}"
DUPLICATE_SERVER="samba-duplicate-${RANDOM}"

cleanup() {
    docker rm -f "${CLIENT}" "${SERVER}" "${CUSTOM_SERVER}" "${DUPLICATE_SERVER}" >/dev/null 2>&1 || true
    docker volume rm "${VOLUME}" "${CUSTOM_VOLUME}" >/dev/null 2>&1 || true
    docker network rm "${NETWORK}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --rm --entrypoint /bin/sh "${IMAGE}" -eu -c '
    ! getent passwd samba >/dev/null
    ! getent group samba >/dev/null
    test "$(stat -c "%u:%g:%a" /shares)" = "0:0:755"
'

docker network create "${NETWORK}" >/dev/null
docker volume create "${VOLUME}" >/dev/null
docker run --rm \
    --entrypoint chown \
    --mount "type=volume,src=${VOLUME},dst=/mediaserver" \
    "${IMAGE}" 1000:1000 /mediaserver

docker run -d \
    --name "${SERVER}" \
    --network "${NETWORK}" \
    --network-alias samba \
    --mount "type=volume,src=${VOLUME},dst=/mediaserver" \
    --env 'USER1=alex;change-me' \
    --env 'SHARE1=mediaserver;/mediaserver;yes;yes;yes' \
    --env 'SHARE2=admin;/mediaserver;yes;no;no;alex' \
    "${IMAGE}" >/dev/null

for _ in {1..60}; do
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${SERVER}")"
    if [[ "${health}" == "healthy" ]]; then
        break
    fi
    if [[ "$(docker inspect --format '{{.State.Running}}' "${SERVER}")" != "true" ]]; then
        docker logs "${SERVER}" >&2
        exit 1
    fi
    sleep 1
done

[[ "$(docker inspect --format '{{.State.Health.Status}}' "${SERVER}")" == "healthy" ]]
[[ "$(docker exec "${SERVER}" id -u samba)" == "1000" ]]
[[ "$(docker exec "${SERVER}" id -g samba)" == "1000" ]]

docker run -d --name "${CLIENT}" --network "${NETWORK}" --entrypoint sleep "${IMAGE}" 300 >/dev/null

config="$(docker exec "${SERVER}" testparm --suppress-prompt 2>/dev/null)"
[[ "$(grep -c '^\[mediaserver\]$' <<<"${config}")" -eq 1 ]]
[[ "$(grep -c '^\[admin\]$' <<<"${config}")" -eq 1 ]]
raw_config="$(docker exec "${SERVER}" cat /run/samba/shares.conf)"
grep -A8 '^\[mediaserver\]$' <<<"${raw_config}" | grep -q '^   read only = yes$'
grep -A8 '^\[mediaserver\]$' <<<"${raw_config}" | grep -q '^   guest ok = yes$'
grep -A8 '^\[admin\]$' <<<"${raw_config}" | grep -q '^   read only = no$'
grep -A8 '^\[admin\]$' <<<"${raw_config}" | grep -q '^   guest ok = no$'
grep -A8 '^\[admin\]$' <<<"${raw_config}" | grep -q '^   valid users = alex$'

docker exec "${CLIENT}" smbclient //samba/mediaserver -N -m SMB3 -c 'ls'
if docker exec "${CLIENT}" smbclient //samba/admin -N -m SMB3 -c 'ls'; then
    echo "Guest access to the authenticated share unexpectedly succeeded" >&2
    exit 1
fi
docker exec "${CLIENT}" smbclient //samba/admin -U 'alex%change-me' -m SMB3 -c 'put /etc/hostname authenticated.txt; ls'
docker exec "${CLIENT}" smbclient //samba/mediaserver -N -m SMB3 -c 'get authenticated.txt /tmp/guest-visible.txt'
docker exec "${CLIENT}" test -s /tmp/guest-visible.txt

docker restart "${SERVER}" >/dev/null
for _ in {1..60}; do
    [[ "$(docker inspect --format '{{.State.Health.Status}}' "${SERVER}")" == "healthy" ]] && break
    sleep 1
done

docker exec "${CLIENT}" smbclient //samba/admin -U 'alex%change-me' -m SMB3 -c 'get authenticated.txt /tmp/authenticated.txt'
docker exec "${CLIENT}" test -s /tmp/authenticated.txt
config="$(docker exec "${SERVER}" testparm --suppress-prompt 2>/dev/null)"
[[ "$(grep -c '^\[mediaserver\]$' <<<"${config}")" -eq 1 ]]
[[ "$(grep -c '^\[admin\]$' <<<"${config}")" -eq 1 ]]
raw_config="$(docker exec "${SERVER}" cat /run/samba/shares.conf)"
[[ "$(grep -c '^\[mediaserver\]$' <<<"${raw_config}")" -eq 1 ]]
[[ "$(grep -c '^\[admin\]$' <<<"${raw_config}")" -eq 1 ]]

docker stop --time 10 "${SERVER}" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "${SERVER}")" == "0" ]]

docker volume create "${CUSTOM_VOLUME}" >/dev/null
docker run --rm \
    --entrypoint chown \
    --mount "type=volume,src=${CUSTOM_VOLUME},dst=/custom" \
    "${IMAGE}" 12345:12346 /custom
docker run -d \
    --name "${CUSTOM_SERVER}" \
    --network "${NETWORK}" \
    --network-alias custom-samba \
    --mount "type=volume,src=${CUSTOM_VOLUME},dst=/custom" \
    --env SAMBA_UID=12345 \
    --env SAMBA_GID=12346 \
    --env 'SHARE1=custom;/custom;yes;no;yes' \
    "${IMAGE}" >/dev/null

for _ in {1..60}; do
    [[ "$(docker inspect --format '{{.State.Health.Status}}' "${CUSTOM_SERVER}")" == "healthy" ]] && break
    sleep 1
done
[[ "$(docker inspect --format '{{.State.Health.Status}}' "${CUSTOM_SERVER}")" == "healthy" ]]
[[ "$(docker exec "${CUSTOM_SERVER}" id -u samba)" == "12345" ]]
[[ "$(docker exec "${CUSTOM_SERVER}" id -g samba)" == "12346" ]]
[[ "$(docker exec "${CUSTOM_SERVER}" stat -c '%u:%g' /custom)" == "12345:12346" ]]
docker exec "${CLIENT}" smbclient //custom-samba/custom -N -m SMB3 -c 'put /etc/hostname custom.txt; ls'

docker run -d \
    --name "${DUPLICATE_SERVER}" \
    --env SAMBA_UID=65534 \
    --env SAMBA_GID=65534 \
    "${IMAGE}" >/dev/null
for _ in {1..60}; do
    [[ "$(docker inspect --format '{{.State.Health.Status}}' "${DUPLICATE_SERVER}")" == "healthy" ]] && break
    sleep 1
done
[[ "$(docker inspect --format '{{.State.Health.Status}}' "${DUPLICATE_SERVER}")" == "healthy" ]]
[[ "$(docker exec "${DUPLICATE_SERVER}" id -u samba)" == "65534" ]]
[[ "$(docker exec "${DUPLICATE_SERVER}" id -g samba)" == "65534" ]]

docker run --rm \
    --entrypoint /bin/sh \
    --env 'SAMBA_SHARES_CONFIG_FILE=/tmp/shares.conf' \
    --env 'SHARE10=ten;/shares/ten' \
    --env 'SHARE2=two;/shares/two' \
    "${IMAGE}" -eu -c '
        printf "# existing source\n" >/tmp/shares.conf
        /usr/local/libexec/samba/load-env
        grep -q "^# existing source$" /tmp/shares.conf
        test "$(grep "^\[" /tmp/shares.conf)" = "[two]
[ten]"
    '

if docker run --rm --env 'USER1=alex;' "${IMAGE}" /bin/true; then
    echo "An empty USER password unexpectedly passed validation" >&2
    exit 1
fi

if docker run --rm --env 'SHARE1=broken;/shares;maybe;yes;yes' "${IMAGE}" /bin/true; then
    echo "An invalid SHARE boolean unexpectedly passed validation" >&2
    exit 1
fi

for setting in 'SAMBA_UID=' 'SAMBA_UID=0' 'SAMBA_UID=invalid' 'SAMBA_GID=' 'SAMBA_GID=0' 'SAMBA_GID=invalid'; do
    if docker run --rm --env "$setting" "${IMAGE}" >/dev/null 2>&1; then
        echo "An invalid service identity setting unexpectedly passed validation: ${setting}" >&2
        exit 1
    fi
done

echo "Docker integration tests passed"
