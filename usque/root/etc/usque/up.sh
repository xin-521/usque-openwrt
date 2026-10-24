#!/bin/sh
# =============================================================================
#  /etc/usque/up.sh  ——  usque (nativetun 模式) 的 on-connect 钩子
#
#  usque 每次成功(重)连后都会以「无参数、无 shell 包装」的方式直接 exec 本脚本，
#  并通过环境变量提供上下文：
#      USQUE_EVENT=connect      USQUE_MODE=nativetun
#      USQUE_IFACE=warp0        USQUE_ENDPOINT=<ip>:<port> 或 [<ipv6>]:<port>
#      USQUE_IPV4=172.16.x.x    USQUE_IPV6=2606:4700:...
#
#  本脚本做两件事（顺序不能颠倒）：
#      1) 给 WARP 端点本身加一条走物理 WAN 的例外路由；
#         否则隧道自己的 QUIC 包会被下面的默认路由送进隧道 → 死循环黑洞。
#      2) 把默认路由指向隧道，metric 低于 WAN 的后备默认路由，
#         从而「只要隧道活着，全部流量都走 WARP」。
#
#  安全语义（重要）：
#      * 隧道活着但断了连接 → 包进隧道被丢弃（fail-closed，不泄漏到 ISP）；
#      * usque 进程退出/设备消失 → 隧道默认路由由内核自动删除，
#        WAN 的后备默认路由（metric 更高）立即接管 → 不会把路由器锁死。
#      因此「停止服务」就是应急自救手段：/etc/init.d/usque stop
#
#  幂等：重连会反复执行，全部使用 replace / del+add，可重复运行。
# =============================================================================

IFACE="${USQUE_IFACE:-warp0}"
ENDPOINT="${USQUE_ENDPOINT:-}"
TUN_METRIC="${USQUE_TUN_METRIC:-10}"
WAN_METRIC="${USQUE_WAN_METRIC:-250}"

log() { logger -t usque-hook "[connect] $*"; }

# 打印物理默认路由: "dev gw"（gw 可能为空）。$1=4|6   $2=要排除的接口
wan_default() {
    ip -"$1" route show default 2>/dev/null | awk -v t="$2" '
        {
            dev = ""; gw = ""
            for (i = 1; i <= NF; i++) {
                if ($i == "via") gw = $(i + 1)
                if ($i == "dev") dev = $(i + 1)
            }
            if (dev != "" && dev != t) { print dev " " gw; exit }
        }'
}

# 严格模式不会保留 WAN 默认路由。此时依赖 usque-routing 预装的端点
# host route，通过内核路由查询反推出 WAN 设备和网关。
wan_endpoint_route() {
    ip -"$1" route get "$2" 2>/dev/null | awk -v t="$3" '
        {
            dev = ""; gw = ""
            for (i = 1; i <= NF; i++) {
                if ($i == "via") gw = $(i + 1)
                if ($i == "dev") dev = $(i + 1)
            }
            if (dev != "" && dev != t) { print dev " " gw; exit }
        }'
}

# ---------------------------------------------------------------------------
# 0. 解析端点地址（去掉端口，识别 v4 / v6）
# ---------------------------------------------------------------------------
EPADDR=""; EPFAM=""
case "$ENDPOINT" in
    \[*\]:*) EPADDR=$(printf '%s' "$ENDPOINT" | sed 's/^\[//; s/\]:[0-9]*$//'); EPFAM=6 ;;
    *:[0-9]*) EPADDR=$(printf '%s' "$ENDPOINT" | sed 's/:[0-9]*$//');          EPFAM=4 ;;
esac

# ---------------------------------------------------------------------------
# 1. 端点例外路由
# ---------------------------------------------------------------------------
if [ -n "$EPADDR" ]; then
    set -- $(wan_default "$EPFAM" "$IFACE")
    WANDEV="$1"; WANGW="$2"
    if [ -z "$WANDEV" ]; then
        set -- $(wan_endpoint_route "$EPFAM" "$EPADDR" "$IFACE")
        WANDEV="$1"; WANGW="$2"
        if [ -n "$WANDEV" ]; then
            log "未找到物理默认路由，使用端点 host route: dev $WANDEV ${WANGW:+via $WANGW}"
        fi
    fi
    if [ -z "$WANDEV" ]; then
        log "ERROR: 找不到可用的物理默认路由或端点 host route，不接管默认路由（保持原状）"
        exit 1
    fi
    VIA=""
    [ -n "$WANGW" ] && VIA="via $WANGW"

    if [ "$EPFAM" = 6 ]; then
        HOSTLEN=128
        ip -6 route replace "$EPADDR/$HOSTLEN" $VIA dev "$WANDEV"
    else
        HOSTLEN=32
        ip route replace "$EPADDR/$HOSTLEN" $VIA dev "$WANDEV"
    fi
    if [ $? -ne 0 ]; then
        log "ERROR: 端点例外路由失败 ($EPADDR/$HOSTLEN dev $WANDEV $VIA)，不接管默认路由"
        exit 1
    fi
    log "端点例外路由: $EPADDR/$HOSTLEN -> dev $WANDEV $VIA"
else
    log "警告: USQUE_ENDPOINT 为空，跳过端点例外路由"
fi

# ---------------------------------------------------------------------------
# 2. 默认路由指向隧道
# ---------------------------------------------------------------------------
if ! ip route replace default dev "$IFACE" metric "$TUN_METRIC" 2>/dev/null; then
    ip route del default dev "$IFACE" 2>/dev/null
    ip route add default dev "$IFACE" metric "$TUN_METRIC" || log "ERROR: IPv4 默认路由设置失败"
fi

if ip -6 route replace default dev "$IFACE" metric "$TUN_METRIC" 2>/dev/null; then
    :
else
    ip -6 route del default dev "$IFACE" 2>/dev/null
    ip -6 route add default dev "$IFACE" metric "$TUN_METRIC" 2>/dev/null \
        || log "提示: IPv6 默认路由未设置（隧道内可能没启用 IPv6，忽略）"
fi

# ---------------------------------------------------------------------------
# 3. 自检 + 提醒（写进 logread，便于排障）
# ---------------------------------------------------------------------------
SEL4=$(ip route get 1.1.1.1 2>/dev/null | head -1)
SEL6=$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | head -1)
log "IPv4 出口自检: $SEL4"
[ -n "$SEL6" ] && log "IPv6 出口自检: $SEL6"

case "$SEL4" in
    *"dev $IFACE"*) : ;;
    *) log "警告: 1.1.1.1 未走 $IFACE。通常是因为 WAN 默认路由 metric($WAN_METRIC 号位) 不大于 $TUN_METRIC。"
       log "      修法: uci set network.wan.metric='$WAN_METRIC'; uci commit network; /etc/init.d/network reload"
       log "      (IPv6 默认路由 metric 一般为 1024，无需修改)" ;;
esac

log "默认路由已切到 $IFACE (metric $TUN_METRIC)，全部流量经 WARP 出口"
exit 0
