#!/usr/bin/env bash
#===============================================================================
#
#          FILE: bbr.sh
#
#         USAGE: sudo ./bbr.sh [options]
#                wget -qO- https://raw.githubusercontent.com/xx2468171796/bbr3/main/bbr.sh | sudo bash
#
#   DESCRIPTION: BBR3 一键安装脚本 - 支持 BBR/BBR2/BBR3 TCP 拥塞控制
#                支持 Debian 10-13, Ubuntu 16.04-24.04, RHEL/CentOS 7-9
#
#       OPTIONS: --help 查看完整帮助
#  REQUIREMENTS: root 权限, bash 4.0+
#        AUTHOR: 孤独制作
#       VERSION: 2.0.1
#       CREATED: 2024
#      REVISION: 2024-11-29
#       LICENSE: MIT
#      TELEGRAM: https://t.me/+RZMe7fnvvUg1OWJl
#        GITHUB: https://github.com/xx2468171796
#
#   功能说明: BBR3 TCP 拥塞控制一键安装与优化脚本
#             - 支持多种场景模式（代理/视频/游戏等）
#             - 自动检测最佳算法和参数
#             - 内核安装验证与回滚机制
#
#   其他工具: PVE Tools 一键脚本
#             wget https://raw.githubusercontent.com/xx2468171796/pvetools/main/pvetools.sh
#             chmod +x pvetools.sh && ./pvetools.sh
#
#===============================================================================

set -uo pipefail

# 注意：不使用 set -e，因为某些命令预期可能失败（如 ping、modprobe 等）
# 我们通过显式检查返回值来处理错误

# Bash 版本检查
if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
    echo "[错误] 此脚本需要 Bash 4.0 或更高版本" >&2
    echo "当前版本: ${BASH_VERSION}" >&2
    exit 1
fi

#===============================================================================
# 版本信息
#===============================================================================
readonly SCRIPT_VERSION="2.0.1"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
readonly GITHUB_URL="https://github.com/xx2468171796"
readonly GITHUB_RAW="https://raw.githubusercontent.com/xx2468171796/bbr3/main"

#===============================================================================
# 颜色定义
#===============================================================================
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly BOLD='\033[1m'
    readonly DIM='\033[2m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly PURPLE=''
    readonly CYAN=''
    readonly WHITE=''
    readonly BOLD=''
    readonly DIM=''
    readonly NC=''
fi

#===============================================================================
# 图标定义
#===============================================================================
readonly ICON_OK="✓"
readonly ICON_FAIL="✗"
readonly ICON_WARN="⚠"
readonly ICON_INFO="ℹ"
readonly ICON_ARROW="➜"
readonly ICON_STAR="★"
readonly ICON_GEAR="⚙"
readonly ICON_NET="🌐"
readonly ICON_DISK="💾"
readonly ICON_CPU="🖥"

#===============================================================================
# 配置文件路径
#===============================================================================
readonly SYSCTL_FILE="/etc/sysctl.d/99-bbr.conf"
readonly BACKUP_DIR="/etc/sysctl.d/bbr-backups"
readonly LOG_FILE="/var/log/bbr3-script.log"
readonly LOG_MAX_SIZE=1048576  # 1MB

#===============================================================================
# 全局变量 - 系统信息
#===============================================================================
DIST_ID=""
DIST_VER=""
DIST_CODENAME=""
ARCH_ID=""
VIRT_TYPE=""
KERNEL_VER=""
PKG_MANAGER=""

#===============================================================================
# 全局变量 - 预检状态
#===============================================================================
PRECHECK_ROOT=0
PRECHECK_OS=0
PRECHECK_ARCH=0
PRECHECK_VIRT=0
PRECHECK_NETWORK=0
PRECHECK_DNS=0
PRECHECK_DISK=0
PRECHECK_DEPS=0
PRECHECK_UPDATE=0
declare -a PRECHECK_MESSAGES=()

#===============================================================================
# 全局变量 - 配置
#===============================================================================
CURRENT_ALGO=""
CURRENT_QDISC=""
AVAILABLE_ALGOS=""
CHOSEN_ALGO=""
CHOSEN_QDISC=""
APPLY_NOW=0
NON_INTERACTIVE=0
DEBUG_MODE=0
PIPE_MODE=0
MENU_CHOICE=""

#===============================================================================
# 全局变量 - 缓冲区调优
#===============================================================================
TUNE_RMEM_MAX=""
TUNE_WMEM_MAX=""
TUNE_TCP_RMEM_HIGH=""
TUNE_TCP_WMEM_HIGH=""

#===============================================================================
# 全局变量 - 场景模式
#===============================================================================
SCENE_MODE=""  # balanced, communication, video, concurrent, speed
SCENE_RECOMMENDED=""  # 推荐的场景模式
SERVER_CPU_CORES=0
SERVER_MEMORY_MB=0
SERVER_BANDWIDTH_MBPS=0
SERVER_TCP_CONNECTIONS=0

#===============================================================================
# 全局变量 - 镜像源
#===============================================================================
MIRROR_REGION=""  # cn/intl/auto
MIRROR_URL=""
USE_CHINA_MIRROR=0

#===============================================================================
# 国内镜像源列表
#===============================================================================
declare -A MIRRORS_CN=(
    ["tsinghua"]="https://mirrors.tuna.tsinghua.edu.cn"
    ["aliyun"]="https://mirrors.aliyun.com"
    ["ustc"]="https://mirrors.ustc.edu.cn"
    ["huawei"]="https://repo.huaweicloud.com"
)

#===============================================================================
# 支持的系统版本
#===============================================================================
readonly SUPPORTED_DEBIAN="10 11 12 13"
readonly SUPPORTED_UBUNTU="16.04 18.04 20.04 22.04 24.04"
readonly SUPPORTED_RHEL="7 8 9"

#===============================================================================
# 必要依赖列表
#===============================================================================
readonly REQUIRED_DEPS="curl wget gnupg ca-certificates"


#===============================================================================
# UI 输出函数
#===============================================================================

# 显示 ASCII Logo
print_logo() {
    echo -e "${CYAN}"
    cat << 'EOF'
    ____  ____  ____  _____    _____           _       __
   / __ )/ __ )/ __ \/__  /   / ___/__________(_)___  / /_
  / __  / __  / /_/ /  / /    \__ \/ ___/ ___/ / __ \/ __/
 / /_/ / /_/ / _, _/  / /    ___/ / /__/ /  / / /_/ / /_
/_____/_____/_/ |_|  /_/    /____/\___/_/  /_/ .___/\__/
                                            /_/
EOF
    echo -e "${NC}"
    echo -e "${DIM}Version ${SCRIPT_VERSION} | 作者: 孤独制作${NC}"
    echo -e "${DIM}电报群: https://t.me/+RZMe7fnvvUg1OWJl${NC}"
    echo -e "${DIM}PVE工具: https://github.com/xx2468171796/pvetools${NC}"
    echo
}

# 显示带边框的标题
print_header() {
    local title="$1"
    local width=60
    local title_len=${#title}
    local padding=$(( (width - title_len - 2) / 2 ))
    local right_padding=$((width - padding - title_len))
    
    echo
    # 使用更兼容的方式生成重复字符
    local border_line=""
    local i
    for ((i=0; i<width; i++)); do border_line+="═"; done
    
    local left_spaces=""
    for ((i=0; i<padding; i++)); do left_spaces+=" "; done
    
    local right_spaces=""
    for ((i=0; i<right_padding; i++)); do right_spaces+=" "; done
    
    echo -e "${CYAN}╔${border_line}╗${NC}"
    echo -e "${CYAN}║${NC}${left_spaces}${BOLD}${title}${NC}${right_spaces}${CYAN}║${NC}"
    echo -e "${CYAN}╚${border_line}╝${NC}"
    echo
}

# 显示分隔线
print_separator() {
    local line=""
    local i
    for ((i=0; i<60; i++)); do line+="─"; done
    echo -e "${DIM}${line}${NC}"
}

# 信息输出
print_info() {
    echo -e "${BLUE}${ICON_INFO}${NC} $*"
}

# 成功输出
print_success() {
    echo -e "${GREEN}${ICON_OK}${NC} $*"
}

# 警告输出
print_warn() {
    echo -e "${YELLOW}${ICON_WARN}${NC} $*"
}

# 错误输出
print_error() {
    echo -e "${RED}${ICON_FAIL}${NC} $*" >&2
}

# 步骤输出
print_step() {
    echo -e "${PURPLE}${ICON_ARROW}${NC} $*"
}

# 调试输出
print_debug() {
    if [[ $DEBUG_MODE -eq 1 ]]; then
        echo -e "${DIM}[DEBUG] $*${NC}" >&2
    fi
}

# 显示格式化菜单
print_menu() {
    local title="$1"
    shift
    local items=("$@")
    
    echo
    echo -e "${BOLD}${title}${NC}"
    print_separator
    
    local i=1
    for item in "${items[@]}"; do
        echo -e "  ${CYAN}${i})${NC} ${item}"
        ((i++))
    done
    
    echo -e "  ${CYAN}0)${NC} 返回/退出"
    print_separator
}

# 显示对齐表格
print_table() {
    local -n data=$1
    local col1_width=${2:-20}
    local col2_width=${3:-40}
    
    for key in "${!data[@]}"; do
        printf "%b%-${col1_width}s%b : %s\n" "$CYAN" "$key" "$NC" "${data[$key]}"
    done
}

# 显示键值对
print_kv() {
    local key="$1"
    local value="$2"
    local width=${3:-15}
    printf "  %b%-${width}s%b : %s\n" "$DIM" "$key" "$NC" "$value"
}

# 显示状态行
print_status() {
    local label="$1"
    local status="$2"
    local width=${3:-40}
    
    printf "  %-${width}s " "$label"
    case "$status" in
        ok|pass|passed|success)
            echo -e "[${GREEN}${ICON_OK} 通过${NC}]"
            ;;
        fail|failed|error)
            echo -e "[${RED}${ICON_FAIL} 失败${NC}]"
            ;;
        warn|warning)
            echo -e "[${YELLOW}${ICON_WARN} 警告${NC}]"
            ;;
        skip|skipped)
            echo -e "[${DIM}跳过${NC}]"
            ;;
        *)
            echo -e "[${status}]"
            ;;
    esac
}

# 显示进度条
show_progress() {
    local current=$1
    local total=$2
    local width=${3:-40}
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    local filled_bar="" empty_bar=""
    local i
    for ((i=0; i<filled; i++)); do filled_bar+="█"; done
    for ((i=0; i<empty; i++)); do empty_bar+="░"; done
    
    printf "\r  [%b%s%b%s] %3d%%" "$GREEN" "$filled_bar" "$NC" "$empty_bar" "$percent"
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# 确认对话框
confirm() {
    local prompt="${1:-确认继续？}"
    local default="${2:-n}"
    
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        [[ "$default" == "y" ]] && return 0 || return 1
    fi
    
    local yn_hint
    if [[ "$default" == "y" ]]; then
        yn_hint="[Y/n]"
    else
        yn_hint="[y/N]"
    fi
    
    while true; do
        echo -en "${YELLOW}${ICON_WARN}${NC} ${prompt} ${yn_hint} "
        read -r answer
        answer=${answer:-$default}
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "请输入 y 或 n" ;;
        esac
    done
}

# 读取用户输入
read_input() {
    local prompt="$1"
    local default="${2:-}"
    local result
    
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        echo "$default"
        return
    fi
    
    if [[ -n "$default" ]]; then
        echo -en "${CYAN}${ICON_ARROW}${NC} ${prompt} [${default}]: "
    else
        echo -en "${CYAN}${ICON_ARROW}${NC} ${prompt}: "
    fi
    
    read -r result
    echo "${result:-$default}"
}

# 读取菜单选择 - 结果存储在全局变量 MENU_CHOICE 中
read_choice() {
    local prompt="${1:-请选择}"
    local max="$2"
    local default="${3:-}"
    
    MENU_CHOICE=""
    
    while true; do
        if [[ -n "$default" ]]; then
            echo -en "${CYAN}${ICON_ARROW}${NC} ${prompt} [${default}]: " >&2
        else
            echo -en "${CYAN}${ICON_ARROW}${NC} ${prompt}: " >&2
        fi
        
        read -r MENU_CHOICE
        MENU_CHOICE=${MENU_CHOICE:-$default}
        
        if [[ "$MENU_CHOICE" =~ ^[0-9]+$ ]] && [[ $MENU_CHOICE -ge 0 ]] && [[ $MENU_CHOICE -le $max ]]; then
            return 0
        fi
        
        print_error "无效选择，请输入 0-${max} 之间的数字"
    done
}


#===============================================================================
# 日志模块
#===============================================================================

# 初始化日志
log_init() {
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    
    # 创建日志目录
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || true
    fi
    
    # 日志轮转
    if [[ -f "$LOG_FILE" ]]; then
        local size
        # Linux 使用 -c%s，macOS/BSD 使用 -f%z
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ $size -gt $LOG_MAX_SIZE ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
        fi
    fi
    
    # 写入日志头
    {
        echo "========================================"
        echo "BBR3 Script Log - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Version: ${SCRIPT_VERSION}"
        echo "========================================"
    } >> "$LOG_FILE" 2>/dev/null || true
}

# 写入日志
_log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    echo "[${timestamp}] [${level}] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
}

# 记录信息
log_info() {
    _log "INFO" "$@"
}

# 记录警告
log_warn() {
    _log "WARN" "$@"
}

# 记录错误
log_error() {
    _log "ERROR" "$@"
}

# 记录调试信息
log_debug() {
    if [[ $DEBUG_MODE -eq 1 ]]; then
        _log "DEBUG" "$@"
    fi
}

# 记录命令执行
log_cmd() {
    local cmd="$1"
    local output="${2:-}"
    local exit_code="${3:-0}"
    
    _log "CMD" "Command: ${cmd}"
    if [[ -n "$output" ]]; then
        _log "CMD" "Output: ${output}"
    fi
    _log "CMD" "Exit code: ${exit_code}"
}

#===============================================================================
# 错误处理
#===============================================================================

# 清理函数
cleanup() {
    # 删除临时文件
    rm -f /tmp/bbr3-*.tmp 2>/dev/null || true
    # 恢复终端设置
    stty sane 2>/dev/null || true
}

# 致命错误处理
die() {
    local msg="$1"
    local code="${2:-1}"
    
    log_error "$msg"
    print_error "$msg"
    cleanup
    exit "$code"
}

# 设置信号处理
setup_traps() {
    trap cleanup EXIT
    trap 'echo; die "用户中断操作" 130' INT
    trap 'die "收到终止信号" 143' TERM
}

# 安全执行命令（允许失败）
safe_run() {
    "$@" || true
}


#===============================================================================
# 系统检测模块
#===============================================================================

# 版本比较函数（A >= B 返回真）
version_ge() {
    local ver_a="$1"
    local ver_b="$2"
    
    # 提取纯版本号部分（去除后缀如 -xanmod1）
    ver_a="${ver_a%%[-+]*}"
    ver_b="${ver_b%%[-+]*}"
    
    # 使用 sort -V 进行版本比较
    [[ "$(printf '%s\n%s\n' "$ver_b" "$ver_a" | sort -V | head -n1)" == "$ver_b" ]]
}

# 版本比较函数（A > B 返回真）
version_gt() {
    local ver_a="$1"
    local ver_b="$2"
    
    if [[ "$ver_a" == "$ver_b" ]]; then
        return 1
    fi
    version_ge "$ver_a" "$ver_b"
}

# 检测操作系统
detect_os() {
    log_debug "开始检测操作系统..."
    
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DIST_ID="${ID:-unknown}"
        DIST_VER="${VERSION_ID:-unknown}"
        DIST_CODENAME="${VERSION_CODENAME:-}"
        
        # 尝试从 lsb_release 获取代号
        if [[ -z "$DIST_CODENAME" ]] && command -v lsb_release >/dev/null 2>&1; then
            DIST_CODENAME=$(lsb_release -sc 2>/dev/null || true)
        fi
    elif [[ -f /etc/redhat-release ]]; then
        # RHEL/CentOS 旧版本
        if grep -qi "centos" /etc/redhat-release; then
            DIST_ID="centos"
        elif grep -qi "red hat" /etc/redhat-release; then
            DIST_ID="rhel"
        else
            DIST_ID="rhel"
        fi
        DIST_VER=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
        DIST_VER="${DIST_VER%%.*}"
    elif [[ -f /etc/debian_version ]]; then
        DIST_ID="debian"
        DIST_VER=$(cat /etc/debian_version)
    else
        DIST_ID="unknown"
        DIST_VER="unknown"
    fi
    
    # 标准化发行版 ID
    DIST_ID="${DIST_ID,,}"  # 转小写
    
    # 获取内核版本
    KERNEL_VER="$(uname -r)"
    
    # 确定包管理器
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    else
        PKG_MANAGER="unknown"
    fi
    
    log_info "检测到系统: ${DIST_ID} ${DIST_VER} (${DIST_CODENAME:-N/A})"
    log_info "内核版本: ${KERNEL_VER}"
    log_info "包管理器: ${PKG_MANAGER}"
}

# 检测 CPU 架构
detect_arch() {
    log_debug "开始检测 CPU 架构..."
    
    if command -v dpkg >/dev/null 2>&1; then
        ARCH_ID=$(dpkg --print-architecture 2>/dev/null || true)
    fi
    
    if [[ -z "${ARCH_ID:-}" ]]; then
        local machine
        machine=$(uname -m)
        case "$machine" in
            x86_64|amd64)
                ARCH_ID="amd64"
                ;;
            aarch64|arm64)
                ARCH_ID="arm64"
                ;;
            armv7*|armhf)
                ARCH_ID="armhf"
                ;;
            i386|i686)
                ARCH_ID="i386"
                ;;
            *)
                ARCH_ID="$machine"
                ;;
        esac
    fi
    
    log_info "CPU 架构: ${ARCH_ID}"
}

