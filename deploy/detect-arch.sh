#!/bin/sh
# =============================================================================
#  detect-arch.sh —— 在 OpenWrt 路由器上运行，输出：环境自检 + 该用哪个 usque 二进制
#
#  用法：  sh detect-arch.sh
#          sh detect-arch.sh /path/to/dist          # 顺便列出可用的二进制文件
# =============================================================================

DIST="${1:-}"

echo "===== 1. 系统信息 ====="
[ -f /etc/openwrt_release ] && cat /etc/openwrt_release
echo "uname -m : $(uname -m)"
echo "内核     : $(uname -r)"
echo "包管理器 : $(command -v apk >/dev/null 2>&1 && echo apk || echo opkg)"

ARCH=$( ( . /etc/openwrt_release 2>/dev/null; echo "$DISTRIB_ARCH" ) )
[ -n "$ARCH" ] || ARCH=$(uname -m)
echo "DISTRIB_ARCH = $ARCH"

echo
echo "===== 2. 依赖自检 ====="
if [ -e /dev/net/tun ] || lsmod 2>/dev/null | grep -q '^tun'; then
    echo "TUN 设备   : 可用 (/dev/net/tun 或 tun.ko 已加载)"
else
    echo "TUN 设备   : 不可用 —— 需要安装 kmod-tun"
    command -v apk >/dev/null 2>&1 && echo "             apk update && apk add kmod-tun" \
                                    || echo "             opkg update && opkg install kmod-tun"
fi

if ip -V 2>&1 | grep -qi busybox; then
    echo "ip 命令    : busybox 内置（够用；若遇奇怪报错可装 ip-full）"
else
    echo "ip 命令    : $(ip -V 2>&1 | head -1)"
fi

echo "根分区可用 : $(df -h / | awk 'NR==2{print $4" 可用 / "$2" 共"}')   (usque 二进制约 12-14MB)"
echo "内存       : $(free -m 2>/dev/null | awk '/Mem:/{print $2" MB 总 / "$7" MB 可用"}')"
echo "当前出口   : $(ip route get 1.1.1.1 2>/dev/null | head -1)"
echo "默认路由   :"
ip route show default 2>/dev/null | sed 's/^/             /'
ip -6 route show default 2>/dev/null | sed 's/^/             [v6] /'

echo
echo "===== 3. 该用哪个二进制 ====="
case "$ARCH" in
    x86_64|amd64)                    BIN=amd64;        NOTE="官方 release" ;;
    x86|i386|i486|i586|i686|geode*|pentium*) BIN=386;  NOTE="本指南附带构建（官方无 linux/386）" ;;
    aarch64*)                        BIN=arm64;        NOTE="官方 release" ;;
    arm_cortex-a5*|arm_cortex-a7*|arm_cortex-a8*|arm_cortex-a9*|arm_cortex-a15*) BIN=armv7; NOTE="官方 release" ;;
    arm_arm1176*|arm_1176*)          BIN=armv6;        NOTE="官方 release" ;;
    arm_arm926*|arm_fa526|arm_xscale|arm_mpcore) BIN=armv5; NOTE="官方 release" ;;
    mipsel_24kc_24kf)                BIN=mipsle;       NOTE="官方 release（24Kf 有 FPU）" ;;
    mipsel*|mips_mips32)             BIN=mipsle-softfloat; NOTE="★ 建议 softfloat（24Kc/74Kc 无 FPU）" ;;
    mips_24kc|mips_4kc*|mips_34kc*)  BIN=mips-softfloat;   NOTE="★ 建议 softfloat（无 FPU）" ;;
    mips*el*)                        BIN=mipsle-softfloat; NOTE="★ 建议 softfloat" ;;
    mips64el*|mips64*el*)            BIN=mips64le;     NOTE="官方 release" ;;
    mips64*)                         BIN=mips64;       NOTE="官方 release" ;;
    riscv64*)                        BIN=riscv64;      NOTE="本指南附带构建（官方无 riscv64）" ;;
    loongarch64*)                    BIN=loong64;      NOTE="本指南附带构建（官方无 loong64）" ;;
    *)                               BIN="未知";       NOTE="请按下面前缀规则人工判断" ;;
esac

echo "架构 $ARCH  =>  usque-linux-$BIN   ($NOTE)"
case "$BIN" in
    未知)
        cat <<'EOF'
前缀规则： x86_64→amd64 | aarch64*→arm64 | arm_cortex-*→armv7 | arm_arm1176*→armv6
           arm_arm926*/fa526/xscale→armv5 | mipsel*→mipsle | mips_24kc→mips
           mips64*→mips64 | mips64el*→mips64le | riscv64*→riscv64 | loongarch64*→loong64
无 FPU 的 MIPS32（24Kc/74Kc/34Kc）请用 softfloat 版本，否则可能 SIGILL。
EOF
        ;;
esac

if [ -n "$DIST" ] && [ -d "$DIST" ]; then
    echo
    echo "===== 4. $DIST 下可用文件 ====="
    ls -l "$DIST" | sed 's/^/  /'
fi

cat <<'EOF'

下一步（详见《行动指南》）：
  1) 把选中的二进制 scp 到路由器：/usr/bin/usque  并 chmod +x
  2) 注册： usque -c /etc/usque/config.json register -n my-router -a
  3) 手动验证： usque -c /etc/usque/config.json nativetun
  4) 接管路由 + 开机自启：安装 /etc/init.d/usque 与 /etc/usque/{up,down}.sh
EOF
