#!/bin/sh
# =============================================================================
#  install-on-router.sh —— 在 OpenWrt 路由器上「一条命令」完成部署（可回滚）
#
#  在路由器上执行（需要 root）：
#      tar xzf usque-deploy-<arch>.tar.gz -C /root
#      cd /root/usque-deploy && sh install-on-router.sh --dry-run   # 先看要改什么
#      cd /root/usque-deploy && sh install-on-router.sh            # 正式安装
#
#  选项：
#      --binary PATH   指定 usque 二进制（默认在 ./dist/bin 里按架构自动挑）
#      --strict        严格模式：WAN 不再提供直连兜底（wan.defaultroute=0）
#      --fallback      后备模式（默认）：WAN 保留高 metric 兜底路由
#      --no-firewall   不改防火墙
#      --no-dns        不改 DNS
#      --dry-run       只打印将执行的命令
#      --rollback      撤销本脚本的所有改动
#      -h|--help
#
#  本脚本只做「安装 + 配置」，不会自动启用服务：
#      装完还要 register → 手动验证 → /etc/init.d/usque enable && start
# =============================================================================

set -u

IFACE=warp0
PROG=/usr/bin/usque
DIR=/etc/usque
INIT=/etc/init.d/usque
SYSCTL=/etc/sysctl.d/90-usque.conf
KEEP=/root/usque-config.json.bak
WAN_METRIC=250
DNS_SERVER=1.1.1.1

DRY=0; STRICT=0; DO_FW=1; DO_DNS=1; ROLLBACK=0; BINARY=""
HERE=$(cd "$(dirname "$0")" && pwd)
# 兼容两种布局：
#   A) 仓库：deploy/install-on-router.sh + ../usque/root（唯一源）
#   B) 发布包：install-on-router.sh + deploy/（make-bundle.sh 从 usque/root 生成）
if [ -d "$HERE/dist" ] || [ ! -d "$HERE/../dist" ]; then
    ROOT=$HERE
else
    ROOT=$(cd "$HERE/.." && pwd)
fi
if [ -d "$ROOT/usque/root" ]; then
    SRC="$ROOT/usque/root"
    UP_SRC="$SRC/etc/usque/up.sh"
    DOWN_SRC="$SRC/etc/usque/down.sh"
    OPTS_SRC="$SRC/etc/usque/options.sh"
    INIT_SRC="$SRC/etc/init.d/usque"
    SYSCTL_SRC="$SRC/etc/sysctl.d/90-usque.conf"
elif [ -d "$ROOT/deploy" ] && [ -f "$ROOT/deploy/up.sh" ]; then
    SRC="$ROOT/deploy"
    UP_SRC="$SRC/up.sh"
    DOWN_SRC="$SRC/down.sh"
    OPTS_SRC="$SRC/options.sh"
    INIT_SRC="$SRC/usque.init"
    SYSCTL_SRC="$SRC/90-usque.conf"
else
    echo "找不到 usque/root 或 deploy/ 中的钩子文件" >&2
    exit 1
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --binary) BINARY="$2"; shift 2 ;;
        --strict) STRICT=1; shift ;;
        --fallback) STRICT=0; shift ;;
        --no-firewall) DO_FW=0; shift ;;
        --no-dns) DO_DNS=0; shift ;;
        --dry-run) DRY=1; shift ;;
        --rollback) ROLLBACK=1; shift ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "未知选项: $1"; exit 1 ;;
    esac
done

RUN() {
    if [ "$DRY" = 1 ]; then
        echo "  [dry-run] $*"
    else
        echo "  + $*"
        "$@" || { echo "  !! 命令失败: $*"; return 1; }
    fi
}

# uci -q delete 在「键本来就不存在」时返回非 0（-q 只压报错文本，不改返回码），
# 这不是错误。统一走 UCI_DEL：先看有没有，没有就跳过。
UCI_DEL() {
    for k in "$@"; do
        if [ "$DRY" = 1 ]; then
            echo "  [dry-run] uci -q delete $k"
            continue
        fi
        if uci -q get "$k" >/dev/null 2>&1; then
            echo "  + uci -q delete $k"
            uci -q delete "$k" || { echo "  !! 命令失败: uci -q delete $k"; return 1; }
        else
            echo "  - $k 不存在，跳过"
        fi
    done
    return 0
}

say()  { echo; echo "==== $* ===="; }
warn() { echo "  [!] $*"; }

[ "$(id -u)" = 0 ] || { echo "请用 root 运行"; exit 1; }
command -v uci >/dev/null || { echo "找不到 uci，确认这是 OpenWrt"; exit 1; }

