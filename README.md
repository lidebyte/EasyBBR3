# EasyBBR3

> 一键安装 BBR/BBR2/BBR3 拥塞控制 + 全面网络调优脚本，适用于 Linux VPS。  
> 作者：孤独制作 · v2.4.0 · MIT License

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.4.0-green.svg)](CHANGELOG.md)

---

## ✨ 最近更新 (v2.4.0)

> 完整记录见 [CHANGELOG.md](CHANGELOG.md)。本次为自 v2.2.0 起的一次全面维护，已在 Ubuntu 24.04 + XanMod 真机验证。

- **修复严重 Bug**：sysctl 配置加载顺序冲突（重启后调优被覆盖）、卸载残留、BusyBox 多值参数兼容、内核验证误判。
- **安全加固**：XanMod 内核走 https 并校验 SHA256；移除裸 `curl | bash`；ELRepo 导入 GPG 公钥；临时文件用 `mktemp`。
- **2026 兼容**：支持 Debian 13 / Ubuntu 24.04+ 的 deb822 `.sources` 换源；BBRv3 标注诚实化（仅 XanMod 提供 BBRv3）。
- **更稳健**：第三方 APT 源损坏时不再中断主流程（明确提示，可一键禁用）；基础源故障才停止并提示换源。
- **更灵活**：LINE 域名清单可通过 `/etc/bbr3-line-domains.conf` 自定义。
- **文档**：重写本 README，新增 LICENSE / CHANGELOG / .gitignore / .gitattributes。

---

## ⚠️ 免责声明

本脚本会修改 **内核参数（sysctl）**、**iptables 规则** 及可选地 **更换系统内核**，操作不可逆且影响系统稳定性。

- 仅在您 **完全控制** 的 VPS / 服务器上使用。
- 生产环境请先在测试机验证，并提前做好快照备份。
- 作者不对任何数据丢失、服务中断或安全问题承担责任。

---

## 快速开始

### 一键运行（推荐）

```bash
wget -qO- https://raw.githubusercontent.com/xx2468171796/EasyBBR3/main/easybbr3.sh | sudo bash
```

### 手动下载后运行

```bash
wget -O easybbr3.sh https://raw.githubusercontent.com/xx2468171796/EasyBBR3/main/easybbr3.sh
chmod +x easybbr3.sh
sudo bash easybbr3.sh
```

> 需要 **root** 权限，建议直接以 root 身份运行或使用 `sudo`。

---

## 功能特性

| 类别 | 功能 |
|------|------|
| 拥塞控制 | BBR / BBR2 / BBR3 安装与一键切换 |
| 内核安装 | XanMod（真正的 BBRv3）、Liquorix、Ubuntu HWE、ELRepo kernel-ml |
| 代理调优向导 | 自动检测带宽 / RTT / MTU，生成最优 sysctl 配置 |
| 智能自动优化 | 场景预设：balanced / communication / video / concurrent / speed / performance |
| 应用专项优化 | LINE / Google / Apple / Meta / X (Twitter) / Telegram |
| 抗丢包模式 | 针对中转 / 跨境高丢包线路（5–15% 丢包）专项调优 |
| 队列规则 | fq / fq_codel / fq_pie / cake 切换与对比建议 |
| 时段自动优化 | 高峰时段（19:00–02:00）自动应用专项配置 |
| 验证与健康评分 | 优化效果验证、健康评分报告 |
| 备份与恢复 | sysctl 配置备份、一键回滚 |
| 卸载回滚 | 彻底卸载所有优化，恢复系统默认 |
| CLI 非交互模式 | 支持全参数化调用，适合自动化脚本 |
| PVE Tools | Proxmox VE 辅助工具 |
| 脚本自更新 | 一键更新至最新版本 |
| bbr3 快捷命令 | 安装后可用 `bbr3` 命令快速调用 |

---

## 支持的系统

| 发行版 | 版本 | 备注 |
|--------|------|------|
| Debian | 10 / 11 / 12 / 13 (Trixie) | 完整支持 |
| Ubuntu | 16.04 – 24.04 | 完整支持；26.04 实验性支持 |
| RHEL / CentOS | 8 / 9 | CentOS 7/8 已 EOL，仅尽力支持 |
| Rocky Linux | 8 / 9 / 10 | 完整支持 |
| AlmaLinux | 8 / 9 / 10 | 完整支持 |

> 第三方内核（XanMod / Liquorix / ELRepo）**仅支持 x86_64** 架构。

---

## 环境要求

