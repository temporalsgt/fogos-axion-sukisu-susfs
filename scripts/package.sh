#!/usr/bin/env bash
# Verify the kernel ABI against the stock vendor modules when a stock
# vendor_boot image is available, repack the Axion VANILLA and GMS/GApps
# boot images when their stock bases are available, and build the
# AnyKernel3 zip.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$REPO_DIR/pins.env"

KERNEL_DIR=${1:?usage: package.sh <kernel-dir>}
KERNEL_DIR=$(cd "$KERNEL_DIR" && pwd)
WORK_DIR=${WORK_DIR:-$REPO_DIR/work}
DIST_DIR=${DIST_DIR:-$REPO_DIR/dist}
IMAGE="$KERNEL_DIR/out/arch/arm64/boot/Image"

test -s "$IMAGE" || { echo "missing $IMAGE"; exit 1; }
test -s "$KERNEL_DIR/out/Module.symvers" || { echo "missing Module.symvers"; exit 1; }

# fogos ships an empty init_boot_a; AK3's BLOCK=auto would select it and
# magiskboot would abort with "Splitting image failed". Never ship auto.
grep -qx 'BLOCK=boot' "$REPO_DIR/ak3/anykernel.sh" || {
  echo "ak3/anykernel.sh must set BLOCK=boot (init_boot_a is empty on fogos)"
  exit 1
}

BUILT_RELEASE=$(grep -a -o 'Linux version [0-9][^ ]*' "$IMAGE" | head -1 | awk '{print $3}')
test "$BUILT_RELEASE" = "$EXPECTED_KERNEL_RELEASE" || {
  echo "built kernel release mismatch: got '$BUILT_RELEASE', expected '$EXPECTED_KERNEL_RELEASE'"
  exit 1
}

fetch_pinned() {
  local url=$1 sha=$2 dest=$3
  if ! echo "$sha  $dest" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$dest"
    curl -L --fail --retry 3 --retry-delay 5 -o "$dest" "$url"
    echo "$sha  $dest" | sha256sum -c -
  fi
}

case "$DIST_DIR" in
  ""|"/") echo "refusing to clean DIST_DIR=$DIST_DIR"; exit 1 ;;
esac
rm -rf "$DIST_DIR"
mkdir -p "$WORK_DIR" "$DIST_DIR"

HAVE_VANILLA_BOOT=false
HAVE_GMS_BOOT=false
HAVE_VENDOR_MODULES=false

if [ -n "${STOCK_BOOT_URL:-}" ] && [ -n "${STOCK_BOOT_SHA256:-}" ]; then
  echo "[+] ensuring stock Axion VANILLA boot image"
  fetch_pinned "$STOCK_BOOT_URL" "$STOCK_BOOT_SHA256" "$WORK_DIR/boot-stock.img"
  HAVE_VANILLA_BOOT=true
else
  echo "[+] STOCK_BOOT_URL not set; skipping VANILLA boot image"
fi

if [ -n "${STOCK_GMS_BOOT_URL:-}" ] && [ -n "${STOCK_GMS_BOOT_SHA256:-}" ]; then
  echo "[+] ensuring stock Axion GMS/GApps boot image"
  fetch_pinned "$STOCK_GMS_BOOT_URL" "$STOCK_GMS_BOOT_SHA256" "$WORK_DIR/boot-gms-stock.img"
  HAVE_GMS_BOOT=true
else
  echo "[+] STOCK_GMS_BOOT_URL not set; skipping GMS/GApps boot image"
fi

if [ -n "${STOCK_VENDOR_BOOT_URL:-}" ] && [ -n "${STOCK_VENDOR_BOOT_SHA256:-}" ]; then
  echo "[+] ensuring stock Axion vendor_boot image"
  fetch_pinned "$STOCK_VENDOR_BOOT_URL" "$STOCK_VENDOR_BOOT_SHA256" "$WORK_DIR/vendor_boot-stock.img"
  HAVE_VENDOR_MODULES=true
else
  echo "[+] STOCK_VENDOR_BOOT_URL not set; skipping vendor module CRC check"
fi

if [ "$HAVE_VANILLA_BOOT" = true ] || [ "$HAVE_GMS_BOOT" = true ] || [ "$HAVE_VENDOR_MODULES" = true ]; then
  echo "[+] ensuring mkbootimg"
  if [ ! -d "$WORK_DIR/mkbootimg/.git" ] || \
     [ "$(git -C "$WORK_DIR/mkbootimg" rev-parse HEAD 2>/dev/null)" != "$MKBOOTIMG_COMMIT" ]; then
    rm -rf "$WORK_DIR/mkbootimg"
    git init -q "$WORK_DIR/mkbootimg"
    git -C "$WORK_DIR/mkbootimg" remote add origin "$MKBOOTIMG_REPO"
    git -C "$WORK_DIR/mkbootimg" fetch -q --depth 1 origin "$MKBOOTIMG_COMMIT"
    git -C "$WORK_DIR/mkbootimg" checkout -q "$MKBOOTIMG_COMMIT"
  fi
  test "$(git -C "$WORK_DIR/mkbootimg" rev-parse HEAD)" = "$MKBOOTIMG_COMMIT" || {
    echo "mkbootimg commit mismatch"; exit 1;
  }
