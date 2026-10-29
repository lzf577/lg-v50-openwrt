# LG V50 OpenWrt 接管 · 操作流程(定稿)

副指挥官 · 2026-10-27 · 取代此前零散的指令 01 至 06 与各类口头补充

## 一、目标与路线

**目标**:让 OpenWrt 跑在 LG V50 上,并用手机原生 Wi-Fi 开出热点。

**路线**:不再替换启动链、不再赌内核自己拉起 OpenWrt。保留 Android 12 内核与驱动,拿到 root 后,把 `system_b` 里的 OpenWrt 当作用户态,在独立的 PID 命名空间里运行。

**当前状态**:基线已还原,Android 12 正常开机,`verifiedbootstate=orange`,`adb shell` 为 uid 2000,没有 root。`system_b`(`/dev/block/sda25`)里已有 LEDE 镜像。

## 二、规则(定案)

**绿区,可自由刷写,无需审批,刷后回报结果**:`boot_a`、`boot_b`、`system_a`、`system_b`、`vbmeta_a`、`vbmeta_b`。

**红区,没有备份一律不碰**:`persist`、`modemst1`/`modemst2`、`fsg`、`fsc`、`devinfo`、`xbl*`、`abl*`、`tz*`、`hyp*`、`keymaster*`、`devcfg*`、`aop*`、`gpt`、`userdata`。

**三条永久禁令**:

1. 禁止在 Fastboot 下刷写,唯一刷写通道是 9008。
2. 禁止整套执行 `rawprogram0` 至 `rawprogram6.xml`(整机恢复专用)。
3. 每次只改一处;失败后先回到基线,不叠加修改。

## 三、阶段 0:一次性准备(工兵,约 15 分钟)

1. 把以下文件再复制一份到另一块盘或网盘:`lun0/persist.bin`、`lun4/devinfo.bin`、`lun5/` 全部、`lun1/`、`lun2/`、`lun3/` 全部。
2. 把工程根目录里历史试验用的 `rawprogram_flash_*.xml`、`rawprogram_swap_systems.xml`、旧的 `boot_v50_*.img` 挪进 `_archive_old/`,避免误用。尤其是 `rawprogram_flash_full_physical.xml`。
3. 只保留 `baseline_restore/` 作为恢复入口。

**通过标准**:第二份备份已核对 sha256;`_archive_old/` 已建立。

## 四、阶段 1:取得 root

### 总指挥的操作(约 10 分钟,不需要 root)

1. 从官方 GitHub(`github.com/topjohnwu/Magisk/releases`)下载 Magisk 稳定版 v30.7 的 APK,不要用预览版。
2. `adb install Magisk-v30.7.apk`
3. `adb push v50_backup/dump/lun4/boot_a.bin /sdcard/Download/boot_a.img`(用副本,原文件不得改动)
4. 手机上打开 Magisk,点“安装”,选“选择并修补一个文件”,选 `boot_a.img`,开始。其余选项保持默认,不要勾选 Recovery Mode。
5. `adb pull /sdcard/Download/magisk_patched-*.img .`,把文件改名为 `magisk_boot_a.img`,记录字节大小与 sha256。

### 工兵的操作

1. 复制 `baseline_restore/rawprogram_restore_boots.xml`,**只保留 `boot_a` 那一行**,删掉 `boot_b`;把 `filename` 改为 `magisk_boot_a.img`;把 `num_partition_sectors` 改为补丁镜像大小向上取整到 4096 字节的扇区数,且不得超过 24576。`start_sector` 保持 118538,LUN 保持 4。
2. 通过 9008 烧录该 XML。**`boot_b` 不动,保持原厂**,这是退路。
3. 设备重启进入 Android 后,首次打开 Magisk,若提示“需要额外设置”,点确定并按提示重启一次。

### 通过标准

- `adb shell su -c id` 输出 `uid=0`
- `getprop ro.boot.verifiedbootstate` 仍为 `orange`
- Android 桌面正常

### 失败处理

- 起不来:ABL 通常会回退到 `boot_b`;用 `baseline_restore/boot_a.bin` 通过 9008 单刷 `boot_a` 即可还原。
- 没有 su:回报 Magisk 日志,不要自行换方案。

## 五、阶段 2:连续作战(工兵,拿到 root 后一次跑完)

以下四步连续执行,每步日志都写入 `/data/local/tmp/`,全部结束后一并回报,不必逐步等批准。某一步失败就停在该步,回报日志,不得跳步,不得叠加修改。

### 步骤 2.1:只读取证

```sh
su -c '
getprop ro.boot.slot_suffix
cat /proc/cmdline
uname -a
getenforce
ls -l /dev/watchdog*
ls -l /sys/fs/pstore
cat /sys/block/sda/queue/logical_block_size
find /proc/device-tree/firmware/android -type f | while read f; do echo "== $f"; cat "$f"; echo; done
getprop | grep init.svc | grep -iE "wifi|wlan|cnss|netd|wificond|supplicant|hostapd"
' > /data/local/tmp/evidence.txt 2>&1
```

在工程目录执行:`grep -n -i ramoops extracted_v50_boot/v50_dts.dts`

### 步骤 2.2:`system_b` 只读验证