# 检测虚拟化环境
detect_virt() {
    log_debug "开始检测虚拟化环境..."
    
    VIRT_TYPE="none"
    
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
    elif command -v virt-what >/dev/null 2>&1; then
        VIRT_TYPE=$(virt-what 2>/dev/null | head -n1 || echo "none")
    elif [[ -f /proc/1/cgroup ]]; then
        if grep -q docker /proc/1/cgroup 2>/dev/null; then
            VIRT_TYPE="docker"
        elif grep -q lxc /proc/1/cgroup 2>/dev/null; then
            VIRT_TYPE="lxc"
        fi
    fi
    
    # 检测 WSL
    if grep -qi microsoft /proc/version 2>/dev/null; then
        VIRT_TYPE="wsl"
    fi
    
    # 检测 OpenVZ
    if [[ -f /proc/vz/veinfo ]]; then
        VIRT_TYPE="openvz"
    fi
    
    [[ "$VIRT_TYPE" == "none" ]] && VIRT_TYPE="物理机/未知"
    
    log_info "虚拟化环境: ${VIRT_TYPE}"
}

# 检查是否支持安装第三方内核
is_kernel_install_supported() {
    # 仅支持 amd64 架构
    if [[ "$ARCH_ID" != "amd64" ]]; then
        return 1
    fi
    
    # 容器环境不支持
    case "$VIRT_TYPE" in
        openvz|lxc|docker|container|wsl)
            return 1
            ;;
    esac
    
    return 0
}

# 检查 Debian 版本是否支持
is_supported_debian() {
    [[ "$DIST_ID" == "debian" ]] || return 1
    
    local ver="${DIST_VER%%.*}"
    case "$ver" in
        10|11|12|13) return 0 ;;
        *) return 1 ;;
    esac
}

# 检查 Ubuntu 版本是否支持
is_supported_ubuntu() {
    [[ "$DIST_ID" == "ubuntu" ]] || return 1
    
    case "$DIST_VER" in
        16.04*|18.04*|20.04*|22.04*|24.04*) return 0 ;;
        *) return 1 ;;
    esac
}

# 检查 RHEL 系版本是否支持
is_supported_rhel() {
    case "$DIST_ID" in
        centos|rhel|rocky|almalinux|fedora) ;;
        *) return 1 ;;
    esac
    
    local ver="${DIST_VER%%.*}"
    case "$ver" in
        7|8|9) return 0 ;;
        *) return 1 ;;
    esac
}

# 检查系统是否在支持列表中
is_system_supported() {
    is_supported_debian && return 0
    is_supported_ubuntu && return 0
    is_supported_rhel && return 0
    return 1
}

# 获取系统友好名称
get_os_pretty_name() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${PRETTY_NAME:-${DIST_ID} ${DIST_VER}}"
    else
        echo "${DIST_ID} ${DIST_VER}"
    fi
}

# 版本比较函数：检查 $1 == $2
version_eq() {
    local ver1="${1:-0}"
    local ver2="${2:-0}"
    
    # 提取纯数字版本部分
    ver1="${ver1%%-*}"
    ver2="${ver2%%-*}"
    
    [[ "$ver1" == "$ver2" ]]
}


#===============================================================================
# 环境预检模块
#===============================================================================

# 检查 root 权限
precheck_root() {
    log_debug "检查 root 权限..."
    
    if [[ $(id -u) -ne 0 ]]; then
        PRECHECK_ROOT=2
        PRECHECK_MESSAGES+=("需要 root 权限运行此脚本")
        return 1
    fi
    
    PRECHECK_ROOT=0
    return 0
}

# 检测网络连通性
precheck_network() {
    log_debug "检查网络连通性..."
    
    local targets=("8.8.8.8" "114.114.114.114" "1.1.1.1")
    local connected=0
    
    for target in "${targets[@]}"; do
        if ping -c 1 -W 3 "$target" >/dev/null 2>&1; then
            connected=1
            break
        fi
    done
    
    if [[ $connected -eq 0 ]]; then
        PRECHECK_NETWORK=2
        PRECHECK_MESSAGES+=("网络连接失败，请检查网络配置")
        return 1
    fi
    
    PRECHECK_NETWORK=0
    return 0
}

# 检测 DNS 解析
precheck_dns() {
    log_debug "检查 DNS 解析..."
    
    local domains=("google.com" "baidu.com" "github.com")
    local resolved=0
    
    for domain in "${domains[@]}"; do
        if host "$domain" >/dev/null 2>&1 || nslookup "$domain" >/dev/null 2>&1 || ping -c 1 -W 3 "$domain" >/dev/null 2>&1; then
            resolved=1
            break
        fi
    done
    
    if [[ $resolved -eq 0 ]]; then
        PRECHECK_DNS=1
        PRECHECK_MESSAGES+=("DNS 解析可能存在问题，建议检查 /etc/resolv.conf")
        return 1
    fi
    
    PRECHECK_DNS=0
    return 0
}

# 检测磁盘空间
precheck_disk() {
    log_debug "检查磁盘空间..."
    
    local min_space_mb=500
    local available_mb
    
    # 检查 /boot 分区
    if [[ -d /boot ]]; then
        available_mb=$(df -m /boot 2>/dev/null | awk 'NR==2 {print $4}')
        if [[ -n "$available_mb" ]] && [[ $available_mb -lt 200 ]]; then
            PRECHECK_DISK=2
            PRECHECK_MESSAGES+=("/boot 分区空间不足 (${available_mb}MB < 200MB)，无法安装内核")
            return 1
        fi
    fi
    
    # 检查根分区
    available_mb=$(df -m / 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "$available_mb" ]] && [[ $available_mb -lt $min_space_mb ]]; then
        PRECHECK_DISK=2
        PRECHECK_MESSAGES+=("根分区空间不足 (${available_mb}MB < ${min_space_mb}MB)")
        return 1
    fi
    
    PRECHECK_DISK=0
    return 0
}

# 检测并安装依赖
precheck_deps() {
    log_debug "检查必要依赖..."
    
    local missing_deps=()
    local dep cmd
    
    for dep in $REQUIRED_DEPS; do
        # 映射包名到检测方式
        case "$dep" in
            gnupg)
                command -v gpg >/dev/null 2>&1 || missing_deps+=("$dep")
                ;;
            ca-certificates)
                # 检查证书目录是否存在
                [[ -d /etc/ssl/certs ]] || missing_deps+=("$dep")
                ;;
            *)
                command -v "$dep" >/dev/null 2>&1 || missing_deps+=("$dep")
                ;;
        esac
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_info "缺少依赖: ${missing_deps[*]}"
        print_info "正在安装缺少的依赖: ${missing_deps[*]}"
        
        case "$PKG_MANAGER" in
            apt)
                apt-get update -qq
                apt-get install -y -qq "${missing_deps[@]}" || {
                    PRECHECK_DEPS=2
                    PRECHECK_MESSAGES+=("依赖安装失败: ${missing_deps[*]}")
                    return 1
                }
                ;;
            dnf)
                dnf install -y -q "${missing_deps[@]}" || {
                    PRECHECK_DEPS=2
                    PRECHECK_MESSAGES+=("依赖安装失败: ${missing_deps[*]}")
                    return 1
                }
                ;;
            yum)
                yum install -y -q "${missing_deps[@]}" || {
                    PRECHECK_DEPS=2
                    PRECHECK_MESSAGES+=("依赖安装失败: ${missing_deps[*]}")
                    return 1
                }
                ;;
            *)
                PRECHECK_DEPS=1
                PRECHECK_MESSAGES+=("未知包管理器，请手动安装: ${missing_deps[*]}")
                return 1
                ;;
        esac
    fi
    
    PRECHECK_DEPS=0
    return 0
}

# 检测系统更新状态
precheck_update() {
    log_debug "检查系统更新状态..."
    
    PRECHECK_UPDATE=0
    
    case "$PKG_MANAGER" in
        apt)
            # 检查 apt 缓存是否过期（超过 1 天）
            local cache_file="/var/cache/apt/pkgcache.bin"
            if [[ -f "$cache_file" ]]; then
                local cache_mtime cache_age
                # Linux 使用 -c %Y，macOS/BSD 使用 -f %m
                cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
                cache_age=$(( $(date +%s) - cache_mtime ))
                if [[ $cache_age -gt 86400 ]]; then
                    PRECHECK_UPDATE=1
                    PRECHECK_MESSAGES+=("APT 缓存已过期，建议运行 apt update")
                fi
            fi
            ;;
        dnf|yum)
            # DNF/YUM 通常自动处理缓存
            ;;
    esac
    
    return 0
}

# 检测 APT/YUM 源可用性
check_package_source() {
    log_debug "检测软件源可用性..."
    
    case "$PKG_MANAGER" in
        apt)
            # 尝试更新 APT 缓存
            if ! apt-get update -qq 2>&1 | grep -qE '(Failed|Error|错误)'; then
                return 0
            fi
            
            # 检测具体错误
            local apt_output
            apt_output=$(apt-get update 2>&1)
            
            if echo "$apt_output" | grep -qE 'Could not resolve|无法解析'; then
                log_warn "APT 源 DNS 解析失败"
                return 1
            fi
            
            if echo "$apt_output" | grep -qE 'Connection timed out|连接超时'; then
                log_warn "APT 源连接超时"
                return 2
            fi
            
            if echo "$apt_output" | grep -qE 'NO_PUBKEY|GPG error'; then
                log_warn "APT 源 GPG 密钥问题"
                return 3
            fi
            
            return 0
            ;;
        dnf)
            if dnf check-update -q 2>&1 | grep -qE '(Error|错误)'; then
                log_warn "DNF 源可能存在问题"
                return 1
            fi
            return 0
            ;;
        yum)
            if yum check-update -q 2>&1 | grep -qE '(Error|错误)'; then
                log_warn "YUM 源可能存在问题"
                return 1
            fi
            return 0
            ;;
    esac
    
    return 0
}

# 修复 APT 源问题
fix_apt_source() {
    log_info "尝试修复 APT 源..."
    
    # 备份当前源
    local backup_file="/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)"
    cp /etc/apt/sources.list "$backup_file" 2>/dev/null || true
    
    # 清理 APT 缓存
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    
    # 如果是国内环境，尝试切换到国内镜像
    if [[ $USE_CHINA_MIRROR -eq 1 ]]; then
        print_info "尝试切换到国内镜像源..."
        
        # 检测当前系统
        local codename="${DIST_CODENAME:-$(lsb_release -cs 2>/dev/null || echo 'stable')}"
        
        case "$DIST_ID" in
            debian)
                cat > /etc/apt/sources.list << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${codename} main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${codename}-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security ${codename}-security main contrib non-free
EOF
                ;;
            ubuntu)
                cat > /etc/apt/sources.list << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${codename} main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${codename}-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${codename}-security main restricted universe multiverse
EOF
                ;;
        esac
    fi
    
    # 重新更新
    if apt-get update -qq 2>&1 | grep -qE '(Failed|Error)'; then
        log_warn "修复后仍有问题，恢复原配置"
        [[ -f "$backup_file" ]] && cp "$backup_file" /etc/apt/sources.list
        return 1
    fi
    
    print_success "APT 源修复成功"
    return 0
}

# 检测网络环境（国内/国外）
detect_network_region() {
    log_debug "检测网络环境..."
    
    # 测试国内外服务器延迟
    local cn_latency=9999
    local intl_latency=9999
    
    # 测试国内服务器 - 使用兼容的方式提取延迟
    local cn_result
    cn_result=$(ping -c 1 -W 2 "114.114.114.114" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -1)
    [[ -n "$cn_result" ]] && cn_latency="${cn_result%%.*}" || cn_latency=9999
    
    # 测试国外服务器
    local intl_result
    intl_result=$(ping -c 1 -W 2 "8.8.8.8" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -1)
    [[ -n "$intl_result" ]] && intl_latency="${intl_result%%.*}" || intl_latency=9999
    
    # 测试 Google 可访问性
    local google_ok=0
    if curl -s --connect-timeout 3 --max-time 5 "https://www.google.com" >/dev/null 2>&1; then
        google_ok=1
    fi
    
    # 判断网络环境
    if [[ $google_ok -eq 0 ]] || { [[ $cn_latency -lt 9999 ]] && [[ $intl_latency -gt 0 ]] && [[ $cn_latency -lt $((intl_latency / 2)) ]]; }; then
        USE_CHINA_MIRROR=1
        MIRROR_REGION="cn"
        log_info "检测到国内网络环境，将使用国内镜像源"
    else
        USE_CHINA_MIRROR=0
        MIRROR_REGION="intl"
        log_info "检测到国际网络环境，将使用官方源"
    fi
}

# 检测当前 APT 源是否为国内镜像（返回 0 表示官方源，返回 1 表示国内镜像）
detect_apt_mirror_region() {
    if [[ "$PKG_MANAGER" != "apt" ]]; then
        return 0
    fi
    
    local sources_file="/etc/apt/sources.list"
    if [[ ! -f "$sources_file" ]]; then
        return 0
    fi
    
    # 检测是否使用国内镜像
    if grep -qE '(mirrors\.(aliyun|tuna|ustc|163|huaweicloud)|mirror\.(nju|sjtu)\.edu\.cn)' "$sources_file" 2>/dev/null; then
        return 1  # 使用国内镜像
    fi
    
    return 0  # 使用官方源或其他源
}

# 执行完整预检
run_precheck() {
    print_header "环境预检"
    
    local all_passed=1
    
    # Root 权限检查
    echo -n "  检查 root 权限..."
    if precheck_root; then
        echo -e " [${GREEN}${ICON_OK}${NC}]"
    else
        echo -e " [${RED}${ICON_FAIL}${NC}]"
        all_passed=0
    fi
    
    # 操作系统检测
    echo -n "  检测操作系统..."
    detect_os
    detect_arch
    detect_virt
    if is_system_supported; then
        PRECHECK_OS=0
        echo -e " [${GREEN}${ICON_OK}${NC}] $(get_os_pretty_name)"
    else
        PRECHECK_OS=1
        echo -e " [${YELLOW}${ICON_WARN}${NC}] $(get_os_pretty_name) (不在官方支持列表)"
        PRECHECK_MESSAGES+=("系统版本不在官方支持列表，部分功能可能受限")
    fi
    
    # 架构检查
    echo -n "  检查 CPU 架构..."
    if [[ "$ARCH_ID" == "amd64" ]]; then
        PRECHECK_ARCH=0
        echo -e " [${GREEN}${ICON_OK}${NC}] ${ARCH_ID}"
    else
        PRECHECK_ARCH=1
        echo -e " [${YELLOW}${ICON_WARN}${NC}] ${ARCH_ID} (第三方内核仅支持 amd64)"
        PRECHECK_MESSAGES+=("当前架构 ${ARCH_ID} 不支持安装第三方内核，仅可配置 sysctl")
    fi
    
    # 虚拟化检查
    echo -n "  检测虚拟化环境..."
    case "$VIRT_TYPE" in
        openvz|lxc|docker|wsl)
            PRECHECK_VIRT=1
            echo -e " [${YELLOW}${ICON_WARN}${NC}] ${VIRT_TYPE} (无法更换内核)"
            PRECHECK_MESSAGES+=("容器环境 ${VIRT_TYPE} 无法更换宿主内核")
            ;;
        *)
            PRECHECK_VIRT=0
            echo -e " [${GREEN}${ICON_OK}${NC}] ${VIRT_TYPE}"
            ;;
    esac
    
    # 网络检查
    echo -n "  检查网络连通性..."
    if precheck_network; then
        echo -e " [${GREEN}${ICON_OK}${NC}]"
    else
        echo -e " [${RED}${ICON_FAIL}${NC}]"
        all_passed=0
    fi
    
    # DNS 检查
    echo -n "  检查 DNS 解析..."
    if precheck_dns; then
        echo -e " [${GREEN}${ICON_OK}${NC}]"
    else
        echo -e " [${YELLOW}${ICON_WARN}${NC}]"
    fi
    
    # 磁盘空间检查
    echo -n "  检查磁盘空间..."
    if precheck_disk; then
        echo -e " [${GREEN}${ICON_OK}${NC}]"
    else
        echo -e " [${RED}${ICON_FAIL}${NC}]"
        all_passed=0
    fi
    
    # 依赖检查
    echo -n "  检查必要依赖..."
    if precheck_deps; then
        echo -e " [${GREEN}${ICON_OK}${NC}]"
    else
        echo -e " [${RED}${ICON_FAIL}${NC}]"
        all_passed=0
    fi
    
    # 系统更新检查
    echo -n "  检查系统更新..."
    precheck_update
    if [[ $PRECHECK_UPDATE -eq 0 ]]; then
        echo -e " [${GREEN}${ICON_OK}${NC}]"
    else
        echo -e " [${YELLOW}${ICON_WARN}${NC}]"
    fi
    
    # 网络环境检测
    echo -n "  检测网络环境..."
    detect_network_region
    if [[ $USE_CHINA_MIRROR -eq 1 ]]; then
        echo -e " [${CYAN}${ICON_NET}${NC}] 国内网络"
    else
        echo -e " [${CYAN}${ICON_NET}${NC}] 国际网络"
    fi
    
    # APT 源配置检测（仅 Debian/Ubuntu）
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        echo -n "  检测软件源配置..."
        if detect_apt_mirror_region; then
            # 使用官方源或其他源
            if [[ $USE_CHINA_MIRROR -eq 1 ]]; then
                echo -e " [${YELLOW}${ICON_WARN}${NC}] 官方源（国内网络建议使用镜像）"
            else
                echo -e " [${GREEN}${ICON_OK}${NC}] 官方源"
            fi
        else
            # 使用国内镜像
            if [[ $USE_CHINA_MIRROR -eq 0 ]]; then
                echo -e " [${YELLOW}${ICON_WARN}${NC}] 国内镜像（国外网络可能需要切换）"
                PRECHECK_MESSAGES+=("系统使用国内镜像源，在国外网络环境下安装第三方内核时可能需要切换到官方源")
            else
                echo -e " [${GREEN}${ICON_OK}${NC}] 国内镜像"
            fi
        fi
    fi
    
    echo
    
    # 显示警告信息
    if [[ ${#PRECHECK_MESSAGES[@]} -gt 0 ]]; then
        print_warn "预检发现以下问题："
        for msg in "${PRECHECK_MESSAGES[@]}"; do
            echo -e "  ${YELLOW}•${NC} ${msg}"
        done
        echo
    fi
    
    # 返回预检结果
    if [[ $all_passed -eq 1 ]]; then
        print_success "环境预检通过"
        return 0
    else
        print_error "环境预检未通过，请解决上述问题后重试"
        return 1
    fi
}


#===============================================================================
# 配置管理模块
#===============================================================================

# 备份当前配置
backup_config() {
    log_debug "备份当前配置..."
    
    # 创建备份目录
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
    fi
    
    # 如果配置文件存在，进行备份
    if [[ -f "$SYSCTL_FILE" ]]; then
        local timestamp
        timestamp=$(date '+%Y%m%d_%H%M%S')
        local backup_file="${BACKUP_DIR}/99-bbr.conf.${timestamp}.bak"
        
        cp "$SYSCTL_FILE" "$backup_file"
        log_info "配置已备份到: ${backup_file}"
        print_info "配置已备份到: ${backup_file}"
        return 0
    fi
    
    return 0
}

# 恢复配置
restore_config() {
    local backup_file="${1:-}"
    
    if [[ -z "$backup_file" ]]; then
        # 列出可用备份
        local backups
        backups=$(ls -t "${BACKUP_DIR}/"*.bak 2>/dev/null || true)
        
        if [[ -z "$backups" ]]; then
            print_warn "没有找到可用的备份文件"
            return 1
        fi
        
        print_info "可用的备份文件："
        local i=1
        local -a backup_list=()
        while IFS= read -r file; do
            backup_list+=("$file")
            local filename
            filename=$(basename "$file")
            echo "  ${i}) ${filename}"
            ((i++))
        done <<< "$backups"
        
        read_choice "选择要恢复的备份" $((i-1))
        
        if [[ "$MENU_CHOICE" == "0" ]]; then
            return 1
        fi
        
        backup_file="${backup_list[$((MENU_CHOICE-1))]}"
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        print_error "备份文件不存在: ${backup_file}"
        return 1
    fi
    
    # 恢复配置
    cp "$backup_file" "$SYSCTL_FILE"
    log_info "配置已从 ${backup_file} 恢复"
    print_success "配置已恢复"
    
    # 应用配置
    if confirm "是否立即应用恢复的配置？" "y"; then
        apply_sysctl
    fi
    
    return 0
}

# 列出备份文件
list_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_info "没有备份目录"
        return
    fi
    
    local backups
    backups=$(ls -t "${BACKUP_DIR}/"*.bak 2>/dev/null || true)
    
    if [[ -z "$backups" ]]; then
        print_info "没有找到备份文件"
        return
    fi
    
    print_info "可用的备份文件："
    while IFS= read -r file; do
        local filename size file_date
        filename=$(basename "$file")
        size=$(du -h "$file" 2>/dev/null | cut -f1 || echo "N/A")
        # Linux 使用 -c %y，macOS/BSD 使用 -f %Sm
        file_date=$(stat -c %y "$file" 2>/dev/null | cut -d'.' -f1 || stat -f %Sm "$file" 2>/dev/null || echo "N/A")
        echo "  • ${filename} (${size}, ${file_date})"
    done <<< "$backups"
}

#===============================================================================
# 场景配置模块
#===============================================================================

# 检测服务器资源
detect_server_resources() {
    log_debug "检测服务器资源..."
    
    # CPU 核心数
    SERVER_CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
    
    # 内存大小 (MB)
    SERVER_MEMORY_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 1024)
    
    # 估算带宽 (通过网卡速度)
    local nic
    nic=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    if [[ -n "$nic" ]] && command -v ethtool >/dev/null 2>&1; then
        local speed
        speed=$(ethtool "$nic" 2>/dev/null | awk -F': ' '/Speed:/{print $2}' | grep -oE '[0-9]+')
        SERVER_BANDWIDTH_MBPS="${speed:-1000}"
    else
        SERVER_BANDWIDTH_MBPS=1000
    fi
    
    # 当前 TCP 连接数
    SERVER_TCP_CONNECTIONS=$(ss -t 2>/dev/null | wc -l || netstat -tn 2>/dev/null | wc -l || echo 0)
    # 减去标题行，使用安全的算术运算
    SERVER_TCP_CONNECTIONS=$((SERVER_TCP_CONNECTIONS > 0 ? SERVER_TCP_CONNECTIONS - 1 : 0))
}

