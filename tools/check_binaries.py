#!/usr/bin/env python3
"""Extract usque zips, then verify each binary's ELF header + Go build info.

The ELF check answers: does this binary match my router's CPU/endianness/FP ABI?
The Go build-info check answers: was it really built for GOOS/GOARCH I expect?

Usage: python tools/check_binaries.py
"""
import json
import os
import struct
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")
BIN = os.path.join(DIST, "bin")
os.makedirs(BIN, exist_ok=True)

MACHINES = {
    3: "i386", 8: "mips", 20: "ppc", 22: "s390", 40: "arm", 62: "x86_64",
    183: "aarch64", 243: "riscv",
}
MIPS_FP_ABI = {0: "ANY", 1: "hard-float(double)", 2: "hard-float(single)", 3: "soft-float", 4: "hard-float(64A)"}
ARM_EABI = {0: "pre-EABI", 1: "EABI v1", 2: "EABI v2", 3: "EABI v3", 4: "EABI v4", 5: "EABI v5"}


def elf_info(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF":
        return {"error": "not an ELF file"}
    ei_class, ei_data = data[4], data[5]
    is64 = ei_class == 2
    endian = "<" if ei_data == 1 else ">"
    machine = struct.unpack_from(endian + "H", data, 18)[0]
    e_flags = struct.unpack_from(endian + "I", data, 36)[0]

    info = {
        "class": "ELF64" if is64 else "ELF32",
        "endianness": "little" if ei_data == 1 else "big",
        "machine": MACHINES.get(machine, "unknown(%d)" % machine),
        "e_flags": hex(e_flags),
    }

    e_shoff = struct.unpack_from(endian + ("Q" if is64 else "I"), data, 40 if is64 else 32)[0]
    e_shentsize = struct.unpack_from(endian + "H", data, 58 if is64 else 46)[0]
    e_shnum = struct.unpack_from(endian + "H", data, 60 if is64 else 48)[0]
    e_shstrndx = struct.unpack_from(endian + "H", data, 62 if is64 else 50)[0]
    shs = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        if is64:
            name, typ, flags, addr, offset, size = struct.unpack_from(endian + "IIQQQQ", data, off)
        else:
            name, typ, flags, addr, offset, size = struct.unpack_from(endian + "IIIIII", data, off)
        shs.append((name, typ, offset, size))
    if not shs:
        return info
    strtab_off, strtab_size = shs[e_shstrndx][2], shs[e_shstrndx][3]
    strtab = data[strtab_off:strtab_off + strtab_size]

    def sname(idx):
        end = strtab.find(b"\x00", idx)
        return strtab[idx:end].decode(errors="replace")

    for name, typ, offset, size in shs:
        if sname(name) == ".MIPS.abiflags" and size >= 7:
            fp_abi = data[offset + 6]
            info["fp_abi"] = MIPS_FP_ABI.get(fp_abi, "unknown(%d)" % fp_abi)
    if info["machine"] == "arm":
        info["eabi"] = ARM_EABI.get((e_flags >> 24) & 0xFF, "?")
        if e_flags & 0x400:
            info["float_abi"] = "hard"
        elif e_flags & 0x200:
            info["float_abi"] = "soft"
        else:
            info["float_abi"] = "unspecified"
    return info


def go_build_info(path):
    out = subprocess.run(["go", "version", "-m", path], capture_output=True, text=True)
    if out.returncode != 0:
        return out.stderr.strip() or "go version -m failed"
    keep = []
    for line in out.stdout.splitlines():
        s = line.strip()
        if s.startswith(("mod", "path", "build", "vcs.revision")) or s.startswith("dep\tgithub.com/quic-go") or s.startswith("dep\tgolang.zx2c4"):
            keep.append(s)
    return "\n    ".join(keep)


def main():
    zips = sorted(f for f in os.listdir(DIST) if f.endswith(".zip") and "linux" in f)
    if not zips:
        print("no linux zips in dist/", file=sys.stderr)
        return 1
    rows = []
    for z in zips:
        arch = z.split("_linux_")[1].replace(".zip", "")
        with zipfile.ZipFile(os.path.join(DIST, z)) as zf:
            names = zf.namelist()
            member = next(n for n in names if n == "usque")
            target = os.path.join(BIN, "usque-linux-" + arch)
            with zf.open(member) as src, open(target, "wb") as dst:
                dst.write(src.read())
        os.chmod(target, 0o755)
        info = elf_info(target)
        gb = go_build_info(target)
        rows.append((arch, z, info, gb))
        print("### %s   (%s, inner member 'usque', %d bytes)" % (arch, z, os.path.getsize(target)))
        print("    ELF: %s" % json.dumps(info, ensure_ascii=False))
        print("    %s" % gb)
        print()

    with open(os.path.join(DIST, "binary-verification.txt"), "w") as f:
        for arch, z, info, gb in rows:
            f.write("%s\t%s\t%s\n" % (arch, z, json.dumps(info, sort_keys=True)))
    print("wrote dist/binary-verification.txt for %d binaries" % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())