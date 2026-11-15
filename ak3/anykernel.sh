# AnyKernel3 configuration for fogos AxionOS 2.9 + SukiSU Ultra/SUSFS
#
# Only the kernel is replaced. The installed ramdisk is preserved bit-for-bit
# so that the AxionOS fstab/verity/AVB configuration and recovery-as-boot
# ramdisk of the running build stay intact.

properties() { '
kernel.string=fogos AxionOS 2.9 SukiSU Ultra + SUSFS
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=fogos
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

# boot shell variables
# fogos has an unused 8 MiB init_boot_a partition that is entirely zeroed;
# the real ramdisk lives in boot_a (header v3). AK3's BLOCK=auto checks
# init_boot before boot, dumps that blank partition, and magiskboot aborts
# with "Splitting image failed". Target boot explicitly.
BLOCK=boot
IS_SLOT_DEVICE=auto
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

# Boot install: "OG AK" kernel-only mode. split_boot dumps and splits the
# installed boot image but does not unpack or repack the ramdisk archive;
# flash_boot then rebuilds the image with the new kernel and flashes it back.
# The repack-free path keeps every ramdisk byte (including cpio metadata)
# identical to the running build -- dump_boot/write_boot would recompress the
# ramdisk and change the modes of the /data and /sdcard mountpoint dirs.
split_boot

flash_boot

# write_boot() also calls these; keep the same behavior if partition images
# are ever added to the zip. They are no-ops for the current payload.
flash_generic vendor_dlkm
flash_generic system_dlkm
flash_generic dtbo