- 操作系统：上表所列发行版之一
- 权限：**root**（或 `sudo`）
- Shell：**Bash 4.0+**
- 网络：可访问 GitHub / 内核源（支持镜像加速）
- BBR3：**必须安装 XanMod 内核**（见下方说明）

---

## 主菜单选项

```
1. 代理智能调优      (推荐翻墙用户！含 10 步向导 + 一键自动优化) ⭐
2. 安装新内核        (XanMod 获取 BBRv3 / Liquorix·HWE·ELRepo 为 BBR v1)
3. 验证优化状态      (检测优化是否生效 + 健康评分)
4. 查看当前状态
5. 备份 / 恢复配置
6. 时间自动优化      (晚高峰 19:00–02:00 自动切换激进模式)
7. 卸载配置          (彻底清理 sysctl / cron / systemd / iptables)
8. 安装快捷命令 bbr3
9. 更新脚本          (从 GitHub 获取最新版本)
10. PVE Tools 一键脚本
0. 退出
```

### 「1. 代理智能调优」进入的场景配置子菜单

```
1)  代理智能调优      10 步向导，自动生成最优代理/VPN 配置  ⭐
2)  智能自动优化      检测带宽/RTT 并应用最优配置
3)  查看当前优化
4)  验证优化状态
5)  恢复默认配置
6)  均衡模式          平衡延迟与吞吐，适合一般用途
7)  通信模式          低延迟，适合实时通信/游戏
8)  视频模式          大文件传输，适合视频流/下载
9)  并发模式          高并发，适合 Web/API 服务器
10) 极速模式          最大化吞吐量，适合大带宽服务器
11) 性能模式          全面性能优化
12) 应用优化          LINE / Google / Apple / Meta / X / Telegram
13) 抗丢包            中转机 / 高丢包环境专用
14) 队列切换          fq / fq_codel / fq_pie / cake
0)  返回主菜单
```

---

## CLI 参数（非交互模式）

| 参数 | 说明 |
|------|------|
| `--algo <bbr\|bbr2\|bbr3>` | 设置拥塞控制算法 |
| `--qdisc <fq\|fq_codel\|fq_pie\|cake>` | 设置队列规则 |
| `--install-kernel <xanmod\|liquorix\|hwe\|elrepo>` | 安装指定内核 |
| `--apply` / `--no-apply` | 是否立即应用 sysctl |
| `--mirror <url>` | 指定下载镜像 |
| `--non-interactive` | 非交互模式（禁止提示） |
| `--status` | 显示当前网络优化状态 |
| `--auto` | 运行智能自动优化 |
| `--smart` | 运行代理智能调优向导 |
| `--detect` | 检测带宽 / RTT / MTU |
| `--verify` | 验证优化效果 |
| `--health` | 输出健康评分报告 |
| `--check-bbr3` | 检测 BBRv3 是否激活 |
| `--proxy-tune` | 运行代理调优（非交互） |
| `--uninstall` | 卸载所有优化 |
| `--install` | 安装（非交互默认配置） |
| `--debug` | 开启调试输出 |
| `--version` | 显示版本号 |
| `--help` | 显示帮助信息 |

### 示例

```bash
# 切换到 BBR3 算法（需已安装 XanMod 内核）
sudo bash easybbr3.sh --algo bbr3 --non-interactive

# 检测当前 BBRv3 状态
sudo bash easybbr3.sh --check-bbr3

# 一键运行智能自动优化（balanced 场景）
sudo bash easybbr3.sh --auto --non-interactive
```

---

## 关于 BBR3 的诚实说明

> **只有 XanMod 内核才能真正使用 BBRv3。**

- **XanMod 内核**：将 Google 的 BBRv3 补丁以模块名 `bbr` 注册进内核。`--check-bbr3` 检测到 `BBR3_ACTIVE=YES` 时，说明您正在运行 XanMod 且 BBRv3 处于激活状态。
- **Liquorix / ELRepo kernel-ml / Ubuntu HWE**：均为主线内核，内置的是 **BBRv1**，即使模块名也叫 `bbr`，实质上不是 BBRv3。
- **如何确认**：安装 XanMod 内核后运行 `sudo bash easybbr3.sh --check-bbr3`，输出 `BBR3_ACTIVE=YES` 即为真正的 BBRv3。

---

## 作者与联系方式

- **作者**：孤独制作
- **GitHub**：[https://github.com/xx2468171796/EasyBBR3](https://github.com/xx2468171796/EasyBBR3)
- **Telegram 群组**：[https://t.me/+RZMe7fnvvUg1OWJl](https://t.me/+RZMe7fnvvUg1OWJl)

---

## License

[MIT License](LICENSE) © 2024-2026 孤独制作