# 根据服务器资源推荐场景模式
recommend_scene_mode() {
    detect_server_resources
    
    # 推荐逻辑（针对 VPS 代理场景优化）
    # 1. VPS 环境（KVM/Xen/虚拟机）-> 默认推荐代理模式
    # 2. 高并发 (连接数>1000 或 多核>=8) -> 并发模式
    # 3. 大带宽 (>=10Gbps) -> 极速模式
    # 4. 物理机/数据中心 -> 性能模式
    
    # 检测是否为 VPS 环境（常见代理服务器场景）
    local is_vps=0
    case "${VIRT_TYPE:-}" in
        kvm|qemu|xen|vmware|virtualbox|hyperv|none)
            is_vps=1
            ;;
    esac
    
    # VPS 环境默认推荐代理模式
    if [[ $is_vps -eq 1 ]] && [[ $SERVER_CPU_CORES -le 4 ]] && [[ $SERVER_MEMORY_MB -le 4096 ]]; then
        SCENE_RECOMMENDED="proxy"
    elif [[ $SERVER_TCP_CONNECTIONS -gt 1000 ]] || [[ $SERVER_CPU_CORES -ge 8 ]]; then
        SCENE_RECOMMENDED="concurrent"
    elif [[ $SERVER_BANDWIDTH_MBPS -ge 10000 ]]; then
        SCENE_RECOMMENDED="speed"
    elif [[ $SERVER_BANDWIDTH_MBPS -ge 1000 ]]; then
        SCENE_RECOMMENDED="video"
    elif [[ "${VIRT_TYPE:-}" == "none" ]] || [[ "${VIRT_TYPE:-}" == "物理机/未知" ]]; then
        SCENE_RECOMMENDED="performance"
    else
        SCENE_RECOMMENDED="proxy"  # VPS 默认代理模式
    fi
}

# 获取场景模式名称
get_scene_name() {
    local mode="$1"
    case "$mode" in
        balanced)      echo "均衡模式" ;;
        communication) echo "通信模式" ;;
        video)         echo "视频模式" ;;
        concurrent)    echo "并发模式" ;;
        speed)         echo "极速模式" ;;
        performance)   echo "性能模式" ;;
        proxy)         echo "代理模式" ;;
        *)             echo "未知模式" ;;
    esac
}

# 获取场景模式描述
get_scene_description() {
    local mode="$1"
    case "$mode" in
        balanced)
            echo "适合一般用途，平衡延迟与吞吐量"
            ;;
        communication)
            echo "优化低延迟，适合实时通信/游戏/SSH"
            ;;
        video)
            echo "优化大文件传输，适合视频流/下载服务"
            ;;
        concurrent)
            echo "优化高并发连接，适合 Web 服务器/API"
            ;;
        speed)
            echo "最大化吞吐量，适合大带宽服务器"
            ;;
        performance)
            echo "全面性能优化，适合高性能计算/数据库"
            ;;
        proxy)
            echo "专为代理/VPN优化，抗丢包、低延迟、高吞吐"
            ;;
    esac
}

# 获取场景模式的 sysctl 参数（根据服务器配置动态调整）
get_scene_params() {
    local mode="$1"
    
    # 确保已检测服务器资源
    [[ $SERVER_CPU_CORES -eq 0 ]] && detect_server_resources
    
    # 根据内存计算缓冲区大小
    # 规则：缓冲区最大不超过内存的 1/4，最小 16MB
    local mem_bytes=$((SERVER_MEMORY_MB * 1024 * 1024))
    local max_buffer=$((mem_bytes / 4))
    [[ $max_buffer -gt 268435456 ]] && max_buffer=268435456  # 最大 256MB
    [[ $max_buffer -lt 16777216 ]] && max_buffer=16777216    # 最小 16MB
    
    # 根据 CPU 核心数计算连接队列
    # 规则：每核心 1024-4096 连接
    local base_somaxconn=$((SERVER_CPU_CORES * 2048))
    [[ $base_somaxconn -gt 65535 ]] && base_somaxconn=65535
    [[ $base_somaxconn -lt 1024 ]] && base_somaxconn=1024
    
    # 根据 CPU 核心数计算网络队列
    local base_backlog=$((SERVER_CPU_CORES * 50000))
    [[ $base_backlog -gt 1000000 ]] && base_backlog=1000000
    [[ $base_backlog -lt 10000 ]] && base_backlog=10000
    
    # 自动检测最佳算法（优先 BBR3）
    local algo
    algo=$(suggest_best_algo)
    
    # 自动检测最佳队列规则（根据场景）
    local qdisc
    qdisc=$(suggest_best_qdisc "$mode")
    local rmem_max=$max_buffer
    local wmem_max=$max_buffer
    local tcp_rmem_high=$max_buffer
    local tcp_wmem_high=$max_buffer
    local somaxconn=$base_somaxconn
    local netdev_backlog=$base_backlog
    local tcp_fastopen=3
    local tcp_low_latency=0
    local tcp_slow_start=1
    local tcp_notsent_lowat=16384
    
    # 注意：algo 和 qdisc 已在上面自动检测，各场景只调整其他参数
    case "$mode" in
        balanced)
            # 均衡模式 - 使用 50% 的计算值，平衡延迟与吞吐
            rmem_max=$((max_buffer / 2))
            wmem_max=$((max_buffer / 2))
            tcp_rmem_high=$((max_buffer / 2))
            tcp_wmem_high=$((max_buffer / 2))
            somaxconn=$((base_somaxconn / 2))
            netdev_backlog=$((base_backlog / 2))
            ;;
        communication)
            # 通信模式 - 小缓冲区，低延迟优先
            rmem_max=$((max_buffer / 4))
            wmem_max=$((max_buffer / 4))
            tcp_rmem_high=$((max_buffer / 4))
            tcp_wmem_high=$((max_buffer / 4))
            somaxconn=$((base_somaxconn / 4))
            netdev_backlog=$((base_backlog / 4))
            tcp_low_latency=1
            tcp_notsent_lowat=4096
            ;;
        video)
            # 视频模式 - 大缓冲区，大吞吐量
            rmem_max=$((max_buffer * 3 / 4))
            wmem_max=$((max_buffer * 3 / 4))
            tcp_rmem_high=$((max_buffer * 3 / 4))
            tcp_wmem_high=$((max_buffer * 3 / 4))
            somaxconn=$base_somaxconn
            netdev_backlog=$base_backlog
            tcp_slow_start=0
            ;;
        concurrent)
            # 并发模式 - 最大化连接数，公平性优先
            rmem_max=$((max_buffer / 2))
            wmem_max=$((max_buffer / 2))
            tcp_rmem_high=$((max_buffer / 2))
            tcp_wmem_high=$((max_buffer / 2))
            somaxconn=65535
            netdev_backlog=$((base_backlog * 2))
            [[ $netdev_backlog -gt 1000000 ]] && netdev_backlog=1000000
            tcp_fastopen=3
            ;;
        speed)
            # 极速模式 - 最大吞吐量
            rmem_max=$max_buffer
            wmem_max=$max_buffer
            tcp_rmem_high=$max_buffer
            tcp_wmem_high=$max_buffer
            somaxconn=$base_somaxconn
            netdev_backlog=$((base_backlog * 2))
            [[ $netdev_backlog -gt 1000000 ]] && netdev_backlog=1000000
            tcp_slow_start=0
            tcp_notsent_lowat=131072
            ;;
        performance)
            # 性能模式 - 全面优化
            rmem_max=$((max_buffer * 3 / 4))
            wmem_max=$((max_buffer * 3 / 4))
            tcp_rmem_high=$((max_buffer * 3 / 4))
            tcp_wmem_high=$((max_buffer * 3 / 4))
            somaxconn=$((base_somaxconn * 3 / 2))
            [[ $somaxconn -gt 65535 ]] && somaxconn=65535
            netdev_backlog=$base_backlog
            tcp_fastopen=3
            tcp_low_latency=1
            tcp_slow_start=0
            tcp_notsent_lowat=65536
            ;;
        proxy)
            # 代理模式 - 专为 VPS 代理/VPN/翻墙优化
            # 特点：抗丢包、低延迟、适中缓冲区、快速重传
            # 适合：V2Ray, Xray, Trojan, Shadowsocks, WireGuard 等
            rmem_max=$((max_buffer * 2 / 3))
            wmem_max=$((max_buffer * 2 / 3))
            tcp_rmem_high=$((max_buffer * 2 / 3))
            tcp_wmem_high=$((max_buffer * 2 / 3))
            somaxconn=$((base_somaxconn * 2))
            [[ $somaxconn -gt 65535 ]] && somaxconn=65535
            netdev_backlog=$((base_backlog * 2))
            [[ $netdev_backlog -gt 1000000 ]] && netdev_backlog=1000000
            tcp_fastopen=3          # 启用 TFO 加速握手
            tcp_low_latency=1       # 低延迟模式
            tcp_slow_start=0        # 禁用慢启动（重连更快）
            tcp_notsent_lowat=16384 # 较小值减少延迟
            ;;
    esac
    
    # 确保最小值
    [[ $rmem_max -lt 16777216 ]] && rmem_max=16777216
    [[ $wmem_max -lt 16777216 ]] && wmem_max=16777216
    [[ $tcp_rmem_high -lt 16777216 ]] && tcp_rmem_high=16777216
    [[ $tcp_wmem_high -lt 16777216 ]] && tcp_wmem_high=16777216
    [[ $somaxconn -lt 1024 ]] && somaxconn=1024
    [[ $netdev_backlog -lt 10000 ]] && netdev_backlog=10000
    
    # 输出参数（用于显示和应用）
    echo "algo=$algo"
    echo "qdisc=$qdisc"
    echo "rmem_max=$rmem_max"
    echo "wmem_max=$wmem_max"
    echo "tcp_rmem_high=$tcp_rmem_high"
    echo "tcp_wmem_high=$tcp_wmem_high"
    echo "somaxconn=$somaxconn"
    echo "netdev_backlog=$netdev_backlog"
    echo "tcp_fastopen=$tcp_fastopen" 
    echo "tcp_low_latency=$tcp_low_latency"
    echo "tcp_slow_start=$tcp_slow_start"
    echo "tcp_notsent_lowat=$tcp_notsent_lowat"
}

# 显示场景模式参数摘要
show_scene_params_summary() {
    local mode="$1"
    
    # 确保服务器资源已检测
    [[ $SERVER_CPU_CORES -eq 0 ]] && detect_server_resources
    
    echo
    print_header "$(get_scene_name "$mode") 参数摘要"
    echo
    echo -e "  ${BOLD}优化目标:${NC} $(get_scene_description "$mode")"
    echo
    
    # 代理模式显示详细说明
    if [[ "$mode" == "proxy" ]]; then
        echo -e "  ${BOLD}适用场景:${NC}"
        echo "    • V2Ray / Xray / Trojan / Trojan-Go"
        echo "    • Shadowsocks / ShadowsocksR / Clash"
        echo "    • WireGuard / OpenVPN / IPsec"
        echo "    • Hysteria / TUIC / NaiveProxy"
        echo "    • 其他代理/VPN 协议"
        echo
        echo -e "  ${BOLD}核心优化:${NC}"
        echo -e "    • ${GREEN}抗丢包${NC}: BBR3 对丢包不敏感，跨国线路更稳定"
        echo -e "    • ${GREEN}低延迟${NC}: 优化 TCP 参数减少响应时间"
        echo -e "    • ${GREEN}快速重连${NC}: 禁用慢启动，断线重连更快"
        echo -e "    • ${GREEN}TFO 加速${NC}: TCP Fast Open 减少握手延迟"
        echo
        echo -e "  ${BOLD}连接优化:${NC}"
        echo -e "    • ${CYAN}快速释放${NC}: FIN 超时 15 秒，快速回收资源"
        echo -e "    • ${CYAN}TIME_WAIT${NC}: 50 万桶，支持高并发短连接"
        echo -e "    • ${CYAN}端口范围${NC}: 1024-65535，更多可用端口"
        echo -e "    • ${CYAN}SYN 优化${NC}: 减少重试次数，加快连接建立"
        echo
    fi
    
    echo -e "  ${BOLD}关键参数:${NC}"
    
    # 解析参数
    local params
    params=$(get_scene_params "$mode")
    
    local algo qdisc rmem wmem somaxconn backlog fastopen lowlat slowstart notsent
    algo=$(echo "$params" | grep "^algo=" | cut -d= -f2)
    qdisc=$(echo "$params" | grep "^qdisc=" | cut -d= -f2)
    rmem=$(echo "$params" | grep "^rmem_max=" | cut -d= -f2)
    wmem=$(echo "$params" | grep "^wmem_max=" | cut -d= -f2)
    somaxconn=$(echo "$params" | grep "^somaxconn=" | cut -d= -f2)
    backlog=$(echo "$params" | grep "^netdev_backlog=" | cut -d= -f2)
    fastopen=$(echo "$params" | grep "^tcp_fastopen=" | cut -d= -f2)
    lowlat=$(echo "$params" | grep "^tcp_low_latency=" | cut -d= -f2)
    slowstart=$(echo "$params" | grep "^tcp_slow_start=" | cut -d= -f2)
    notsent=$(echo "$params" | grep "^tcp_notsent_lowat=" | cut -d= -f2)
    
    printf "    %-25s : %s (自动检测)\n" "拥塞控制算法" "$algo"
    printf "    %-25s : %s (自动检测)\n" "队列规则" "$qdisc"
    printf "    %-25s : %s (%s MB)\n" "接收缓冲区" "$rmem" "$((rmem/1024/1024))"
    printf "    %-25s : %s (%s MB)\n" "发送缓冲区" "$wmem" "$((wmem/1024/1024))"
    printf "    %-25s : %s\n" "最大连接队列" "$somaxconn"
    printf "    %-25s : %s\n" "网络设备队列" "$backlog"
    printf "    %-25s : %s\n" "TCP Fast Open" "$fastopen"
    
    # 代理模式显示额外参数（根据 VPS 配置动态计算）
    if [[ "$mode" == "proxy" ]]; then
        printf "    %-25s : %s (禁用=更快重连)\n" "慢启动" "$slowstart"
        printf "    %-25s : %s (较小=更低延迟)\n" "发送低水位" "$notsent"
        echo
        
        # 动态计算代理专用参数
        local tw_buckets orphans
        if [[ $SERVER_MEMORY_MB -le 512 ]]; then
            tw_buckets=100000; orphans=32768
        elif [[ $SERVER_MEMORY_MB -le 1024 ]]; then
            tw_buckets=200000; orphans=65535
        elif [[ $SERVER_MEMORY_MB -le 2048 ]]; then
            tw_buckets=300000; orphans=65535
        else
            tw_buckets=500000; orphans=131072
        fi
        
        echo -e "  ${BOLD}代理专用优化 (根据 ${SERVER_MEMORY_MB}MB 内存动态调整):${NC}"
        printf "    %-25s : %s\n" "FIN 超时" "15秒 (快速释放)"
        printf "    %-25s : %s\n" "Keepalive 时间" "600秒"
        printf "    %-25s : %s (根据内存)\n" "TIME_WAIT 桶" "$tw_buckets"
        printf "    %-25s : %s\n" "端口范围" "1024-65535"
        printf "    %-25s : %s\n" "SYN 重试" "2次"
        printf "    %-25s : %s (根据内存)\n" "孤儿连接上限" "$orphans"
    fi
    echo
}

