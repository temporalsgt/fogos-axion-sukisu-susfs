# fogos AxionOS 2.9 — SukiSU Ultra + SUSFS

Kernel untuk **Motorola Moto G45 5G (`fogos`, SM6375/Holi, Linux 5.4.302)** yang dijalankan di **AxionOS 2.9** resmi, dengan **SukiSU Ultra** mode `builtin` dan **SUSFS v2.4.0**.

- Repo: <https://github.com/temporalsgt/fogos-axion-sukisu-susfs>
- ROM acuan: `axion-2.9-NOESIS-20261028-OFFICIAL-VANILLA-fogos`
- Kernel release acuan: `5.4.302-moto-g92683a4fde22`
- Build: GitHub Actions (`ubuntu-24.04`)
- **Release terbaru:** [`fogos-axion-sukisu-susfs-20261114`](https://github.com/temporalsgt/fogos-axion-sukisu-susfs/releases/tag/fogos-axion-sukisu-susfs-20261114)

## Download

Paket siap flash tersedia di GitHub Release:

| Asset | Ukuran |
| --- | ---: |
| `boot.img` | 57.987.072 |
| `fogos-axion-sukisu-susfs-20261114.zip` | 21.658.322 |
| `Image` | 39.463.424 |
| `kernel.config` | 184.880 |
| `System.map` | 10.832.918 |
| `Module.symvers` | 762.744 |

Artifact `fogos-axion-sukisu-susfs` di GitHub Actions tetap tersedia sebagai hasil build mentah. Artifact memerlukan login GitHub dan bisa kedaluwarsa; release lebih stabil untuk distribusi.

## Build

Workflow: `.github/workflows/build.yml` (manual dispatch).

```bash
gh workflow run build.yml --repo temporalsgt/fogos-axion-sukisu-susfs
gh run watch --repo temporalsgt/fogos-axion-sukisu-susfs
```

Provenance build release `20261114`:

| Item | Nilai |
| --- | --- |
| Workflow run | `43600827588` |
| Commit repo | `c7518443e7c28e48bf1db46ddd341fa6e3de2964` |
| Commit kernel | `92683a4fde22b3d76efa18e11508af49a808bf77` |
| Clang | Android `r563880c` (21.0.0) |
| SukiSU Manager | `v4.3.0-r2` |

Artifact `fogos-axion-sukisu-susfs` berisi:

| File | Fungsi |
| --- | --- |
| `boot.img` | Flash fastboot, sudah berisi kernel baru + ramdisk Axion |
| `fogos-axion-sukisu-susfs-YYYYMMDD.zip` | Zip AnyKernel3 untuk recovery |
| `Image` | Kernel mentah |
| `kernel.config` | Config hasil build |
| `System.map` | Symbol map untuk verifikasi |
| `Module.symvers` | CRC simbol hasil build |

## Flash

Bootloader HP sudah **unlocked** (`securestate: flashing_unlocked`), jadi
kedua cara bisa dipakai.

### Fastboot (disarankan)

```bash
adb reboot bootloader
fastboot flash boot_a boot.img
fastboot reboot
```

Perintah di atas hanya menulis ke **`boot_a`**. Slot `boot_b` dibiarkan stock
Axion sebagai fallback. Hindari `fastboot flash boot` tanpa suffix kalau ingin
memastikan slot B tidak tersentuh.

`boot.img` di release adalah **boot Axion 2.9 yang di-repack**, bukan boot
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
# harus: uid=0(root) context=u:r:ksu:s0

adb shell dmesg | grep -iE 'vermagic|disagrees about version|unknown symbol|invalid module'
adb shell lsmod | wc -l
```

Tidak boleh ada error `version magic ... should be ...` atau
`disagrees about version of symbol`. Kalau ada, kernel tidak cocok dengan
modul vendor ROM.

Install **SukiSU Manager v4.3.0** untuk mengelola root dan melihat status
SUSFS. Manager yang sama juga menampilkan versi kernel, status SUSFS, dan
daftar modul.

## Rollback

### Kembali ke stock Axion 2.9

Stock `boot.img` Axion 2.9 tersedia di release
[`stock-axion-2.9-20261028`](https://github.com/temporalsgt/fogos-axion-sukisu-susfs/releases/tag/stock-axion-2.9-20261028).

```bash
adb reboot bootloader
fastboot flash boot_a boot.img
fastboot reboot
```

### Kembali ke kernel custom sebelumnya

Flash `boot.img` dari release custom yang sebelumnya dipakai dengan perintah
yang sama:

```bash
fastboot flash boot_a boot.img
fastboot reboot
```

Kalau bootloop dan `adb` mati: tahan **Power + Volume Down** sampai
bootloader muncul, lalu flash stock boot dari PC. Data pengguna tidak
terhapus oleh flashing partisi `boot`.

## Batasan dan catatan

- **Hanya untuk build AxionOS 2.9 `20261028`.** Setelah OTA Axion, kernel dan
  modul vendor bisa berubah; build ulang dengan commit/config/boot image baru.
- OTA akan menimpa `boot`; kernel ini tidak punya survival otomatis.
- Play Integrity/attestation tidak dijamin. SUSFS bukan solusi PIF, dan
  bootloader tetap unlocked.
- Jangan mengunci ulang bootloader selama memakai kernel custom.
- Jangan flash `vendor_boot` atau `dtbo`; keduanya harus tetap stock.
- Masih ada 10 simbol mengandung `ksu` di `/proc/kallsyms`
  (`setup_ksu_cred`, `is_task_ksu_domain`, `anon_ksu_ioctl`, dan lainnya).
  Ini keterbatasan filter SUSFS v2.4.0; root dan SUSFS tetap berfungsi.
- `CONFIG_KPM=n` — KPM memang tidak dibangun.
- Fitur “Sembunyikan modifikasi SELinux” tidak didukung kernel ini.
- Log `feature: invalid feature_id 10003` bisa muncul di dmesg. Itu fitur
  opsional Manager yang tidak ada di kernel 5.4; tidak memengaruhi root.
- Zygisk tidak termasuk dalam kernel; itu komponen terpisah.
- Jangan memberikan akses root ke aplikasi yang tidak dikenal.

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
