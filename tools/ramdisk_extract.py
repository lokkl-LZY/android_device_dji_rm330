#!/usr/bin/env python3
"""Extract + decompress ramdisk from an Android boot image (v1), then list/unpack
selected files from the newc cpio. Read-only against the source image.
Usage:
  python -I ramdisk_extract.py <boot.img> <out_dir> [--list]
"""
import gzip, io, os, struct, sys, zlib, hashlib

def read_hdr(path):
    with open(path, "rb") as f:
        h = f.read(2048)
    if h[:8] != b"ANDROID!":
        raise SystemExit("not bootimg")
    ks, ka, rs, ra, ss, sa, ta, ps = struct.unpack_from("<8I", h, 8)
    return ks, rs, ps

def get_ramdisk(path, out_dir, want_list):
    ks, rs, ps = read_hdr(path)
    if rs == 0:
        raise SystemExit("ramdisk_size == 0 (system-as-root boot image)")
    off = ps + ((ks + ps - 1) // ps) * ps
    with open(path, "rb") as f:
        f.seek(off)
        rd = f.read(rs)
    print(f"ramdisk offset={off:#x} size={rs} sha256={hashlib.sha256(rd).hexdigest()}")
    print("first bytes:", rd[:8].hex())
    if rd[:2] == b"\x1f\x8b":
        data = gzip.decompress(rd)
    elif rd[:6] == b"\xfd7zXZ\x00":
        import lzma; data = lzma.decompress(rd)
    elif rd[:4] == b"\x04\x22\x4d\x18":
        raise SystemExit("lz4 ramdisk: need lz4 tool")
    else:
        data = rd  # raw cpio
    print(f"cpio bytes={len(data)} first={data[:6]!r}")
    os.makedirs(out_dir, exist_ok=True)
    pos = 0
    while pos + 110 <= len(data):
        magic = data[pos:pos+6]
        if magic not in (b"070701", b"070702"):
            print(f"bad cpio magic at {pos:#x}: {magic!r}"); break
        def fld(i):
            return int(data[pos+6+i*8: pos+6+i*8+8], 16)
        ino, mode, uid, gid, nlink, mtime, filesize, dmaj, dmin, rmaj, rmin, namesize, chksum = [fld(i) for i in range(13)]
        name = data[pos+110:pos+110+namesize-1].decode("utf-8", "replace")
        hdr_len = 110 + namesize
        hdr_len = (hdr_len + 3) & ~3
        fdata = data[pos+hdr_len:pos+hdr_len+filesize]
        pos = pos + hdr_len + ((filesize + 3) & ~3)
        if name == "TRAILER!!!":
            break
        if want_list:
            print(f"{oct(mode)} {filesize:>8} {name}")
        if name.endswith("/"):
            continue
        dest = os.path.join(out_dir, name.lstrip("./"))
        try:
            os.makedirs(os.path.dirname(dest) or out_dir, exist_ok=True)
        except (FileExistsError, NotADirectoryError, OSError):
            continue  # path sits under a symlink/dir we cannot materialize on Windows
        if os.path.lexists(dest) and not os.path.isfile(dest):
            try: os.unlink(dest)
            except OSError: pass
        if mode & 0o170000 == 0o120000:  # symlink
            try: os.symlink(fdata.decode(), dest)
            except OSError: pass
            continue
        with open(dest, "wb") as f:
            f.write(fdata)
    print(f"unpacked to {os.path.abspath(out_dir)}")

if __name__ == "__main__":
    get_ramdisk(sys.argv[1], sys.argv[2], "--list" in sys.argv)
