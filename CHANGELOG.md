# Changelog

All notable changes to EasyBBR3 will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2.4.3] - 2026-06-08

### Changed
- **一次性引导成功提示大改**：内核一次性引导安全模式配置成功后的末尾提示，从一行容易被忽略的
  "再次运行会自动设为默认"，改为醒目的分步骤框：清楚区分①当前是一次性引导、新内核【还没转正】、
  默认仍是旧内核；②重启后新内核能正常起来需再跑一次脚本（或用菜单项）才转正为永久默认；
  ③不转正则下次重启退回旧内核；④起不来则断电自动回滚、锁不死。避免用户重启后忘记回来转正。

### Added
- **新增手动转正菜单项**：主菜单新增「🔧 固定/转正当前内核为默认 (一次性引导后用此项确认)」，
  调用新函数 `pin_current_kernel()`，可在没有 pending 标记时也把当前运行内核固定为 GRUB 永久默认，
  并自动清理一次性引导待确认标记。

## [2.4.2] - 2026-06-01

### Changed
- **真 BBRv3 校验铁证化**：`kernel_has_bbr3` 改用 `tcp_bbr` 模块自报的 `version` 字段判定
  （`modinfo tcp_bbr` → `version: 3`，对 builtin 模块同样有效），只有模块版本 ≥3 才认定为真 BBRv3。
  这能可靠区分"真 BBRv3"与"被冒充的 BBR v1"，不再仅凭内核名是否含 xanmod 猜测。
- `--check-bbr3` 增加 `BBR_MODULE_VERSION=N` 输出；验证报告显示"✅ 真 BBRv3 已启用 (tcp_bbr 模块 version=3)"。
- 已在实机验证：XanMod `6.17.10-x64v3-xanmod1` → 模块 version=3 → 判定为真 BBRv3。

## [2.4.1] - 2026-06-01

### Changed
- 内核安装简化为**仅 XanMod**（它是唯一提供 BBRv3 的内核）：Debian/Ubuntu 直接安装/更新到
  **最新版** XanMod（按 CPU 自动选 x64v1/v2/v3），不再在菜单里列 Liquorix/HWE；已是 XanMod
  时会提示"继续将更新到最新版"。
- RHEL/CentOS 系明确提示 XanMod 不支持，并可选改用 ELRepo kernel-ml（仍保留，CLI `--install-kernel`
  也仍支持 liquorix/hwe/elrepo）。

## [2.4.0] - 2026-06-01

> 自 v2.2.0 起的一次全面维护：修复会影响系统行为的严重 Bug、加固内核/脚本下载安全、
> 适配 2026 年的发行版（deb822 / 新内核），并补齐文档与可配置项。全部改动已在
> Ubuntu 24.04 + XanMod 真机验证。

### Fixed
- **C1** sysctl 配置文件加载顺序冲突：配置改用 90–94 数字前缀编码加载优先级，确保附加优化（抗丢包/LINE/应用/qdisc）能正确覆盖基础配置；并新增 `migrate_legacy_configs` 自动迁移旧版 `99-*` 文件（已在 Ubuntu 24.04 实机验证）
- **C2** 卸载残留：`do_uninstall` 现彻底清理全部 sysctl 片段（含旧版）、cron 时段任务、bbr3-line-warmup systemd 服务/定时器及 LINE/各应用的 iptables QoS 链（实机验证）
- 时段优化配置迁出 `/etc/sysctl.d`（改放 `/var/lib/easybbr3`），避免开机被 `sysctl --system` 无条件加载而强制进入某一模式；并增加 `@reboot` cron 保证开机即按时段生效
- BusyBox sysctl 兼容：逐行应用时规范化 `key=val`，避免多值参数（tcp_rmem 等）在 BusyBox sysctl 上被整行拒绝而静默失效
- 内核验证锚定匹配：GRUB 内核检测由裸子串匹配改为锚定 `vmlinuz-`/`kernel-` 路径，避免误报"验证通过"
- APT 更新容错：`apt-get update` 因残留的第三方源（如旧 xanmod 源）报错时不再整体失败/中断主流程——
  按"出错源位于哪个文件"区分基础系统源与第三方源：仅第三方源失败则警告并继续（交互模式可一键禁用），
  基础系统源失败才停止并给出换源/检查网络的明确提示（已在 Ubuntu 24.04 实机验证两种情况）

