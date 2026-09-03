#!/bin/sh
set -eu

CONFIG_FILE="${SAMBA_CONFIG_FILE:-/etc/samba/smb.conf}"
SHARES_CONFIG_FILE="${SAMBA_SHARES_CONFIG_FILE:-/run/samba/shares.conf}"
SAMBA_UID="${SAMBA_UID-1000}"
SAMBA_GID="${SAMBA_GID-1000}"
ENV_LOADER=/usr/local/libexec/samba/load-env

die() {
    echo "entrypoint: $*" >&2
    exit 64
}

validate_id() {
    case "$2" in
        ''|0|*[!0-9]*) die "$1 must be a positive integer" ;;
    esac
}

configure_service_identity() {
    validate_id SAMBA_UID "$SAMBA_UID"
    validate_id SAMBA_GID "$SAMBA_GID"

    if getent group samba >/dev/null 2>&1; then
        [ "$(getent group samba | cut -d: -f3)" = "$SAMBA_GID" ] ||
            die "samba group already exists with an unexpected GID"
    else
        groupadd --non-unique --gid "$SAMBA_GID" samba
    fi

    if id samba >/dev/null 2>&1; then
        [ "$(id -u samba)" = "$SAMBA_UID" ] ||
            die "samba user already exists with an unexpected UID"
        [ "$(id -g samba)" = "$SAMBA_GID" ] ||
            die "samba user already exists with an unexpected primary GID"
    else
        useradd --non-unique --uid "$SAMBA_UID" --gid samba \
            --home-dir /nonexistent --shell /sbin/nologin samba
    fi
}

configure_service_identity

[ -r "$CONFIG_FILE" ] || die "configuration file is not readable: $CONFIG_FILE"
mkdir -p /run/samba /var/cache/samba /var/lib/samba/private
: >"$SHARES_CONFIG_FILE" || die "generated configuration file is not writable: $SHARES_CONFIG_FILE"

[ -x "$ENV_LOADER" ] || die "environment loader is not executable: $ENV_LOADER"
"$ENV_LOADER"

testparm --suppress-prompt "$CONFIG_FILE" >/dev/null

exec smbd --foreground --no-process-group --debug-stdout --configfile="$CONFIG_FILE"
