#!/usr/bin/env python3
"""Offline probes: decompress zImage payload and compare with a raw ARM Image;
parse dtbo header/entries; parse AVB vbmeta header flags. Read-only."""
import hashlib, json, os, struct, sys, zlib

def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()

def zimage_compare(zimg, raw_image):
    d = open(zimg, "rb").read()
    magic = struct.unpack_from("<I", d, 0x24)[0]
    start, end = struct.unpack_from("<II", d, 0x28)
    out = {"zImage": zimg, "zImage_size": len(d), "zImage_sha256": sha(zimg),
           "magic_0x24": hex(magic), "zimage_start": hex(start), "zimage_end": hex(end)}
    gz = None
    for off in range(0x30, min(len(d), 0x20000)):
        if d[off:off+2] == b"\x1f\x8b":
            gz = off; break
    out["gzip_offset"] = hex(gz) if gz else None
    if gz is None:
        return out
    dec = zlib.decompressobj(16 + zlib.MAX_WBITS)
    payload = dec.decompress(d[gz:])
    out["payload_size"] = len(payload)
    out["payload_sha256"] = hashlib.sha256(payload).hexdigest()
    out["payload_first64"] = payload[:64].hex()
    if raw_image and os.path.exists(raw_image):
        raw = open(raw_image, "rb").read()
        out["raw_image"] = raw_image
        out["raw_size"] = len(raw)
        out["raw_sha256"] = hashlib.sha256(raw).hexdigest()
        out["raw_first64"] = raw[:64].hex()
        out["payload_equals_raw"] = payload == raw
        # tolerate trailing pad in raw
        out["payload_prefix_of_raw"] = raw.startswith(payload)
        out["raw_prefix_of_payload"] = payload.startswith(raw)
    return out

def parse_dtbo(path):
    d = open(path, "rb").read()
    magic, total, hdr_size, ent_size, ent_cnt, ent_off, page_size, version = \
        struct.unpack_from("<8I", d, 0)
    out = {"file": path, "sha256": sha(path), "file_size": len(d),
           "magic": hex(magic), "magic_ok": magic == 0xd7b7ab1e,
           "total_size": total, "header_size": hdr_size, "entry_size": ent_size,
           "entry_count": ent_cnt, "entries_offset": ent_off,
           "page_size": page_size, "version": version, "entries": []}
    for i in range(ent_cnt):
        base = ent_off + i * ent_size
        dt_size, dt_off, dt_id, dt_rev = struct.unpack_from("<4I", d, base)
        custom = struct.unpack_from("<4I", d, base + 16)
        blob = d[dt_off:dt_off + dt_size]
        # FDT strings: model/compatible are NUL-terminated strings in blob
        txt = [s.decode("latin1", "replace") for s in blob.split(b"\x00") if len(s) >= 4]
        hints = [s for s in txt if any(k in s for k in ("qcom,", "msm", "rm330", "dji", "DJI", "model"))][:8]
        out["entries"].append({"index": i, "size": dt_size, "offset": hex(dt_off),
                               "id": hex(dt_id), "rev": dt_rev, "custom": list(custom),
                               "sha256": hashlib.sha256(blob).hexdigest(),
                               "strings_hint": hints})
    return out

def parse_vbmeta(path):
    d = open(path, "rb").read()
    out = {"file": path, "sha256": sha(path), "size": len(d), "magic": d[:4].decode("latin1")}
    if d[:4] != b"AVB0":
        return out
    (maj, mnr, auth_sz, aux_sz, alg, hoff, hsz, soff, ssz, pkoff, pksz,
     pkmoff, pkmsz, doff, dsz) = struct.unpack_from(">IIIIIIIIIIIIIII", d, 4)
    rollback, flags, rbloc = struct.unpack_from(">QII", d, 4 + 60)
    rel = d[4+72:4+72+48].split(b"\x00")[0].decode("latin1", "replace")
    out.update({"required_libavb_major": maj, "required_libavb_minor": mnr,
                "auth_block_size": auth_sz, "aux_block_size": aux_sz,
                "algorithm_type": alg, "rollback_index": rollback,
                "flags": flags,
                "hashtree_disabled": bool(flags & 1),
                "verification_disabled": bool(flags & 2),
                "rollback_index_location": rbloc, "release_string": rel})
    return out

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "zimage":
        print(json.dumps(zimage_compare(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None), indent=2))
    elif mode == "dtbo":
        print(json.dumps(parse_dtbo(sys.argv[2]), indent=2)[:12000])
    elif mode == "vbmeta":
        print(json.dumps(parse_vbmeta(sys.argv[2]), indent=2))
