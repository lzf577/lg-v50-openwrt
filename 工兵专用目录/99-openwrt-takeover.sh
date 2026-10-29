#!/system/bin/sh
# OpenWrt Takeover Autostart Service for LG V50

LOG_FILE=/data/local/tmp/openwrt_autostart.log
exec > "$LOG_FILE" 2>&1

echo "=== [$(date)] OpenWrt Autostart Initiated ==="

# 1. 等待 Android 系统完全启动
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 3
done
echo "=== sys.boot_completed detected, waiting for cnss-daemon ==="

# 2. 等待高通 WLAN 守护进程就绪
while [ "$(getprop init.svc.cnss-daemon)" != "running" ]; do
    sleep 2
done
# 缓冲 5 秒确保平台稳固
sleep 5
echo "=== cnss-daemon ready, releasing Android Wi-Fi stack ==="

# 3. 安全停止 Android Wi-Fi 栈
setprop ctl.stop wpa_supplicant
setprop ctl.stop wificond
setprop ctl.stop vendor.wifi-hal-1-1
setprop ctl.stop vendor.wifi_hal_legacy
setprop ctl.stop vendor.wifidisplayhalservice

# 4. 挂载 OpenWrt 环境
M=/data/local/tmp/lede
mkdir -p $M
mount | grep -q "$M " || mount -t ext4 -o rw /dev/block/sda25 $M
mount | grep -q "$M/dev " || mount -o bind /dev $M/dev
mount | grep -q "$M/proc " || mount -t proc proc $M/proc
mount | grep -q "$M/sys " || mount -t sysfs sysfs $M/sys
mkdir -p $M/vendor
mount | grep -q "$M/vendor " || mount -o bind /vendor $M/vendor

# 5. 配置 OpenWrt DNS 解析与关键 group
rm -f $M/etc/resolv.conf
echo "nameserver 223.5.5.5" > $M/etc/resolv.conf
echo "nameserver 119.29.29.29" >> $M/etc/resolv.conf

grep -q "^root:x:0:" $M/etc/group 2>/dev/null || echo "root:x:0:root" >> $M/etc/group
grep -q "^ubus:x:81:" $M/etc/group 2>/dev/null || echo "ubus:x:81:ubus" >> $M/etc/group

# 6. 开启内核 IPv4 转发与 WAN 口 NAT / 策略路由
echo 1 > /proc/sys/net/ipv4/ip_forward

# 检测以太网 WAN 口
WAN_IF=$(ip link show | grep -oE "eth[0-9]" | head -1)
if [ -n "$WAN_IF" ]; then
    echo "=== Configuring WAN Interface: $WAN_IF ==="
    ip link set $WAN_IF up
    
    # 注入 iptables 转发与 NAT 伪装规则（置顶避免被 Android tetherctrl 阻断）
    iptables -D FORWARD -i wlan0 -o $WAN_IF -j ACCEPT 2>/dev/null
    iptables -I FORWARD 1 -i wlan0 -o $WAN_IF -j ACCEPT
    iptables -D FORWARD -i $WAN_IF -o wlan0 -m state --state RELATED,ESTABLISHED 2>/dev/null
    iptables -I FORWARD 2 -i $WAN_IF -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT

    iptables -t nat -D POSTROUTING -o $WAN_IF -j MASQUERADE 2>/dev/null
    iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE
fi

# 7. 在 Mount 命名空间启动 OpenWrt 容器与服务
nohup unshare -m chroot $M /bin/busybox sh -c "
  export PATH=/usr/sbin:/usr/bin:/sbin:/bin
  mount -t tmpfs tmpfs /tmp 2>/dev/null
  mount -t tmpfs tmpfs /run 2>/dev/null
  mkdir -p /tmp/run /tmp/lib/misc /tmp/lock /tmp/log /tmp/run/ubus /etc/dropbear

  # 检查或生成 Dropbear key
  if [ ! -f /etc/dropbear/dropbear_ed25519_host_key ] || [ ! -s /etc/dropbear/dropbear_ed25519_host_key ]; then
    rm -f /etc/dropbear/dropbear_ed25519_host_key
    dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key
  fi

  # 清理旧 socket 并拉起核心总线 ubusd
  rm -f /var/run/ubus/ubus.sock
  /sbin/ubusd &
  sleep 1

  # 拉起系统基础服务 procd
  /sbin/procd &
  sleep 1

  # 启动 rpcd (LuCI RPC 与会话认证核心)
  /etc/init.d/rpcd restart
  sleep 1

  # 启动 SSH 服务
  killall -9 dropbear 2>/dev/null
  /usr/sbin/dropbear -R -B -p 127.0.0.1:2222

  # 策略路由解封：确保 main 路由表优先于 Android netd 的 unreachable 策略
  ip rule add pref 999 lookup main 2>/dev/null

  # 配置并拉起 Wi-Fi 与 DHCP
  ip link set wlan0 down
  ip link set wlan0 up
  ip addr flush dev wlan0
  ip addr add 192.168.10.1/24 dev wlan0

  killall dnsmasq 2>/dev/null
  dnsmasq -C /etc/dnsmasq-v50.conf

  killall hostapd 2>/dev/null
  hostapd -B -P /tmp/hostapd.pid /etc/hostapd/hostapd-5g.conf

  # 启动 Web 界面服务 (uhttpd)
  /etc/init.d/uhttpd restart
" > /data/local/tmp/lede_takeover.log 2>&1 &

echo "=== [$(date)] OpenWrt Autostart Trigger Complete ==="
