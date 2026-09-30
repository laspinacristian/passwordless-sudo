# passwordless-sudo

Temporarily allow `sudo` without a password: 15 minutes by default, from 1 to 100.
The window applies to your user in every terminal and to programs that call sudo.

Supported: Debian 12+, Ubuntu 24.04+ and Fedora 43+, for members of the `sudo` or `wheel` group.
Requires systemd and sudo 1.9+ or sudo-rs.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/laspinacristian/passwordless-sudo/main/install.sh | sudo bash
```

This installs `/usr/local/bin/passwordless-sudo`. No window is activated.

## Usage

```bash
passwordless-sudo          # 15 minutes (asks for your password)
passwordless-sudo 30       # 30 minutes
passwordless-sudo status   # time remaining
passwordless-sudo off      # revoke now
```

## How it works

Each activation writes a sudoers rule under `/run`, so it never survives a reboot, and schedules
a systemd timer that deletes the rule when the window ends. With the original sudo the rule also
carries a `NOTAFTER` expiry, checked on every call, so the window closes on time even if the
timer does not run. Commands started during the window keep running after it ends.

sudo-rs (the default on Ubuntu 25.10 and later) does not support `NOTAFTER`, so there the timer
alone ends the window. For both safeguards, switch to the original sudo, which Ubuntu still ships:

```bash
sudo update-alternatives --set sudo /usr/bin/sudo.ws
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/laspinacristian/passwordless-sudo/main/install.sh | sudo bash -s -- --uninstall
```

## Tests

`tests/run.sh` runs end-to-end tests with podman in systemd containers for every supported
release, including Ubuntu 26.04 with both sudo-rs and the original sudo.
