# Flash dan Rollback — fogos AxionOS 2.9 + SukiSU/SUSFS

Panduan ini hanya berlaku untuk **AxionOS 2.9 build `20261028`** di `fogos`
dengan bootloader unlocked.

- Kernel release: `5.4.302-moto-g92683a4fde22`
- Kernel commit: `92683a4fde22b3d76efa18e11508af49a808bf77`
- Stock `boot.img` SHA-256: `a6bee11325db92a5752797ba522970a2b1a4d37c0069c22c9ce7d7e0bd85d527`
- Stock `vendor_boot.img` SHA-256: `eeb22d287ad6b6c159150d15ee01fdc64974f016ae5a5b960fb603f08474ed0a`

**Jangan flash `boot.img` ini di build Axion lain.** Ramdisk di dalamnya
berasal dari build 20261028, dan modul `vendor_dlkm` build lain punya
`vermagic`/CRC yang bisa berbeda.

## Sebelum flash

1. Backup data penting.
2. Siapkan PC dengan `adb` dan `fastboot`.
3. Cek build yang terpasang:

   ```bash
   adb shell getprop ro.axion.version
   ```

   Harus:

   ```text
   2.9-NOESIS-20261028-OFFICIAL-VANILLA-fogos
   ```

   Kalau berbeda, **berhenti** — build ulang kernel untuk build tersebut.
4. Unduh stock `boot.img` dari release
   `stock-axion-2.9-20261028` dan simpan sebagai `boot-stock.img`.
5. Verifikasi file stock:

   ```bash
   sha256sum boot-stock.img
   # a6bee11325db92a5752797ba522970a2b1a4d37c0069c22c9ce7d7e0bd85d527
   ```

6. Catat slot aktif:

   ```bash
   adb reboot bootloader
   fastboot getvar current-slot
   ```

   Axion 2.9 di HP ini memakai slot `a`, tetapi selalu cek ulang.

## Flash kernel

### Opsi A — fastboot (utama)

```bash
adb reboot bootloader
fastboot flash boot boot.img
fastboot reboot
```

`boot.img` adalah artifact CI (`dist/boot.img`), bukan boot stock.

### Opsi B — AnyKernel3 (TWRP/OrangeFox)

Gunakan hanya di build 20261028. Zip AK3 memakai mode kernel-only
(`split_boot` + `flash_boot`): hanya kernel yang diganti, ramdisk yang sedang
terpasang dipertahankan bit-for-bit tanpa ekstrak/repack.

1. Salin `fogos-axion-sukisu-susfs-*.zip` ke storage.
2. Boot ke TWRP/OrangeFox.
3. Install zip, lalu reboot.

Recovery resmi Axion biasanya menolak zip unsigned; gunakan fastboot atau
TWRP.

> **Troubleshooting:** kalau instalasi berhenti dengan
> `Splitting image failed. Aborting...`, zip AK3 tersebut masih memakai
> `BLOCK=auto`. Di HP ini `init_boot_a` kosong (8 MiB nol), sehingga
> auto-deteksi memilih partisi itu dan bukan `boot_a`. Pakai zip build
> **20261115** atau lebih baru (sudah `BLOCK=boot`), atau flash `boot.img`
> lewat fastboot.

## Verifikasi setelah boot

```bash
adb shell uname -r
adb shell getprop ro.axion.version
```

`uname -r` harus **persis**:

```text
5.4.302-moto-g92683a4fde22
```

Kalau ada suffix `-dirty` atau hash lain, jangan lanjut — modul `vendor_dlkm`
tidak akan cocok.

Install **SukiSU Manager v4.3.0**, lalu:

```bash
adb shell su -c id
# uid=0(root)

adb shell 'zcat /proc/config.gz | grep -E "CONFIG_KSU=|CONFIG_KSU_SUSFS="'
adb shell dmesg | grep -iE 'module|vermagic|disagrees|invalid'
adb shell lsmod | wc -l
```

Tidak boleh ada `version magic ... should be ...` atau
`disagrees about version of symbol`.

## Rollback dan perbaikan bootloop

### Yang harus disiapkan sebelum flash

- `boot-stock.img`: stock `boot.img` Axion 2.9 build 20261028
  (`a6bee113…`), sudah diverifikasi dengan `sha256sum`.
- PC + kabel USB + `adb`/`fastboot`.
- Jangan pernah mengunci ulang bootloader selama memakai kernel custom.

### 1. Masuk ke bootloader

Kalau `adb` masih jalan:

```bash
adb reboot bootloader
```

