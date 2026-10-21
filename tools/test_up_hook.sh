#!/bin/sh
# =============================================================================
#  test_up_hook.sh —— 在没有 Linux 路由器的情况下验证 up.sh 的路由逻辑
#
#  原理：把 `ip` / `logger` 换成 mock 记录器，喂入真实格式的
#        `ip route show default` 输出，检查 up.sh 实际下发的命令序列。
#
#  用法： sh tools/test_up_hook.sh
# =============================================================================
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
UP="$ROOT/usque/root/etc/usque/up.sh"
[ -f "$UP" ] || { echo "找不到 $UP"; exit 1; }
mkdir -p "$ROOT/temp"
WORK="$ROOT/temp/_test-work-$$"
rm -rf "$WORK"
mkdir -p "$WORK"
MOCK="$WORK/bin"
mkdir -p "$MOCK"
LOG="$WORK/calls.log"
: > "$LOG"

# ---------- mock ip ----------
cat > "$MOCK/ip" <<'EOF'
#!/bin/sh
echo "ip $*" >> "$CALLS"
case "$*" in
  *"route show default"*)
      case "$*" in
        *-6*) [ -n "$MOCK_V6_DEFAULT" ] && echo "$MOCK_V6_DEFAULT" ;;
        *)    echo "$MOCK_V4_DEFAULT" ;;
      esac
      ;;
  *"route get 1.1.1.1"*)                 echo "${MOCK_GET_V4:-1.1.1.1 via 172.16.0.1 dev warp0 src 172.16.0.2}" ;;
  *"route get 2606:4700:4700::1111"*)    echo "${MOCK_GET_V6:-2606:4700:4700::1111 dev warp0 src 2606:4700:103::1}" ;;
  *"replace default dev"*)
      if [ -n "$MOCK_FAIL_REPLACE" ]; then exit 2; fi
      ;;
esac
exit 0
EOF

cat > "$MOCK/logger" <<'EOF'
#!/bin/sh
# logger -t TAG msg...
shift 2>/dev/null || true
echo "LOGGED: $*" >> "$CALLS"
exit 0
EOF
chmod +x "$MOCK/ip" "$MOCK/logger"

run() { # $1=描述
    echo
    echo "################ $1"
    : > "$LOG"
    CALLS="$LOG" PATH="$MOCK:$PATH" \
    USQUE_EVENT=connect USQUE_MODE=nativetun USQUE_IFACE=warp0 \
    USQUE_ENDPOINT="$EP" USQUE_IPV4=172.16.0.2 USQUE_IPV6=2606:4700:103::1 \
    MOCK_V4_DEFAULT="$V4D" MOCK_V6_DEFAULT="$V6D" MOCK_FAIL_REPLACE="$FAILREPL" \
    MOCK_GET_V4="$MOCK_GET_V4" \
        sh "$UP" || echo "up.sh 退出码=$?"
    cat "$LOG"
}

# 场景 1：常规 —— WAN(v4,v6) 齐全，端点走 v4，密码无关
V4D='default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.100 metric 250'
V6D='default via fe80::1 dev eth0 proto ra metric 1024'
EP='162.159.198.1:443'; FAILREPL=''
run "场景1: IPv4 端点 + WAN 有 v4/v6 默认路由"

# 场景 2：端点走 IPv6（[v6]:port，模拟 usque -6）
V4D='default via 192.168.1.1 dev eth0 metric 250'
V6D='default via fe80::1 dev eth0 proto ra metric 1024'
EP='[2606:4700:103::]:443'
run "场景2: IPv6 端点（USQUE_ENDPOINT 带方括号）"

# 场景 3：busybox ip 不支持 replace → 应回退 del+add
V4D='default via 192.168.1.1 dev eth0 metric 250'
V6D=''
EP='162.159.198.1:443'; FAILREPL=1
run "场景3: replace 失败 → del+add 回退"

# 场景 4 结束前重置，避免影响场景 5
V4D=''
V6D=''; EP='162.159.198.1:443'; FAILREPL=''
run "场景4: 无物理默认路由 → 安全退出"

# 场景 5：WAN metric=0（未按指南设置）→ 应打印警告
V4D='default via 192.168.1.1 dev eth0 metric 0'
V6D=''
EP='162.159.198.1:443'; FAILREPL=''
MOCK_GET_V4='1.1.1.1 via 192.168.1.1 dev eth0 src 192.168.1.100'
run "场景5: WAN metric=0 → 自检应告警"
MOCK_GET_V4=''

rm -rf "$WORK"
echo
echo "=== 测试结束 ==="
