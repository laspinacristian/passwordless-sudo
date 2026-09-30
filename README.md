# passwordless-sudo

Temporarily allow `sudo` without a password: 15 minutes by default, from 1 to 100.
The window applies to your user in every terminal and to programs that call sudo.

Supported: Debian 12+, Ubuntu 24.04+ and Fedora 43+, for members of the `sudo` or `wheel` group.
Requires systemd.

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

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/laspinacristian/passwordless-sudo/main/install.sh | sudo bash -s -- --uninstall
```
