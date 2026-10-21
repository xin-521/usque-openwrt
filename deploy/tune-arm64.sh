#!/bin/sh
# =============================================================================
#  tune-arm64.sh —— OpenWrt 25.12 / aarch64 运行时性能调优（可选、可回滚）
#
#  只做两件对「单条 QUIC 隧道」真正有效的事，不动二进制、不动内核模块：
#    1. CPU governor → performance
#       arm64 软路由默认 schedutil/ondemand，突发流量时升频有延迟；用户态 QUIC
#       是单线程热点，升频慢会直接吃掉首屏/测速的前几秒。
#       代价：待机功耗与温度上升（无风扇小盒子请先观察 /sys/class/thermal）。
#    2. packet_steering=1（UCI，持久）
#       把网卡软中断分散到多核，给跑 usque 的那个核腾出 CPU。
#
#  用法：
#    sh tune-arm64.sh              # 只看现状与建议（默认，只读）
#    sh tune-arm64.sh --apply      # governor=performance + packet_steering=1
#    sh tune-arm64.sh --revert     # 恢复原 governor、删掉 packet_steering
#
#  说明：
#    - governor 通过 /etc/init.d/usque-perf 持久化（可单独删除）
#    - --apply 里的 network reload 会让接口短暂闪断；远端 SSH 操作请先开 tmux/screen
#    - 不支持 aarch64 的平台直接退出
# =============================================================================

GOV_GLOBS="/sys/devices/system/cpu/cpufreq/policy*/scaling_governor /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor"
STATE=/etc/usque/governor.orig
PERF_INIT=/etc/init.d/usque-perf
SYSCTL=/etc/sysctl.d/90-usque.conf

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-status}" in
    -h|--help|help) usage; exit 0 ;;
esac

[ "$(uname -m)" = "aarch64" ] || { echo "只支持 aarch64（当前 $(uname -m)）"; exit 1; }

gov_list() {
    n=0
    for f in $GOV_GLOBS; do
        [ -f "$f" ] || continue
        echo "  ${f#/sys/devices/system/cpu/} = $(cat "$f" 2>/dev/null)"
        n=$((n + 1))
    done
    [ "$n" -eq 0 ] && echo "  （无 cpufreq：内核没带调频驱动，governor 无需处理）"
    return 0
}

show() {
    echo "CPU        : $(awk -F: '/^(Processor|model name|Hardware)/{gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)"
    echo "核心数     : $(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)"
    echo "调频策略   :"
    gov_list
    echo "UDP 缓冲   : rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null) wmem_max=$(sysctl -n net.core.wmem_max 2>/dev/null) backlog=$(sysctl -n net.core.netdev_max_backlog 2>/dev/null)"
    echo "包分流     : packet_steering=$(uci -q get network.globals.packet_steering 2>/dev/null || echo '<未设置>')"
    printf "RPS 状态   : "
    for q in /sys/class/net/*/queues/rx-0/rps_cpus; do
        [ -f "$q" ] || continue
        i=${q#/sys/class/net/}; i=${i%%/*}
        printf '%s=%s ' "$i" "$(cat "$q" 2>/dev/null)"
    done
    echo
    echo
    echo "建议："
    echo "  1) 确认 UDP 缓冲已生效（否则 quic-go 必掉包）："
    echo "     sysctl -p $SYSCTL"
    echo "  2) 想榨干单核性能： sh $0 --apply"
    echo "  3) 观察是否被单核限制（跑测速时）："
    echo "     top -b -n1 | head -12 ; cat /proc/net/dev | grep warp0"
}

apply_governor() {
    mkdir -p /etc/usque
    : > "$STATE"
    for f in $GOV_GLOBS; do
        [ -f "$f" ] || continue
        echo "${f#/sys/devices/system/cpu/} $(cat "$f" 2>/dev/null)" >> "$STATE"
        if grep -qw performance "${f%scaling_governor}scaling_available_governors" 2>/dev/null; then
            echo performance > "$f" 2>/dev/null && echo "  ✓ $f = performance"
        else
            echo "  - 跳过 $f（不支持 performance）"
        fi
    done
    [ -s "$STATE" ] || { echo "  （没有 cpufreq，跳过）"; rm -f "$STATE"; return 0; }

    cat > "$PERF_INIT" <<'EOF'
#!/bin/sh /etc/rc.common
# 由 tune-arm64.sh 生成：开机把 CPU governor 设为 performance
START=99
start() {
    for p in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor \
             /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
        [ -w "$p" ] && echo performance > "$p" 2>/dev/null
    done
}
EOF
    chmod +x "$PERF_INIT"
    "$PERF_INIT" enable >/dev/null 2>&1
    echo "  ✓ 已启用开机持久化：$PERF_INIT"
}

apply_steering() {
    if ! command -v uci >/dev/null 2>&1; then
        echo "  - 没有 uci，跳过 packet_steering"
        return 0
    fi
    uci -q get network.globals >/dev/null 2>&1 || uci set network.globals=globals
    uci set network.globals.packet_steering='1' || return 1
    uci commit network || return 1
    echo "  ✓ network.globals.packet_steering=1（重新加载网络，接口会短暂闪断）"
    /etc/init.d/network reload >/dev/null 2>&1
}

revert_all() {
    if [ -f "$STATE" ]; then
        while read -r rel val; do
            [ -n "$rel" ] || continue
            f="/sys/devices/system/cpu/$rel"
            [ -w "$f" ] && echo "$val" > "$f" 2>/dev/null && echo "  ✓ 恢复 $rel = $val"
        done < "$STATE"
        rm -f "$STATE"
    fi
    if [ -x "$PERF_INIT" ]; then
        "$PERF_INIT" disable >/dev/null 2>&1
        rm -f "$PERF_INIT"
        echo "  ✓ 已移除 $PERF_INIT"
    fi
    if command -v uci >/dev/null 2>&1 && [ -n "$(uci -q get network.globals.packet_steering 2>/dev/null)" ]; then
        uci -q delete network.globals.packet_steering
        uci commit network
        echo "  ✓ 已删除 packet_steering"
        /etc/init.d/network reload >/dev/null 2>&1
    fi
}

case "${1:-status}" in
    status|"") show ;;
    --apply)
        echo "== 应用 arm64 调优 =="
        [ -f "$SYSCTL" ] && sysctl -p "$SYSCTL" >/dev/null 2>&1
        apply_governor
        apply_steering
        echo
        show
        ;;
    --revert) echo "== 回滚 =="; revert_all ;;
    -h|--help|help) usage ;;
    *) usage; exit 1 ;;
esac
