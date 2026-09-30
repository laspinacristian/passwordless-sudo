#!/bin/bash
# Runs inside a systemd container as root; the repository is mounted at /src.
set -u
failed=0
check()    { if "${@:2}" >/dev/null 2>&1; then echo "PASS $1"; else echo "FAIL $1"; failed=1; fi; }
checknot() { if "${@:2}" >/dev/null 2>&1; then echo "FAIL $1"; failed=1; else echo "PASS $1"; fi; }
as_alice() { runuser -u alice -- "$@"; }
activate() { echo pw | as_alice sudo -S -k -- /usr/local/bin/passwordless-sudo "$@"; }

until systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded'; do sleep 1; done
group=wheel; getent group sudo >/dev/null && group=sudo
useradd -m -G "$group" alice && echo alice:pw | chpasswd && useradd -m bob
echo "$(. /etc/os-release; echo "$PRETTY_NAME"), $(sudo -V | head -n1), admin group: $group"

check    'install' bash /src/install.sh
check    'reinstall' bash /src/install.sh
check    'sudoers valid' visudo -c
checknot 'no passwordless sudo before activation' as_alice sudo -n true
for bad in 0 101 1.5 15m -1 '1 2'; do
    checknot "rejects duration '$bad'" as_alice passwordless-sudo $bad
done
check    'activate 1 minute' activate 1
check    'passwordless sudo during window' as_alice sudo -n true
checknot 'reactivation still needs a password' as_alice sudo -n /usr/local/bin/passwordless-sudo 5
check    'status active' bash -c 'runuser -u alice -- passwordless-sudo status | grep -q ^Active'
checknot 'non-admin refused' env SUDO_UID="$(id -u bob)" /usr/local/bin/passwordless-sudo 1
checknot 'bob unaffected' runuser -u bob -- sudo -n true
if sudo -V | head -n1 | grep -q '^sudo-rs'; then
    # sudo-rs has no NOTAFTER: the timer alone ends the window.
    sleep 65
    checknot 'expired after 1 minute (timer)' as_alice sudo -n true
else
    # With the original sudo, NOTAFTER ends the window even without the timer.
    check    'rule carries NOTAFTER' grep -q NOTAFTER= "/run/passwordless-sudo/user-$(id -u alice)"
    systemctl stop 'passwordless-sudo-*.timer'
    sleep 65
    checknot 'expired after 1 minute (NOTAFTER, timer stopped)' as_alice sudo -n true
fi
check    'status inactive' bash -c '[[ $(runuser -u alice -- passwordless-sudo status) == Inactive. ]]'
check    'no leftover timers' bash -c '! systemctl list-units --all --no-legend "passwordless-sudo-*" | grep -q .'
check    'activate 5 minutes' activate 5
check    'renew replaces window' activate 10
check    'passwordless sudo after renewal' as_alice sudo -n true
check    'off' activate off
checknot 'off revokes' as_alice sudo -n true
check    'activate before uninstall' activate 5
check    'uninstall' bash /src/install.sh --uninstall
checknot 'revoked by uninstall' as_alice sudo -n true
checknot 'files removed' ls /usr/local/bin/passwordless-sudo /etc/sudoers.d/zz-passwordless-sudo /etc/tmpfiles.d/passwordless-sudo.conf /run/passwordless-sudo
check    'sudoers valid after uninstall' visudo -c
echo "RESULT $failed"
