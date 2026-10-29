# LG V50 随身软路由系统与接管工具链 (LG V50 OpenWrt)

本项目旨在将高通骁龙 855 旗舰手机 **LG V50 ThinQ** 改造为兼具极致便携性与强悍网络吞吐能力的 **随身软路由系统**。

通过独立挂载 OpenWrt 命名空间与底层硬件接管方案，实现开机免手动干预自启、RTL8153 USB 有线千兆网卡即插即用（WAN 自愈）、5GHz 高频 Wi-Fi 硬件热点（WCN3998 80MHz）、透明分流（OpenClash）与虚拟组网（ZeroTier）。

---

## 🌟 核心特性与架构亮点

1. **Magisk 级开机自动接管**
   - 监听 Android `sys.boot_completed=1` 事件；
   - 封锁 Android 原生网络栈干扰，挂载独立 Mount 命名空间；
   - 按严密依赖拓扑自动拉起 OpenWrt 守护进程栈（`ubusd` $\rightarrow$ `procd` $\rightarrow$ `rpcd` $\rightarrow$ `hostapd` $\rightarrow$ `dnsmasq` $\rightarrow$ `uhttpd`）。
2. **WAN 口热插拔自愈守护**
   - 内置 `wan_watchdog` 毫秒级巡检 RTL8153 USB 网卡；
   - 支持网线热插拔自动 DHCP 续租、补齐全局默认路由网关，防 Android netd 出海阻断。
3. **原生硬件级 5G Wi-Fi 热点**
   - 深度提取并挂载高通 WCN3998 射频校准数据（`bdwlan.bin` / NV assets）；
   - 支持 802.11ac 5GHz 80MHz 极速频宽，提供稳定局域网覆盖。
4. **完备的出海与穿透网络套件**
   - 集成 LuCI Web 管理控制后台；
   - 集成 OpenClash 透明代理与 DNS 劫持防护；
   - 集成 ZeroTier 内网穿透与多节点跨地域互联。

---

## 📁 目录结构导引

| 目录/文件 | 说明 |
| :--- | :--- |
| [**`第1版目录/`**](./第1版目录/) | **核心工程基线**：包含第 1 版调通固化的所有标准配置文件、开机脚本与射频文件 |
| ├── [`第1版目录/README.md`](./第1版目录/README.md) | **系统配置与实操全典**：详细解读每一个配置项与故障处理指南 |
| ├── [`autostart_scripts/`](./第1版目录/autostart_scripts/) | 开机接管与自愈脚本 (`99-openwrt-takeover.sh`, `wan_watchdog.sh`, `dnsmasq-v50.conf`) |
| ├── [`openwrt_config/`](./第1版目录/openwrt_config/) | OpenWrt `/etc/config/` 标准配置模板（网络、无线、防火墙、OpenClash、ZeroTier） |
| └── [`wifi_hardware_assets/`](./第1版目录/wifi_hardware_assets/) | 高通 WCN3998 射频天线与校准资产数据 |

---

## 🚀 快速上手流程

1. **底层解锁与准备**
   - LG V50 手机需已解锁 Bootloader；
   - 刷入修补后的 Magisk Boot 镜像以获得开机 root 引导执行权限。
2. **部署 OpenWrt RootFS 与配置**
   - 将系统镜像解包至手机端 `/data/local/tmp/lede`（或专属 ext4 分区）；
   - 将 [`第1版目录/openwrt_config/config/`](./第1版目录/openwrt_config/config/) 复制至手机内对应 `/etc/config/`。
3. **部署自启脚本**
   - 将 [`autostart_scripts/`](./第1版目录/autostart_scripts/) 目录下的脚本部署至手机 `/data/adb/service.d/`；
   - 赋予可执行权限：`chmod 755 /data/adb/service.d/*.sh`。
4. **启动与验证**
   - 重启手机，待开机震动并进入桌面后，手机自动拉起 OpenWrt；
   - 默认 Wi-Fi SSID：`LEDE`（5GHz），默认管理后台：`http://192.168.10.1`。

---

## 📦 固件与大文件下载 (Releases)

根据 GitHub 社区规范，为保证仓库轻量精简，完整的固件底包、分区 Dump 备份以及编译好的 Magisk Boot 镜像托管在 GitHub Releases：

- 访问 [**Releases 页面**](https://github.com/lzf577/lg-v50-openwrt/releases) 下载：
  - `magisk_boot_a.img`（V50 Magisk 修补启动镜像）
  - `openwrt_v2_usable.tar.gz`（即装即用的 OpenWrt Rootfs 预装环境）
  - `system_2g.img` / 分区表基线文件

---

## ⚠️ 免责声明

本项目仅供嵌入式技术交流与软路由技术研发验证使用。刷写底层分区与修改系统启动流程存在一定风险，请务必提前通过 EDL 9008 全量备份关键分区（尤其是 `lun0`~`lun5` 的 EFS/基带数据）。
