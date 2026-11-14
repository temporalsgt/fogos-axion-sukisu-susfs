#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  check-module-crcs.sh <Module.symvers> <stock-modules-dir>
  check-module-crcs.sh --stock-manifest <stock-crcs.txt> <Module.symvers>
  check-module-crcs.sh --write-symvers <modules-dir>
  check-module-crcs.sh --write-stock-manifest <modules-dir>...

Compares kernel symbol CRCs against stock vendor modules. A mismatch means the
kernel ABI differs and a stock module would be rejected with
"disagrees about version of symbol".
EOF
  exit 2
}

MODE=
SYMVERS=/dev/null
MODULES=
MANIFEST=
case "${1:-}" in
  --stock-manifest)
    [ "$#" -eq 3 ] || usage
    MODE=check-manifest
    MANIFEST=$2
    SYMVERS=$3
    ;;
  --write-symvers)
    [ "$#" -eq 2 ] || usage
    MODE=dump-symvers
    MODULES=$2
    ;;
  --write-stock-manifest)
    [ "$#" -ge 2 ] || usage
    MODE=dump-manifest
    shift
    MODULES="$*"
    ;;
  *)
    [ "$#" -eq 2 ] || usage
    MODE=check
    SYMVERS=$1
    MODULES=$2
    ;;
esac

if [ "$MODE" = check ]; then
  test -d "$MODULES" || { echo "check-module-crcs: no module dir: $MODULES" >&2; exit 1; }
  test -s "$SYMVERS" || { echo "check-module-crcs: no Module.symvers: $SYMVERS" >&2; exit 1; }
fi
if [ "$MODE" = check-manifest ]; then
  test -s "$SYMVERS" || { echo "check-module-crcs: no Module.symvers: $SYMVERS" >&2; exit 1; }
  test -s "$MANIFEST" || { echo "check-module-crcs: no manifest: $MANIFEST" >&2; exit 1; }
fi

python3 - "$MODE" "$SYMVERS" "$MODULES" "$MANIFEST" <<'PY'
import glob
import os
import struct
import sys

mode, symvers_path, modules_arg, manifest_path = sys.argv[1:5]

def elf_sections(path):
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        raise SystemExit(f"{path}: not a little-endian ELF64 file")
    e_shoff = struct.unpack_from("<Q", data, 0x28)[0]
    e_shentsize = struct.unpack_from("<H", data, 0x3A)[0]
    e_shnum = struct.unpack_from("<H", data, 0x3C)[0]
    e_shstrndx = struct.unpack_from("<H", data, 0x3E)[0]
    headers = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        headers.append(struct.unpack_from("<IIQQQQIIQQ", data, off))
    shstr = headers[e_shstrndx]
    names = data[shstr[4]:shstr[4] + shstr[5]]
    out = {}
    for h in headers:
        end = names.find(b"\0", h[0])
        out[names[h[0]:end].decode()] = {"type": h[1], "offset": h[4], "size": h[5]}
    return data, out

def module_crcs(path):
    data, sections = elf_sections(path)
    if "__versions" not in sections:
        return {}
    sec = sections["__versions"]
    raw = data[sec["offset"]:sec["offset"] + sec["size"]]
    if len(raw) % 64:
        raise SystemExit(f"{path}: __versions size {len(raw)} is not a multiple of 64")
    crcs = {}
    for i in range(0, len(raw), 64):
        crc = struct.unpack_from("<Q", raw, i)[0]
        name = raw[i + 8:i + 64].split(b"\0", 1)[0].decode()
        crcs[name] = crc
    return crcs

def module_symtab(path):
    data, sections = elf_sections(path)
    if ".symtab" not in sections:
        return []
    sec = sections[".symtab"]
    raw = data[sec["offset"]:sec["offset"] + sec["size"]]
    strtab = sections.get(".strtab")
    if strtab is None:
        return []
    strings = data[strtab["offset"]:strtab["offset"] + strtab["size"]]
    syms = []
    for i in range(0, len(raw), 24):
        st_name, st_info, _st_other, st_shndx = struct.unpack_from("<IBBH", raw, i)
        if st_shndx == 0:
            continue
        if (st_info >> 4) not in (1, 2):
            continue
        end = strings.find(b"\0", st_name)
        syms.append(strings[st_name:end].decode())
    return syms

def read_symvers(path):
    crcs = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 2:
            continue
        try:
            crc = int(parts[0], 16)
        except ValueError:
            continue
        crcs[parts[1]] = crc
    return crcs

def read_manifest(path):
    crcs = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            parts = line.split()
        if len(parts) < 2:
            continue
        crcs[parts[1]] = int(parts[0], 16)
    return crcs