```sh
su -c '
mkdir -p /data/local/tmp/mnt_b
mount -t ext4 -o ro,noload /dev/block/sda25 /data/local/tmp/mnt_b
ls -l /data/local/tmp/mnt_b/sbin/init /data/local/tmp/mnt_b/bin/busybox
ls -l /data/local/tmp/mnt_b/lib | grep -i -E "ld-musl|libc"
mkdir -p /data/local/tmp/chk
cp /data/local/tmp/mnt_b/bin/busybox /data/local/tmp/chk/
chmod 644 /data/local/tmp/chk/*
umount /data/local/tmp/mnt_b
'
```

PC 端:`adb pull /data/local/tmp/chk ./chk`,然后 `file chk/busybox`、`readelf -h chk/busybox | grep -E 'Class|Machine'`。

**通过标准**:架构为 AArch64,动态链接器文件存在。否则停止,回报。

### 步骤 2.3:chroot 冒烟测试

```sh
su -c '
M=/data/local/tmp/mnt_b
mount -t ext4 -o ro,noload /dev/block/sda25 $M
mount -o bind /dev $M/dev
mount -t proc proc $M/proc
mount -t sysfs sysfs $M/sys
chroot $M /bin/sh -c "uname -a; ls /; cat /etc/openwrt_release"
umount $M/sys; umount $M/proc; umount $M/dev; umount $M
'
```

失败时采集:`dmesg | grep -i avc | tail -50`、`logcat -d | grep -i 'avc: denied' | tail -50`。

### 步骤 2.4:在独立 PID 命名空间拉起 OpenWrt 的 init

先确认:`which unshare chroot nohup`。`unshare` 不存在则停止并回报。

```sh
su -c '
M=/data/local/tmp/lede
mkdir -p $M
mount -t ext4 -o rw /dev/block/sda25 $M
mount -o bind /dev $M/dev
mount -t sysfs sysfs $M/sys
mkdir -p $M/vendor && mount -o bind /vendor $M/vendor
nohup unshare -p -f -m chroot $M /bin/sh -c "
  mount -t proc proc /proc
  mount -t tmpfs tmpfs /tmp
  mount -t tmpfs tmpfs /run
  /usr/sbin/dropbear -R -B -p 127.0.0.1:2222 &
  exec /sbin/init
" > /data/local/tmp/lede_takeover.log 2>&1 &
'
```

PC 端验证:`adb forward tcp:2222 tcp:2222`,`ssh -p 2222 root@127.0.0.1`,登录后执行 `ubus list` 与 `ps`。

**通过标准**:能 ssh 进入 OpenWrt,`ubus list` 有输出。

**降级**:若 OpenWrt 标准的 preinit 在 chroot 内失败,不要改镜像。回报日志,由副指挥研判是否改为直接运行 `procd`。

### 阶段 2 的回报内容

`evidence.txt`、`file`/`readelf` 输出、2.3 与 2.4 的完整日志、`lede_takeover.log`、`dmesg | tail -100`,以及每一步的通过或失败结论。

## 六、阶段 3:Wi-Fi 接管与热点

**前提**:阶段 2 全部通过。

1. 记录当前网卡:`ip link`、`iw dev`(chroot 内外各一次),并确认 chroot 内能看到 `/vendor/firmware`。
2. 停止 Android 侧的 Wi-Fi 服务:`wificond`、Wi-Fi HAL、`wpa_supplicant` 一类。**严禁停止**:`adbd`、`servicemanager`、`hwservicemanager`、`vendor.cnss-daemon`、任何 `vendor.qti.*` 基础服务、`vold`、`logd`。每停一个,先确认 `adb devices` 仍在线。
3. 在 OpenWrt 内用 `v50_assets/wifi_configs/` 的配置,以 `hostapd`(`driver=nl80211`)起一个测试热点:WPA2-PSK,信道 36 或 1。
4. 另一台设备连接热点,验证获取 IP、能 ping 通网关。

**通过标准**:热点可被搜索并连接,终端获得 IP。

**失败处理**:`adb` 失联或设备重启,则重启回 Android 重来。`hostapd` 报驱动不支持或接口缺失,回报 `hostapd` 日志与 `dmesg | grep -i -E 'wlan|cnss|qca'`,由副指挥研判,不要自行调整驱动参数。

## 七、阶段 4:开机自启(阶段 3 成功后再做)

用 Magisk 的 `/data/adb/service.d/` 放一个启动脚本,在 Android 开机完成后自动执行阶段 2.4 与阶段 3 的命令。**不需要再刷 boot**。出问题时删除该脚本即可恢复。具体脚本由副指挥在阶段 3 成功后出方案。

## 八、退路速查

| 情况 | 处理 |
| :-- | :-- |
| 补丁的 `boot_a` 起不来 | ABL 回退 `boot_b`;或用 `baseline_restore/boot_a.bin` 通过 9008 单刷 `boot_a` |
| 系统异常、需要整体回到原厂 | 用 `baseline_restore/` 里的 XML 刷回 `boot_a`、`boot_b`、`system_a` |
| OpenWrt 拉起后手机卡死 | 长按电源强制重启;OpenWrt 在命名空间里,重启后 Android 恢复正常 |
| 自启脚本导致异常 | 通过 Magisk 安全模式或 9008 恢复,删除 `/data/adb/service.d/` 下的脚本 |

## 九、角色分工

- **总指挥**:阶段 1 的 Magisk 补丁,最终裁决。
- **工兵**:所有刷写与命令执行,按阶段回报。
- **副指挥**:事后审日志,卡住时研判方向,阶段 3 之后出自启方案。
