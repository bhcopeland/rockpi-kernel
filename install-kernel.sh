#!/usr/bin/env bash
set -euo pipefail

HOST="${DECK_HOST:-ben@192.168.0.71}"
OUT="${KERNEL_OUT:-${XDG_CACHE_HOME:-$HOME/.cache}/rockpi-kernel/out}"
SSH_OPTS=(${DECK_SSH_OPTS:-})
VERSION=$(zcat "$OUT/Image.gz" | strings | sed -n 's/^Linux version \([^ ]*\) .*/\1/p' | head -1)
[ -n "$VERSION" ] || { echo "no kernel version found in $OUT/Image.gz" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9A-Za-z._+-]+$ ]] || { echo "unexpected kernel version string: $VERSION" >&2; exit 1; }
FILES=(Image.gz modules.tar.xz dtbs.tar.xz config)
SUMS=$(cd "$OUT" && sha256sum "${FILES[@]}")

echo "==> Installing $VERSION on $HOST"
STAGE=$(ssh "${SSH_OPTS[@]}" "$HOST" 'mktemp -d')
[[ "$STAGE" =~ ^/tmp/tmp\.[A-Za-z0-9]+$ ]] || { echo "unexpected staging directory: $STAGE" >&2; exit 1; }
trap 'ssh "${SSH_OPTS[@]}" "$HOST" "rm -rf $STAGE" >/dev/null 2>&1 || true' EXIT
(cd "$OUT" && scp -q "${SSH_OPTS[@]}" "${FILES[@]}" "$HOST:$STAGE/")
printf '%s\n' "$SUMS" | ssh "${SSH_OPTS[@]}" "$HOST" "cd $STAGE && sha256sum --quiet -c -" \
    || { echo "checksum mismatch after copying to the board" >&2; exit 1; }
ssh -t "${SSH_OPTS[@]}" "$HOST" "sudo sh -ec '
V=$VERSION
S=$STAGE
gunzip -c \$S/Image.gz > /boot/vmlinuz-\$V
install -m 644 \$S/config /boot/config-\$V
rm -rf /usr/lib/modules/\$V
tar -C /usr -xJf \$S/modules.tar.xz
depmod -a \$V
mkdir \$S/dtbx && tar -C \$S/dtbx -xJf \$S/dtbs.tar.xz
rm -rf /boot/dtb-\$V && mv \$S/dtbx/dtbs /boot/dtb-\$V
update-initramfs -c -k \$V >/dev/null 2>&1 || update-initramfs -u -k \$V
cd /boot && ln -sfn vmlinuz-\$V Image && ln -sfn uInitrd-\$V uInitrd && ln -sfn dtb-\$V dtb
ls -la /boot/Image /boot/uInitrd /boot/dtb
'"
echo "==> Installed $VERSION. Reboot the board to use it: ssh $HOST sudo reboot"