def load_modules(spec):
    files = []
    for p in spec.split():
        if os.path.isdir(p):
            files.extend(sorted(glob.glob(os.path.join(p, "*.ko"))))
        elif p:
            files.append(p)
    if not files:
        raise SystemExit(f"check-module-crcs: no .ko files in {spec}")
    return files

if mode == "check-manifest":
    built = read_symvers(symvers_path)
    stock = read_manifest(manifest_path)
    mismatches = [(s, c, built[s]) for s, c in stock.items() if s in built and built[s] != c]
    missing = [s for s in stock if s not in built]
    for sym, want, got in mismatches[:30]:
        print(f"check-module-crcs: CRC mismatch for {sym}: stock 0x{want:08x}, built 0x{got:08x}", file=sys.stderr)
    for sym in missing[:30]:
        print(f"check-module-crcs: symbol not exported by built kernel: {sym}", file=sys.stderr)
    if len(mismatches) > 30 or len(missing) > 30:
        print(f"check-module-crcs: ... {len(mismatches)} mismatches, {len(missing)} missing total", file=sys.stderr)
    if mismatches or missing:
        raise SystemExit(1)
    if len(stock) < 100:
        raise SystemExit(f"check-module-crcs: only {len(stock)} symbols in manifest, refusing a vacuous pass")
    print(f"check-module-crcs: OK ({len(stock)} stock kernel CRCs match)")
    raise SystemExit(0)

if mode == "check":
    modules = load_modules(modules_arg)
    built = read_symvers(symvers_path)
    per_module = {os.path.basename(m): module_crcs(m) for m in modules}
    stock_exports = set()
    for m in modules:
        stock_exports.update(module_symtab(m))
    checked = 0
    mismatches = []
    missing = []
    for name, crcs in per_module.items():
        for sym, crc in crcs.items():
            if sym not in built:
                # Exported by another stock module is fine: we do not rebuild
                # vendor modules, so their mutual exports never appear in our
                # kernel-only Module.symvers.
                if sym not in stock_exports:
                    missing.append((name, sym))
                continue
            checked += 1
            if built[sym] != crc:
                mismatches.append((name, sym, crc, built[sym]))
    for name, sym, want, got in mismatches:
        print(f"check-module-crcs: {name}: CRC mismatch for {sym}: stock 0x{want:08x}, built 0x{got:08x}", file=sys.stderr)
    for name, sym in missing[:20]:
        print(f"check-module-crcs: {name}: symbol not exported by built kernel: {sym}", file=sys.stderr)
    if len(missing) > 20:
        print(f"check-module-crcs: ... and {len(missing) - 20} more missing symbols", file=sys.stderr)
    if mismatches or missing:
        raise SystemExit(1)
    if checked < 10:
        raise SystemExit(f"check-module-crcs: only {checked} CRCs compared, refusing a vacuous pass")
    print(f"check-module-crcs: OK ({checked} symbol CRCs match across {len(modules)} stock modules)")
    raise SystemExit(0)

if mode == "dump-symvers":
    modules = load_modules(modules_arg)
    seen = {}
    conflicts = []
    for m in modules:
        for sym, crc in module_crcs(m).items():
            if sym in seen and seen[sym] != crc:
                conflicts.append((sym, seen[sym], crc, os.path.basename(m)))
            seen.setdefault(sym, crc)
    if conflicts:
        for sym, a, b, name in conflicts:
            print(f"check-module-crcs: CRC conflict for {sym}: 0x{a:08x} vs 0x{b:08x} ({name})", file=sys.stderr)
        raise SystemExit(1)
    for sym in sorted(seen):
        print(f"0x{seen[sym]:08x}\t{sym}\tvmlinux\tEXPORT_SYMBOL")
    raise SystemExit(0)

if mode == "dump-manifest":
    modules = load_modules(modules_arg)
    per_module = {os.path.basename(m): module_crcs(m) for m in modules}
    stock_exports = set()
    for m in modules:
        stock_exports.update(module_symtab(m))
    kernel_crcs = {}
    conflicts = []
    for name, crcs in per_module.items():
        for sym, crc in crcs.items():
            if sym in stock_exports:
                continue
            if sym in kernel_crcs and kernel_crcs[sym] != crc:
                conflicts.append((sym, kernel_crcs[sym], crc, name))
            kernel_crcs.setdefault(sym, crc)
    if conflicts:
        for sym, a, b, name in conflicts:
            print(f"check-module-crcs: CRC conflict for {sym}: 0x{a:08x} vs 0x{b:08x} ({name})", file=sys.stderr)
        raise SystemExit(1)
    print("# Stock kernel symbol CRCs extracted from LineageOS vendor modules.")
    print("# Regenerate only when the LineageOS build changes.")
    for sym in sorted(kernel_crcs):
        print(f"0x{kernel_crcs[sym]:08x}\t{sym}")
    raise SystemExit(0)

raise SystemExit("check-module-crcs: bad mode")
PY
