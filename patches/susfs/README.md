# SUSFS v2.4.0 — 5.4 backport

File di direktori ini di-vendor agar build reproducible.

## Sumber

- **Kernel-side SUSFS patches**: `simonpunk` / `backslashxx`, proyek `susfs4ksu`.
- **Backport 5.4 + inline hook script**: `JackA1ltman/NonGKI_Kernel_Build_2nd`:
  - `Patches/Patch/susfs_patch_to_5.4.patch` (v2.4.0)
  - `Patches/susfs_inline_hook_patches.sh` (hook untuk SUSFS v2.3+)
- **SukiSU Ultra**: `SukiSU-Ultra/SukiSU-Ultra`, branch `builtin`, commit
  `f9aa2fec23c3f4a06a935f69dc04cb85b261e7f3` (Manager v4.3.0).

## Catatan

- `susfs_patch_to_5.4_v2.4.0.patch` membawa adaptasi hunk `fs/proc/fd.c`
  untuk tree LineageOS (backport `ino` ke `seq_printf`). Tree Axion 2.9
  berbasis `lineage-23.2` dan memakai backport yang sama.
- SHA-256 patch/hook ada di `pins.env` dan diverifikasi sebelum apply.
- `susfs_inline_hook_patches.sh` di-vendor dengan satu penyesuaian lokal:
  penambahan `#include "mount.h"` ke `fs/stat.c` dibuang. Include itu hanya
  dipakai untuk fitur `stat->mnt_id` kernel 5.10 dan membuat genksyms
  menghitung CRC `generic_fillattr` berbeda, sehingga modul stock `exfat.ko`
  menolak dimuat.
- File ini bukan kernel repo pihak ketiga; hanya patch yang di-vendor.
