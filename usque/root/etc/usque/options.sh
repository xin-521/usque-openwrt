# /etc/usque/options.sh —— 由 /etc/init.d/usque source，改完重启服务生效。
#   /etc/init.d/usque restart
#
# USQUE_IFACE      隧道接口名（同时用于防火墙 zone，保持默认即可）
# USQUE_EXTRA_ARGS 追加给 `usque nativetun` 的参数（抗封锁调优都在这里）
#
# 抗封锁速查（按需启用其一/多项）：
#   --http2                UDP/QUIC 被封锁时改走 TCP+HTTP/2（端点默认 162.159.198.2:443）
#   -s example.com         改写 TLS SNI，避免 client-masque.SNI 被 DPI 命中
#   -P 500                 换连接端口（443 被封时依次试 500 / 1701 / 4500 / 53）
#   -6                     用 IPv6 连 WARP 端点（需要 WAN 有可用 IPv6）
#   --keepalive-period 30s NAT 空闲踢连接时缩短保活
#   --insecure             关闭端点证书 pinning（仅排障！会失去对中间人的防护）
#
# 例（QUIC 被 QoS/封锁时的组合）：
#   USQUE_EXTRA_ARGS="--always-reconnect --http2 -s www.bing.com -P 500"

USQUE_IFACE="warp0"
USQUE_EXTRA_ARGS="--always-reconnect"
