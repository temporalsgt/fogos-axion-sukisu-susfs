# fogos AxionOS 2.9 — SukiSU Ultra + SUSFS

Kernel untuk **Motorola Moto G45 5G (`fogos`, SM6375/Holi, Linux 5.4.302)** yang dijalankan di **AxionOS 2.9** resmi, dengan **SukiSU Ultra** mode `builtin` dan **SUSFS v2.4.0**.

- Repo: <https://github.com/temporalsgt/fogos-axion-sukisu-susfs>
- ROM acuan: `axion-2.9-NOESIS-20261028-OFFICIAL-VANILLA-fogos`
- Kernel release acuan: `5.4.302-moto-g92683a4fde22`
- Build: GitHub Actions (`ubuntu-24.04`), output `boot.img` + zip AnyKernel3

## Kenapa source ini

Kernel yang berjalan di HP melaporkan:

```text
Linux version 5.4.302-moto-g92683a4fde22 (byben@ServerHive)
Android clang 21.0.0 (based on r563880c), LTO + CFI
```

Commit `92683a4fde22b3d76efa18e11508af49a808bf77` adalah merge commit
`Merge branch 'LineageOS:lineage-23.2' into axion` di
`LineageOS/android_kernel_motorola_sm6375`. Build ini memakai commit tersebut,
bukan branch head `lineage-23.2`, supaya tree-nya sama dengan kernel ROM.

Config kernel diambil utuh dari HP (`/proc/config.gz`) dan dipakai sebagai
defconfig. Artinya seluruh opsi vendor/fogos, LTO/ThinLTO/CFI, dan layout
simbol tetap sama. Hanya opsi SukiSU/SUSFS dan `CONFIG_LOCALVERSION` yang
ditambahkan lewat fragment.

## Fitur

- SukiSU Ultra `builtin` (bukan LKM), commit `f9aa2fec...` (Manager v4.3.0).
- SUSFS v2.4.0 backport Linux 5.4 + inline hooks.
- Manual hooks untuk kernel 5.4 (bukan kprobes).
- Clang **r563880c** persis seperti kernel ROM.
- `CONFIG_LTO_CLANG`, `CONFIG_THINLTO`, `CONFIG_CFI_CLANG` tetap aktif.
- Vermagic dipaksa `5.4.302-moto-g92683a4fde22` agar modul vendor
  (`vendor_dlkm`) tetap bisa dimuat.
- Verifikasi CRC simbol kernel terhadap modul stock di `vendor_boot.img`.
- Output `boot.img` hasil repack + zip AnyKernel3.

## Build

Workflow: `.github/workflows/build.yml` (manual dispatch).

```bash
gh workflow run build.yml --repo temporalsgt/fogos-axion-sukisu-susfs
gh run watch --repo temporalsgt/fogos-axion-sukisu-susfs
```

Artifact `fogos-axion-sukisu-susfs` berisi:

| File | Fungsi |
| --- | --- |
| `boot.img` | Flash fastboot, sudah berisi kernel baru + ramdisk Axion |
| `fogos-axion-sukisu-susfs-YYYYMMDD.zip` | Zip AnyKernel3 untuk recovery |
| `Image` | Kernel mentah |
| `kernel.config` | Config hasil build |
| `System.map` | Symbol map untuk verifikasi |
| `Module.symvers` | CRC simbol hasil build |
| `SHA256SUMS` | Checksum semua artifact |

## Flash

Bootloader HP sudah **unlocked** (`securestate: flashing_unlocked`), jadi
kedua cara bisa dipakai.

### Fastboot (disarankan)

```bash
adb reboot bootloader
fastboot flash boot boot.img
fastboot reboot
```

`boot.img` di artifact adalah **boot Axion 2.9 yang di-repack**, bukan boot
stock. Jangan flash `vendor_boot` atau `dtbo` — build ini tidak mengubahnya.

### Recovery (AnyKernel3)

1. Salin zip `fogos-axion-sukisu-susfs-*.zip` ke storage HP.
2. Boot ke TWRP/OrangeFox.
3. Install zip, lalu reboot.

Zip AK3 hanya mengganti kernel di boot yang sedang terpasang; ramdisk,
dtb, dan konfigurasi verity/AVB Axion tetap dipertahankan.

## Verifikasi setelah boot

```bash
adb shell uname -r
# harus: 5.4.302-moto-g92683a4fde22

adb shell su -c id
# harus: uid=0(root)

adb shell 'zcat /proc/config.gz | grep -E "CONFIG_KSU=|CONFIG_KSU_SUSFS="'
adb shell dmesg | grep -iE 'vermagic|disagrees about version|invalid module'
adb shell lsmod | wc -l
```

Tidak boleh ada error `version magic ... should be ...` atau
`disagrees about version of symbol`. Kalau ada, kernel tidak cocok dengan
modul vendor ROM.

Install **SukiSU Manager v4.3.0** untuk mengelola root dan melihat status
SUSFS.

## Rollback

Stock `boot.img` Axion 2.9 tersedia di release
[`stock-axion-2.9-20261028`](https://github.com/temporalsgt/fogos-axion-sukisu-susfs/releases/tag/stock-axion-2.9-20261028)
(SHA-256 `a6bee11325db92a5752797ba522970a2b1a4d37c0069c22c9ce7d7e0bd85d527`).

```bash
adb reboot bootloader
fastboot flash boot boot-stock.img
fastboot reboot
```

Kalau bootloop dan `adb` mati: tahan **Power + Volume Down** sampai
bootloader muncul, lalu flash `boot-stock.img` dari PC.

## Batasan

- **Hanya untuk build AxionOS 2.9 `20261028`.** Setelah OTA Axion, kernel dan
  modul vendor bisa berubah; build ulang dengan commit/config/boot image baru.
- OTA akan menimpa `boot`; kernel ini tidak punya survival otomatis.
- Play Integrity/attestation tidak dijamin. SUSFS bukan solusi PIF.
- Jangan mengunci ulang bootloader selama memakai kernel custom.

## Struktur

```text
config/axion-fogos_defconfig        config utuh dari HP
config/axion_sukisu_susfs.config    fragment KSU + SUSFS + LOCALVERSION
patches/susfs/                      SUSFS 5.4 v2.4.0 + inline hooks
patches/sukisu/                     patch kompatibilitas SukiSU untuk 5.4
scripts/apply-patches.sh            apply patch + integrasi SukiSU
scripts/build.sh                    download clang + build Image
scripts/verify.sh                   cek config, release, vermagic, simbol
scripts/package.sh                  CRC modul, repack boot.img, zip AK3
scripts/check-module-crcs.sh        pembanding CRC modul vendor
pins.env                            semua versi/commit/URL di-pin
```