# 应用场景模式
apply_scene_mode() {
    local mode="$1"
    
    log_info "应用场景模式: $mode"
    
    # 获取参数
    local params
    params=$(get_scene_params "$mode")
    
    # 解析参数
    local algo qdisc rmem_max wmem_max tcp_rmem_high tcp_wmem_high
    local somaxconn netdev_backlog tcp_fastopen tcp_low_latency tcp_slow_start tcp_notsent_lowat
    
    algo=$(echo "$params" | grep "^algo=" | cut -d= -f2)
    qdisc=$(echo "$params" | grep "^qdisc=" | cut -d= -f2)
    rmem_max=$(echo "$params" | grep "^rmem_max=" | cut -d= -f2)
    wmem_max=$(echo "$params" | grep "^wmem_max=" | cut -d= -f2)
    tcp_rmem_high=$(echo "$params" | grep "^tcp_rmem_high=" | cut -d= -f2)
    tcp_wmem_high=$(echo "$params" | grep "^tcp_wmem_high=" | cut -d= -f2)
    somaxconn=$(echo "$params" | grep "^somaxconn=" | cut -d= -f2)
    netdev_backlog=$(echo "$params" | grep "^netdev_backlog=" | cut -d= -f2)
    tcp_fastopen=$(echo "$params" | grep "^tcp_fastopen=" | cut -d= -f2)
    tcp_low_latency=$(echo "$params" | grep "^tcp_low_latency=" | cut -d= -f2)
    tcp_slow_start=$(echo "$params" | grep "^tcp_slow_start=" | cut -d= -f2)
    tcp_notsent_lowat=$(echo "$params" | grep "^tcp_notsent_lowat=" | cut -d= -f2)
    
    # 备份当前配置
    backup_config
    
    # 写入配置文件
    local proxy_header=""
    if [[ "$mode" == "proxy" ]]; then
        proxy_header="# 
# ========== 代理模式详解 ==========
# 适用: V2Ray/Xray/Trojan/SS/WireGuard/Hysteria 等
# 特点:
#   - 抗丢包: BBR3 对丢包不敏感，跨国线路更稳定
#   - 低延迟: 优化 TCP 参数减少响应时间
#   - 快速重连: tcp_slow_start=0 断线重连更快
#   - TFO加速: tcp_fastopen=3 减少握手延迟
#   - 适中缓冲: 平衡延迟和吞吐量
#"
    fi
    
    cat > "$SYSCTL_FILE" << CONF
# BBR3 Script 场景配置
# 场景模式: $(get_scene_name "$mode")
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 版本: ${SCRIPT_VERSION}
# 内核版本: $(uname -r)
${proxy_header}
# ========== 拥塞控制（自动检测最佳算法）==========
# 算法: ${algo} (自动选择: BBR3 > BBR2 > BBR > CUBIC)
# 队列: ${qdisc} (根据场景自动匹配)
net.ipv4.tcp_congestion_control = ${algo}
net.core.default_qdisc = ${qdisc}

# ========== 缓冲区配置 ==========
net.core.rmem_max = ${rmem_max}
net.core.wmem_max = ${wmem_max}
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 87380 ${tcp_rmem_high}
net.ipv4.tcp_wmem = 4096 65536 ${tcp_wmem_high}
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# ========== 连接优化 ==========
net.core.somaxconn = ${somaxconn}
net.core.netdev_max_backlog = ${netdev_backlog}
net.ipv4.tcp_max_syn_backlog = ${somaxconn}
net.ipv4.tcp_fastopen = ${tcp_fastopen}

# ========== TCP 优化 ==========
# 注意: tcp_low_latency 在 Linux 4.14+ 已移除，不再设置
net.ipv4.tcp_slow_start_after_idle = ${tcp_slow_start}
net.ipv4.tcp_notsent_lowat = ${tcp_notsent_lowat}
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_syncookies = 1
CONF

    # 代理模式添加专用优化参数（根据 VPS 配置动态调整）
    if [[ "$mode" == "proxy" ]]; then
        # 根据内存动态计算参数
        local tw_buckets orphans tcp_mem_low tcp_mem_pressure tcp_mem_high
        
        # TIME_WAIT 桶数量：根据内存调整
        # 512MB -> 100000, 1GB -> 200000, 2GB -> 300000, 4GB+ -> 500000
        if [[ $SERVER_MEMORY_MB -le 512 ]]; then
            tw_buckets=100000
            orphans=32768
        elif [[ $SERVER_MEMORY_MB -le 1024 ]]; then
            tw_buckets=200000
            orphans=65535
        elif [[ $SERVER_MEMORY_MB -le 2048 ]]; then
            tw_buckets=300000
            orphans=65535
        else
            tw_buckets=500000
            orphans=131072
        fi
        
        # TCP 内存限制：根据总内存调整（单位：页，4KB/页）
        # 低水位 = 内存的 1/16，压力值 = 1/8，高水位 = 1/4
        local mem_pages=$((SERVER_MEMORY_MB * 256))  # MB 转页数
        tcp_mem_low=$((mem_pages / 16))
        tcp_mem_pressure=$((mem_pages / 8))
        tcp_mem_high=$((mem_pages / 4))
        
        # 确保最小值
        [[ $tcp_mem_low -lt 65536 ]] && tcp_mem_low=65536
        [[ $tcp_mem_pressure -lt 131072 ]] && tcp_mem_pressure=131072
        [[ $tcp_mem_high -lt 262144 ]] && tcp_mem_high=262144
        
        cat >> "$SYSCTL_FILE" << PROXY_CONF

# ========== 代理模式专用优化 ==========
# 根据 VPS 配置动态调整: CPU=${SERVER_CPU_CORES}核, 内存=${SERVER_MEMORY_MB}MB

# 连接超时优化（更快释放资源）
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15

# TIME_WAIT 优化（根据内存动态调整）
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = ${tw_buckets}

# 端口范围扩大（支持更多并发连接）
net.ipv4.ip_local_port_range = 1024 65535

# SYN 队列优化（根据 CPU 核心数调整）
net.ipv4.tcp_max_syn_backlog = ${somaxconn}
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# 孤儿连接优化（根据内存调整）
net.ipv4.tcp_orphan_retries = 2
net.ipv4.tcp_max_orphans = ${orphans}

# 重传优化（跨国线路重要）
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 8

# 内存优化（根据总内存动态调整）
net.ipv4.tcp_mem = ${tcp_mem_low} ${tcp_mem_pressure} ${tcp_mem_high}
net.ipv4.udp_mem = ${tcp_mem_low} ${tcp_mem_pressure} ${tcp_mem_high}

# IPv6 优化（如果启用）
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
PROXY_CONF
    else
        # 非代理模式使用标准参数
        cat >> "$SYSCTL_FILE" << 'STD_CONF'

# ========== 连接管理 ==========
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.ip_local_port_range = 1024 65535
STD_CONF
    fi
    
    # 应用配置（忽略不支持的参数）
    local sysctl_output
    local sysctl_errors=0
    
    # 先尝试完整应用
    if sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
        print_success "配置已完整应用"
    else
        # 如果失败，逐行应用，跳过不支持的参数
        print_warn "部分参数可能不被当前内核支持，正在逐行应用..."
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            # 跳过空行和注释
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            
            # 提取参数名
            local param_name="${line%%=*}"
            param_name="${param_name// /}"
            
            # 尝试应用单个参数
            if ! sysctl -w "$line" >/dev/null 2>&1; then
                log_warn "参数不支持或无法设置: ${param_name}"
                ((++sysctl_errors))
            fi
        done < "$SYSCTL_FILE"
        
        if [[ $sysctl_errors -gt 0 ]]; then
            print_warn "有 ${sysctl_errors} 个参数未能应用（可能不被当前内核支持）"
        fi
    fi
    
    # 应用 qdisc
    apply_qdisc_runtime "$qdisc" 2>/dev/null || true
    
    # 记录到日志
    log_info "场景模式已应用: $(get_scene_name "$mode")"
    log_info "参数: algo=$algo, qdisc=$qdisc, rmem=$rmem_max, wmem=$wmem_max"
    
    SCENE_MODE="$mode"
    return 0
}

# 场景配置菜单
scene_config_menu() {
    # 检测服务器资源并推荐模式
    recommend_scene_mode
    
    while true; do
        print_header "场景配置"
        
        echo -e "${DIM}根据使用场景选择预设优化方案，参数会根据服务器配置动态调整${NC}"
        echo -e "${DIM}注意: 此功能与「自动优化配置」互斥，后执行的会覆盖前者${NC}"
        echo
        
        # 获取自动检测的算法和队列
        local auto_algo auto_qdisc
        auto_algo=$(suggest_best_algo)
        auto_qdisc=$(suggest_best_qdisc "$SCENE_RECOMMENDED")
        
        # 显示服务器资源信息
        echo -e "  ${BOLD}服务器资源:${NC}"
        printf "    %-15s : %s 核\n" "CPU" "$SERVER_CPU_CORES"
        printf "    %-15s : %s MB\n" "内存" "$SERVER_MEMORY_MB"
        printf "    %-15s : %s Mbps\n" "网卡速度" "$SERVER_BANDWIDTH_MBPS"
        printf "    %-15s : %s\n" "TCP 连接数" "$SERVER_TCP_CONNECTIONS"
        printf "    %-15s : %s\n" "虚拟化" "${VIRT_TYPE:-未知}"
        echo
        echo -e "  ${BOLD}自动检测:${NC}"
        printf "    %-15s : %s\n" "最佳算法" "$auto_algo"
        printf "    %-15s : %s\n" "最佳队列" "$auto_qdisc"
        echo
        echo -e "  ${BOLD}推荐模式:${NC} ${GREEN}$(get_scene_name "$SCENE_RECOMMENDED")${NC}"
        echo -e "  ${DIM}$(get_scene_description "$SCENE_RECOMMENDED")${NC}"
        echo
        
        print_separator
        echo
        echo -e "  ${CYAN}1)${NC} 均衡模式    - 平衡延迟与吞吐量，适合一般用途"
        echo -e "  ${CYAN}2)${NC} 通信模式    - 优化低延迟，适合实时通信/游戏"
        echo -e "  ${CYAN}3)${NC} 视频模式    - 优化大文件传输，适合视频流/下载"
        echo -e "  ${CYAN}4)${NC} 并发模式    - 优化高并发，适合 Web/API 服务器"
        echo -e "  ${CYAN}5)${NC} 极速模式    - 最大化吞吐量，适合大带宽服务器"
        echo -e "  ${CYAN}6)${NC} 性能模式    - 全面性能优化，适合高性能计算"
        echo -e "  ${GREEN}7)${NC} ${GREEN}代理模式${NC}    - ${GREEN}专为代理/VPN优化，推荐翻墙使用${NC}"
        echo
        echo -e "  ${CYAN}0)${NC} 返回主菜单"
        echo
        
        read_choice "请选择场景模式" 7
        
        local selected_mode=""
        case "$MENU_CHOICE" in
            0) return ;;
            1) selected_mode="balanced" ;;
            2) selected_mode="communication" ;;
            3) selected_mode="video" ;;
            4) selected_mode="concurrent" ;;
            5) selected_mode="speed" ;;
            6) selected_mode="performance" ;;
            7) selected_mode="proxy" ;;
            *) continue ;;
        esac
        
        # 显示参数摘要
        show_scene_params_summary "$selected_mode"
        
        # 二次确认
        if confirm "确认应用 $(get_scene_name "$selected_mode")？" "y"; then
            print_step "正在应用配置..."
            
            if apply_scene_mode "$selected_mode"; then
                echo
                print_success "$(get_scene_name "$selected_mode") 已成功应用！"
                echo
                echo -e "  ${BOLD}变更摘要:${NC}"
                echo "    - 配置文件: ${SYSCTL_FILE}"
                echo "    - 日志文件: ${LOG_FILE}"
                echo "    - 可使用备份功能回滚"
                echo
                
                read -rp "按 Enter 键继续..."
            else
                print_error "配置应用失败"
                read -rp "按 Enter 键继续..."
            fi
        fi
    done
}

# 验证 sysctl 配置文件格式
validate_sysctl_config() {
    local config_file="${1:-$SYSCTL_FILE}"
    
    if [[ ! -f "$config_file" ]]; then
        return 0  # 文件不存在，无需验证
    fi
    
    log_debug "验证配置文件格式: ${config_file}"
    
    local line_num=0
    local errors=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((++line_num))
        
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # 检查格式：key = value 或 key=value
        if ! echo "$line" | grep -qE '^[a-zA-Z0-9_.]+[[:space:]]*=[[:space:]]*[^[:space:]]'; then
            log_warn "配置文件第 ${line_num} 行格式错误: ${line}"
            ((++errors))
        fi
    done < "$config_file"
    
    if [[ $errors -gt 0 ]]; then
        log_warn "配置文件存在 ${errors} 处格式错误"
        return 1
    fi
    
    return 0
}

# 修复损坏的 sysctl 配置文件
repair_sysctl_config() {
    local config_file="${1:-$SYSCTL_FILE}"
    
    if [[ ! -f "$config_file" ]]; then
        return 0
    fi
    
    log_info "尝试修复配置文件: ${config_file}"
    
    # 备份原文件
    local backup_file="${config_file}.broken.$(date +%Y%m%d%H%M%S)"
    cp "$config_file" "$backup_file"
    log_info "原配置已备份到: ${backup_file}"
    
    # 创建临时文件
    local tmp_file
    tmp_file=$(mktemp)
    
    # 只保留有效行
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 保留空行和注释
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            echo "$line" >> "$tmp_file"
            continue
        fi
        
        # 只保留格式正确的配置行
        if echo "$line" | grep -qE '^[a-zA-Z0-9_.]+[[:space:]]*=[[:space:]]*[^[:space:]]'; then
            echo "$line" >> "$tmp_file"
        fi
    done < "$config_file"
    
    # 替换原文件
    mv "$tmp_file" "$config_file"
    
    print_success "配置文件已修复"
    return 0
}

# 写入 sysctl 配置
write_sysctl() {
    local algo="$1"
    local qdisc="$2"
    
    log_debug "写入 sysctl 配置: algo=${algo}, qdisc=${qdisc}"
    
    # 先备份
    backup_config
    
    # 创建配置目录
    mkdir -p "$(dirname "$SYSCTL_FILE")"
    
    # 写入配置
    cat > "$SYSCTL_FILE" << CONF
# BBR3 Script 自动生成配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 版本: ${SCRIPT_VERSION}

# TCP 拥塞控制算法
net.ipv4.tcp_congestion_control = ${algo}

# 默认队列规则
net.core.default_qdisc = ${qdisc}

# TCP 缓冲区优化
net.core.rmem_max = ${TUNE_RMEM_MAX:-67108864}
net.core.wmem_max = ${TUNE_WMEM_MAX:-67108864}
net.ipv4.tcp_rmem = 4096 87380 ${TUNE_TCP_RMEM_HIGH:-67108864}
net.ipv4.tcp_wmem = 4096 65536 ${TUNE_TCP_WMEM_HIGH:-67108864}

# 网络性能优化
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
CONF
    
    log_info "配置已写入: ${SYSCTL_FILE}"
    print_success "配置已写入: ${SYSCTL_FILE}"
}

# 应用 sysctl 配置
apply_sysctl() {
    log_debug "应用 sysctl 配置..."
    
    # 先尝试完整应用
    if sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1; then
        log_info "sysctl 配置已应用"
        print_success "配置已生效"
        return 0
    fi
    
    # 如果失败，尝试 sysctl --system
    log_warn "sysctl -p 失败，尝试 sysctl --system"
    if sysctl --system >/dev/null 2>&1; then
        print_success "配置已生效"
        return 0
    fi
    
    # 如果仍然失败，逐行应用
    log_warn "尝试逐行应用配置..."
    local errors=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # 尝试应用单个参数
        if ! sysctl -w "$line" >/dev/null 2>&1; then
            ((++errors))
        fi
    done < "$SYSCTL_FILE"
    
    if [[ $errors -gt 0 ]]; then
        print_warn "有 ${errors} 个参数未能应用（可能不被当前内核支持）"
    else
        print_success "配置已生效"
    fi
    
    return 0
}

