#
# Device makefile — DJI RC RM330
#

LOCAL_PATH := device/dji/rm330

# Recovery-side properties. ro.hardware is normally supplied by
# androidboot.hardware=qcom in the kernel cmdline; keep it explicit anyway.
PRODUCT_PROPERTY_OVERRIDES += \
    ro.hardware=qcom \
    ro.board.platform=msm8953 \
    ro.sf.lcd_density=400

# The stock ramdisk has no recovery.fstab of its own and the stock recovery
# binary is not present in the recovery ramdisk (it expects /system/bin/recovery),
# so TWRP must ship its own fstab. TARGET_RECOVERY_FSTAB in BoardConfig.mk is
# the canonical installation path; do not add a duplicate PRODUCT_COPY_FILES rule
# for the same destination or the build will fail with a duplicate copy error.
