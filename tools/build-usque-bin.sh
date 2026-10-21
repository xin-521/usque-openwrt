#!/bin/sh
# ???? usque ? dist/bin/usque-linux-<goarch> ??? ELF?
# ??? VERSION=v4.2.1 sh tools/build-usque-bin.sh arm64|amd64|mipsle
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
GOARCH_IN=${1:?usage: build-usque-bin.sh <arm64|amd64|mipsle>}
OUT="$ROOT/dist/bin/usque-linux-$GOARCH_IN"
mkdir -p "$ROOT/dist/bin"

export CGO_ENABLED=0 GOOS=linux GOARCH=$GOARCH_IN
MACHINE=""
case "$GOARCH_IN" in
    arm64)  GOARM64=v8.0; MACHINE=183 ;;
    amd64)  MACHINE=62 ;;
    mipsle) GOMIPS=softfloat; MACHINE=8 ;;
    *) echo "unsupported goarch: $GOARCH_IN" >&2; exit 1 ;;
esac
export GOARM64 GOMIPS

VERSION=${VERSION:-dev}
COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
DATE=$(date +%F)

cd "$ROOT/usque-src"
go build -trimpath -buildmode=exe \
    -ldflags "-s -w -buildid= -X github.com/Diniboy1123/usque/cmd.version=$VERSION -X github.com/Diniboy1123/usque/cmd.commit=$COMMIT -X github.com/Diniboy1123/usque/cmd.date=$DATE" \
    -o "$OUT" .

python3 - "$OUT" "$MACHINE" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read()
want = int(sys.argv[2])
assert d[:4] == b"\x7fELF", "not ELF"
e_type, e_machine = struct.unpack_from("<HH", d, 16)
phoff, = struct.unpack_from("<Q", d, 32)
phentsize, phnum = struct.unpack_from("<HH", d, 54)
interp = any(struct.unpack_from("<I", d, phoff + i * phentsize)[0] == 3 for i in range(phnum))
assert e_type == 2, "still PIE"
assert not interp, "has PT_INTERP (not static)"
assert e_machine == want, "wrong e_machine %d" % e_machine
print("ELF OK machine=%d size=%d" % (e_machine, len(d)))
PY
