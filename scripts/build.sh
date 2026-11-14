#!/usr/bin/env bash
# Fetch the pinned clang, build the full AxionOS config + SukiSU/SUSFS
# fragment, and compile the arm64 Image.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$REPO_DIR/pins.env"

KERNEL_DIR=${1:?usage: build.sh <kernel-dir>}
KERNEL_DIR=$(cd "$KERNEL_DIR" && pwd)
TOOLCHAIN_DIR=${TOOLCHAIN_DIR:-$REPO_DIR/.toolchain/clang}
TOOLCHAIN_CACHE="$REPO_DIR/.toolchain"

if [ -x "$TOOLCHAIN_DIR/bin/clang" ] && \
   "$TOOLCHAIN_DIR/bin/clang" --version 2>/dev/null | head -n1 | grep -q 'r563880c'; then
  echo "[+] using cached clang: $("$TOOLCHAIN_DIR/bin/clang" --version | head -n1)"
else
  echo "[+] downloading AOSP $CLANG_VERSION"
  rm -rf "$TOOLCHAIN_DIR"
  mkdir -p "$TOOLCHAIN_DIR" "$TOOLCHAIN_CACHE"
  curl -L --fail --retry 3 --retry-delay 5 \
    -o "$TOOLCHAIN_CACHE/clang.tar.gz" "$CLANG_URL"
  tar -xzf "$TOOLCHAIN_CACHE/clang.tar.gz" -C "$TOOLCHAIN_DIR"
fi

test -x "$TOOLCHAIN_DIR/bin/clang" || {
  echo "clang is missing after extraction: $TOOLCHAIN_DIR/bin/clang"
  echo "archive contents: $(ls -A "$TOOLCHAIN_DIR" 2>/dev/null | head -5 | tr '\n' ' ')"
  exit 1
}
"$TOOLCHAIN_DIR/bin/clang" --version | head -n1 | grep -q 'r563880c' || {
  echo "unexpected clang version: $("$TOOLCHAIN_DIR/bin/clang" --version | head -n1)"
  exit 1
}

export PATH="$TOOLCHAIN_DIR/bin:$PATH"
# The patched source tree is a dirty git checkout and the LineageOS
# setlocalversion appends "+" unless LOCALVERSION is set in the environment.
# An empty LOCALVERSION suppresses that suffix so the release is exactly
# $EXPECTED_KERNEL_RELEASE, matching the stock vendor module vermagic.
export LOCALVERSION=

cd "$KERNEL_DIR"
rm -rf out

MAKE_ARGS=(O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 CLANG_TRIPLE=aarch64-linux-gnu-)
FRAGMENT="$REPO_DIR/config/axion_sukisu_susfs.config"
BASE_CONFIG="$REPO_DIR/config/axion-fogos_defconfig"

test -f "$BASE_CONFIG" || { echo "missing base config: $BASE_CONFIG"; exit 1; }
test -f "$FRAGMENT" || { echo "missing config fragment: $FRAGMENT"; exit 1; }

echo "[+] preparing full AxionOS defconfig"
cp "$BASE_CONFIG" arch/arm64/configs/axion-fogos_defconfig
make "${MAKE_ARGS[@]}" axion-fogos_defconfig

echo "[+] merging SukiSU/SUSFS fragment"
./scripts/kconfig/merge_config.sh -O out -m out/.config "$FRAGMENT"
make "${MAKE_ARGS[@]}" olddefconfig

echo "[+] compiling Image"
make "${MAKE_ARGS[@]}" -j"$(nproc)" Image

test -s out/arch/arm64/boot/Image || { echo "Image was not produced"; exit 1; }
echo "[+] built $(du -h out/arch/arm64/boot/Image | cut -f1) Image"
