#!/system/bin/sh
# WAN Hotplug & NAT & Default Gateway Watchdog for LG V50

while true; do
    WAN_IF=$(ip link show | grep -oE "eth[0-9]" | head -1)
    if [ -n "$WAN_IF" ]; then
        # 确保接口状态为 UP
        ip link set $WAN_IF up 2>/dev/null
        
        # 检查是否已获取 IPv4 地址与默认网关
        HAS_GW=$(ip route show table main | grep -E "^default.*dev $WAN_IF")
        if [ -z "$HAS_GW" ]; then
            # 自动拉取 DHCP 并配置网关与 DNS
            udhcpc -i $WAN_IF -q -n -s /system/etc/dhcpcd/dhcpcd-run-hooks 2>/dev/null || udhcpc -i $WAN_IF -q -n 2>/dev/null
            
            # 若仍无默认网关，基于 192.168.7.x 网段自动补齐网关
            IP_PREFIX=$(ip -4 addr show dev $WAN_IF | grep -oE "inet [0-9]+\.[0-9]+\.[0-9]+" | awk '{print $2}' | head -1)
            if [ -n "$IP_PREFIX" ]; then
                ip route replace default via ${IP_PREFIX}.1 dev $WAN_IF 2>/dev/null
            fi
        fi

        # 确保内核转发开启
        echo 1 > /proc/sys/net/ipv4/ip_forward

        # 检查置顶转发与 NAT 规则
        if ! iptables -C FORWARD -i wlan0 -o $WAN_IF -j ACCEPT 2>/dev/null; then
            iptables -I FORWARD 1 -i wlan0 -o $WAN_IF -j ACCEPT
        fi
        if ! iptables -C FORWARD -i $WAN_IF -o wlan0 -m state --state RELATED,ESTABLISHED 2>/dev/null; then
            iptables -I FORWARD 2 -i $WAN_IF -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
        fi
        if ! iptables -t nat -C POSTROUTING -o $WAN_IF -j MASQUERADE 2>/dev/null; then
            iptables -t nat -I POSTROUTING 1 -o $WAN_IF -j MASQUERADE
        fi

        # 确保 main 路由表优先于 Android netd 的 unreachable 策略
        if ! ip rule show | grep -q "lookup main"; then
            ip rule add pref 999 lookup main 2>/dev/null
        fi
    fi
    sleep 3
done
