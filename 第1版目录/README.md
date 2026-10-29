# LG V50 随身软路由 - 第 1 版稳定核心配置与使用全典

本手册面向战役最高指挥官，详尽记录 **第 1 版已调通固化系统** 中每一个核心配置文件的功能、核心参数与实操使用方式。

---

## 目录索引
1. [开机接管与自愈脚本 (`autostart_scripts/`)](#一-开机接管与自愈脚本-autostart_scripts)
2. [OpenWrt 核心标准配置文件 (`openwrt_config/config/`)](#二-openwrt-核心标准配置文件-openwrt_configconfig)
   - [网络与通信基石：network / wireless / dhcp / firewall](#1-网络与通信基石)
   - [核心战略大杀器：openclash / zerotier / turboacc](#2-核心战略大杀器)
   - [管理与交互后台：luci / uhttpd / rpcd / dropbear](#3-管理与交互后台)
   - [日常辅助与自动化工具：nlbwmon / upnpd / arpbind / autoreboot / etherwake](#4-日常辅助与自动化工具)
3. [高通硬件射频校准数据 (`wifi_hardware_assets/`)](#三-高通硬件射频校准数据-wifi_hardware_assets)
4. [战役一键复原与回退指引](#四-战役一键复原与回退指引)

---

## 一、 开机接管与自愈脚本 (`autostart_scripts/`)

> **存放路径**：手机端 `/data/adb/service.d/`  
> **执行权限**：`chmod 755`（由 Magisk 在开机阶段以 root 权限自动调起）

### 1. `99-openwrt-takeover.sh`（主开机接管脚本）
- **核心职能**：
  - 监听 Android 系统启动完毕事件（`sys.boot_completed=1`）；
  - 封锁 Android 原生网络栈（停用 `wpa_supplicant`、`wificond`、`netd` 对热点的干扰）；
  - 挂载 OpenWrt rootfs 到独立 Mount 命名空间；
  - 按严格依赖时序拉起 OpenWrt 内部服务：`ubusd` $\rightarrow$ `procd` $\rightarrow$ `rpcd` $\rightarrow$ `hostapd` $\rightarrow$ `dnsmasq` $\rightarrow$ `uhttpd`。
- **使用/维护方式**：
  若修改了 OpenWrt 启动参数，手机执行 `sh /data/adb/service.d/99-openwrt-takeover.sh` 可一键全量重启接管栈。

### 2. `wan_watchdog.sh`（WAN 网卡热插拔与默认路由自愈守护）
- **核心职能**：
  - 每 3 秒巡检一次 USB 有线网卡接口（`eth0`）；
  - 检测到插入网线时，自动拉取上级路由器 DHCP 分配的 IP；
  - **核心绝杀**：自动检测并补齐默认路由网关（`ip route replace default via 192.168.x.1 dev eth0`），防止 Android netd 阻断数据包出海；
  - 动态维持置顶 iptables MASQUERADE 双向 NAT 转发规则。
- **使用方式**：开机常驻后台，完全免人工干预。任意插拔 USB 网线，3 秒内自动自愈恢复上网。

### 3. `dnsmasq-v50.conf`（热点专用 DHCP 与 DNS 配置）
- **核心职能**：
  - 托管 Wi-Fi 热点接口（`wlan0`）的客户端 IP 地址池（`192.168.10.100` ~ `192.168.10.200`）；
  - 强制向客户端分发网关 `192.168.10.1` 与高速公网 DNS（`223.5.5.5`、`119.29.29.29`）；
  - 彻底规避 Android 原生 DNS 代理导致的“已连接但无互联网”假死问题。

---

## 二、 OpenWrt 核心标准配置文件 (`openwrt_config/config/`)

所有文件对应手机内路径：`/data/local/tmp/lede/etc/config/<名称>`

### 1. 网络与通信基石

#### ① `network`（物理与虚拟网络接口定义）
- **主要配置项**：
  - `config interface 'lan'`：定义热点局域网网段，IP 为 `192.168.10.1`，掩码 `255.255.255.0`；
  - `config interface 'wan'`：绑定物理网卡 `eth0`，协议为 `dhcp`，用于连接主路由网线。
- **使用方式**：
  在 Web 界面【网络】$\rightarrow$【接口】中可视化修改；或命令行执行 `uci set network.lan.ipaddr='192.168.10.1'` 后 `uci commit network`。

#### ② `wireless`（Wi-Fi 射频天线与热点控制）
- **主要配置项**：
  - `config wifi-device`：高通 WCN3998 射频硬件，支持 802.11ac 5GHz 高频与 80MHz 频宽；
  - `config wifi-iface`：热点 SSID（默认为 `OpenWrt-V50-5G`）、加密方式（`WPA2-PSK`）、Wi-Fi 密码。
- **使用方式**：
  可在 Web 界面【网络】$\rightarrow$【无线】修改 Wi-Fi 密码与热点名称。

#### ③ `dhcp`（租约分发与 DNS 转发）
- **主要配置项**：
  - `config dnsmasq`：本地 DNS 解析规则与缓存大小；
  - `config dhcp 'lan'`：热点局域网 IP 租期（默认 12 小时）与自动分发策略。
- **使用方式**：
  在 Web 界面【网络】$\rightarrow$【DHCP/DNS】中添加静态 IP 分配、自定义主机名映射或更改上游 DNS。

#### ④ `firewall`（网络防火墙与流量转发规则）
- **主要配置项**：
  - `config zone 'lan'` / `config zone 'wan'`：定义内网安全区与外网安全区；
  - `option forwarding 'ACCEPT'`：允许 LAN 到 WAN 流量自由穿透并实行 IP 伪装（MASQUERADE）。
- **配套文件**：`openwrt_config/firewall.user`，包含每次防火墙重载时自动注入的置顶全通规则。

---

### 2. 核心战略大杀器

#### ⑤ `openclash`（无感出海与透明分流控制）
- **主要配置项**：
  - `proxy_port` (`7892`) / `tproxy_port` (`7895`)：内核透明代理重定向端口；
  - 规则模式（Rule / Global / Direct）：支持国内流量直连、国外流量自动走节点代理；
  - DNS 劫持与防污染模式（Fake-IP 模式）。
- **使用方式**：
  1. 浏览器打开 LuCI 后台 $\rightarrow$ 点击【服务】$\rightarrow$【OpenClash】；
  2. 在【配置订阅】中粘贴您的机场/代理订阅链接，点击“一键更新配置”；
  3. 启动 OpenClash 服务，随身连接热点的所有手机、电脑立即享受无感出海。

#### ⑥ `zerotier`（公司内网穿透与虚拟专网互联）
- **主要配置项**：
  - `list join 'xxxxxxxxxxxx'`：填入您公司的 ZeroTier 16 位 Network ID；
  - `option enabled '1'`：随路由开机自动连接公司虚拟内网。
- **使用方式**：
  1. 打开 LuCI 后台 $\rightarrow$ 点击【VPN】$\rightarrow$【ZeroTier】；
  2. 勾选“启用”，填入公司的 Network ID 并保存；
  3. 在 ZeroTier 网页控制台授权该设备（本台 V50 节点 ID：`dda9c80cf9`）；
  4. 您的随身所有终端连上 V50 热点后，无需安装任何客户端，直接在浏览器输入公司服务器内网 IP 即可访问！

#### ⑦ `turboacc`（高通网络加速引擎）
- **主要配置项**：
  - `option sw_flow_offloading '1'`：开启软件流量快速卸载（Flow Offloading）；
  - `option bbr_cca '1'`：开启 TCP BBR 拥塞控制算法。
- **使用方式**：
  在【网络】$\rightarrow$【Turbo ACC 网络加速】中启用，能让千兆转发 CPU 占用率降至 5% 以下，极大降低手机发热并延长待机时间。

---

### 3. 管理与交互后台

#### ⑧ `luci`（Web 管理界面设置）
- **主要配置项**：
  - `option lang 'zh_cn'`：强制锁定后台界面为简体中文；
  - `option mediaurlbase '/luci-static/bootstrap'`：界面主题。
- **使用方式**：在【系统】$\rightarrow$【语言和界面】中自由切换。

#### ⑨ `uhttpd`（Web 服务器参数）
- **主要配置项**：
  - `list listen_http '0.0.0.0:80'`：在 80 端口监听 Web 访问；
  - `list listen_https '0.0.0.0:443'`：支持 HTTPS 加密访问后台。

#### ⑩ `rpcd`（RPC 总线数据通信守护）
- **主要配置项**：会话超时时间（`3600` 秒）与 ACL 权限映射，确保 Web 界面能够安全读写内核 UCI 数据。

#### ⑪ `dropbear`（SSH 远程管理服务）
- **主要配置项**：
  - 默认监听端口 `22` / 映射端口 `2222`；
  - 绑定主机密钥文件：`openwrt_config/dropbear/dropbear_ed25519_host_key`。
- **使用方式**：
  电脑终端执行 `ssh root@192.168.10.1` 即可进入底层 OpenWrt Linux 终端命令行。

---

### 4. 日常辅助与自动化工具

#### ⑫ `nlbwmon`（网络流量实时监控与统计）
- **作用**：记录每个连入热点的手机、电脑的实时上下行带宽占用与历史总流量统计。
- **查看路径**：LuCI 后台【状态】$\rightarrow$【流量统计】。

#### ⑬ `upnpd`（通用即插即用端口自动映射）
- **作用**：为接入局域网的 Switch 联机、BT 下载工具自动打通外部路由器端口映射，实现最优 NAT 状态。

#### ⑭ `arpbind`（静态 ARP 绑定）
- **作用**：将公司核心电脑或常备手机的 MAC 与 IP 进行一对一强制绑定，杜绝 IP 漂移与冲突。

#### ⑮ `autoreboot`（定时自动化维护重启）
- **作用**：可设定每周固定凌晨时间（如周日 04:00）自动重启系统，清理长时间运行的缓存与内存碎片。

#### ⑯ `etherwake` & `luci-wol`（局域网远程唤醒）
- **作用**：在出差在外时，通过 V50 远程发送 Magic Packet 唤醒办公室处于休眠状态的台式机或服务器。

#### ⑰ `openssl`（底层安全加解密库）
- **作用**：提供 HTTPS、SSL 证书验证与加密算法底层支持，无需手动编辑。

---

## 三、 高通硬件射频校准数据 (`wifi_hardware_assets/`)

- **`bdwlan.bin` 系列（出厂射频功率表）**：
  LG 官方针对韩版 V50 出厂严密校准的 Board Data File。包含韩版（KR_ALL）、北美（NA_SPR/NA_VZW）及通用频段功率参数。
- **`WCNSS_qcom_cfg.ini`**：
  高通骁龙 855 底层 Wi-Fi 芯片初始化参数文件，决定了并发连接上限、信道自动规避与抗干扰逻辑。

---

## 四、 战役一键复原与回退指引

若日后固件被调试改乱或需要原地重装复原，只需在手机连接状态下执行以下三步命令：

1. **一键恢复 OpenWrt 内部配置**：
   ```bash
   adb push openwrt_config/* /data/local/tmp/lede/etc/
   ```
2. **一键恢复宿主自启动与看门狗脚本**：
   ```bash
   adb push autostart_scripts/* /data/adb/service.d/
   adb shell "su -c 'chmod 755 /data/adb/service.d/*.sh'"
   ```
3. **重启生效**：
   ```bash
   adb shell "su -c 'reboot'"
   ```
手机重启后，系统将**100% 满血复原到今天验证通过的完美中文、正常上网基线状态！**