### Security
- XanMod 直接下载：传输改用 https，并依据仓库元数据对内核 `.deb` 做 SHA256 完整性校验后再 `dpkg -i`
- 移除 Liquorix/PVE 的裸 `curl | bash`：改为下载到临时文件 → 校验为合法 shell 脚本（shebang + `bash -n`）→ 再执行
- ELRepo：安装 release RPM 前先 `rpm --import` 官方 GPG 公钥
- nexttrace：改用 `mktemp` 并校验下载内容为 ELF 可执行文件后再安装
- 临时文件统一改用 `mktemp`，避免 `/tmp` 固定路径的符号链接竞争
- 新增 `--qdisc` 取值校验，防止非法值写入持久化 sysctl 配置

### Changed
- deb822 格式支持：兼容 Debian 13 / Ubuntu 24.04+ 的 `.sources` APT 源格式，换源时直接重写权威 `.sources` 并保留 `Signed-By`（已在 Ubuntu 24.04 实机验证）
- CentOS 7/8 已 EOL：明确提示 base 源需迁移至 vault.centos.org（不自动改写以免误伤）
- codename 默认值更新为 trixie / noble（无法解析时的合理回退）
- BBR3 标注诚实化：内核菜单与状态明确区分 XanMod（真 BBRv3）与主线内核（仅 BBRv1）
- `detect_cpu_level`：统一 x86-64-v2 判定基线为 SSE4.2（修正内联副本误用 AVX 的问题）
- LINE 域名清单改为可由 `/etc/bbr3-line-domains.conf` 配置（不存在时用内置清单自动初始化，支持注释/增删），
  满足 openspec 中"域名清单可配置"的需求（已实机验证）；并更新 openspec 验证勾选项
- HWE 菜单：移除已 EOL 的 16.04/18.04，加入 26.04
- 支持被 `source` 而不自动执行 `main`（便于测试与函数复用）
- 修正 `usage()` 中错误的安装 URL（`bbr.sh` → `easybbr3.sh`）

### Documentation
- 重写 README.md：中文说明，准确反映功能、系统支持、BBR3 实际情况
- 新增 LICENSE（MIT，2024-2026 孤独制作）
- 新增 .gitignore
- 新增 .gitattributes（强制 LF 行尾，防止 Windows CRLF 损坏脚本）
- 新增 CHANGELOG.md

---

## [2.2.0] - 2025

### Changed
- 大规模 Bug 修复与兼容性更新
- grub-reboot 安全模式：内核更新后通过 grub-reboot 一次性引导新内核，失败自动回退
- 修复 `wc -l` 输出解析导致的语法错误
- 改进磁盘检测与内核支持检查逻辑

---

## [2.1.0] - 2024

### Added
- 时段自动优化：高峰时段（19:00–02:00）自动切换专项配置
- 带宽检测改进：优先使用 `ethtool`，增加 sysfs 回退（适配 KVM/虚拟化环境），支持用户手动输入
- 代理智能调优向导：自动检测带宽 / RTT / MTU 并生成最优配置
- TCP Keepalive 与路由缓存优化
- conntrack / netdev / ARP 优化参数

### Changed
- 脚本自更新功能集成至主菜单
- 场景预设（smart_auto_optimize）整合进场景配置菜单，简化主菜单结构
- 内核安装 UX 改进，预检更完善

---

## [2.0.1] - 2024

### Added
- 队列规则切换模块：fq / fq_codel / fq_pie / cake，含对比建议
- 抗丢包模式：针对中转/跨境高丢包线路（5–15%）专项调优
- 应用专项优化：Google / Apple / Meta / X(Twitter) / Telegram
- LINE 优化模块：45+ 域名（含 CDN、VOIP、STUN/TURN），大文件传输修复（64MB TCP 缓冲区）

### Fixed
- LINE 大文件传输 99% 失败问题：激进 TCP 重试、缩短 keepalive、FIN 超时优化

---

[2.4.2]: https://github.com/xx2468171796/EasyBBR3/compare/v2.4.1...v2.4.2
[2.4.1]: https://github.com/xx2468171796/EasyBBR3/compare/v2.4.0...v2.4.1
[2.4.0]: https://github.com/xx2468171796/EasyBBR3/compare/v2.2.0...v2.4.0
[2.2.0]: https://github.com/xx2468171796/EasyBBR3/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/xx2468171796/EasyBBR3/compare/v2.0.1...v2.1.0
[2.0.1]: https://github.com/xx2468171796/EasyBBR3/releases/tag/v2.0.1