# ---- 判断架构 → 选二进制 ----------------------------------------------------
ARCH=$( ( . /etc/openwrt_release 2>/dev/null; echo "${DISTRIB_ARCH:-}" ) )
[ -n "$ARCH" ] || ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)            A=amd64 ;;
    x86|i386|i486|i586|i686|geode*|pentium*) A=386 ;;
    aarch64*)                A=arm64 ;;
    arm_cortex-a5*|arm_cortex-a7*|arm_cortex-a8*|arm_cortex-a9*|arm_cortex-a15*) A=armv7 ;;
    arm_arm1176*|arm_1176*)  A=armv6 ;;
    arm_arm926*|arm_fa526|arm_xscale|arm_mpcore) A=armv5 ;;
    mipsel_24kc_24kf)        A=mipsle ;;
    mipsel*)                 A=mipsle-softfloat ;;
    mips_24kc|mips_4kc*|mips_34kc*) A=mips-softfloat ;;
    mips64el*)               A=mips64le ;;
    mips64*)                 A=mips64 ;;
    mips*el*)                A=mipsle-softfloat ;;
    riscv64*)                A=riscv64 ;;
    loongarch64*)            A=loong64 ;;
    *)                       A="" ;;
esac
[ -n "$BINARY" ] || [ -z "$A" ] || BINARY="$ROOT/dist/bin/usque-linux-$A"

# ---- 回滚 -------------------------------------------------------------------
if [ "$ROLLBACK" = 1 ]; then
    say "回滚：停止并删除服务与文件"
    if [ -x "$INIT" ]; then
        RUN "$INIT" stop
        RUN "$INIT" disable
    else
        echo "  - 未安装 $INIT，跳过停止/禁用"
    fi
    if [ -f "$DIR/config.json" ]; then
        RUN cp "$DIR/config.json" "$KEEP"
        warn "注册信息已备份到 $KEEP（重装后拷回 $DIR/config.json 即可）"
    fi
    RUN rm -f "$PROG" "$INIT" "$SYSCTL"
    RUN rm -rf "$DIR"
    say "回滚：恢复 UCI 配置"
    UCI_DEL firewall.warp
    UCI_DEL firewall.lan_warp
    UCI_DEL network.warp
    UCI_DEL dhcp.warp_dns
    UCI_DEL network.wan.metric
    UCI_DEL network.wan.defaultroute
    RUN uci -q set network.wan.peerdns=1
    UCI_DEL network.wan.dns
    RUN uci commit
    say "回滚：重载网络与防火墙"
    RUN /etc/init.d/network reload
    RUN /etc/init.d/firewall reload
    echo
    echo "已回滚。注意：/etc/config/network 原先若有自定义 metric/peerdns，请自行核对。"
    exit 0
fi
# ---- 0. 环境自检 ------------------------------------------------------------
say "0. 环境自检"
echo "  架构: $ARCH  →  二进制: ${BINARY:-<未识别，请用 --binary 指定>}"
command -v apk >/dev/null 2>&1 && PM="apk" || PM="opkg"
echo "  包管理器: $PM"

if [ -e /dev/net/tun ] || lsmod 2>/dev/null | grep -q '^tun'; then
    echo "  TUN: 可用"
else
    warn "TUN 不可用，需要安装 kmod-tun"
    if [ "$PM" = apk ]; then RUN apk add kmod-tun; else RUN opkg update; RUN opkg install kmod-tun; fi
fi

[ -f "$BINARY" ] || { echo "  !! 找不到二进制 $BINARY（用 --binary 指定）"; exit 1; }
SIZE=$(ls -l "$BINARY" | awk '{print $5}')
FREE=$(df -k / | awk 'NR==2{print $4*1024}')
echo "  二进制: $((SIZE/1048576)) MB，根分区可用: $((FREE/1048576)) MB"
[ "$FREE" -gt $((SIZE + 2097152)) ] || warn "根分区剩余空间偏紧，建议腾空间或用 extroot/U 盘"

