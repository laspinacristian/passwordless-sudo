#!/bin/bash
# End-to-end tests in systemd containers. Requires podman.
# Usage: tests/run.sh [debian-12 ubuntu-24.04 ubuntu-26.04 ubuntu-26.04-sudo.ws fedora-43]
set -euo pipefail
cd "$(dirname "$0")/.."

apt='RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq systemd systemd-sysv sudo >/dev/null'
declare -A build=(
    [debian-12]="FROM docker.io/library/debian:12
$apt"
    [ubuntu-24.04]="FROM docker.io/library/ubuntu:24.04
$apt"
    [ubuntu-26.04]="FROM docker.io/library/ubuntu:26.04
$apt"
    [ubuntu-26.04-sudo.ws]="FROM docker.io/library/ubuntu:26.04
$apt && update-alternatives --set sudo /usr/bin/sudo.ws"
    [fedora-43]="FROM registry.fedoraproject.org/fedora:43
RUN dnf install -y -q systemd sudo util-linux shadow-utils >/dev/null"
)
targets=("$@")
(( ${#targets[@]} )) || targets=(debian-12 ubuntu-24.04 ubuntu-26.04 ubuntu-26.04-sudo.ws fedora-43)
logs=$(mktemp -d)
trap 'rm -rf -- "$logs"' EXIT

for target in "${targets[@]}"; do
    [[ -v build[$target] ]] || { echo "Unknown target: $target" >&2; exit 1; }
    (
        name=passwordless-sudo-test-$target
        podman build -q -t "$name" -f - . >/dev/null 2>&1 <<<"${build[$target]}
CMD [\"/sbin/init\"]"
        podman run -d --replace --name "$name" --systemd=always -v "$PWD:/src:ro,z" "$name" >/dev/null
        podman exec "$name" bash /src/tests/e2e.sh > "$logs/$target" 2>&1 || true
        podman rm -f -t0 "$name" >/dev/null
    ) &
done
wait

failed=0
for target in "${targets[@]}"; do
    echo "===== $target"
    cat "$logs/$target"
    grep -q '^RESULT 0$' "$logs/$target" || failed=1
done
exit "$failed"