#===============================================================================
# BBR 核心功能
#===============================================================================

# 尝试加载内核模块（带错误处理）
try_load_modules() {
    log_debug "尝试加载内核模块..."
    
    local modules=("tcp_bbr3" "tcp_bbr" "sch_fq" "sch_fq_codel" "sch_cake" "sch_fq_pie")
    local loaded=0
    local failed=0
    local -a failed_modules=()
    
    for mod in "${modules[@]}"; do
        if modprobe "$mod" 2>/dev/null; then
            log_debug "模块 ${mod} 加载成功"
            ((++loaded))
        else
            # 检查模块是否已经加载
            if lsmod | grep -q "^${mod}"; then
                log_debug "模块 ${mod} 已加载"
                ((++loaded))
            else
                log_debug "模块 ${mod} 加载失败或不存在"
                failed_modules+=("$mod")
                ((++failed))
            fi
        fi
    done
    
    log_info "模块加载完成: ${loaded} 成功, ${failed} 失败/不存在"
    
    # 如果关键模块加载失败，记录警告
    if [[ " ${failed_modules[*]} " =~ " tcp_bbr " ]] && [[ " ${failed_modules[*]} " =~ " tcp_bbr3 " ]]; then
        log_warn "BBR 相关模块均未加载，可能需要更新内核"
    fi
    
    return 0
}

# 加载指定模块（带详细错误信息）
load_module_with_error() {
    local module="$1"
    local error_output
    
    if lsmod | grep -q "^${module}"; then
        log_debug "模块 ${module} 已加载"
        return 0
    fi
    
    error_output=$(modprobe "$module" 2>&1)
    local ret=$?
    
    if [[ $ret -eq 0 ]]; then
        log_info "模块 ${module} 加载成功"
        return 0
    fi
    
    # 分析错误原因
    if echo "$error_output" | grep -qi "not found"; then
        log_warn "模块 ${module} 不存在，可能需要安装对应内核或模块包"
    elif echo "$error_output" | grep -qi "Operation not permitted"; then
        log_warn "模块 ${module} 加载被拒绝，可能是安全限制"
    elif echo "$error_output" | grep -qi "Invalid argument"; then
        log_warn "模块 ${module} 参数无效"
    else
        log_warn "模块 ${module} 加载失败: ${error_output}"
    fi
    
    return 1
}

# 获取可用的拥塞控制算法
detect_available_algos() {
    local algo_file="/proc/sys/net/ipv4/tcp_available_congestion_control"
    
    if [[ -r "$algo_file" ]]; then
        AVAILABLE_ALGOS=$(cat "$algo_file" 2>/dev/null | tr ' ' '\n' | sort -u | tr '\n' ' ')
    else
        AVAILABLE_ALGOS=""
    fi
    
    echo "$AVAILABLE_ALGOS"
}

# 获取当前拥塞控制算法
get_current_algo() {
    CURRENT_ALGO=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    echo "$CURRENT_ALGO"
}

# 获取当前队列规则
get_current_qdisc() {
    CURRENT_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
    echo "$CURRENT_QDISC"
}

# 检查算法是否可用
algo_supported() {
    local algo="$1"
    local available
    available=$(detect_available_algos)
    
    # 直接匹配
    if echo "$available" | grep -qw "$algo"; then
        return 0
    fi
    
    # BBR3 兼容性检查（某些内核以 bbr 名称提供 BBR3）
    if [[ "$algo" == "bbr3" ]]; then
        local kver
        kver=$(uname -r | sed 's/[^0-9.].*$//')
        if echo "$available" | grep -qw "bbr" && version_ge "$kver" "6.9.0"; then
            return 0
        fi
    fi
    
    return 1
}

# 检查队列规则是否可用
qdisc_supported() {
    local qdisc="$1"
    
    case "$qdisc" in
        fq|fq_codel)
            # 这些在大多数现代内核中都可用
            return 0
            ;;
        cake)
            modprobe sch_cake 2>/dev/null && return 0
            lsmod | grep -q '^sch_cake' && return 0
            return 1
            ;;
        fq_pie)
            modprobe sch_fq_pie 2>/dev/null && return 0
            lsmod | grep -q '^sch_fq_pie' && return 0
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# 规范化算法名称
normalize_algo() {
    local algo="$1"
    local kver
    kver=$(uname -r | sed 's/[^0-9.].*$//')
    
    # BBR3 可能以 bbr 名称提供
    if [[ "$algo" == "bbr3" ]]; then
        if ! echo "$(detect_available_algos)" | grep -qw "bbr3"; then
            if echo "$(detect_available_algos)" | grep -qw "bbr" && version_ge "$kver" "6.9.0"; then
                print_info "此内核以 'bbr' 名称提供 BBRv3"
                echo "bbr"
                return 0
            fi
        fi
    fi
    
    echo "$algo"
}

# 获取推荐算法
suggest_best_algo() {
    local kver
    kver=$(uname -r | sed 's/[^0-9.].*$//')
    
    # 优先检测 bbr3 模块（XanMod 等内核）
    if algo_supported "bbr3"; then
        echo "bbr3"
        return
    fi
    
    # 检测主线 6.9+ 内核的 BBRv3（以 bbr 名称提供）
    if algo_supported "bbr" && version_ge "$kver" "6.9.0"; then
        echo "bbr"  # 实际是 BBRv3
        return
    fi
    
    # BBR2（某些补丁内核）
    if algo_supported "bbr2"; then
        echo "bbr2"
        return
    fi
    
    # BBRv1
    if algo_supported "bbr"; then
        echo "bbr"
        return
    fi
    
    echo "cubic"
}

# 获取推荐队列规则（根据场景自动选择）
suggest_best_qdisc() {
    local mode="${1:-balanced}"
    
    # 根据场景推荐最佳 qdisc
    case "$mode" in
        communication)
            # 通信模式：低延迟优先，fq_codel 有更好的延迟控制
            if qdisc_supported "fq_codel"; then
                echo "fq_codel"
            else
                echo "fq"
            fi
            ;;
        video|speed)
            # 视频/极速模式：大吞吐量，fq 是 BBR 最佳搭配
            echo "fq"
            ;;
        concurrent)
            # 并发模式：公平性重要，fq_codel 更公平
            if qdisc_supported "fq_codel"; then
                echo "fq_codel"
            else
                echo "fq"
            fi
            ;;
        performance)
            # 性能模式：尝试 cake（功能最全），否则 fq
            if qdisc_supported "cake"; then
                echo "cake"
            else
                echo "fq"
            fi
            ;;
        proxy)
            # 代理模式：fq 是 BBR 最佳搭配，抗丢包性能好
            # fq 对代理流量的 pacing 效果最好
            echo "fq"
            ;;
        balanced|*)
            # 均衡模式：fq_codel 平衡延迟和吞吐
            if qdisc_supported "fq_codel"; then
                echo "fq_codel"
            else
                echo "fq"
            fi
            ;;
    esac
}

# 获取默认网络接口
get_main_iface() {
    local dev
    dev=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
    
    if [[ -z "$dev" ]]; then
        dev=$(ip -o link 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}')
    fi
    
    echo "$dev"
}

# 应用运行时 qdisc
apply_qdisc_runtime() {
    local qdisc="$1"
    local dev
    dev=$(get_main_iface)
    
    [[ -z "$dev" ]] && return 0
    command -v tc >/dev/null 2>&1 || return 0
    
    log_debug "应用 qdisc ${qdisc} 到 ${dev}"
    
    tc qdisc replace dev "$dev" root "$qdisc" 2>/dev/null || true
}

# 自动调优
auto_tune() {
    log_debug "执行自动调优..."
    
    # 测量 RTT
    local target rtt_ms
    target=$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')
    [[ -z "$target" ]] && target="8.8.8.8"
    
    rtt_ms=$(ping -c 3 -W 2 "$target" 2>/dev/null | awk -F'/' '/rtt|round-trip/ {print $5}' | head -1)
    rtt_ms="${rtt_ms%%.*}"
    [[ -z "$rtt_ms" || "$rtt_ms" == "0" || ! "$rtt_ms" =~ ^[0-9]+$ ]] && rtt_ms=20
    
    # 获取接口速度
    local dev speed_mbps
    dev=$(get_main_iface)
    speed_mbps=1000
    
    if [[ -n "$dev" ]] && command -v ethtool >/dev/null 2>&1; then
        local speed_str
        speed_str=$(ethtool "$dev" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}')
        if [[ "$speed_str" =~ ([0-9]+) ]]; then
            speed_mbps="${BASH_REMATCH[1]}"
        fi
    fi
    
    # 计算 BDP
    local bdp_bytes max_bytes
    bdp_bytes=$(( speed_mbps * 1000000 / 8 * rtt_ms / 1000 ))
    max_bytes=$(( bdp_bytes * 2 ))
    
    # 限制范围 32MB - 256MB
    [[ $max_bytes -lt 33554432 ]] && max_bytes=33554432
    [[ $max_bytes -gt 268435456 ]] && max_bytes=268435456
    
    TUNE_RMEM_MAX=$max_bytes
    TUNE_WMEM_MAX=$max_bytes
    TUNE_TCP_RMEM_HIGH=$max_bytes
    TUNE_TCP_WMEM_HIGH=$max_bytes
    
    # 选择算法
    CHOSEN_ALGO=$(suggest_best_algo)
    
    # 选择 qdisc
    if [[ "$CHOSEN_ALGO" =~ ^bbr ]]; then
        CHOSEN_QDISC="fq"
    else
        CHOSEN_QDISC="fq_codel"
    fi
    
    print_info "自动调优结果："
    print_kv "RTT" "${rtt_ms} ms"
    print_kv "接口速度" "${speed_mbps} Mbps"
    print_kv "缓冲区大小" "$((max_bytes / 1048576)) MB"
    print_kv "推荐算法" "$CHOSEN_ALGO"
    print_kv "推荐队列" "$CHOSEN_QDISC"
}


#===============================================================================
# 镜像源管理
#===============================================================================

# 获取镜像源 URL
get_mirror_url() {
    local mirror_name="${1:-tsinghua}"
    
    if [[ $USE_CHINA_MIRROR -eq 1 ]]; then
        echo "${MIRRORS_CN[$mirror_name]:-${MIRRORS_CN[tsinghua]}}"
    else
        echo ""
    fi
}

# 测试镜像源可用性
test_mirror() {
    local url="$1"
    local timeout=5
    
    if curl -s --connect-timeout "$timeout" --max-time "$timeout" -o /dev/null -w "%{http_code}" "$url" | grep -q "^[23]"; then
        return 0
    fi
    return 1
}

# 选择最佳镜像源
select_best_mirror() {
    if [[ $USE_CHINA_MIRROR -eq 0 ]]; then
        return
    fi
    
    print_info "正在测试镜像源..."
    
    for name in tsinghua aliyun ustc huawei; do
        local url="${MIRRORS_CN[$name]}"
        if test_mirror "$url"; then
            MIRROR_URL="$url"
            log_info "选择镜像源: ${name} (${url})"
            print_success "使用镜像源: ${name}"
            return 0
        fi
    done
    
    print_warn "所有国内镜像源不可用，将使用官方源"
    USE_CHINA_MIRROR=0
}

#===============================================================================
# 内核安装模块
#===============================================================================

# 切换 APT 源到官方源
switch_to_official_apt_sources() {
    local sources_file="/etc/apt/sources.list"
    local backup_file="/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)"
    
    print_step "检测到系统使用国内镜像源，正在切换到官方源..."
    
    # 备份当前源
    cp "$sources_file" "$backup_file"
    print_info "已备份原源配置到: $backup_file"
    
    # 根据发行版生成官方源
    case "$DIST_ID" in
        debian)
            local codename="${DIST_CODENAME:-bookworm}"
            cat > "$sources_file" << EOF
# Debian Official Sources - Generated by BBR3 Script
deb http://deb.debian.org/debian ${codename} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${codename}-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security ${codename}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${codename}-backports main contrib non-free non-free-firmware
EOF
            ;;
        ubuntu)
            local codename="${DIST_CODENAME:-jammy}"
            cat > "$sources_file" << EOF
# Ubuntu Official Sources - Generated by BBR3 Script
deb http://archive.ubuntu.com/ubuntu ${codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu ${codename}-security main restricted universe multiverse
EOF
            ;;
        *)
            print_warn "不支持自动切换源的系统: $DIST_ID"
            return 1
            ;;
    esac
    
    print_success "已切换到官方源"
    
    # 更新源缓存
    print_step "更新软件包缓存..."
    if apt-get update -qq; then
        print_success "软件包缓存更新成功"
        return 0
    else
        print_error "软件包缓存更新失败，正在恢复原源配置..."
        cp "$backup_file" "$sources_file"
        apt-get update -qq || true
        return 1
    fi
}

# 切换 APT 源到国内镜像
switch_to_china_apt_sources() {
    local sources_file="/etc/apt/sources.list"
    local backup_file="/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)"
    local mirror_url="${MIRROR_URL:-https://mirrors.tuna.tsinghua.edu.cn}"
    
    print_step "正在切换到国内镜像源..."
    
    # 备份当前源
    cp "$sources_file" "$backup_file"
    print_info "已备份原源配置到: $backup_file"
    
    # 根据发行版生成国内镜像源
    case "$DIST_ID" in
        debian)
            local codename="${DIST_CODENAME:-bookworm}"
            cat > "$sources_file" << EOF
# Debian China Mirror Sources - Generated by BBR3 Script
deb ${mirror_url}/debian ${codename} main contrib non-free non-free-firmware
deb ${mirror_url}/debian ${codename}-updates main contrib non-free non-free-firmware
deb ${mirror_url}/debian-security ${codename}-security main contrib non-free non-free-firmware
deb ${mirror_url}/debian ${codename}-backports main contrib non-free non-free-firmware
EOF
            ;;
        ubuntu)
            local codename="${DIST_CODENAME:-jammy}"
            cat > "$sources_file" << EOF
# Ubuntu China Mirror Sources - Generated by BBR3 Script
deb ${mirror_url}/ubuntu ${codename} main restricted universe multiverse
deb ${mirror_url}/ubuntu ${codename}-updates main restricted universe multiverse
deb ${mirror_url}/ubuntu ${codename}-backports main restricted universe multiverse
deb ${mirror_url}/ubuntu ${codename}-security main restricted universe multiverse
EOF
            ;;
        *)
            print_warn "不支持自动切换源的系统: $DIST_ID"
            return 1
            ;;
    esac
    
    print_success "已切换到国内镜像源"
    
    # 更新源缓存
    print_step "更新软件包缓存..."
    if apt-get update -qq; then
        print_success "软件包缓存更新成功"
        return 0
    else
        print_error "软件包缓存更新失败，正在恢复原源配置..."
        cp "$backup_file" "$sources_file"
        apt-get update -qq || true
        return 1
    fi
}

# 检查并修复 APT 源（用于国外环境）
fix_apt_sources_for_intl() {
    # 仅在国外网络环境下执行
    if [[ $USE_CHINA_MIRROR -eq 1 ]]; then
        return 0
    fi
    
    # 检测是否使用国内镜像
    if ! detect_apt_mirror_region; then
        print_warn "检测到国外网络环境，但系统使用国内镜像源"
        print_info "这可能导致第三方软件源（如 XanMod）无法正常访问"
        echo
        
        if [[ $NON_INTERACTIVE -eq 1 ]]; then
            # 非交互模式自动切换
            switch_to_official_apt_sources
        else
            if confirm "是否切换到官方源？（推荐）" "y"; then
                switch_to_official_apt_sources
            else
                print_warn "保持当前源配置，安装可能会失败"
            fi
        fi
    fi
}

# 检查并优化 APT 源（用于国内环境）
fix_apt_sources_for_china() {
    # 仅在国内网络环境下执行
    if [[ $USE_CHINA_MIRROR -eq 0 ]]; then
        return 0
    fi
    
    # 检测是否已使用国内镜像
    if detect_apt_mirror_region; then
        # 使用官方源，询问是否切换到国内镜像
        print_info "检测到国内网络环境，但系统使用官方源"
        print_info "切换到国内镜像可以加速软件包下载"
        echo
        
        if [[ $NON_INTERACTIVE -eq 0 ]]; then
            if confirm "是否切换到国内镜像源？" "n"; then
                switch_to_china_apt_sources
            fi
        fi
    fi
}

# 内核安装前检查
kernel_precheck() {
    local kernel_type="$1"
    
    # 架构检查
    if [[ "$ARCH_ID" != "amd64" ]]; then
        print_error "当前架构 ${ARCH_ID} 不支持安装 ${kernel_type} 内核（仅支持 amd64）"
        return 1
    fi
    
    # 虚拟化检查
    case "$VIRT_TYPE" in
        openvz|lxc|docker|wsl)
            print_error "容器环境 ${VIRT_TYPE} 无法安装内核"
            return 1
            ;;
    esac
    
    # 磁盘空间检查
    if ! precheck_disk; then
        return 1
    fi
    
    # 检查并修复 APT 源（国外环境）
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        fix_apt_sources_for_intl
    fi
    
    return 0
}

# 全局变量：记录安装前的内核列表
KERNEL_LIST_BEFORE=""
INSTALLED_KERNEL_PKG=""

# 记录安装前的内核列表
record_kernel_list_before() {
    log_debug "记录安装前的内核列表..."
    
    case "$PKG_MANAGER" in
        apt)
            KERNEL_LIST_BEFORE=$(dpkg -l | grep -E '^ii\s+linux-image-' | awk '{print $2}' | sort)
            ;;
        dnf|yum)
            KERNEL_LIST_BEFORE=$(rpm -qa | grep -E '^kernel-[0-9]|^kernel-ml|^kernel-lt' | sort)
            ;;
    esac
    
    log_debug "安装前内核列表: ${KERNEL_LIST_BEFORE}"
}

