#
# TWRP device configuration — DJI RC RM330 (msm8953 / pm8953 + pmi632)
#
# Evidence base (all read-only, extracted from the device's stock images):
#   boot.img header      : ANDROID!, page=2048, header_version=1,
#                          kernel_size=14139668, kernel_addr=0x80008000,
#                          ramdisk_size=0, ramdisk_addr=0x81000000, tags=0x80000100
#   vendor/etc/fstab.qcom: system -> / (ext4, wait,avb); userdata -> /data
#                          (fileencryption=ice,quota,reservedsize=128M)
#   partition manifest   : recovery/boot = 64 MiB, system = 817889280,
#                          vendor = 1048576000, dtbo = 8388608, no metadata part
#   build.prop           : Android 10 / SDK 29, 32-bit only (abilist32=armeabi,
#                          abilist64=), board=msm8953, model=DJI RC
#

DEVICE_PATH := device/dji/rm330

# ---------------------------------------------------------------- architecture
# 32-bit ARM only. Stock build.prop reports the standard 32-bit ARM ABI
# (ro.product.cpu.abi=armeabi-v7a, abilist64 empty); TARGET_CPU_ABI must use the
# same ABI name so the build's ABI directories match the device.
TARGET_ARCH := arm
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := armeabi-v7a
TARGET_CPU_ABI2 := armeabi
TARGET_CPU_VARIANT := cortex-a53
TARGET_CPU_SMP := true
TARGET_IS_64_BIT := false
TARGET_USES_64_BIT_BINDER := false

TARGET_BOARD_PLATFORM := msm8953
TARGET_BOOTLOADER_BOARD_NAME := msm8953
TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true
TARGET_OTA_ASSERT_DEVICE := rm330

# ---------------------------------------------------------------------- kernel
# Stock boot.img contains a 32-bit ARM zImage (self-decompressing, gzip payload
# at 0x4944, ARM zImage magic 0x016f2818 at 0x24). ABL loads it as-is, so the
# prebuilt stays in zImage form — do NOT substitute the decompressed Image
# (D:\download\DJI\fw_work\real_Image.bin is a *different* 2025-01-16 build;
#  boot.img zImage is the 2024-04-17 build that matches this device's vendor).
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/zImage
BOARD_KERNEL_IMAGE_NAME := zImage

# Copied from boot.img header v1, plus permissive SELinux for first TWRP bring-up.
# The stock line ends with "buildvariant=user"; that token is omitted here because
# build/make appends "buildvariant=$(TARGET_BUILD_VARIANT)" (eng for our lunch) and
# keeping both would duplicate the parameter.
BOARD_KERNEL_CMDLINE := console=ttyMSM0,115200,n8 androidboot.console=ttyMSM0 androidboot.hardware=qcom user_debug=30 msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlycon=msm_hsl_uart,0x78af000 androidboot.usbconfigfs=true vmalloc=300M loop.max_part=7 usbcore.autosuspend=-1 androidboot.selinux=permissive

BOARD_KERNEL_BASE := 0x80000000
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x01000000
BOARD_KERNEL_TAGS_OFFSET := 0x00000100
BOARD_KERNEL_PAGESIZE := 2048
BOARD_MKBOOTIMG_ARGS := --header_version 1

# The stock dtbo lives in its own partition and is loaded by ABL; do not pack a
# DTB into the recovery image.
# NOTE: leave this variable unset (do NOT set it to "false"): build/make tests it
# with $(if $(BOARD_INCLUDE_RECOVERY_DTBO),...) so any non-empty value, including
# "false", appends an empty --recovery_dtbo argument and mkbootimg fails.
# BOARD_INCLUDE_RECOVERY_DTBO :=

# ------------------------------------------------------------ partition layout
# Sizes come from backup_manifest.xml (last_lba - first_lba + 1) * 512.
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 67108864
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 817889280
BOARD_VENDORIMAGE_PARTITION_SIZE := 1048576000
BOARD_CACHEIMAGE_PARTITION_SIZE := 268435456
BOARD_USERDATAIMAGE_PARTITION_SIZE := 4260863488
BOARD_DTBOIMG_PARTITION_SIZE := 8388608
BOARD_FLASH_BLOCK_SIZE := 131072

BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_COPY_OUT_SYSTEM := system
TARGET_COPY_OUT_VENDOR := vendor

# Device is A-only with a dedicated 64 MiB recovery partition (no _a/_b slots,
# no recovery-as-boot, no dynamic partitions).
AB_OTA_UPDATER := false
BOARD_USES_RECOVERY_AS_BOOT := false
BOARD_BUILD_SYSTEM_ROOT_IMAGE := true

# No /metadata partition exists on this device (confirmed in the 55-entry GPT
# manifest and in vendor/etc/fstab.qcom). FBE keys live under /data.
BOARD_USES_METADATA_PARTITION := false

# Recovery build
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"
TARGET_SYSTEM_PROP := $(DEVICE_PATH)/system.prop
BOARD_AVB_ENABLE := false

# ------------------------------------------------------------------ TWRP flags
TW_THEME := portrait_hdpi
TW_DEVICE_VERSION := RM330-A10-skeleton
TW_DEFAULT_LANGUAGE := zh_CN

# Encryption: stock /data uses fileencryption=ice (hardware ICE, keymaster 4.0),
# with no metadata partition and no keydirectory flag.
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_FBE := true
# TW_INCLUDE_CRYPTO automatically sets TW_INCLUDE_CRYPTO_FBE and
# -DTW_INCLUDE_FBE_METADATA_DECRYPT in twrp-10.0; the latter is harmless here
# because there is no /metadata partition.
# If built-in fscrypt cannot talk to qti keymaster, try the system-vold path:
# TW_CRYPTO_USE_SYSTEM_VOLD := true

TW_EXCLUDE_TWRPAPP := true
TW_USE_TOOLBOX := true
TW_NO_REBOOT_BOOTLOADER := true
RECOVERY_SDCARD_ON_DATA := true

# Display / backlight (path taken from the stock recovery init.recovery.qcom.rc)
TW_MAX_BRIGHTNESS := 255
TW_BRIGHTNESS_PATH := "/sys/class/backlight/panel0-backlight/brightness"

# External storage
TW_EXTERNAL_STORAGE_PATH := "/external_sd"
TW_EXTERNAL_STORAGE_MOUNT_POINT := "external_sd"

# Optional size savers for the 64 MiB recovery budget (enable if the image is
# too large): TW_INCLUDE_NTFS_3G adds ~3 MiB. Leave disabled for first build.
# TW_INCLUDE_NTFS_3G := true

# Touch controller is unknown until first boot. If touch does not work, collect
# `getevent -l` / dmesg in recovery, then blacklist the wrong input device here:
# TW_INPUT_BLACKLIST := "<driver-name>"

# Omni/TWRP common board config: pulls in vendor/omni/config/BoardConfigKernel.mk
# (prebuilt-kernel copy rule) and BoardConfigSoong.mk. Must come after
# TARGET_PREBUILT_KERNEL so BoardConfigKernel.mk clears TARGET_KERNEL_SOURCE.
include vendor/omni/config/BoardConfigOmni.mk
