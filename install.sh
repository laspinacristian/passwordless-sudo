#!/usr/bin/env bash
# Install:   curl -fsSL https://raw.githubusercontent.com/laspinacristian/passwordless-sudo/main/install.sh | sudo bash
# Uninstall: curl -fsSL https://raw.githubusercontent.com/laspinacristian/passwordless-sudo/main/install.sh | sudo bash -s -- --uninstall
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

SOURCE_URL=https://raw.githubusercontent.com/laspinacristian/passwordless-sudo/main/passwordless-sudo
BIN=/usr/local/bin/passwordless-sudo
FRAGMENT=/etc/sudoers.d/zz-passwordless-sudo
TMPFILES=/etc/tmpfiles.d/passwordless-sudo.conf
RUNTIME=/run/passwordless-sudo

die() { echo "Error: $*" >&2; exit 1; }

do_uninstall() {
    # Serialize with activations and expiry services.
    exec 9>/run/passwordless-sudo.lock
    flock -x 9
    for state in "$RUNTIME"/user-*.json; do
        [[ -f "$state" ]] || continue
        uid=${state##*/user-}
        uid=${uid%.json}
        user=$(getent passwd "$uid" | cut -d: -f1) || continue
        runuser -u "$user" -- sudo -K
    done
    rm -f "$FRAGMENT"
    visudo -c >/dev/null
    systemctl stop 'passwordless-sudo-*.timer'
    rm -rf "$RUNTIME" "$TMPFILES" "$BIN"
    echo 'Uninstalled. Normal sudo behaviour restored.'
}

do_install() {
    for cmd in sudo visudo systemd-run systemctl runuser flock; do
        command -v "$cmd" >/dev/null || die "missing required command: $cmd"
    done
    [[ -d /run/systemd/system ]] || die 'systemd is not running.'
    # sudo before 1.9 lacks @includedir. sudo-rs is supported without NOTAFTER.
    version=$(sudo -V | head -n1)
    if [[ $version != sudo-rs* ]]; then
        version=${version#Sudo version }
        [[ $(printf '1.9\n%s\n' "$version" | sort -V | head -n1) == 1.9 ]] \
            || die 'requires sudo 1.9 or newer, or sudo-rs.'
    fi
    visudo -c >/dev/null
    grep -Eq '^\s*[@#]includedir\s+/etc/sudoers\.d/?\s*$' /etc/sudoers \
        || die '/etc/sudoers does not include /etc/sudoers.d.'
    if [[ -e "$FRAGMENT" ]] && ! grep -qx "@includedir $RUNTIME" "$FRAGMENT"; then
        die "unrecognised existing file $FRAGMENT, not overwritten."
    fi

    work=$(mktemp -d)
    trap 'rm -rf -- "$work"' EXIT
    local_copy="$(dirname -- "${BASH_SOURCE[0]:-/nonexistent}")/passwordless-sudo"
    if [[ -f "$local_copy" ]]; then
        cp -- "$local_copy" "$work/passwordless-sudo"
    elif command -v curl >/dev/null; then
        curl -fsSL "$SOURCE_URL" -o "$work/passwordless-sudo"
    else
        wget -qO "$work/passwordless-sudo" "$SOURCE_URL"
    fi
    bash -n "$work/passwordless-sudo" || die 'downloaded program is not valid.'

    install -d -o root -g root -m 0755 "$RUNTIME"
    install -o root -g root -m 0755 "$work/passwordless-sudo" "$BIN"
    printf 'd %s 0755 root root -\n' "$RUNTIME" > "$TMPFILES"
    chmod 0644 "$TMPFILES"
    # sudo skips names containing a dot, so the pending file is never read.
    pending=$(mktemp /etc/sudoers.d/.passwordless-sudo.XXXXXX)
    trap 'rm -rf -- "$work" "$pending"' EXIT
    printf '# Managed by passwordless-sudo\n@includedir %s\n' "$RUNTIME" > "$pending"
    chmod 0440 "$pending"
    visudo -cf "$pending" >/dev/null
    mv -f -- "$pending" "$FRAGMENT"
    if ! visudo -c >/dev/null; then
        rm -f -- "$FRAGMENT"
        die 'sudoers validation failed, integration removed.'
    fi
    if command -v restorecon >/dev/null; then
        restorecon "$BIN" "$FRAGMENT" "$TMPFILES" "$RUNTIME"
    fi
    echo 'Installed. No window is active yet. Run: passwordless-sudo'
}

(( EUID == 0 )) || die 'run as root, e.g. with sudo.'
case "${1:-}" in
    '') do_install ;;
    --uninstall) do_uninstall ;;
    *) die "unknown option: $1" ;;
esac