# 验证内核安装是否成功
verify_kernel_installation() {
    local kernel_type="$1"
    local expected_pattern="${2:-}"
    
    echo
    print_header "内核安装验证"
    
    local kernel_list_after=""
    local new_kernels=""
    local all_checks_passed=1
    local kernel_version=""
    
    # ========== 检查 1: 新内核包 ==========
    echo -n "  [1/5] 检查新安装的内核包..."
    
    case "$PKG_MANAGER" in
        apt)
            kernel_list_after=$(dpkg -l | grep -E '^ii\s+linux-image-' | awk '{print $2}' | sort)
            new_kernels=$(comm -13 <(echo "$KERNEL_LIST_BEFORE") <(echo "$kernel_list_after"))
            ;;
        dnf|yum)
            kernel_list_after=$(rpm -qa | grep -E '^kernel-[0-9]|^kernel-ml|^kernel-lt' | sort)
            new_kernels=$(comm -13 <(echo "$KERNEL_LIST_BEFORE") <(echo "$kernel_list_after"))
            ;;
    esac
    
    if [[ -z "$new_kernels" ]]; then
        echo -e " [${RED}${ICON_FAIL}${NC}] 未检测到"
        all_checks_passed=0
    else
        local pkg_count
        pkg_count=$(echo "$new_kernels" | grep -c . || echo 0)
        echo -e " [${GREEN}${ICON_OK}${NC}] 检测到 ${pkg_count} 个新包"
        echo "      新安装的包:"
        echo "$new_kernels" | while read -r pkg; do
            [[ -n "$pkg" ]] && echo "        - $pkg"
        done
    fi
    
    # ========== 检查 2: vmlinuz 内核文件 ==========
    echo -n "  [2/5] 检查内核文件 (vmlinuz)..."
    
    local kernel_file=""
    case "$PKG_MANAGER" in
        apt)
            for pkg in $new_kernels; do
                local version="${pkg#linux-image-}"
                version="${version%-unsigned}"
                if [[ -f "/boot/vmlinuz-${version}" ]]; then
                    kernel_file="/boot/vmlinuz-${version}"
                    kernel_version="$version"
                    INSTALLED_KERNEL_PKG="$pkg"
                    break
                fi
            done
            ;;
        dnf|yum)
            for pkg in $new_kernels; do
                local version
                version=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' "$pkg" 2>/dev/null)
                if [[ -f "/boot/vmlinuz-${version}" ]]; then
                    kernel_file="/boot/vmlinuz-${version}"
                    kernel_version="$version"
                    INSTALLED_KERNEL_PKG="$pkg"
                    break
                fi
            done
            ;;
    esac
    
    if [[ -z "$kernel_file" ]]; then
        echo -e " [${RED}${ICON_FAIL}${NC}] 未找到"
        all_checks_passed=0
    else
        local file_size
        file_size=$(ls -lh "$kernel_file" 2>/dev/null | awk '{print $5}')
        echo -e " [${GREEN}${ICON_OK}${NC}] 存在"
        echo "      文件: $kernel_file"
        echo "      大小: $file_size"
    fi
    
    # ========== 检查 3: initramfs 文件 ==========
    echo -n "  [3/5] 检查 initramfs 文件..."
    
    local initramfs_file=""
    if [[ -n "$kernel_version" ]]; then
        case "$PKG_MANAGER" in
            apt)
                [[ -f "/boot/initrd.img-${kernel_version}" ]] && initramfs_file="/boot/initrd.img-${kernel_version}"
                ;;
            dnf|yum)
                [[ -f "/boot/initramfs-${kernel_version}.img" ]] && initramfs_file="/boot/initramfs-${kernel_version}.img"
                ;;
        esac
    fi
    
    if [[ -z "$initramfs_file" ]]; then
        echo -e " [${YELLOW}${ICON_WARN}${NC}] 未找到，尝试生成..."
        if regenerate_initramfs "$new_kernels"; then
            # 重新检查
            case "$PKG_MANAGER" in
                apt)
                    [[ -f "/boot/initrd.img-${kernel_version}" ]] && initramfs_file="/boot/initrd.img-${kernel_version}"
                    ;;
                dnf|yum)
                    [[ -f "/boot/initramfs-${kernel_version}.img" ]] && initramfs_file="/boot/initramfs-${kernel_version}.img"
                    ;;
            esac
            if [[ -n "$initramfs_file" ]]; then
                echo -e "      [${GREEN}${ICON_OK}${NC}] 生成成功: $initramfs_file"
            else
                echo -e "      [${RED}${ICON_FAIL}${NC}] 生成失败"
                all_checks_passed=0
            fi
        else
            echo -e "      [${RED}${ICON_FAIL}${NC}] 生成失败"
            all_checks_passed=0
        fi
    else
        local file_size
        file_size=$(ls -lh "$initramfs_file" 2>/dev/null | awk '{print $5}')
        echo -e " [${GREEN}${ICON_OK}${NC}] 存在"
        echo "      文件: $initramfs_file"
        echo "      大小: $file_size"
    fi
    
    # ========== 检查 4: GRUB 配置 ==========
    echo -n "  [4/5] 检查 GRUB 配置..."
    
    local grub_cfg=""
    for cfg in /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg; do
        [[ -f "$cfg" ]] && grub_cfg="$cfg" && break
    done
    
    local grub_has_kernel=0
    if [[ -n "$grub_cfg" ]] && [[ -n "$kernel_version" ]]; then
        if grep -q "$kernel_version" "$grub_cfg" 2>/dev/null; then
            grub_has_kernel=1
        fi
    fi
    
    if [[ $grub_has_kernel -eq 0 ]]; then
        echo -e " [${YELLOW}${ICON_WARN}${NC}] 未找到新内核，尝试更新..."
        if update_grub_config; then
            # 重新检查
            if [[ -n "$grub_cfg" ]] && grep -q "$kernel_version" "$grub_cfg" 2>/dev/null; then
                echo -e "      [${GREEN}${ICON_OK}${NC}] GRUB 更新成功"
                grub_has_kernel=1
            else
                echo -e "      [${RED}${ICON_FAIL}${NC}] GRUB 更新后仍未找到新内核"
                all_checks_passed=0
            fi
        else
            echo -e "      [${RED}${ICON_FAIL}${NC}] GRUB 更新失败"
            all_checks_passed=0
        fi
    else
        echo -e " [${GREEN}${ICON_OK}${NC}] 已包含新内核"
        echo "      配置文件: $grub_cfg"
    fi
    
    # ========== 检查 5: 默认启动项 ==========
    echo -n "  [5/5] 检查默认启动项..."
    
    local default_kernel=""
    if [[ -f /etc/default/grub ]]; then
        local grub_default
        grub_default=$(grep "^GRUB_DEFAULT=" /etc/default/grub 2>/dev/null | cut -d= -f2 | tr -d '"')
        if [[ "$grub_default" == "0" ]] || [[ "$grub_default" == "saved" ]]; then
            # 获取第一个启动项
            if [[ -n "$grub_cfg" ]]; then
                default_kernel=$(grep -m1 "menuentry.*linux" "$grub_cfg" 2>/dev/null | head -1)
            fi
            echo -e " [${GREEN}${ICON_OK}${NC}] 默认启动最新内核"
        else
            echo -e " [${YELLOW}${ICON_WARN}${NC}] GRUB_DEFAULT=$grub_default"
            echo "      可能不会启动新内核，请检查 /etc/default/grub"
        fi
    else
        echo -e " [${YELLOW}${ICON_WARN}${NC}] 无法检测"
    fi
    
    # ========== 总结 ==========
    echo
    print_separator
    
    if [[ $all_checks_passed -eq 1 ]]; then
        print_success "内核安装验证通过！"
        echo
        echo "  新内核版本: ${kernel_version}"
        echo "  内核文件:   ${kernel_file}"
        echo "  initramfs:  ${initramfs_file}"
        echo
        return 0
    else
        print_error "内核安装验证失败！"
        echo
        print_warn "建议操作："
        echo "  1. 不要重启系统"
        echo "  2. 检查 /boot 目录空间: df -h /boot"
        echo "  3. 检查安装日志: /var/log/apt/history.log"
        echo "  4. 尝试重新安装或回滚"
        echo
        return 1
    fi
}

# 重新生成 initramfs
regenerate_initramfs() {
    local kernels="$1"
    
    print_step "重新生成 initramfs..."
    
    case "$PKG_MANAGER" in
        apt)
            for pkg in $kernels; do
                local version="${pkg#linux-image-}"
                version="${version%-unsigned}"
                print_info "为 ${version} 生成 initramfs..."
                if ! update-initramfs -c -k "$version" 2>/dev/null; then
                    # 尝试使用 -u 更新
                    update-initramfs -u -k "$version" || return 1
                fi
            done
            ;;
        dnf|yum)
            for pkg in $kernels; do
                local version
                version=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' "$pkg" 2>/dev/null)
                print_info "为 ${version} 生成 initramfs..."
                dracut -f "/boot/initramfs-${version}.img" "$version" || return 1
            done
            ;;
    esac
    
    return 0
}

# 验证 GRUB 配置
verify_grub_config() {
    local kernels="$1"
    
    print_step "验证 GRUB 配置..."
    
    local grub_cfg=""
    if [[ -f /boot/grub/grub.cfg ]]; then
        grub_cfg="/boot/grub/grub.cfg"
    elif [[ -f /boot/grub2/grub.cfg ]]; then
        grub_cfg="/boot/grub2/grub.cfg"
    elif [[ -f /boot/efi/EFI/*/grub.cfg ]]; then
        grub_cfg=$(ls /boot/efi/EFI/*/grub.cfg 2>/dev/null | head -1)
    fi
    
    if [[ -z "$grub_cfg" ]] || [[ ! -f "$grub_cfg" ]]; then
        print_warn "未找到 GRUB 配置文件"
        return 1
    fi
    
    # 检查新内核是否在 GRUB 配置中
    for pkg in $kernels; do
        local version=""
        case "$PKG_MANAGER" in
            apt)
                version="${pkg#linux-image-}"
                version="${version%-unsigned}"
                ;;
            dnf|yum)
                version=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' "$pkg" 2>/dev/null)
                ;;
        esac
        
        if grep -q "$version" "$grub_cfg" 2>/dev/null; then
            print_success "GRUB 配置包含新内核: ${version}"
            return 0
        fi
    done
    
    print_warn "GRUB 配置中未找到新内核"
    return 1
}

# 更新 GRUB 配置
update_grub_config() {
    print_step "更新 GRUB 配置..."
    
    case "$PKG_MANAGER" in
        apt)
            if command -v update-grub >/dev/null 2>&1; then
                update-grub || return 1
            elif command -v grub-mkconfig >/dev/null 2>&1; then
                grub-mkconfig -o /boot/grub/grub.cfg || return 1
            else
                print_error "未找到 GRUB 更新命令"
                return 1
            fi
            ;;
        dnf|yum)
            if command -v grub2-mkconfig >/dev/null 2>&1; then
                local grub_cfg="/boot/grub2/grub.cfg"
                [[ -d /boot/efi/EFI ]] && grub_cfg="/boot/efi/EFI/$(ls /boot/efi/EFI/ | grep -v BOOT | head -1)/grub.cfg"
                grub2-mkconfig -o "$grub_cfg" || return 1
            else
                print_error "未找到 GRUB 更新命令"
                return 1
            fi
            ;;
    esac
    
    print_success "GRUB 配置已更新"
    return 0
}

# 回滚内核安装
rollback_kernel_installation() {
    local kernel_type="$1"
    
    print_header "回滚 ${kernel_type} 内核安装"
    print_warn "内核安装验证失败，正在回滚..."
    
    if [[ -z "$INSTALLED_KERNEL_PKG" ]]; then
        # 尝试找出新安装的内核包
        local kernel_list_after=""
        case "$PKG_MANAGER" in
            apt)
                kernel_list_after=$(dpkg -l | grep -E '^ii\s+linux-image-' | awk '{print $2}' | sort)
                INSTALLED_KERNEL_PKG=$(comm -13 <(echo "$KERNEL_LIST_BEFORE") <(echo "$kernel_list_after") | head -1)
                ;;
            dnf|yum)
                kernel_list_after=$(rpm -qa | grep -E '^kernel-[0-9]|^kernel-ml|^kernel-lt' | sort)
                INSTALLED_KERNEL_PKG=$(comm -13 <(echo "$KERNEL_LIST_BEFORE") <(echo "$kernel_list_after") | head -1)
                ;;
        esac
    fi
    
    if [[ -z "$INSTALLED_KERNEL_PKG" ]]; then
        print_warn "未找到需要回滚的内核包"
        return 1
    fi
    
    print_step "卸载内核包: ${INSTALLED_KERNEL_PKG}"
    
    case "$PKG_MANAGER" in
        apt)
            # 卸载内核包及相关包
            apt-get remove -y "$INSTALLED_KERNEL_PKG" || true
            # 清理相关的 headers 包
            local headers_pkg="${INSTALLED_KERNEL_PKG/linux-image/linux-headers}"
            apt-get remove -y "$headers_pkg" 2>/dev/null || true
            # 自动清理
            apt-get autoremove -y || true
            ;;
        dnf|yum)
            if command -v dnf >/dev/null 2>&1; then
                dnf remove -y "$INSTALLED_KERNEL_PKG" || true
            else
                yum remove -y "$INSTALLED_KERNEL_PKG" || true
            fi
            ;;
    esac
    
    # 更新 GRUB 配置
    update_grub_config || true
    
    print_success "内核回滚完成"
    print_info "系统将继续使用当前内核: $(uname -r)"
    
    return 0
}

# 安全的内核安装包装函数
safe_kernel_install() {
    local kernel_type="$1"
    local install_func="$2"
    
    # 记录安装前状态
    record_kernel_list_before
    
    # 执行安装
    if ! $install_func; then
        print_error "${kernel_type} 内核安装失败"
        return 1
    fi
    
    # 验证安装
    if ! verify_kernel_installation "$kernel_type"; then
        print_error "${kernel_type} 内核安装验证失败"
        
        if [[ $NON_INTERACTIVE -eq 1 ]]; then
            # 非交互模式自动回滚
            rollback_kernel_installation "$kernel_type"
        else
            if confirm "是否回滚内核安装？（强烈建议）" "y"; then
                rollback_kernel_installation "$kernel_type"
            else
                print_error "警告：内核安装可能不完整，重启后系统可能无法启动！"
                print_warn "建议手动检查 /boot 目录和 GRUB 配置"
            fi
        fi
        return 1
    fi
    
    print_success "${kernel_type} 内核安装并验证成功"
    return 0
}

# 全局变量：XanMod 安装方式
XANMOD_INSTALL_METHOD="auto"  # auto, apt, direct

# 检测 CPU 支持的 x86-64 微架构级别
detect_cpu_level() {
    local level="1"
    local cpuinfo
    cpuinfo=$(cat /proc/cpuinfo 2>/dev/null)
    
    if echo "$cpuinfo" | grep -q "avx512"; then
        level="4"
    elif echo "$cpuinfo" | grep -q "avx2"; then
        level="3"
    elif echo "$cpuinfo" | grep -q "sse4_2"; then
        level="2"
    fi
    
    echo "$level"
}



# 从 GitHub 下载 XanMod deb 包
download_xanmod_from_github() {
    local tmp_dir="/tmp/xanmod-install-$$"
    mkdir -p "$tmp_dir"
    
    print_step "从 GitHub 获取 XanMod 最新版本..."
    
    # XanMod 官方 GitHub 不直接提供 deb 包
    # 但我们可以使用第三方预编译源或者直接从官方 CDN 下载
    
    # 检测 CPU 支持的指令集级别
    local cpu_level="v1"
    if grep -q "avx512" /proc/cpuinfo 2>/dev/null; then
        cpu_level="v4"
    elif grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
        cpu_level="v3"
    elif grep -q "avx" /proc/cpuinfo 2>/dev/null; then
        cpu_level="v2"
    fi
    
    print_info "检测到 CPU 支持级别: x64${cpu_level}"
    
    # 使用 jsDelivr CDN 加速 GitHub 下载（如果可用）
    local jsdelivr_available=0
    if curl -fsSL --connect-timeout 5 "https://cdn.jsdelivr.net" >/dev/null 2>&1; then
        jsdelivr_available=1
        print_info "jsDelivr CDN 可用，将使用加速下载"
    fi
    
    # 尝试从多个源下载
    local download_urls=(
        "https://dl.xanmod.org"
        "https://github.com/xanmod/linux/releases"
    )
    
    # 由于 XanMod 主要通过 APT 源分发，GitHub 上没有直接的 deb 包
    # 我们改为优化 APT 源的下载速度
    
    rm -rf "$tmp_dir"
    return 1  # 返回失败，回退到 APT 方式
}

