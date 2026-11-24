#!/usr/bin/env python3
"""Parse Android boot image header (v0/v1/v2), dump fields, extract kernel.
Read-only: never writes into the source image.
Usage: python -I bootimg_parse.py <boot.img> [--extract <out_kernel>]
"""
import hashlib
import struct
import sys
import json
import os

MAGIC = b"ANDROID!"

def parse(path):
    with open(path, "rb") as f:
        data = f.read(4096)
    if data[:8] != MAGIC:
        raise SystemExit(f"{path}: not an Android boot image (magic={data[:8]!r})")
    (kernel_size, kernel_addr, ramdisk_size, ramdisk_addr,
     second_size, second_addr, tags_addr, page_size,
     field40, field44) = struct.unpack_from("<10I", data, 8)
    name = data[48:64].split(b"\x00")[0].decode("latin1")
    cmdline = data[64:576].split(b"\x00")[0].decode("latin1", "replace")
    extra = data[608:1632].split(b"\x00")[0].decode("latin1", "replace")
    hdr_ver = field40 if field40 < 10 else 0  # v0 puts dt_size here (>=4096)
    os_ver = field44
    out = {
        "file": os.path.abspath(path),
        "file_size": os.path.getsize(path),
        "sha256": hashlib.sha256(open(path, "rb").read()).hexdigest(),
        "magic": data[:8].decode(),
        "kernel_size": kernel_size,
        "kernel_addr": hex(kernel_addr),
        "ramdisk_size": ramdisk_size,
        "ramdisk_addr": hex(ramdisk_addr),
        "second_size": second_size,
        "second_addr": hex(second_addr),
        "tags_addr": hex(tags_addr),
        "page_size": page_size,
        "header_version": hdr_ver,
        "field40_raw": field40,
        "os_version_raw": hex(os_ver),
        "name": name,
        "cmdline": cmdline,
        "extra_cmdline": extra,
        "id": data[576:608].hex(),
    }
    return out

def extract_kernel(path, info, out_path):
    page = info["page_size"]
    ksize = info["kernel_size"]
    with open(path, "rb") as f:
        f.seek(page)
        kern = f.read(ksize)
    with open(out_path, "wb") as f:
        f.write(kern)
    h = hashlib.sha256(kern).hexdigest()
    # zImage header probe (ARM zImage: magic 0x016f2818 at 0x24)
    zmagic = struct.unpack_from("<I", kern, 0x24)[0] if len(kern) > 0x28 else 0
    zstart, zend = (struct.unpack_from("<II", kern, 0x28) if len(kern) > 0x30 else (0, 0))
    comp = "unknown"
    for off in range(0x30, min(len(kern), 0x20000)):
        b = kern[off:off + 4]
        if b[:2] == b"\x1f\x8b":
            comp = f"gzip@{off:#x}"; break
        if b == b"\xfd7zXZ\x00"[:4]:
            comp = f"xz@{off:#x}"; break
        if b == b"\x04\x22\x4d\x18":
            comp = f"lz4@{off:#x}"; break
        if b == b"\x28\xb5\x2f\xfd":
            comp = f"zstd@{off:#x}"; break
        if b == b"BZh":
            comp = f"bzip2@{off:#x}"; break
        if b == b"\x89LZO":
            comp = f"lzo@{off:#x}"; break
    return {
        "kernel_file": os.path.abspath(out_path),
        "kernel_sha256": h,
        "zimage_magic_0x24": hex(zmagic),
        "zimage_is_arm": zmagic == 0x016f2818,
        "zimage_start": hex(zstart), "zimage_end": hex(zend),
        "payload_compression": comp,
        "first64_hex": kern[:64].hex(),
    }

if __name__ == "__main__":
    img = sys.argv[1]
    info = parse(img)
    print(json.dumps(info, indent=2, ensure_ascii=False))
    if "--extract" in sys.argv:
        out = sys.argv[sys.argv.index("--extract") + 1]
        print(json.dumps(extract_kernel(img, info, out), indent=2))
