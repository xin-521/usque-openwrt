#!/bin/sh
# =============================================================================
#  build_arm64_v8.sh —— OpenWrt 25.12 aarch64 专用构建（只产出 ARMv8.0 一份）
#
#  为什么只锁定 v8.0：
#    OpenWrt 的 aarch64 子目标覆盖 Cortex-A53/A72（ARMv8.0，无 LSE 原子指令）
#    与 Cortex-A76（ARMv8.2，有 LSE）。GOARM64=v8.1 及以上会把 LSE 指令直接编进
#    代码，在 A53/A72 上必然 SIGILL；v8.0 是能跑遍所有 arm64 路由器的唯一基线。
#    （Go 运行时仍会在支持的 CPU 上动态启用 LSE/CRC 等特性，不需要编译期抬高基线。）
#
#  性能相关构建选项：
#    -buildmode=exe   显式非 PIE（无重定位开销；Go 1.27 默认已是 exe，这里钉死）
#    -trimpath        去掉本机绝对路径（可复现、体积略小）
#    -s -w -buildid=  去符号表/调试信息/DWARF 与 build id（体积最小，页入更快）
#    CGO_ENABLED=0    纯静态，musl/glibc 通吃，无 libc 调用开销
#    -pgo=auto        仅当 usque-src/default.pgo 存在时启用（见文末说明）
#
#  用法： sh tools/build_arm64_v8.sh
#         PGO=1 sh tools/build_arm64_v8.sh   # 有 default.pgo 时启用 PGO
#  产物： dist/bin/usque-linux-arm64     （与 install-on-router.sh 的自动选包名一致）
# =============================================================================
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
cd "$ROOT"

SRC="${SRC:-./usque-src}"
OUT="${OUT:-./dist/bin}"
case "$SRC" in /*) ;; *) SRC="$ROOT/$SRC" ;; esac
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac
NAME="usque-linux-arm64"
TAG="v4.2.1"
DATE="$(date +%F)"

[ -d "$SRC" ] || { echo "找不到源码目录 $SRC"; exit 1; }
mkdir -p "$OUT"

export CGO_ENABLED=0
export GOOS=linux
export GOARCH=arm64
export GOARM64=v8.0

COMMIT="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
VERSION="${TAG}-arm64-v8.0"

PGOFLAG=""
if [ -n "${PGO:-}" ]; then
    [ -f "$SRC/default.pgo" ] || { echo "PGO=1 但 $SRC/default.pgo 不存在"; exit 1; }
    PGOFLAG="-pgo=auto"
fi

echo "==> $NAME  (go $(go env GOVERSION | sed 's/^go//'), GOARM64=v8.0, PIE=off, PGO=${PGOFLAG:-off})"
( cd "$SRC" && go build -trimpath -buildmode=exe $PGOFLAG \
    -ldflags "-s -w -buildid= \
-X github.com/Diniboy1123/usque/cmd.version=$VERSION \
-X github.com/Diniboy1123/usque/cmd.commit=$COMMIT \
-X github.com/Diniboy1123/usque/cmd.date=$DATE" \
    -o "$OUT/$NAME" . )

BIN="$OUT/$NAME"

# ---- 硬性校验：架构/基线错一个都不许出厂 -----------------------------------
INFO="$(go version -m "$BIN")"
echo "$INFO" | grep -q 'GOARCH=arm64'    || { echo "!! GOARCH 不是 arm64"; exit 1; }
echo "$INFO" | grep -q 'GOARM64=v8.0'    || { echo "!! GOARM64 不是 v8.0"; exit 1; }
echo "$INFO" | grep -q 'CGO_ENABLED=0'   || { echo "!! 不是纯静态构建"; exit 1; }

# ELF: e_machine=183(aarch64), e_type=2(EXEC, 非 PIE), 且无 PT_INTERP
if command -v python >/dev/null 2>&1; then
    python - "$BIN" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read()
assert d[:4] == b"\x7fELF", "not ELF"
e_type, e_machine = struct.unpack_from("<HH", d, 16)
phoff, = struct.unpack_from("<Q", d, 32)
phentsize, phnum = struct.unpack_from("<HH", d, 54)
interp = any(struct.unpack_from("<I", d, phoff + i * phentsize)[0] == 3 for i in range(phnum))
print("ELF: machine=%d(%s) type=%d(%s) interp=%s"
      % (e_machine, "aarch64" if e_machine == 183 else "?",
         e_type, "EXEC" if e_type == 2 else "DYN/PIE" if e_type == 3 else "?",
         "yes" if interp else "no"))
assert e_machine == 183, "e_machine != aarch64"
assert e_type == 2, "still PIE"
assert not interp, "has PT_INTERP (not static)"
PY
fi

SIZE=$(wc -c < "$BIN" | tr -d ' ')
if command -v sha256sum >/dev/null 2>&1; then SUM=$(sha256sum "$BIN" | cut -d' ' -f1)
else SUM=$(shasum -a 256 "$BIN" | cut -d' ' -f1); fi

echo "==> OK  $BIN  ${SIZE} bytes  sha256=${SUM}"
echo "$INFO" | grep -E 'GOARM64|CGO_ENABLED|vcs.revision' | sed 's/^/    /'
echo
echo "下一步： sh tools/make-bundle.sh arm64"
echo "说明：  PGO 需要真实流量画像（default.pgo）。没有就保持默认，别用假画像。"
