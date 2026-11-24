# TWRP device tree — DJI RC RM330

Unofficial TWRP recovery device tree for the **DJI RC (RM330)**, a Qualcomm
msm8953-based Android 10 remote controller. Personal research project; not
affiliated with or endorsed by DJI.

## Device facts (verified from a full ISP backup of the unit)

| Item | Value |
|---|---|
| SoC | Qualcomm msm8953 (pm8953 + pmi632), 32-bit ARM userspace |
| OS | Android 10 (SDK 29), A-only, system-as-root |
| ABI | `armeabi-v7a` (vendor-customised ABI name reported by the stock build) |
| Recovery partition | 64 MiB, dedicated (not recovery-as-boot) |
| Boot partition | 64 MiB, boot header v1, page size 2048, **ramdisk_size = 0** |
| Kernel | 32-bit ARM zImage, `Linux 4.9.227-perf+`, built 2024-04-17 |
| system / vendor | ext4, 817,889,280 B / 1,048,576,000 B |
| /data | ext4 with `fileencryption=ice` (FBE), no `/metadata` partition |
| vbmeta | AVB, hashtree+verification currently disabled on the running unit |

## Tree contents

```
device/dji/rm330/
  BoardConfig.mk        architecture, kernel, partition sizes, TWRP flags
  device.mk             recovery product properties
  AndroidProducts.mk    lunch entry (twrp_rm330-eng)
  twrp_rm330.mk         product definition
  recovery.fstab        canonical fstab (also used as TW fstab)
  twrp.fstab            copy of recovery.fstab for TWRP conventions
  system.prop           extra recovery props
  vendorsetup.sh        legacy lunch hook
  prebuilt/zImage       stock kernel, byte-identical to boot.img kernel
  prebuilt/zImage.sha256
  prebuilt/README.md    kernel provenance and verification
build.sh                Linux build helper (repo init/sync → lunch → mka)
tools/                  read-only image/boot-header analysis helpers
```

Kernel SHA-256: `d8f778c599762f308ed882cc85007f799a6afdbae187c52d054c339f605ab8f1`
(14,139,668 B, zImage magic `0x016f2818` at offset 0x24).

## Building (Linux only)

Recommended host: Ubuntu 20.04, 8+ cores, 16 GB RAM, **80 GB+ free disk**
(source ≈ 25–35 GB, out ≈ 8–15 GB). AOSP 10 does not build with modern JDK 21.

```bash
# 1. dependencies
sudo apt-get update
sudo apt-get install -y bc bison build-essential ccache curl flex g++-multilib \
  gcc-multilib git gnupg gperf imagemagick lib32ncurses5-dev lib32readline-dev \
  lib32z1-dev liblz4-tool libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev \
  libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc zip \
  zlib1g-dev python3 python-is-python3 openjdk-8-jdk

# 2. TWRP minimal manifest (branch verified on GitHub)
mkdir -p ~/twrp10 && cd ~/twrp10
repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni.git \
  -b twrp-10.0-deprecated --depth=1
repo sync -j8 --force-sync --no-clone-bundle --no-tags

# 3. device tree
mkdir -p device/dji
cp -r /path/to/this/repo/device/dji/rm330 device/dji/rm330

# 4. build
source build/envsetup.sh
lunch twrp_rm330-eng
mka recoveryimage -j8
# out/target/product/rm330/recovery.img  (must be < 64 MiB)
```

`build.sh` automates the same flow and includes environment/disk checks:

```bash
./build.sh --check          # host, disk, tools
./build.sh --sync --yes     # sync + build
```

## CI

`ci/build-twrp.yml` is a workflow template for a **self-hosted Linux runner**
with ≥80 GB free disk (GitHub-hosted standard runners have ≈14 GB free and
cannot hold an AOSP 10 tree). To enable it, copy it to
`.github/workflows/build-twrp.yml`; pushing workflow files requires a GitHub
token with the `workflow` scope (`gh auth refresh -s workflow`), or add it
through the web UI.

## Flashing and rollback

- Flash **recovery only** (`fastboot flash recovery recovery.img` while in
  fastboot, or via an ISP/eMMC writer). Do not touch `boot`, `aboot`, `sbl1`.
- Keep vbmeta verification/hashtree disabled (flags `0x3` on this unit),
  otherwise a modified recovery will be rejected by AVB.
- Rollback: restore the stock `recovery.img` from your own full backup.
- non-A/B device: no slot suffixes.

## Known limitations

- **/data decryption is unlikely to work.** Stock `/data` uses FBE with
  `fileencryption=ice` and qti keymaster 4.0; the stock recovery does not start
  that HAL. TWRP may show `/data` as 0 MB / fail to decrypt. Do not format
  `/data` unless you accept losing it.
- `TW_THEME := portrait_hdpi` may need to become `landscape_hdpi` depending on
  the panel orientation at first boot.
- The kernel is the stock prebuilt (no source). Do not substitute the
  decompressed `Image` from a newer firmware: it is a different build and may
  break module/vermagic compatibility.

## Provenance / disclaimer

The kernel in `prebuilt/` was extracted from a boot image of a personally owned
device. All other files were written from scratch based on read-only analysis of
that device's partitions. Use at your own risk; no warranty.
