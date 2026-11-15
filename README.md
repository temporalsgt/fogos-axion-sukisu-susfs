# fogos AxionOS 2.9 — SukiSU Ultra + SUSFS

Kernel untuk **Motorola Moto G45 5G (`fogos`, SM6375/Holi, Linux 5.4.302)** yang dijalankan di **AxionOS 2.9** resmi, dengan **SukiSU Ultra** mode `builtin` dan **SUSFS v2.4.0**.

Build ini mendukung dua varian ROM: **VANILLA** dan **GMS/GApps**. Kernel dan modul vendornya sama; yang berbeda hanya ramdisk boot. Release ini menyediakan satu zip AnyKernel3 **kernel-only** yang mempertahankan ramdisk yang sedang terpasang, sehingga bisa dipakai untuk kedua varian.

- Repo: <https://github.com/temporalsgt/fogos-axion-sukisu-susfs>
- ROM acuan: `axion-2.9-NOESIS-20261028-OFFICIAL-VANILLA-fogos` dan `axion-2.9-NOESIS-20261028-OFFICIAL-GMS-fogos`
- Kernel release acuan: `5.4.302-moto-g92683a4fde22`
- Build: GitHub Actions (`ubuntu-24.04`)
- **Release terbaru:** [`fogos-axion-sukisu-susfs-20261115`](https://github.com/temporalsgt/fogos-axion-sukisu-susfs/releases/tag/fogos-axion-sukisu-susfs-20261115)

## Download

Paket siap flash tersedia di GitHub Release:

| Asset | Varian | Ukuran |
| --- | --- | ---: |
| `fogos-axion-sukisu-susfs-20261115.zip` | VANILLA + GMS/GApps | 21.660.691 |
| `Image` | Semua varian | 39.463.424 |
| `kernel.config` | Semua varian | 184.880 |
| `System.map` | Semua varian | 10.832.918 |
| `Module.symvers` | Semua varian | 762.744 |
| `SHA256SUMS` | Semua varian | 414 |

Zip AnyKernel3 memakai mode kernel-only: ramdisk ROM yang sedang terpasang dipertahankan byte-for-byte, jadi satu zip bisa dipakai di kedua varian. Release ini tidak menyertakan `boot.img`/`boot-gms.img`; stock boot tidak dihosting. Kalau perlu fastboot, ekstrak stock boot dari zip ROM Axion yang sesuai lalu repack dengan kernel dari asset `Image`.

Artifact `fogos-axion-sukisu-susfs` di GitHub Actions tetap tersedia sebagai hasil build mentah. Artifact memerlukan login GitHub dan bisa kedaluwarsa; release lebih stabil untuk distribusi.

## Build

Workflow: `.github/workflows/build.yml` (manual dispatch).

```bash
gh workflow run build.yml --repo temporalsgt/fogos-axion-sukisu-susfs
gh run watch --repo temporalsgt/fogos-axion-sukisu-susfs
```

Provenance build release `20261115`:

| Item | Nilai |
| --- | --- |
| Workflow run | `43724199764` |
| Commit repo | `e19d5eb5afabd446879d353c5f739b4baa38a4e8` |
| Commit kernel | `92683a4fde22b3d76efa18e11508af49a808bf77` |
| Clang | Android `r563880c` (21.0.0) |
| SukiSU Manager | `v4.3.0-r2-f9aa2fec` |

Artifact `fogos-axion-sukisu-susfs` berisi:

| File | Fungsi |
| --- | --- |
| `fogos-axion-sukisu-susfs-YYYYMMDD.zip` | Zip AnyKernel3 untuk recovery, bisa dipakai di kedua varian |
| `Image` | Kernel mentah |
| `kernel.config` | Config hasil build |
| `System.map` | Symbol map untuk verifikasi |
| `Module.symvers` | CRC simbol hasil build |
| `SHA256SUMS` | Checksum semua artifact |

`scripts/package.sh` menghasilkan `boot.img` dan `boot-gms.img` bila stock boot Axion yang sesuai tersedia; jika tidak, build tetap menghasilkan kernel, config, dan zip AK3. Stock boot tidak lagi dihosting di release terpisah.

## Flash

Bootloader HP sudah **unlocked** (`securestate: flashing_unlocked`). Release
ini memakai zip AK3, jadi flash lewat recovery. Zip ini hanya mengganti kernel
di `boot` yang sedang terpasang; ramdisk, DTB, dan konfigurasi verity/AVB
Axion tetap dipertahankan.

### Recovery (disarankan)

1. Salin `fogos-axion-sukisu-susfs-20261115.zip` ke storage HP.
2. Boot ke TWRP/OrangeFox.
3. Install zip, lalu reboot.

Zip ini **unsigned**; matikan verifikasi signature di recovery sebelum install.

Zip AK3 memakai mode kernel-only ("OG AK"): boot yang sedang terpasang
di-split, kernel diganti, lalu di-flash ulang tanpa mengekstrak atau
merepack ramdisk. Ramdisk, dtb, dan konfigurasi verity/AVB Axion tetap
bit-for-bit sama. Satu zip ini bisa dipakai untuk VANILLA maupun GMS/GApps.

### Fastboot (opsional)

Release ini tidak menyertakan `boot.img`/`boot-gms.img`. Kalau perlu flash
lewat fastboot, ekstrak `boot.img` dari zip ROM Axion yang sesuai, lalu repack
dengan kernel dari asset `Image` (lihat `scripts/package.sh`). Jangan menukar
`boot.img` VANILLA dan GMS/GApps; kernel-nya sama, tetapi ramdisk-nya berbeda.
Jangan flash `vendor_boot` atau `dtbo` — build ini tidak mengubahnya.

## Verifikasi setelah boot

```bash
adb shell uname -r
# harus: 5.4.302-moto-g92683a4fde22

adb shell getprop ro.axion.version
# VANILLA: 2.9-NOESIS-20261028-OFFICIAL-VANILLA-fogos
# GMS/GApps: 2.9-NOESIS-20261028-OFFICIAL-GMS-fogos

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

Stock boot tidak lagi dihosting di release terpisah. Ekstrak `boot.img` dari
zip ROM Axion yang sesuai, lalu flash:

```bash
adb reboot bootloader
fastboot flash boot_a boot.img
fastboot reboot
```

Untuk GMS/GApps, ekstrak `boot.img` dari zip
`axion-2.9-NOESIS-20261028-OFFICIAL-GMS-fogos.zip`.

### Kembali ke kernel custom sebelumnya

Flash ulang zip AK3 versi sebelumnya lewat recovery, atau restore backup
`boot` yang dibuat sebelum flashing. Kalau memakai image fastboot, flash
`boot.img` yang sesuai dengan varian ROM.

Kalau bootloop dan `adb` mati: tahan **Power + Volume Down** sampai
bootloader muncul, lalu flash stock boot dari PC. Data pengguna tidak
terhapus oleh flashing partisi `boot`.

## Batasan dan catatan

- **Hanya untuk build AxionOS 2.9 `20261028`**, varian VANILLA atau GMS/GApps.
  Setelah OTA Axion, kernel dan modul vendor bisa berubah; build ulang dengan
  commit/config/boot image baru.
- Zip AK3 bisa dipakai untuk VANILLA maupun GMS/GApps karena mempertahankan
  ramdisk terpasang. Kalau membuat `boot.img` sendiri, jangan menyilangkan
  varian: ramdisk-nya berbeda meskipun kernel-nya sama.
- Partisi `init_boot_a` di fogos kosong (8 MiB nol) dan ramdisk sebenarnya ada
  di `boot_a`. Zip AK3 memakai `BLOCK=boot` agar tidak salah memilih
  `init_boot` lalu gagal dengan `Splitting image failed`. Zip juga memakai
  flow kernel-only (`split_boot` + `flash_boot`) agar ramdisk tidak di-repack.
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
scripts/package.sh                  CRC modul, repack boot.img opsional, zip AK3
scripts/check-module-crcs.sh        pembanding CRC modul vendor
pins.env                            semua versi/commit/URL di-pin
```
