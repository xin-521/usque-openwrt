#!/bin/sh
# =============================================================================
#  make-bundle.sh —— 生成「传到路由器上就能装」的压缩包
#
#  用法（任意目录下均可）：
#      sh tools/make-bundle.sh mipsle-softfloat   # 或 arm64 / armv7 / amd64 ...
#      sh tools/make-bundle.sh                    # 不带参数则列出所有可选目标
#
#  产物： dist/usque-deploy-<arch>.tar.gz
#         传输后在路由器上： tar xzf usque-deploy-<arch>.tar.gz -C /root
#                           cd /root/usque-deploy
#                           sh install-on-router.sh --dry-run
# =============================================================================
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
cd "$ROOT"

if [ -z "${1:-}" ]; then
    echo "可选目标（dist/bin 下已有的二进制）："
    for f in dist/bin/usque-linux-*; do
        a=${f##*/usque-linux-}
        echo "  $a   →   sh tools/make-bundle.sh $a"
    done
    exit 0
fi

ARCH="$1"
BIN="dist/bin/usque-linux-$ARCH"
[ -f "$BIN" ] || { echo "找不到 $BIN"; exit 1; }

OUT="dist/usque-deploy-$ARCH.tar.gz"

# 打包布局（与文档一致）：
#   usque-deploy/
#     install-on-router.sh      ← 顶层，直接 sh install-on-router.sh
#     deploy/                   ← 钩子、init、sysctl（从 usque/root 复制）
#     dist/bin/usque-linux-<arch>
#     dist/MANIFEST.tsv
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT INT TERM HUP
cp -R deploy "$STAGE/deploy"
mv "$STAGE/deploy/install-on-router.sh" "$STAGE/install-on-router.sh"
chmod 755 "$STAGE/install-on-router.sh"
# 钩子/init/sysctl 的唯一源在 usque/root；发布包里平铺进 deploy/
cp usque/root/etc/usque/up.sh usque/root/etc/usque/down.sh \
   usque/root/etc/usque/options.sh "$STAGE/deploy/"
cp usque/root/etc/init.d/usque "$STAGE/deploy/usque.init"
cp usque/root/etc/sysctl.d/90-usque.conf "$STAGE/deploy/90-usque.conf"
mkdir -p "$STAGE/dist/bin"
cp "$BIN" "$STAGE/dist/bin/"
[ -f dist/MANIFEST.tsv ] && cp dist/MANIFEST.tsv "$STAGE/dist/"
tar czf "$OUT" -C "$STAGE" install-on-router.sh deploy dist
rm -rf "$STAGE"
trap - EXIT INT TERM HUP

echo "已生成 $ROOT/$OUT  ($(du -h "$OUT" | awk '{print $1}'))"
sha256sum "$OUT" 2>/dev/null || shasum -a 256 "$OUT"
echo
BASE=${OUT##*/}
echo "传到路由器："
echo "  scp $OUT root@192.168.1.1:/tmp/"
echo "  ssh root@192.168.1.1 'mkdir -p /root/usque-deploy && tar xzf /tmp/$BASE -C /root/usque-deploy && cd /root/usque-deploy && sh install-on-router.sh --dry-run'"