Kalau tidak (layar bootloop/logo):

1. Tahan **Power + Volume Down** ±10 detik sampai layar bootloader muncul.
2. Kalau hanya bergetar/restart, lepaskan lalu tekan kombinasi lagi.
3. Di menu bootloader, gunakan Volume untuk memilih dan Power untuk konfirmasi.

### 2. Kembalikan boot stock

```bash
fastboot devices
fastboot getvar current-slot        # a atau b
fastboot flash boot boot-stock.img  # menulis slot aktif
fastboot reboot
```

Kalau perintah `boot` ditolak ("partition not found"), tulis eksplisit ke slot
aktif:

```bash
fastboot flash boot_a boot-stock.img   # jika current-slot: a
fastboot flash boot_b boot-stock.img   # jika current-slot: b
```

Build ini tidak mengubah `dtbo`/`vendor_boot`, jadi jangan flash keduanya.

### 3. Pastikan rollback berhasil

Kernel stock dan kernel custom punya release string yang **sama**
(`5.4.302-moto-g92683a4fde22`). Cek yang membedakan:

```bash
adb shell su -c id
# harus GAGAL (tidak ada root)

adb shell 'zcat /proc/config.gz | grep CONFIG_KSU'
# harus kosong

adb shell uname -v
# stock: ... Wed Oct 28 04:15:28 UTC 2026
# custom: waktu build baru

adb shell dmesg | grep -i susfs
# harus kosong pada kernel stock

adb shell lsmod | wc -l
# modul vendor tetap harus termuat
```

### 4. Kalau masih bootloop setelah boot stock

1. Masuk recovery (dari bootloader pilih **Recovery mode**, atau
   `fastboot reboot recovery` bila tersedia).
2. Sideload ulang ROM resmi build 20261028:
   ```bash
   adb sideload axion-2.9-NOESIS-20261028-OFFICIAL-VANILLA-fogos.zip
   ```
3. Kalau masih gagal, di recovery lakukan **Factory reset → Format data**,
   lalu sideload ROM lagi. Ini menghapus data.
4. Jangan flash kernel custom lagi sampai penyebabnya diketahui.

### 5. Ambil log untuk analisis

Kalau HP sempat boot sebagian:

```bash
adb shell dmesg > dmesg-bootloop.txt
adb shell 'cat /proc/last_kmsg' > last-kmsg.txt
```

Kalau tidak sempat, dari recovery:

```bash
adb shell
cat /sys/fs/pstore/console-ramoops* > /tmp/ramoops.txt
exit
adb pull /tmp/ramoops.txt
```

`pstore` aktif di kernel stock maupun custom (`CONFIG_PSTORE_RAM=y`), jadi log
panic boot sebelumnya biasanya masih tersimpan.

### 6. Kalau fastboot sama sekali tidak bisa masuk

- Coba kombinasi tombol lagi dengan kabel USB terpasang.
- Coba PC lain / kabel lain / port USB 2.0.
- Jangan langsung ke EDL/firehose; itu jalur darurat dan berisiko.

Kalau bootloader bisa dibuka, bootloop hampir selalu bisa dipulihkan dengan
`fastboot flash boot boot-stock.img`.

## Setelah update AxionOS (OTA)

OTA akan menimpa `boot` dan biasanya juga mengubah modul di partisi vendor.
Kernel custom ini **tidak otomatis ikut update** dan **tidak boleh** dipakai
di build baru.

Sebelum update, matikan update otomatis sampai kernel di-build ulang untuk
build tersebut.

Setelah OTA:

1. Boot ke sistem sekali untuk memastikan update normal.
2. Catat `ro.axion.version` dan kernel release stock baru.
3. Build ulang kernel dari commit kernel + `boot.img` build baru, lalu update
   `KERNEL_COMMIT`, `EXPECTED_KERNEL_RELEASE`, `STOCK_BOOT_*`, dan
   `STOCK_VENDOR_BOOT_*` di `pins.env`.
4. Flash hasil build baru dan verifikasi ulang.

Tidak ada mekanisme survival otomatis pada versi ini.

## Catatan keamanan

- Bootloader unlocked berarti peringatan verified boot; ini normal untuk
  kernel custom. Properti `ro.boot.flash.locked=1` di ROM Axion adalah spoof
  Play Integrity, bukan status bootloader sebenarnya.
- Jangan menonaktifkan verity/verification kecuali benar-benar diperlukan.
- SUSFS bukan solusi Play Integrity/attestation. Aplikasi banking tertentu
  tetap bisa mendeteksi root.