# 直接从 XanMod APT 池下载 deb 包（绕过 APT 索引）
download_xanmod_direct() {
    local cpu_level
    cpu_level=$(detect_cpu_level)
    local tmp_dir="/tmp/xanmod-install-$$"
    
    mkdir -p "$tmp_dir"
    
    print_step "直接下载 XanMod 内核包..."
    print_info "CPU 微架构级别: x64v${cpu_level}"
    
    # 从 APT 源的 Packages 文件获取包信息
    local pkg_list_url="http://deb.xanmod.org/dists/releases/main/binary-amd64/Packages.gz"
    local pkg_list
    
    print_info "获取包列表..."
    pkg_list=$(curl -fsSL --connect-timeout 15 "$pkg_list_url" 2>/dev/null | gunzip 2>/dev/null)
    
    if [[ -z "$pkg_list" ]]; then
        pkg_list_url="http://deb.xanmod.org/dists/releases/main/binary-amd64/Packages"
        pkg_list=$(curl -fsSL --connect-timeout 15 "$pkg_list_url" 2>/dev/null)
    fi
    
    if [[ -z "$pkg_list" ]]; then
        print_warn "无法获取包列表"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # 查找匹配的内核包
    local pkg_filename=""
    local pkg_name=""
    
    for try_level in $cpu_level 3 2 1; do
        pkg_name="linux-xanmod-x64v${try_level}"
        pkg_filename=$(echo "$pkg_list" | awk -v pkg="$pkg_name" '
            /^Package:/ { current_pkg = $2 }
            /^Filename:/ && current_pkg == pkg { print $2; exit }
        ')
        [[ -n "$pkg_filename" ]] && break
    done
    
    if [[ -z "$pkg_filename" ]]; then
        for pkg_name in "linux-xanmod-edge" "linux-xanmod-lts" "linux-xanmod"; do
            pkg_filename=$(echo "$pkg_list" | awk -v pkg="$pkg_name" '
                /^Package:/ { current_pkg = $2 }
                /^Filename:/ && current_pkg == pkg { print $2; exit }
            ')
            [[ -n "$pkg_filename" ]] && break
        done
    fi
    
    if [[ -z "$pkg_filename" ]]; then
        print_warn "未找到合适的内核包"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    print_info "找到内核包: ${pkg_name}"
    
    local pkg_url="http://deb.xanmod.org/${pkg_filename}"
    local deb_file="${tmp_dir}/$(basename "$pkg_filename")"
    
    print_info "下载: $(basename "$pkg_filename")"
    print_info "文件较大（约 100-200MB），请耐心等待..."
    
    # 使用 wget 或 curl 下载
    if command -v wget >/dev/null 2>&1; then
        if ! wget --progress=bar:force -O "$deb_file" "$pkg_url"; then
            print_error "下载失败"
            rm -rf "$tmp_dir"
            return 1
        fi
    else
        if ! curl -fL --progress-bar -o "$deb_file" "$pkg_url"; then
            print_error "下载失败"
            rm -rf "$tmp_dir"
            return 1
        fi
    fi
    
    print_success "下载完成"
    
    # 安装 deb 包
    print_step "安装内核包..."
    if dpkg -i "$deb_file"; then
        print_success "内核包安装成功"
        apt-get install -f -y 2>/dev/null || true
        rm -rf "$tmp_dir"
        return 0
    else
        print_warn "dpkg 安装失败，尝试修复依赖..."
        apt-get install -f -y
        if dpkg -i "$deb_file"; then
            print_success "内核包安装成功"
            rm -rf "$tmp_dir"
            return 0
        fi
        print_error "内核包安装失败"
        rm -rf "$tmp_dir"
        return 1
    fi
}

# 测试 XanMod APT 源速度
test_xanmod_apt_speed() {
    local test_url="http://deb.xanmod.org/gpg.key"
    local start_time end_time elapsed
    
    start_time=$(date +%s%N)
    if curl -fsSL --connect-timeout 5 --max-time 10 "$test_url" >/dev/null 2>&1; then
        end_time=$(date +%s%N)
        elapsed=$(( (end_time - start_time) / 1000000 ))  # 毫秒
        echo "$elapsed"
        return 0
    fi
    
    echo "9999"
    return 1
}

# 选择最佳 XanMod 下载方式
select_xanmod_download_method() {
    print_step "检测最佳下载方式..."
    
    # 测试官方 APT 源速度
    local apt_speed
    apt_speed=$(test_xanmod_apt_speed)
    print_info "XanMod APT 源响应时间: ${apt_speed}ms"
    
    # 如果是国外环境且 APT 源响应较慢，使用直接下载
    if [[ $USE_CHINA_MIRROR -eq 0 ]] && [[ $apt_speed -gt 2000 ]]; then
        print_info "国外环境检测到 APT 源较慢，尝试直接下载..."
        XANMOD_INSTALL_METHOD="direct"
        return 0
    fi
    
    # 如果 APT 源响应很慢（超过 5 秒）
    if [[ $apt_speed -gt 5000 ]]; then
        print_warn "XanMod APT 源响应较慢"
        
        if [[ $NON_INTERACTIVE -eq 0 ]]; then
            echo
            print_info "请选择下载方式："
            echo "  1) 直接下载 deb 包（推荐，可能更快）"
            echo "  2) 使用 APT 源安装（标准方式）"
            echo "  3) 取消安装"
            echo
            read_choice "请选择" 3 "1"
            
            case "$MENU_CHOICE" in
                1)
                    XANMOD_INSTALL_METHOD="direct"
                    ;;
                2)
                    XANMOD_INSTALL_METHOD="apt"
                    ;;
                3)
                    return 1
                    ;;
            esac
        else
            # 非交互模式，使用直接下载
            XANMOD_INSTALL_METHOD="direct"
        fi
    else
        XANMOD_INSTALL_METHOD="apt"
    fi
    
    return 0
}

# XanMod 内核安装核心逻辑（内部函数）
_install_kernel_xanmod_core() {
    case "$DIST_ID" in
        debian|ubuntu)
            # 检测最佳下载方式
            select_xanmod_download_method || return 1
            
            # 安装依赖
            apt-get update -qq
            apt-get install -y -qq curl gnupg
            
            # 如果选择直接下载方式
            if [[ "$XANMOD_INSTALL_METHOD" == "direct" ]]; then
                print_info "使用直接下载方式安装..."
                if download_xanmod_direct; then
                    return 0
                else
                    print_warn "直接下载失败，回退到 APT 方式..."
                    XANMOD_INSTALL_METHOD="apt"
                fi
            fi
            
            # APT 方式安装
            print_step "添加 XanMod APT 源..."
            
            # 添加 GPG 密钥（使用多个源尝试，包括 GitHub 镜像）
            local gpg_urls=(
                "https://dl.xanmod.org/gpg.key"
                "https://raw.githubusercontent.com/xanmod/linux/main/gpg.key"
            )
            

            
            local gpg_downloaded=0
            for gpg_url in "${gpg_urls[@]}"; do
                print_info "尝试从 ${gpg_url} 获取 GPG 密钥..."
                if curl -fsSL --connect-timeout 10 "$gpg_url" | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg 2>/dev/null; then
                    gpg_downloaded=1
                    print_success "GPG 密钥获取成功"
                    break
                fi
            done
            
            if [[ $gpg_downloaded -eq 0 ]]; then
                print_error "无法获取 XanMod GPG 密钥"
                return 1
            fi
            
            # 添加源
            local repo_url="http://deb.xanmod.org"
            echo "deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] ${repo_url} releases main" > /etc/apt/sources.list.d/xanmod.list
            
            # 更新源（带重试）
            local retry_count=0
            local max_retries=3
            while [[ $retry_count -lt $max_retries ]]; do
                if apt-get update 2>&1 | grep -v "^W:"; then
                    break
                fi
                ((++retry_count))
                print_warn "更新源失败，重试 ${retry_count}/${max_retries}..."
                sleep 2
            done
            
            # 检测 CPU 支持的指令集级别
            local cpu_level="1"
            if grep -q "avx512" /proc/cpuinfo 2>/dev/null; then
                cpu_level="4"
            elif grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
                cpu_level="3"
            elif grep -q "avx" /proc/cpuinfo 2>/dev/null; then
                cpu_level="2"
            fi
            
            print_info "检测到 CPU 支持级别: x64v${cpu_level}"
            
            # 根据 CPU 级别选择合适的内核包
            local candidates=()
            case "$cpu_level" in
                4)
                    candidates=("linux-xanmod-x64v4" "linux-xanmod-x64v3" "linux-xanmod-x64v2" "linux-xanmod")
                    ;;
                3)
                    candidates=("linux-xanmod-x64v3" "linux-xanmod-x64v2" "linux-xanmod")
                    ;;
                2)
                    candidates=("linux-xanmod-x64v2" "linux-xanmod")
                    ;;
                *)
                    candidates=("linux-xanmod")
                    ;;
            esac
            
            # 添加 edge 和 lts 变体
            candidates+=("linux-xanmod-edge" "linux-xanmod-lts")
            
            # 尝试安装
            print_step "安装 XanMod 内核..."
            print_info "内核包较大（约 100-200MB），下载可能需要几分钟..."
            local installed=0
            
            for pkg in "${candidates[@]}"; do
                if apt-cache show "$pkg" >/dev/null 2>&1; then
                    print_info "尝试安装 ${pkg}..."
                    
                    # 使用 apt-get 安装，显示进度
                    # 添加 -o 选项优化下载
                    if apt-get install -y \
                        -o Acquire::http::Timeout=60 \
                        -o Acquire::https::Timeout=60 \
                        -o Acquire::Retries=3 \
                        "$pkg"; then
                        installed=1
                        print_success "成功安装 ${pkg}"
                        break
                    else
                        print_warn "安装 ${pkg} 失败，尝试下一个..."
                    fi
                fi
            done
            
            if [[ $installed -eq 0 ]]; then
                print_error "未找到可安装的 XanMod 内核包"
                return 1
            fi
            ;;
        *)
            print_error "XanMod 仅支持 Debian/Ubuntu 系统"
            return 1
            ;;
    esac
    
    return 0
}

# 安装 XanMod 内核（带验证和回滚）
install_kernel_xanmod() {
    print_header "安装 XanMod 内核"
    
    kernel_precheck "XanMod" || return 1
    
    # 使用安全安装包装函数
    if safe_kernel_install "XanMod" _install_kernel_xanmod_core; then
        print_warn "请重启系统以使用新内核"
        return 0
    else
        return 1
    fi
}

# Liquorix 内核安装核心逻辑（内部函数）
_install_kernel_liquorix_core() {
    case "$DIST_ID" in
        ubuntu)
            print_step "添加 Liquorix PPA..."
            apt-get update -qq
            apt-get install -y -qq software-properties-common
            add-apt-repository -y ppa:damentz/liquorix
            apt-get update -qq
            
            print_step "安装 Liquorix 内核..."
            apt-get install -y linux-image-liquorix-amd64 linux-headers-liquorix-amd64
            ;;
        debian)
            print_step "安装 Liquorix 内核..."
            curl -s 'https://liquorix.net/install-liquorix.sh' | bash
            ;;
        *)
            print_error "Liquorix 仅支持 Debian/Ubuntu 系统"
            return 1
            ;;
    esac
    
    return 0
}

# 安装 Liquorix 内核（带验证和回滚）
install_kernel_liquorix() {
    print_header "安装 Liquorix 内核"
    
    kernel_precheck "Liquorix" || return 1
    
    # 使用安全安装包装函数
    if safe_kernel_install "Liquorix" _install_kernel_liquorix_core; then
        print_warn "请重启系统以使用新内核"
        return 0
    else
        return 1
    fi
}

# ELRepo 内核安装核心逻辑（内部函数）
_install_kernel_elrepo_core() {
    case "$DIST_ID" in
        centos|rhel|rocky|almalinux)
            local rhel_ver="${DIST_VER%%.*}"
            
            print_step "更新软件包缓存..."
            if command -v dnf >/dev/null 2>&1; then
                dnf makecache -q || true
            else
                yum makecache -q || true
            fi
            
            print_step "启用 ELRepo..."
            
            local elrepo_url="https://www.elrepo.org/elrepo-release-${rhel_ver}.el${rhel_ver}.elrepo.noarch.rpm"
            
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y "$elrepo_url" || true
                
                print_step "安装 kernel-ml..."
                dnf --enablerepo=elrepo-kernel install -y kernel-ml
            else
                yum install -y "$elrepo_url" || true
                
                print_step "安装 kernel-ml..."
                yum --enablerepo=elrepo-kernel install -y kernel-ml
            fi
            ;;
        *)
            print_error "ELRepo 仅支持 RHEL/CentOS/Rocky/AlmaLinux 系统"
            return 1
            ;;
    esac
    
    return 0
}

# 安装 ELRepo 内核（带验证和回滚）
install_kernel_elrepo() {
    print_header "安装 ELRepo 内核"
    
    kernel_precheck "ELRepo" || return 1
    
    # 使用安全安装包装函数
    if safe_kernel_install "ELRepo" _install_kernel_elrepo_core; then
        print_warn "请重启系统以使用新内核"
        return 0
    else
        return 1
    fi
}

# HWE 内核安装核心逻辑（内部函数）
_install_kernel_hwe_core() {
    print_step "更新软件包列表..."
    apt-get update -qq
    
    print_step "安装 HWE 内核..."
    
    case "$DIST_VER" in
        16.04*)
            apt-get install -y linux-generic-hwe-16.04
            ;;
        18.04*)
            apt-get install -y linux-generic-hwe-18.04
            ;;
        20.04*)
            apt-get install -y linux-generic-hwe-20.04
            ;;
        *)
            print_error "当前 Ubuntu 版本不支持 HWE 内核"
            return 1
            ;;
    esac
    
    return 0
}

# 安装 HWE 内核（带验证和回滚）
install_kernel_hwe() {
    print_header "安装 HWE 内核"
    
    if [[ "$DIST_ID" != "ubuntu" ]]; then
        print_error "HWE 内核仅支持 Ubuntu 系统"
        return 1
    fi
    
    kernel_precheck "HWE" || return 1
    
    # 使用安全安装包装函数
    if safe_kernel_install "HWE" _install_kernel_hwe_core; then
        print_warn "请重启系统以使用新内核"
        return 0
    else
        return 1
    fi
}

# 重启提示
prompt_reboot() {
    echo
    if confirm "是否现在重启系统？" "n"; then
        print_info "系统将在 5 秒后重启..."
        sleep 5
        reboot
    else
        print_warn "请记得稍后重启系统以使用新内核"
    fi
}


#===============================================================================
# 状态显示
#===============================================================================

# 显示当前状态
show_status() {
    # 确保系统信息已检测
    [[ -z "$DIST_ID" ]] && detect_os
    [[ -z "$ARCH_ID" ]] && detect_arch
    [[ -z "$VIRT_TYPE" ]] && detect_virt
    
    print_header "系统状态"
    
    # 系统信息
    echo -e "${BOLD}系统信息${NC}"
    print_kv "操作系统" "$(get_os_pretty_name)"
    print_kv "内核版本" "$(uname -r)"
    print_kv "CPU 架构" "$ARCH_ID"
    print_kv "虚拟化" "${VIRT_TYPE:-未知}"
    echo
    
    # BBR 状态
    echo -e "${BOLD}BBR 状态${NC}"
    local current_algo current_qdisc available_algos
    current_algo=$(get_current_algo)
    current_qdisc=$(get_current_qdisc)
    available_algos=$(detect_available_algos)
    
    print_kv "当前算法" "$current_algo"
    print_kv "当前队列" "$current_qdisc"
    print_kv "可用算法" "$available_algos"
    echo
    
    # BBR3 检测
    echo -e "${BOLD}BBR3 检测${NC}"
    local kver bbr3_available bbr3_active
    kver=$(uname -r | sed 's/[^0-9.].*$//')
    
    if algo_supported "bbr3"; then
        bbr3_available="${GREEN}是${NC}"
    else
        bbr3_available="${RED}否${NC}"
    fi
    
    if [[ "$current_algo" == "bbr3" ]] || { [[ "$current_algo" == "bbr" ]] && version_ge "$kver" "6.9.0"; }; then
        bbr3_active="${GREEN}是${NC}"
    else
        bbr3_active="${RED}否${NC}"
    fi
    
    echo -e "  BBR3 可用    : ${bbr3_available}"
    echo -e "  BBR3 已启用  : ${bbr3_active}"
    print_kv "内核版本" "$kver"
    
    if version_ge "$kver" "6.9.0"; then
        echo -e "  主线 BBRv3   : ${GREEN}是${NC} (>= 6.9.0)"
    else
        echo -e "  主线 BBRv3   : ${YELLOW}否${NC} (需要 >= 6.9.0)"
    fi
    echo
    
    # 推荐
    echo -e "${BOLD}推荐配置${NC}"
    local recommended
    recommended=$(suggest_best_algo)
    print_kv "推荐算法" "$recommended"
    print_kv "推荐队列" "fq"
    
    # 场景模式推荐
    recommend_scene_mode
    print_kv "推荐场景" "$(get_scene_name "$SCENE_RECOMMENDED")"
    echo -e "  ${DIM}$(get_scene_description "$SCENE_RECOMMENDED")${NC}"
    echo
    
    # 备份信息
    if [[ -d "$BACKUP_DIR" ]]; then
        local backup_count
        backup_count=$(ls -1 "${BACKUP_DIR}/"*.bak 2>/dev/null | wc -l || echo 0)
        if [[ $backup_count -gt 0 ]]; then
            echo -e "${BOLD}备份信息${NC}"
            print_kv "备份数量" "$backup_count"
            echo
        fi
    fi
    
    # 配置文件
    if [[ -f "$SYSCTL_FILE" ]]; then
        echo -e "${BOLD}当前配置 (${SYSCTL_FILE})${NC}"
        grep -E '^net\.(core|ipv4)' "$SYSCTL_FILE" 2>/dev/null | head -5 | while read -r line; do
            echo "  $line"
        done
        echo
    fi
}

#===============================================================================
# 交互式菜单
#===============================================================================

# 主菜单
show_main_menu() {
    # 首次进入时检测并推荐场景模式
    recommend_scene_mode
    
    while true; do
        print_header "BBR3 一键脚本"
        
        echo -e "${DIM}当前: $(get_current_algo) / $(get_current_qdisc) | 推荐: $(suggest_best_algo)${NC}"
        echo -e "${DIM}推荐场景: $(get_scene_name "$SCENE_RECOMMENDED")${NC}"
        echo
        echo -e "${YELLOW}提示: 选项 5 和 6 功能相似，选择其一即可，后者会覆盖前者配置${NC}"
        echo
        
        print_menu "请选择操作" \
            "查看当前状态" \
            "启用 BBR (推荐)" \
            "启用 BBR2" \
            "启用 BBR3" \
            "场景配置 (按用途优化，推荐VPS代理使用)" \
            "自动优化配置 (按网络环境自动调参)" \
            "安装新内核" \
            "备份/恢复配置" \
            "卸载配置" \
            "安装快捷命令 bbr3"
        
        read_choice "请选择" 10
        
        case "$MENU_CHOICE" in
            0) 
                print_info "感谢使用，再见！"
                exit 0
                ;;
            1) show_status ;;
            2) apply_bbr "bbr" ;;
            3) apply_bbr "bbr2" ;;
            4) apply_bbr "bbr3" ;;
            5) scene_config_menu ;;
            6) do_auto_tune ;;
            7) show_kernel_menu ;;
            8) show_backup_menu ;;
            9) do_uninstall ;;
            10) install_shortcut ;;
        esac
        
        echo
        if [[ $NON_INTERACTIVE -eq 0 ]]; then
            read -r -p "按 Enter 继续..."
        fi
    done
}

