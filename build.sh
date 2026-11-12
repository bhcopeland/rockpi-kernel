#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KERNEL_REPO="${KERNEL_REPO:-$HOME/linux/linux-stable}"
KERNEL_TREE="${KERNEL_TREE:-$HOME/linux/linux-rockpi}"
KERNEL_BASE="${KERNEL_BASE:-$(cat "$HERE/BASE")}"
OUT="${KERNEL_OUT:-${XDG_CACHE_HOME:-$HOME/.cache}/rockpi-kernel/out}"

if [ ! -d "$KERNEL_TREE" ]; then
    echo "==> Creating a detached worktree at $KERNEL_TREE from $KERNEL_BASE"
    git -C "$KERNEL_REPO" rev-parse -q --verify "$KERNEL_BASE^{commit}" >/dev/null \
        || git -C "$KERNEL_REPO" fetch -q origin tag "$KERNEL_BASE"
    git -C "$KERNEL_REPO" worktree add -q --detach "$KERNEL_TREE" "$KERNEL_BASE"
fi

if [ -n "$(git -C "$KERNEL_TREE" status --porcelain --untracked-files=no)" ]; then
    echo "$KERNEL_TREE has uncommitted changes; commit or stash them, then export them into patches/" >&2
    exit 1
fi

echo "==> Resetting $KERNEL_TREE to $KERNEL_BASE and applying patches/"
git -C "$KERNEL_TREE" -c advice.detachedHead=false checkout -q --detach "$KERNEL_BASE"
git -C "$KERNEL_TREE" am -q "$HERE"/patches/*.patch
git -C "$KERNEL_TREE" log --oneline "$KERNEL_BASE"..HEAD

echo "==> Building with tuxmake into $OUT"
mkdir -p "$OUT"
tuxmake --runtime podman --target-arch arm64 --toolchain gcc \
    --kconfig "$HERE/rockpi.config" --directory "$KERNEL_TREE" \
    --output-dir "$OUT" -j"$(nproc)" kernel modules dtbs
echo "==> Built: $(zcat "$OUT/Image.gz" | strings | sed -n 's/^Linux version \([^ ]*\) .*/\1/p' | head -1)"