fi

if [ "$HAVE_VANILLA_BOOT" = true ]; then
  echo "[+] unpacking stock VANILLA boot image"
  rm -rf "$WORK_DIR/boot-unpacked"
  python3 "$WORK_DIR/mkbootimg/unpack_bootimg.py" \
    --boot_img "$WORK_DIR/boot-stock.img" \
    --out "$WORK_DIR/boot-unpacked" \
    --format mkbootimg > "$WORK_DIR/mkbootimg.cmd"

  STOCK_RELEASE=$(grep -a -o 'Linux version [0-9][^ ]*' "$WORK_DIR/boot-unpacked/kernel" | head -1 | awk '{print $3}')
  test "$STOCK_RELEASE" = "$EXPECTED_KERNEL_RELEASE" || {
    echo "stock VANILLA kernel release mismatch: got '$STOCK_RELEASE', expected '$EXPECTED_KERNEL_RELEASE'"
    exit 1
  }
  echo "[+] stock VANILLA release matches: $STOCK_RELEASE"
  cp "$IMAGE" "$WORK_DIR/boot-unpacked/kernel"
fi

if [ "$HAVE_GMS_BOOT" = true ]; then
  echo "[+] unpacking stock GMS/GApps boot image"
  rm -rf "$WORK_DIR/boot-gms-unpacked"
  python3 "$WORK_DIR/mkbootimg/unpack_bootimg.py" \
    --boot_img "$WORK_DIR/boot-gms-stock.img" \
    --out "$WORK_DIR/boot-gms-unpacked" \
    --format mkbootimg > "$WORK_DIR/mkbootimg-gms.cmd"

  STOCK_GMS_RELEASE=$(grep -a -o 'Linux version [0-9][^ ]*' "$WORK_DIR/boot-gms-unpacked/kernel" | head -1 | awk '{print $3}')
  test "$STOCK_GMS_RELEASE" = "$EXPECTED_KERNEL_RELEASE" || {
    echo "stock GMS/GApps kernel release mismatch: got '$STOCK_GMS_RELEASE', expected '$EXPECTED_KERNEL_RELEASE'"
    exit 1
  }
  echo "[+] stock GMS/GApps release matches: $STOCK_GMS_RELEASE"
  cp "$IMAGE" "$WORK_DIR/boot-gms-unpacked/kernel"
fi

if [ "$HAVE_VENDOR_MODULES" = true ]; then
  echo "[+] extracting stock vendor modules from vendor_boot"
  rm -rf "$WORK_DIR/vendor_boot-unpacked" "$WORK_DIR/vendor_boot-ramdisk" "$WORK_DIR/vendor-modules"
  python3 "$WORK_DIR/mkbootimg/unpack_bootimg.py" \
    --boot_img "$WORK_DIR/vendor_boot-stock.img" \
    --out "$WORK_DIR/vendor_boot-unpacked" >/dev/null
  RAMDISK="$WORK_DIR/vendor_boot-unpacked/vendor_ramdisk"
  RAMDISK_CPIO="$WORK_DIR/vendor_boot-unpacked/vendor_ramdisk.cpio"
  case "$(od -An -tx1 -N4 "$RAMDISK" | tr -d ' \n')" in
    # gzip, xz, zstd, modern LZ4 frame, legacy LZ4
    1f8b*) gzip -dc "$RAMDISK" > "$RAMDISK_CPIO" ;;
    fd377a585a00*) xz -dc "$RAMDISK" > "$RAMDISK_CPIO" ;;
    28b52ffd*) zstd -dc "$RAMDISK" > "$RAMDISK_CPIO" ;;
    04224d18|02214c18) lz4 -d -f -q "$RAMDISK" "$RAMDISK_CPIO" ;;
    *) cp "$RAMDISK" "$RAMDISK_CPIO" ;;
  esac
  mkdir -p "$WORK_DIR/vendor_boot-ramdisk"
  (cd "$WORK_DIR/vendor_boot-ramdisk" && cpio -idm --quiet < "$RAMDISK_CPIO")
  FIRST_KO=$(find "$WORK_DIR/vendor_boot-ramdisk" -name '*.ko' -print -quit)
  test -n "$FIRST_KO" || { echo "no stock vendor modules found in vendor_boot"; exit 1; }
  mkdir -p "$WORK_DIR/vendor-modules"
  find "$WORK_DIR/vendor_boot-ramdisk" -name '*.ko' -exec cp -f {} "$WORK_DIR/vendor-modules/" \;

  echo "[+] checking built kernel ABI against stock vendor module CRCs"
  bash "$REPO_DIR/scripts/check-module-crcs.sh" \
    "$KERNEL_DIR/out/Module.symvers" "$WORK_DIR/vendor-modules"
