#
# Product makefile — TWRP for DJI RC RM330
#
# Base: TWRP 10.0 (Omni-based minimal manifest twrp-10.0-deprecated)
# The TWRP recovery source itself is bootable/recovery from TeamWin android-10.0
# (pulled by twrp-extras.xml in that manifest).
#

LOCAL_PATH := device/dji/rm330

# Android 10 has no product/embedded.mk; TWRP 10 (omni) trees inherit
# core_minimal.mk (verified against TWRP 10 reference device trees).
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_minimal.mk)
$(call inherit-product, vendor/omni/config/common.mk)

$(call inherit-product, $(LOCAL_PATH)/device.mk)

PRODUCT_DEVICE := rm330
PRODUCT_NAME := twrp_rm330
PRODUCT_BRAND := DJI
PRODUCT_MODEL := DJI RC
PRODUCT_MANUFACTURER := DJI
PRODUCT_RELEASE_NAME := rm330
