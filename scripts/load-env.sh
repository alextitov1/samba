#!/bin/sh
set -eu

SHARES_CONFIG_FILE="${SAMBA_SHARES_CONFIG_FILE:-/run/samba/shares.conf}"
VETO_FILES='/.apdisk/.DS_Store/.TemporaryItems/.Trashes/desktop.ini/ehthumbs.db/Network Trash Folder/Temporary Items/Thumbs.db/'

die() {
    echo "entrypoint: $*" >&2
    exit 64
}

validate_account_name() {
    case "$2" in
        ''|*[!A-Za-z0-9_.-]*) die "$1 contains an unsupported account name: $2" ;;
    esac
}

validate_text() {
    case "$2" in
        *"
"*|*"
"*) die "$1 must not contain newline characters" ;;
    esac
}

validate_yes_no() {
    case "$2" in
        yes|no) ;;
        *) die "$1 must be 'yes' or 'no'" ;;
    esac
}

validate_id() {
    case "$2" in
        ''|0|*[!0-9]*) die "$1 must be a positive integer" ;;
    esac
}

validate_user_list() {
    value=$2
    [ -z "$value" ] && return
    case "$value" in
        all|none) return ;;
        ,*|*,|*,,*|*[!A-Za-z0-9_.,-]*) die "$1 contains an unsupported user list: $value" ;;
    esac
}

numbered_variables() {
    prefix=$1
    env | sed -n "s/^\(${prefix}[0-9][0-9]*\)=.*/\1/p" |
        awk -v prefix="$prefix" '{ print substr($0, length(prefix) + 1), $0 }' |
        sort -n -k1,1 -k2,2 |
        awk '{ print $2 }'
}

field_count() {
    printf '%s\n' "$1" | awk -F ';' '{ print NF }'
}

field() {
    printf '%s\n' "$1" | awk -F ';' -v number="$2" '{ print $number }'
}

configure_user() {
    variable=$1
    definition=$(printenv "$variable")
    validate_text "$variable" "$definition"
    [ "$(field_count "$definition")" -le 5 ] || die "$variable contains more than 5 fields"

    username=$(field "$definition" 1)
    password=$(field "$definition" 2)
    uid=$(field "$definition" 3)
    group=$(field "$definition" 4)
    gid=$(field "$definition" 5)

    validate_account_name "$variable username" "$username"
    [ -n "$password" ] || die "$variable password must not be empty"
    [ -z "$uid" ] || validate_id "$variable UID" "$uid"
    [ -z "$group" ] || validate_account_name "$variable group" "$group"
    [ -z "$gid" ] || validate_id "$variable GID" "$gid"
    [ -n "$group" ] || [ -z "$gid" ] || die "$variable GID requires a group"

    if [ -n "$group" ] && ! getent group "$group" >/dev/null 2>&1; then
        if [ -n "$gid" ]; then
            groupadd --gid "$gid" "$group"
        else
            groupadd "$group"
        fi
    fi

    if ! id "$username" >/dev/null 2>&1; then
        set -- useradd --no-create-home --shell /sbin/nologin
        if [ -n "$uid" ]; then
            set -- "$@" --uid "$uid"
        fi
        if [ -n "$group" ]; then
            set -- "$@" --gid "$group"
        fi
        set -- "$@" --groups samba "$username"
        "$@"
    fi

    printf '%s\n%s\n' "$password" "$password" | smbpasswd -s -a "$username"
    unset password
}

write_user_option() {
    option=$1
    value=$2
    sentinel=$3
    [ -n "$value" ] || return 0
    [ "$value" = "$sentinel" ] && return 0
    printf '   %s = %s\n' "$option" "$(printf '%s' "$value" | tr ',' ' ')" >>"$SHARES_CONFIG_FILE"
}

configure_share() {
    variable=$1
    definition=$(printenv "$variable")
    validate_text "$variable" "$definition"
    [ "$(field_count "$definition")" -le 9 ] || die "$variable contains more than 9 fields"

    share_name=$(field "$definition" 1)
    share_path=$(field "$definition" 2)
    browsable=$(field "$definition" 3)
    readonly=$(field "$definition" 4)
    guest=$(field "$definition" 5)
    users=$(field "$definition" 6)
    admins=$(field "$definition" 7)
    writelist=$(field "$definition" 8)
    comment=$(field "$definition" 9)
    browsable=${browsable:-yes}
    readonly=${readonly:-yes}
    guest=${guest:-yes}

    case "$share_name" in
        ''|*[!A-Za-z0-9_.\ -]*) die "$variable contains an unsupported share name: $share_name" ;;
    esac
    case "$share_path" in
        /*) ;;
        *) die "$variable path must be absolute" ;;
    esac
    validate_yes_no "$variable browsable" "$browsable"
    validate_yes_no "$variable readonly" "$readonly"
    validate_yes_no "$variable guest" "$guest"
    validate_user_list "$variable users" "$users"
    validate_user_list "$variable admins" "$admins"
    validate_user_list "$variable write list" "$writelist"

    mkdir -p "$share_path"

    {
        printf '\n[%s]\n' "$share_name"
        printf '   path = %s\n' "$share_path"
        printf '   browsable = %s\n' "$browsable"
        printf '   read only = %s\n' "$readonly"
        printf '   guest ok = %s\n' "$guest"
        printf '   veto files = %s\n' "$VETO_FILES"
        printf '   delete veto files = yes\n'
    } >>"$SHARES_CONFIG_FILE"
    write_user_option 'valid users' "$users" all
    write_user_option 'admin users' "$admins" none
    write_user_option 'write list' "$writelist" none
    if [ -n "$comment" ] && [ "$comment" != none ]; then
        printf '   comment = %s\n' "$comment" >>"$SHARES_CONFIG_FILE"
    fi
}

for variable in $(numbered_variables USER); do
    configure_user "$variable"
done

for variable in $(numbered_variables SHARE); do
    configure_share "$variable"
done
