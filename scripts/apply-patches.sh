#!/usr/bin/env bash
# Apply SUSFS v2.4.0, integrate SukiSU Ultra builtin, and install the manual
# hooks this 5.4 kernel needs.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$REPO_DIR/pins.env"

KERNEL_DIR=${1:?usage: apply-patches.sh <kernel-dir>}
cd "$KERNEL_DIR"

test -d drivers || { echo "not a kernel tree: $KERNEL_DIR"; exit 1; }
test -f Makefile || { echo "missing Makefile"; exit 1; }

echo "[+] verifying vendored files"
echo "$SUSFS_PATCH_SHA256  $REPO_DIR/patches/susfs/susfs_patch_to_5.4_v2.4.0.patch" | sha256sum -c -
echo "$SUSFS_HOOKS_SHA256  $REPO_DIR/patches/susfs/susfs_inline_hook_patches.sh" | sha256sum -c -
echo "$SUKISU_COMPAT_SHA256SUMS_SHA256  $REPO_DIR/patches/sukisu/sha256sums" | sha256sum -c -
(cd "$REPO_DIR/patches/sukisu" && sha256sum -c sha256sums)

manifest_count=$(grep -c '\.patch$' "$REPO_DIR/patches/sukisu/sha256sums")
file_count=$(find "$REPO_DIR/patches/sukisu" -maxdepth 1 -name '*.patch' | wc -l)
test "$manifest_count" -eq "$file_count" || {
  echo "patches/sukisu manifest does not list every patch"; exit 1;
}
for p in "$REPO_DIR"/patches/sukisu/*.patch; do
  grep -q "  $(basename "$p")$" "$REPO_DIR/patches/sukisu/sha256sums" || {
    echo "unlisted SukiSU patch: $(basename "$p")"; exit 1;
  }
done

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  test -z "$(git status --porcelain)" || { echo "kernel tree is dirty"; exit 1; }
fi

echo "[+] applying SUSFS 5.4 v2.4.0"
patch -p1 --fuzz=3 < "$REPO_DIR/patches/susfs/susfs_patch_to_5.4_v2.4.0.patch"
find . -path ./.git -prune -o -name '*.orig' -exec rm -f {} +

echo "[+] integrating SukiSU $SUKISU_REF @ $SUKISU_COMMIT"
rm -rf KernelSU
git init -q KernelSU
git -C KernelSU remote add origin "$SUKISU_REPO"
git -C KernelSU fetch -q --depth 1 origin "$SUKISU_COMMIT"
git -C KernelSU checkout -q -B "$SUKISU_REF" FETCH_HEAD
test "$(git -C KernelSU rev-parse HEAD)" = "$SUKISU_COMMIT" || {
  echo "SukiSU commit mismatch"; exit 1;
}

echo "[+] applying SukiSU 5.4 compatibility patches"
for p in "$REPO_DIR"/patches/sukisu/*.patch; do
  echo "    $(basename "$p")"
  patch -d KernelSU -p1 --fuzz=3 < "$p"
done
ln -sfn ../KernelSU/kernel drivers/kernelsu
grep -q 'kernelsu' drivers/Makefile || echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig || \
  sed -i '/endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig

echo "[+] applying SukiSU manual hooks"
bash "$REPO_DIR/patches/susfs/susfs_inline_hook_patches.sh" ./

echo "[+] checking rejects"
if find . -path ./.git -prune -o \( -name '*.rej' -o -name '*.orig' \) -print -quit | grep -q .; then
  find . -path ./.git -prune -o \( -name '*.rej' -o -name '*.orig' \) -print
  echo "patch rejects remain"; exit 1
fi

echo "[+] checking expected hooks"
grep -q 'ksu_handle_setresuid' kernel/sys.c
grep -q 'ksu_handle_faccessat' fs/open.c
grep -q 'ksu_handle_stat' fs/stat.c
grep -q 'ksu_handle_execveat' fs/exec.c
test -L drivers/kernelsu

echo "[+] patches applied"
