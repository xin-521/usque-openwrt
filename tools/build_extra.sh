#!/bin/sh
# =============================================================================
#  build_extra.sh —— 复现本指南附带的「官方未提供」构建目标
#
#  官方 release(v4.2.1) 提供:
#      android_arm64 / darwin_{amd64,arm64}
#      linux_{amd64,arm64,armv5,armv6,armv7,mips,mipsle,mips64,mips64le}
#      windows_{386,amd64,arm64}
#  本脚本补齐:
#      linux/386、linux/riscv64、linux/loong64（官方完全没有）
#      MIPS32 softfloat 变体（官方是 hardfloat，无 FPU 的 24Kc/74Kc 会 SIGILL）
#
#  用法： sh tools/build_extra.sh              # 全部构建
#         sh tools/build_extra.sh mipsle-softfloat   # 只构建一个
#
#  依赖： Go >= 1.26.3；能访问 goproxy.cn（本机已配置）
#  产物： dist/bin/usque-linux-<name>，版本戳形如 4.2.1-<name>
# =============================================================================
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
cd "$ROOT"

SRC="${SRC:-./usque-src}"
OUT="${OUT:-./dist/bin}"
TAG="v4.2.1"
COMMIT="6aa03fc97d12848dce34eedbd187fb1077b5d1ea"
DATE="2026-10-21"

case "$SRC" in /*) ;; *) SRC="$ROOT/$SRC" ;; esac
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac

export CGO_ENABLED=0

if [ ! -d "$SRC" ]; then
    echo "克隆源码 ..."
    git clone --depth 1 https://github.com/Diniboy1123/usque.git "$SRC"
fi
mkdir -p "$OUT"

build() { # <name> <goarch> <extra env...>
    name="$1"; arch="$2"; shift 2
    echo "==> usque-linux-$name  (GOARCH=$arch $*)"
    ( cd "$SRC" && env GOOS=linux GOARCH="$arch" "$@" \
        go build -trimpath \
        -ldflags "-s -w \
-X github.com/Diniboy1123/usque/cmd.version=$TAG-$name \
-X github.com/Diniboy1123/usque/cmd.commit=$COMMIT \
-X github.com/Diniboy1123/usque/cmd.date=$DATE" \
        -o "$OUT/usque-linux-$name" . )
    ls -l "$OUT/usque-linux-$name"
}

want="${1:-all}"
[ "$want" = all ] || [ "$want" = mipsle-softfloat ] && build mipsle-softfloat mipsle GOMIPS=softfloat
[ "$want" = all ] || [ "$want" = mips-softfloat ]  && build mips-softfloat  mips   GOMIPS=softfloat
[ "$want" = all ] || [ "$want" = riscv64 ]         && build riscv64         riscv64 GORISCV64=rva20u64
[ "$want" = all ] || [ "$want" = loong64 ]         && build loong64         loong64
[ "$want" = all ] || [ "$want" = 386 ]             && build 386             386

echo
echo "完成。校验（Go 构建信息 + ELF 头）："
echo "  python tools/check_binaries.py"
echo "  python tools/scan_fpu.py $OUT/usque-linux-mipsle $OUT/usque-linux-mipsle-softfloat"