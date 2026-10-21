#!/bin/sh
# =============================================================================
#  /etc/usque/down.sh  ——  usque (nativetun 模式) 的 on-disconnect 钩子
#
#  触发时机：隧道连接丢失（usque 会立刻按 --reconnect-delay 重连）。
#  环境变量：USQUE_EVENT=disconnect, USQUE_IFACE, USQUE_ENDPOINT, ...
#
#  设计选择：这里「故意什么都不清理」。
#
#  原因：warp0 接口此时仍然存在，隧道默认路由（metric 10）依然优先于
#  WAN 的后备默认路由（metric 250）。于是掉线期间的数据包会被送进隧道并丢弃
#  —— 这是 fail-closed：宁可断网，也不把流量明文泄漏到 ISP。
#  usque 重连成功后会再次调用 up.sh，用户几乎无感。
#
#  如果确实希望「掉线就自动回退直连」（fail-open），把下面两行注释放开即可：
#      ip route del default dev "$IFACE" metric 10 2>/dev/null
#      ip -6 route del default dev "$IFACE" metric 10 2>/dev/null
#
#  注意：如果 usque 进程彻底退出/被停掉，warp0 设备消失，内核会自动删掉挂在
#  它上面的默认路由，WAN 的后备默认路由随即接管 —— 所以不会把自己锁死在断网状态。
# =============================================================================

IFACE="${USQUE_IFACE:-warp0}"
log() { logger -t usque-hook "[disconnect] $*"; }

log "隧道断开（$USQUE_ENDPOINT），保持 fail-closed，等待 usque 自动重连"
exit 0