else
  echo "[+] no vendor_boot image; skipping vendor module CRC check"
fi

if [ "$HAVE_VANILLA_BOOT" = true ]; then
  echo "[+] repacking boot.img (VANILLA)"
  cd "$WORK_DIR"
  MKB_CMD=$(cat mkbootimg.cmd)
  eval "python3 \"$WORK_DIR/mkbootimg/mkbootimg.py\" $MKB_CMD --output \"$DIST_DIR/boot.img\""

  echo "[+] verifying repacked boot.img (VANILLA)"
  rm -rf "$WORK_DIR/boot-verify"
  python3 "$WORK_DIR/mkbootimg/unpack_bootimg.py" \
    --boot_img "$DIST_DIR/boot.img" --out "$WORK_DIR/boot-verify" >/dev/null
  cmp "$WORK_DIR/boot-verify/kernel" "$IMAGE"
fi

if [ "$HAVE_GMS_BOOT" = true ]; then
  echo "[+] repacking boot-gms.img (GMS/GApps)"
  cd "$WORK_DIR"
  MKB_GMS_CMD=$(cat mkbootimg-gms.cmd)
  eval "python3 \"$WORK_DIR/mkbootimg/mkbootimg.py\" $MKB_GMS_CMD --output \"$DIST_DIR/boot-gms.img\""

  echo "[+] verifying repacked boot-gms.img (GMS/GApps)"
  rm -rf "$WORK_DIR/boot-gms-verify"
  python3 "$WORK_DIR/mkbootimg/unpack_bootimg.py" \
    --boot_img "$DIST_DIR/boot-gms.img" --out "$WORK_DIR/boot-gms-verify" >/dev/null
  cmp "$WORK_DIR/boot-gms-verify/kernel" "$IMAGE"
  cmp "$WORK_DIR/boot-gms-verify/ramdisk" "$WORK_DIR/boot-gms-unpacked/ramdisk"
fi

echo "[+] building AnyKernel3 zip"
if [ ! -d "$WORK_DIR/AnyKernel3/.git" ]; then
  rm -rf "$WORK_DIR/AnyKernel3"
  git clone "$AK3_REPO" "$WORK_DIR/AnyKernel3"
fi
git -C "$WORK_DIR/AnyKernel3" fetch --depth 1 origin "$AK3_COMMIT" >/dev/null 2>&1 || true
git -C "$WORK_DIR/AnyKernel3" checkout -q "$AK3_COMMIT"
cp "$IMAGE" "$WORK_DIR/AnyKernel3/Image"
cp "$REPO_DIR/ak3/anykernel.sh" "$WORK_DIR/AnyKernel3/anykernel.sh"

DATE=$(date -u +%Y%m%d)
ZIP_NAME="fogos-axion-sukisu-susfs-$DATE.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
python3 - "$WORK_DIR/AnyKernel3" "$ZIP_PATH" <<'PY'
import os
import sys
import zipfile

src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _dirs, files in os.walk(src):
        if ".git" in root.split(os.sep):
            continue
        for name in files:
            path = os.path.join(root, name)
            z.write(path, os.path.relpath(path, src))
PY

python3 - "$ZIP_PATH" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as z:
    cfg = z.read("anykernel.sh").decode()
if "\nBLOCK=boot\n" not in "\n" + cfg + "\n":
    sys.exit("packaged anykernel.sh must set BLOCK=boot (init_boot_a is empty on fogos)")
PY

cp "$IMAGE" "$DIST_DIR/Image"
cp "$KERNEL_DIR/out/.config" "$DIST_DIR/kernel.config"
cp "$KERNEL_DIR/out/System.map" "$DIST_DIR/System.map"
cp "$KERNEL_DIR/out/Module.symvers" "$DIST_DIR/Module.symvers"

CHECKSUM_FILES=(Image kernel.config System.map Module.symvers "$ZIP_NAME")
[ -f "$DIST_DIR/boot.img" ] && CHECKSUM_FILES=(boot.img "${CHECKSUM_FILES[@]}")
[ -f "$DIST_DIR/boot-gms.img" ] && CHECKSUM_FILES=(boot-gms.img "${CHECKSUM_FILES[@]}")
(
  cd "$DIST_DIR"
  sha256sum "${CHECKSUM_FILES[@]}" > SHA256SUMS
  sha256sum -c SHA256SUMS
)

echo "[+] artifacts:"
ls -lh "$DIST_DIR"/* 2>/dev/null || true