# 内核安装菜单
show_kernel_menu() {
    print_header "安装新内核"
    
    if ! is_kernel_install_supported; then
        print_warn "当前环境不支持安装第三方内核"
        print_info "原因: 架构=${ARCH_ID}, 虚拟化=${VIRT_TYPE}"
        return
    fi
    
    echo -e "${DIM}安装新内核可获得 BBR2/BBR3 支持${NC}"
    echo
    
    local menu_items=()
    
    case "$DIST_ID" in
        debian|ubuntu)
            menu_items+=("XanMod (推荐，支持 BBR3)")
            menu_items+=("Liquorix (桌面优化)")
            if [[ "$DIST_ID" == "ubuntu" ]] && [[ "$DIST_VER" =~ ^(16|18|20)\. ]]; then
                menu_items+=("HWE 内核 (官方硬件支持)")
            fi
            ;;
        centos|rhel|rocky|almalinux)
            menu_items+=("ELRepo kernel-ml (最新主线)")
            ;;
    esac
    
    if [[ ${#menu_items[@]} -eq 0 ]]; then
        print_warn "当前系统没有可用的内核选项"
        return
    fi
    
    print_menu "选择要安装的内核" "${menu_items[@]}"
    
    read_choice "请选择" ${#menu_items[@]}
    
    [[ "$MENU_CHOICE" == "0" ]] && return
    
    # 二次确认
    echo
    print_warn "安装新内核是一个重要操作，可能影响系统启动"
    if ! confirm "确定要继续吗？" "n"; then
        print_info "已取消"
        return
    fi
    
    case "$DIST_ID" in
        debian|ubuntu)
            case "$MENU_CHOICE" in
                1) install_kernel_xanmod && prompt_reboot ;;
                2) install_kernel_liquorix && prompt_reboot ;;
                3) install_kernel_hwe && prompt_reboot ;;
            esac
            ;;
        centos|rhel|rocky|almalinux)
            install_kernel_elrepo && prompt_reboot
            ;;
    esac
}

# 备份/恢复菜单
show_backup_menu() {
    print_header "备份/恢复配置"
    
    print_menu "选择操作" \
        "查看备份列表" \
        "创建新备份" \
        "恢复备份"
    
    read_choice "请选择" 3
    
    case "$MENU_CHOICE" in
        0) return ;;
        1) list_backups ;;
        2) backup_config ;;
        3) restore_config ;;
    esac
}

# 应用 BBR 配置
apply_bbr() {
    local algo="$1"
    
    print_header "启用 ${algo^^}"
    
    # 检查算法是否可用
    if ! algo_supported "$algo"; then
        print_error "算法 ${algo} 在当前内核中不可用"
        print_info "可用算法: $(detect_available_algos)"
        
        if is_kernel_install_supported; then
            echo
            if confirm "是否安装支持 ${algo} 的新内核？" "n"; then
                show_kernel_menu
            fi
        fi
        return 1
    fi
    
    # 规范化算法名称
    local actual_algo
    actual_algo=$(normalize_algo "$algo")
    
    # 设置默认 qdisc
    local qdisc="fq"
    
    # 设置默认缓冲区
    TUNE_RMEM_MAX=${TUNE_RMEM_MAX:-67108864}
    TUNE_WMEM_MAX=${TUNE_WMEM_MAX:-67108864}
    TUNE_TCP_RMEM_HIGH=${TUNE_TCP_RMEM_HIGH:-67108864}
    TUNE_TCP_WMEM_HIGH=${TUNE_TCP_WMEM_HIGH:-67108864}
    
    # 写入配置
    write_sysctl "$actual_algo" "$qdisc"
    
    # 应用配置
    if apply_sysctl; then
        apply_qdisc_runtime "$qdisc"
        
        echo
        print_success "配置已应用"
        print_kv "算法" "$actual_algo"
        print_kv "队列" "$qdisc"
        
        # 验证
        echo
        local current
        current=$(get_current_algo)
        if [[ "$current" == "$actual_algo" ]]; then
            print_success "验证通过: 当前算法为 ${current}"
        else
            print_warn "验证失败: 期望 ${actual_algo}, 实际 ${current}"
        fi
    fi
}

# 自动优化
do_auto_tune() {
    print_header "自动优化配置"
    
    echo -e "${DIM}根据网络 RTT 和带宽自动计算最佳缓冲区大小${NC}"
    echo -e "${DIM}注意: 此功能与「场景配置」互斥，后执行的会覆盖前者${NC}"
    echo -e "${DIM}如果是 VPS 代理用途，建议使用「场景配置 > 代理模式」${NC}"
    echo
    
    auto_tune
    
    echo
    if confirm "是否应用以上配置？" "y"; then
        write_sysctl "$CHOSEN_ALGO" "$CHOSEN_QDISC"
        apply_sysctl
        apply_qdisc_runtime "$CHOSEN_QDISC"
        print_success "自动优化配置已应用"
    fi
}

# 卸载配置
do_uninstall() {
    print_header "卸载配置"
    
    if [[ ! -f "$SYSCTL_FILE" ]]; then
        print_info "没有找到配置文件，无需卸载"
        return
    fi
    
    print_warn "这将删除 BBR 配置并恢复系统默认设置"
    
    if ! confirm "确定要卸载吗？" "n"; then
        print_info "已取消"
        return
    fi
    
    # 备份后删除
    backup_config
    rm -f "$SYSCTL_FILE"
    
    # 重新加载系统配置
    sysctl --system >/dev/null 2>&1 || true
    
    print_success "配置已卸载"
    print_info "系统将使用默认的拥塞控制算法"
}

# 安装快捷命令
install_shortcut() {
    print_header "安装快捷命令"
    
    local shortcut_path="/usr/local/bin/bbr3"
    local script_url="${GITHUB_RAW}/bbr.sh"
    
    echo -e "${DIM}安装后可直接使用 'bbr3' 命令运行此脚本${NC}"
    echo
    
    if [[ -f "$shortcut_path" ]]; then
        print_info "快捷命令已存在: $shortcut_path"
        if ! confirm "是否覆盖更新？" "y"; then
            return
        fi
    fi
    
    print_step "下载脚本到 ${shortcut_path}..."
    
    # 下载脚本
    if curl -fsSL "$script_url" -o "$shortcut_path" 2>/dev/null; then
        chmod +x "$shortcut_path"
        print_success "快捷命令安装成功！"
        echo
        echo -e "  使用方法: ${GREEN}bbr3${NC}"
        echo -e "  查看帮助: ${GREEN}bbr3 --help${NC}"
        echo -e "  查看状态: ${GREEN}bbr3 --status${NC}"
    elif wget -qO "$shortcut_path" "$script_url" 2>/dev/null; then
        chmod +x "$shortcut_path"
        print_success "快捷命令安装成功！"
        echo
        echo -e "  使用方法: ${GREEN}bbr3${NC}"
        echo -e "  查看帮助: ${GREEN}bbr3 --help${NC}"
        echo -e "  查看状态: ${GREEN}bbr3 --status${NC}"
    else
        print_error "下载失败，请检查网络连接"
        return 1
    fi
}

# 卸载快捷命令
uninstall_shortcut() {
    local shortcut_path="/usr/local/bin/bbr3"
    
    if [[ ! -f "$shortcut_path" ]]; then
        print_info "快捷命令未安装"
        return
    fi
    
    if confirm "确定要卸载快捷命令 bbr3？" "n"; then
        rm -f "$shortcut_path"
        print_success "快捷命令已卸载"
    fi
}


#===============================================================================
# 帮助信息
#===============================================================================

usage() {
    cat << EOF
${BOLD}BBR3 一键脚本 v${SCRIPT_VERSION}${NC}

${BOLD}用法:${NC}
  sudo $SCRIPT_NAME [选项]
  wget -qO- ${GITHUB_RAW}/bbr.sh | sudo bash
  curl -fsSL ${GITHUB_RAW}/bbr.sh | sudo bash -s -- [选项]

${BOLD}选项:${NC}
  ${CYAN}--algo <name>${NC}           设置拥塞算法: bbr|bbr2|bbr3|cubic|reno
  ${CYAN}--qdisc <name>${NC}          设置队列规则: fq|fq_codel|fq_pie|cake [默认: fq]
  ${CYAN}--install-kernel <type>${NC} 安装新内核: xanmod|liquorix|elrepo|hwe
  ${CYAN}--apply${NC}                 立即应用配置
  ${CYAN}--no-apply${NC}              仅写入配置，不立即应用
  ${CYAN}--mirror <name>${NC}         指定镜像源: tsinghua|aliyun|ustc|auto [默认: auto]
  ${CYAN}--non-interactive${NC}       非交互模式
  ${CYAN}--status${NC}                显示当前状态
  ${CYAN}--auto${NC}                  自动检测并应用最优配置
  ${CYAN}--check-bbr3${NC}            检测 BBR3 是否启用
  ${CYAN}--uninstall${NC}             卸载配置
  ${CYAN}--install${NC}               安装快捷命令 bbr3 到 /usr/local/bin
  ${CYAN}--debug${NC}                 启用调试模式
  ${CYAN}--version, -v${NC}           显示版本号
  ${CYAN}--help, -h${NC}              显示帮助

${BOLD}示例:${NC}
  # 交互式运行
  sudo $SCRIPT_NAME

  # 直接启用 BBR3
  sudo $SCRIPT_NAME --algo bbr3 --apply

  # 自动优化
  sudo $SCRIPT_NAME --auto

  # 安装 XanMod 内核
  sudo $SCRIPT_NAME --install-kernel xanmod

  # 查看状态
  sudo $SCRIPT_NAME --status

  # 使用国内镜像
  sudo $SCRIPT_NAME --mirror tsinghua --install-kernel xanmod

${BOLD}支持的系统:${NC}
  • Debian: 10 (Buster), 11 (Bullseye), 12 (Bookworm), 13 (Trixie)
  • Ubuntu: 16.04, 18.04, 20.04, 22.04, 24.04
  • RHEL/CentOS/Rocky/AlmaLinux: 7, 8, 9

${BOLD}注意:${NC}
  • BBR2/BBR3 需要较新内核支持，脚本会自动检测
  • 安装新内核后需要重启才能生效
  • 容器环境 (OpenVZ/LXC/Docker) 无法更换内核
  • 第三方内核仅支持 x86_64/amd64 架构

${BOLD}作者信息:${NC}
  作者: 孤独制作
  电报群: https://t.me/+RZMe7fnvvUg1OWJl

${BOLD}项目地址:${NC}
  ${GITHUB_URL}

${BOLD}其他工具:${NC}
  PVE Tools 一键脚本:
  wget https://raw.githubusercontent.com/xx2468171796/pvetools/main/pvetools.sh
  chmod +x pvetools.sh && ./pvetools.sh

EOF
}

#===============================================================================
# 主函数
#===============================================================================

main() {
    # 检测管道执行模式
    if [[ ! -t 0 ]]; then
        PIPE_MODE=1
        NON_INTERACTIVE=1
    fi
    
    # 初始化
    log_init
    setup_traps
    
    # 解析参数
    local install_kernel=""
    local show_status_only=0
    local show_help=0
    local do_uninstall_flag=0
    local do_auto=0
    local check_bbr3=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --algo)
                [[ -z "${2:-}" ]] && { print_error "--algo 需要参数"; exit 1; }
                CHOSEN_ALGO="$2"
                shift 2
                ;;
            --qdisc)
                [[ -z "${2:-}" ]] && { print_error "--qdisc 需要参数"; exit 1; }
                CHOSEN_QDISC="$2"
                shift 2
                ;;
            --install-kernel)
                [[ -z "${2:-}" ]] && { print_error "--install-kernel 需要参数"; exit 1; }
                install_kernel="$2"
                shift 2
                ;;
            --apply)
                APPLY_NOW=1
                shift
                ;;
            --no-apply)
                APPLY_NOW=0
                shift
                ;;
            --mirror)
                local mirror_name="${2:-auto}"
                case "$mirror_name" in
                    tsinghua|aliyun|ustc|huawei)
                        USE_CHINA_MIRROR=1
                        MIRROR_URL="${MIRRORS_CN[$mirror_name]}"
                        ;;
                    auto)
                        # 自动检测，稍后处理
                        ;;
                    *)
                        print_error "未知镜像源: $mirror_name"
                        print_info "可用选项: tsinghua, aliyun, ustc, huawei, auto"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --non-interactive)
                NON_INTERACTIVE=1
                shift
                ;;
            --status)
                show_status_only=1
                shift
                ;;
            --auto)
                do_auto=1
                APPLY_NOW=1
                shift
                ;;
            --check-bbr3)
                check_bbr3=1
                shift
                ;;
            --uninstall)
                do_uninstall_flag=1
                shift
                ;;
            --install)
                # 安装快捷命令
                print_logo
                detect_os
                install_shortcut
                exit $?
                ;;
            --debug)
                DEBUG_MODE=1
                shift
                ;;
            --help|-h)
                show_help=1
                shift
                ;;
            --version|-v)
                echo "BBR3 一键脚本 v${SCRIPT_VERSION}"
                echo "项目地址: ${GITHUB_URL}"
                exit 0
                ;;
            *)
                print_error "未知选项: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # 显示帮助
    if [[ $show_help -eq 1 ]]; then
        usage
        exit 0
    fi
    
    # 检查 root 权限
    if [[ $(id -u) -ne 0 ]]; then
        print_error "请使用 root 权限运行此脚本"
        echo
        echo "  使用方法:"
        echo "    sudo $SCRIPT_NAME"
        echo "  或"
        echo "    sudo bash $SCRIPT_NAME"
        exit 1
    fi
    
    # 显示 Logo
    print_logo
    
    # 执行预检
    detect_os
    detect_arch
    detect_virt
    try_load_modules
    
    # 快速检测 BBR3
    if [[ $check_bbr3 -eq 1 ]]; then
        local kver algo
        kver=$(uname -r | sed 's/[^0-9.].*$//')
        algo=$(get_current_algo)
        
        if [[ "$algo" == "bbr3" ]] || { [[ "$algo" == "bbr" ]] && version_ge "$kver" "6.9.0"; }; then
            echo "BBR3_ACTIVE=YES"
            echo "KERNEL=${kver}"
            echo "ALGO=${algo}"
            exit 0
        else
            echo "BBR3_ACTIVE=NO"
            echo "KERNEL=${kver}"
            echo "ALGO=${algo}"
            exit 1
        fi
    fi
    
    # 仅显示状态
    if [[ $show_status_only -eq 1 ]]; then
        # 确保加载内核模块以检测可用算法
        try_load_modules
        show_status
        exit 0
    fi
    
    # 卸载
    if [[ $do_uninstall_flag -eq 1 ]]; then
        do_uninstall
        exit 0
    fi
    
    # 执行完整预检
    if ! run_precheck; then
        if [[ $NON_INTERACTIVE -eq 1 ]]; then
            exit 1
        fi
        if ! confirm "预检未完全通过，是否继续？" "n"; then
            exit 1
        fi
    fi
    
    # 选择镜像源
    if [[ $USE_CHINA_MIRROR -eq 1 ]] && [[ -z "$MIRROR_URL" ]]; then
        select_best_mirror
    fi
    
    # 安装内核
    if [[ -n "$install_kernel" ]]; then
        case "$install_kernel" in
            xanmod)
                install_kernel_xanmod && prompt_reboot
                ;;
            liquorix)
                install_kernel_liquorix && prompt_reboot
                ;;
            elrepo)
                install_kernel_elrepo && prompt_reboot
                ;;
            hwe)
                install_kernel_hwe && prompt_reboot
                ;;
            *)
                print_error "未知内核类型: $install_kernel"
                exit 1
                ;;
        esac
        exit $?
    fi
    
    # 自动优化
    if [[ $do_auto -eq 1 ]]; then
        auto_tune
        write_sysctl "$CHOSEN_ALGO" "$CHOSEN_QDISC"
        apply_sysctl
        apply_qdisc_runtime "$CHOSEN_QDISC"
        print_success "自动优化完成"
        show_status
        exit 0
    fi
    
    # 命令行指定算法
    if [[ -n "$CHOSEN_ALGO" ]]; then
        # 验证算法
        if ! algo_supported "$CHOSEN_ALGO"; then
            print_error "算法 ${CHOSEN_ALGO} 不可用"
            print_info "可用算法: $(detect_available_algos)"
            exit 1
        fi
        
        # 规范化
        CHOSEN_ALGO=$(normalize_algo "$CHOSEN_ALGO")
        CHOSEN_QDISC="${CHOSEN_QDISC:-fq}"
        
        # 设置默认缓冲区
        TUNE_RMEM_MAX=${TUNE_RMEM_MAX:-67108864}
        TUNE_WMEM_MAX=${TUNE_WMEM_MAX:-67108864}
        TUNE_TCP_RMEM_HIGH=${TUNE_TCP_RMEM_HIGH:-67108864}
        TUNE_TCP_WMEM_HIGH=${TUNE_TCP_WMEM_HIGH:-67108864}
        
        # 写入配置
        write_sysctl "$CHOSEN_ALGO" "$CHOSEN_QDISC"
        
        # 应用配置
        if [[ $APPLY_NOW -eq 1 ]]; then
            apply_sysctl
            apply_qdisc_runtime "$CHOSEN_QDISC"
        fi
        
        print_success "配置完成"
        print_kv "算法" "$CHOSEN_ALGO"
        print_kv "队列" "$CHOSEN_QDISC"
        print_kv "已应用" "$([[ $APPLY_NOW -eq 1 ]] && echo '是' || echo '否')"
        exit 0
    fi
    
    # 交互模式
    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        print_error "非交互模式下必须指定 --algo 或 --auto"
        usage
        exit 1
    fi
    
    show_main_menu
}

# 运行主函数
main "$@"
