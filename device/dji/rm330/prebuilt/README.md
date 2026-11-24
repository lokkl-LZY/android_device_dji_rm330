# prebuilt/zImage — provenance and verification

## What this is

The kernel extracted **byte-for-byte** from `a7a备份/boot.img` (Android boot image,
header v1, page size 2048). Offset in image: 2048, length 14,139,668 bytes.

| Property | Value |
|---|---|
| File | `zImage` (32-bit ARM zImage, gzip-compressed payload) |
| Size | 14,139,668 bytes |
| SHA-256 | `d8f778c599762f308ed882cc85007f799a6afdbae187c52d054c339f605ab8f1` |
| zImage magic @0x24 | `0x016f2818` (ARM) |
| gzip payload offset | `0x4944` |
| Decompressed payload | 24,424,452 bytes |
| Kernel banner | `Linux version 4.9.227-perf+ ... #2 SMP PREEMPT Wed Apr 17 08:53:27 CST 2024` |

`a7a备份/recovery.img` contains the **identical** kernel
(`kernel_size=14139668`, same SHA-256), so one prebuilt serves both.

## Why zImage and not a decompressed Image

The stock boot chain (Qualcomm ABL) loads the zImage exactly as shipped and relies
on the kernel's own self-decompression stub. Keeping the original zImage
guarantees the same load/entry behaviour and the same `kernel_addr=0x80008000`
layout that the boot image header declares.

## Do not use real_Image.bin here

`D:\download\DJI\fw_work\real_Image.bin` is a **different build**:

| | boot.img zImage payload | real_Image.bin |
|---|---|---|
| Size | 24,424,452 | 24,424,452 |
| SHA-256 | `df64c92aa268bf9a34348bd028257ff5faf69d85eca00bc04205cd5890ad4390` | `f807219015bce6d99fb8c32763cd3205542b45852aa2ebbd82f7c8ce961b9e02` |
| Banner | `Wed Apr 17 08:53:27 CST 2024` | `Thu Jan 16 11:51:04 CST 2025` |

Byte comparison: 1,240 differing bytes in 5 clusters (offset `0xff8076` …
`0x160974d`), i.e. a different kernel build, not just padding.

Additional evidence that the boot.img kernel is the right one: the device's
`vendor/build.prop` and `system/build.prop` are dated `Wed Apr 17 08:35:40 CST 2024`
(fingerprint `DJI/rm330/rm330:10/V00.14.00.59/59:user/test-keys`), and the boot.img
kernel banner is `Wed Apr 17 08:53:27 CST 2024` — same build day. The January 2025
`real_Image.bin` belongs to a newer firmware and risks `vermagic`/module mismatch.

## How to re-verify / re-extract

```bash
# from the repo root; boot.img is a stock boot partition image from your own device
python3 tools/bootimg_parse.py /path/to/boot.img --extract device/dji/rm330/prebuilt/zImage
cd device/dji/rm330/prebuilt && sha256sum -c zImage.sha256
```

The `bootimg_parse.py` script is read-only against `boot.img`.
