#!/usr/bin/env python3
"""Count MIPS floating-point (COP1) instructions in a binary's .text section.

Why: Go's default GOMIPS is hardfloat. A hardfloat binary executes FPU
instructions; on FPU-less MIPS32 SoCs (MT7620/MT7621, AR934x, ...) that traps
with SIGILL ("Illegal instruction"). Soft-float builds avoid COP1 entirely.

Usage: python scan_fpu.py <elf-file> [more files...]
"""
import struct
import sys

import capstone


def sections(path):
    data = open(path, "rb").read()
    endian = "<" if data[5] == 1 else ">"
    is64 = data[4] == 2
    e_shoff = struct.unpack_from(endian + ("Q" if is64 else "I"), data, 40 if is64 else 32)[0]
    e_shentsize = struct.unpack_from(endian + "H", data, 58 if is64 else 46)[0]
    e_shnum = struct.unpack_from(endian + "H", data, 60 if is64 else 48)[0]
    e_shstrndx = struct.unpack_from(endian + "H", data, 62 if is64 else 50)[0]
    raw = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        if is64:
            name, typ, flags, addr, offset, size = struct.unpack_from(endian + "IIQQQQ", data, off)
        else:
            name, typ, flags, addr, offset, size = struct.unpack_from(endian + "IIIIII", data, off)
        raw.append((name, typ, addr, offset, size))
    strtab = data[raw[e_shstrndx][3]: raw[e_shstrndx][3] + raw[e_shstrndx][4]]
    out = {}
    for name, typ, addr, offset, size in raw:
        end = strtab.find(b"\x00", name)
        out[strtab[name:end].decode(errors="replace")] = (addr, offset, size)
    return data, out


# COP1 access / compare / branch instructions. Note: movn/movz/madd(integer) are NOT FP.
FP_MNEMONICS_PREFIX = ("lwc1", "swc1", "ldc1", "sdc1", "mtc1", "mfc1", "ctc1", "cfc1", "bc1")


def is_fp(insn):
    m = insn.mnemonic.lower()
    if "." in m:          # add.s / mul.d / cvt.w.s / cmp.le.s ...
        return True
    return m.startswith(FP_MNEMONICS_PREFIX)


def scan(path):
    data, secs = sections(path)
    if ".text" not in secs:
        print("%s: no .text section" % path)
        return
    addr, off, size = secs[".text"]
    code = data[off:off + size]
    mode = capstone.CS_MODE_MIPS64 if data[4] == 2 else capstone.CS_MODE_MIPS32
    mode += capstone.CS_MODE_LITTLE_ENDIAN if data[5] == 1 else capstone.CS_MODE_BIG_ENDIAN
    md = capstone.Cs(capstone.CS_ARCH_MIPS, mode)
    md.detail = False
    total = fp = 0
    samples = []
    for insn in md.disasm(code, addr):
        total += 1
        if is_fp(insn):
            fp += 1
            if len(samples) < 5:
                samples.append("%x: %s %s" % (insn.address, insn.mnemonic, insn.op_str))
    pct = (100.0 * fp / total) if total else 0.0
    print("%-46s .text=%d bytes  decoded=%d insns  COP1/FP=%d (%.4f%%)" % (path, size, total, fp, pct))
    for s in samples:
        print("      e.g. %s" % s)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    for p in sys.argv[1:]:
        scan(p)