# ---- 1. 安装文件 -----------------------------------------------------------
say "1. 安装文件"
RUN mkdir -p "$DIR"
RUN cp "$BINARY" "$PROG"
RUN chmod 755 "$PROG"
for pair in "up.sh:$UP_SRC" "down.sh:$DOWN_SRC"; do
    f=${pair%%:*}; src=${pair#*:}
    [ -f "$src" ] || { echo "  !! 缺少 $f（$src）"; exit 1; }
    RUN cp "$src" "$DIR/$f"
    RUN chmod 755 "$DIR/$f"
done
[ -f "$OPTS_SRC" ] || { echo "  !! 缺少 options.sh（$OPTS_SRC）"; exit 1; }
RUN cp "$OPTS_SRC" "$DIR/options.sh"
RUN chmod 644 "$DIR/options.sh"
[ -f "$INIT_SRC" ] || { echo "  !! 缺少 init（$INIT_SRC）"; exit 1; }
RUN cp "$INIT_SRC" "$INIT"
RUN chmod 755 "$INIT"
[ -f "$SYSCTL_SRC" ] || { echo "  !! 缺少 sysctl（$SYSCTL_SRC）"; exit 1; }
RUN cp "$SYSCTL_SRC" "$SYSCTL"
[ -f "$DIR/config.json" ] || warn "还没有 $DIR/config.json —— 下一步必须先注册（见指南步骤 2）"

# ---- 2. 网络配置（默认路由优先级）------------------------------------------
say "2. 网络配置（默认路由优先级）"
if [ "$STRICT" = 1 ]; then
    echo "  严格模式：WAN 不再产生默认路由（断线不回退直连）"
    RUN uci set network.wan.defaultroute=0
    if uci -q get network.wan6 >/dev/null 2>&1; then RUN uci set network.wan6.defaultroute=0; fi
else
    echo "  后备模式：WAN 默认路由 metric=$WAN_METRIC（隧道不可用时自动直连兜底）"
    RUN uci set network.wan.metric="$WAN_METRIC"
    UCI_DEL network.wan.defaultroute
fi

RUN uci set network.warp=interface
RUN uci set network.warp.proto=none
RUN uci set network.warp.device="$IFACE"
RUN uci set network.warp.defaultroute=0
RUN uci set network.warp.peerdns=0
RUN uci set network.warp.auto=1
RUN uci commit network

# ---- 3. 防火墙 -------------------------------------------------------------
say "3. 防火墙（warp zone + lan→warp 转发 + NAT）"
if [ "$DO_FW" = 1 ]; then
    RUN uci set firewall.warp=zone
    RUN uci set firewall.warp.name=warp
    RUN uci set firewall.warp.input=REJECT
    RUN uci set firewall.warp.output=ACCEPT
    RUN uci set firewall.warp.forward=REJECT
    RUN uci set firewall.warp.masq=1
    RUN uci set firewall.warp.masq6=1
    RUN uci set firewall.warp.mtu_fix=1
    UCI_DEL firewall.warp.network
    RUN uci add_list firewall.warp.network=warp
    if command -v fw4 >/dev/null 2>&1; then
        UCI_DEL firewall.warp.device
        RUN uci add_list firewall.warp.device="$IFACE"
    fi
    RUN uci set firewall.lan_warp=forwarding
    RUN uci set firewall.lan_warp.src=lan
    RUN uci set firewall.lan_warp.dest=warp
    RUN uci commit firewall
else
    echo "  跳过（--no-firewall）"
fi

# ---- 4. DNS ---------------------------------------------------------------
say "4. DNS（dnsmasq 上游走隧道，避免 DNS 泄漏）"
if [ "$DO_DNS" = 1 ]; then
    RUN uci set network.wan.peerdns=0
    UCI_DEL network.wan.dns
    RUN uci add_list network.wan.dns="$DNS_SERVER"
    RUN uci commit network
    RUN uci set dhcp.warp_dns=dnsmasq
    UCI_DEL dhcp.warp_dns.server
    RUN uci add_list dhcp.warp_dns.server="$DNS_SERVER"
    RUN uci set dhcp.warp_dns.strictorder=0
    RUN uci commit dhcp
else
    echo "  跳过（--no-dns）"
fi

# ---- 5. 生效 --------------------------------------------------------------
say "5. 生效"
RUN sysctl -p "$SYSCTL"
RUN /etc/init.d/network reload
RUN /etc/init.d/firewall reload

cat <<'NEXT_STEPS'

================= 安装完成（服务尚未启用）=================
还要做 3 件事：

1) 注册（若 /etc/usque/config.json 还不存在）
   usque -c /etc/usque/config.json register -n openwrt-router -a
   注册需要访问 api.cloudflareclient.com；也可在 PC 上注册后把 config.json 拷过来

2) 手动跑一次，确认隧道可用（不改路由）
   usque -c /etc/usque/config.json nativetun --interface-name warp0
   另开一个 ssh： ip link show warp0 ; ping -c2 -I warp0 1.1.1.1

3) 验证通过后，启用常驻
   /etc/init.d/usque enable && /etc/init.d/usque start
   logread -e usque            # 看钩子自检日志
   ip route show default       # 应看到 dev warp0 的默认路由优先

撤销全部改动： sh install-on-router.sh --rollback
NEXT_STEPS
