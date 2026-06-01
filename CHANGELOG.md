# Changelog

All notable changes to EasyBBR3 will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2.3.0] - 2026-06-01

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

[2.3.0]: https://github.com/xx2468171796/EasyBBR3/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/xx2468171796/EasyBBR3/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/xx2468171796/EasyBBR3/compare/v2.0.1...v2.1.0
[2.0.1]: https://github.com/xx2468171796/EasyBBR3/releases/tag/v2.0.1
