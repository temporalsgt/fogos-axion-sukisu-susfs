#!/usr/bin/env bash
# Verify that the built Image really contains SukiSU/SUSFS, preserves the
# stock kernel ABI options, and reports the exact release string the vendor
# modules expect.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$REPO_DIR/pins.env"

KERNEL_DIR=${1:?usage: verify.sh <kernel-dir>}
KERNEL_DIR=$(cd "$KERNEL_DIR" && pwd)
cd "$KERNEL_DIR"

CONFIG=out/.config
IMAGE=out/arch/arm64/boot/Image
SYSMAP=out/System.map

fail() { echo "verify: FAIL: $*" >&2; exit 1; }

test -s "$CONFIG" || fail "missing $CONFIG"
test -s "$IMAGE" || fail "missing $IMAGE"
test -s "$SYSMAP" || fail "missing $SYSMAP"

# Every option in our fragment must survive merge_config + olddefconfig.
while IFS= read -r opt; do
  case "$opt" in
    ''|'#'*) continue ;;
  esac
  grep -qxF "$opt" "$CONFIG" || fail "config fragment option not applied: $opt"
done < "$REPO_DIR/config/axion_sukisu_susfs.config"

for opt in \
  CONFIG_KSU=y \
  CONFIG_KSU_SUSFS=y \
  CONFIG_THREAD_INFO_IN_TASK=y \
  CONFIG_KALLSYMS_ALL=y \
  CONFIG_MODVERSIONS=y \
  CONFIG_MODULES=y \
  CONFIG_PREEMPT=y \
  CONFIG_LTO_CLANG=y \
  CONFIG_THINLTO=y \
  CONFIG_CFI_CLANG=y
do
  grep -qx "$opt" "$CONFIG" || fail "$opt not set in $CONFIG"
done

grep -qx '# CONFIG_LOCALVERSION_AUTO is not set' "$CONFIG" ||
  fail "CONFIG_LOCALVERSION_AUTO must be disabled to keep vermagic stable"
grep -qxF "CONFIG_LOCALVERSION=\"-moto-g92683a4fde22\"" "$CONFIG" ||
  fail "CONFIG_LOCALVERSION does not match the Axion release"

# The kernel embeds its config (CONFIG_IKCONFIG=y).
test -x scripts/extract-ikconfig || fail "missing scripts/extract-ikconfig"
scripts/extract-ikconfig "$IMAGE" > out/.config.extracted
while IFS= read -r opt; do
  case "$opt" in
    ''|'#'*) continue ;;
  esac
  grep -qxF "$opt" out/.config.extracted || fail "fragment option not embedded: $opt"
done < "$REPO_DIR/config/axion_sukisu_susfs.config"

strings "$IMAGE" > out/Image.strings
grep -q 'v2.4.0' out/Image.strings || fail "SUSFS v2.4.0 string missing"
grep -qF "Linux version $EXPECTED_KERNEL_RELEASE " out/Image.strings ||
  fail "kernel release is not $EXPECTED_KERNEL_RELEASE"
grep -qF "$EXPECTED_KERNEL_RELEASE SMP preempt mod_unload modversions aarch64" out/Image.strings ||
  fail "vermagic does not match stock modules (expected SMP preempt mod_unload modversions aarch64)"
if grep -qF "Linux version $EXPECTED_KERNEL_RELEASE-dirty" out/Image.strings; then
  fail "kernel release contains -dirty (vermagic would not match stock modules)"
fi
if grep -qF "Linux version $EXPECTED_KERNEL_RELEASE+" out/Image.strings; then
  fail "kernel release contains + (dirty git tree; export LOCALVERSION= is required)"
fi

test -s out/include/config/kernel.release || fail "missing out/include/config/kernel.release"
grep -qxF "$EXPECTED_KERNEL_RELEASE" out/include/config/kernel.release ||
  fail "kernel.release is not exactly $EXPECTED_KERNEL_RELEASE"

grep -q 'ksu_' "$SYSMAP" || fail "ksu symbols missing from System.map"
grep -q 'susfs_' "$SYSMAP" || fail "susfs symbols missing from System.map"

echo "verify: OK (release $EXPECTED_KERNEL_RELEASE, LTO/CFI preserved)"
