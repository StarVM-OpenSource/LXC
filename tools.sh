#!/bin/bash

# --- 安全设置 ---
set -o errexit
set -o nounset
set -o pipefail

# --- 颜色定义 ---
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_NC='\033[0m'

# --- 消息函数 ---
msg_info()  { echo -e "${COLOR_CYAN}[*] $1${COLOR_NC}"; }
msg_ok()    { echo -e "${COLOR_GREEN}[+] $1${COLOR_NC}"; }
msg_error() { echo -e "${COLOR_RED}[!] 错误: $1${COLOR_NC}" >&2; }
msg_warn()  { echo -e "${COLOR_YELLOW}[-] 警告: $1${COLOR_NC}"; }

# --- 核心功能变量 ---
declare -A SCRIPTS
OS_TYPE=""

# --- 核心功能函数 ---
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        msg_error "此脚本的大部分功能需要 root 权限，请使用 'sudo' 运行。"
        exit 1
    fi
}

check_dependencies() {
    local dependencies=("curl" "mktemp" "sort")
    msg_info "正在检查核心依赖: ${dependencies[*]}..."
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            msg_error "依赖命令 '$cmd' 未找到，请先安装它。"
            exit 1
        fi
    done
    if ! command -v "clear" &>/dev/null; then
        msg_warn "'clear' 命令未找到。将使用备用方式清屏，不影响功能。"
    fi
}

clear_screen() {
    if command -v "clear" &>/dev/null; then
        clear
    else
        printf '\033[2J\033[H'
    fi
}

detect_os() {
    if [[ -e /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION_ID="$VERSION_ID"
    else
        msg_error "无法识别当前系统。缺少 /etc/os-release。"
        exit 1
    fi

    case "$OS_ID" in
        debian)
            case "$OS_VERSION_ID" in
                11)
                    OS_TYPE="debian11"
                    msg_ok "检测到 Debian 11 系统。"
                    ;;
                12)
                    OS_TYPE="debian12"
                    msg_ok "检测到 Debian 12 系统。"
                    ;;
                *)
                    msg_error "不支持的 Debian 版本: $OS_VERSION_ID。仅支持 11 和 12。"
                    exit 1
                    ;;
            esac
            ;;
        alpine)
            if [[ "$OS_VERSION_ID" == "3.20" ]]; then
                OS_TYPE="alpine"
                msg_ok "检测到 Alpine 3.20 系统。"
            else
                msg_error "不支持的 Alpine 版本: $OS_VERSION_ID。仅支持 3.20。"
                exit 1
            fi
            ;;
        *)
            msg_error "不支持的系统类型: $OS_ID"
            exit 1
            ;;
    esac
}

initialize_scripts() {
    case "$OS_TYPE" in
        debian11)
            SCRIPTS=(
                ["1"]="Debian11 初始化环境;https://example.com/debian11/init.sh"
                ["2"]="Debian11 安装 LXC;https://example.com/debian11/lxc.sh"
                ["3"]="Debian11 特有功能;https://example.com/debian11/special.sh"
            )
            ;;
        debian12)
            SCRIPTS=(
                ["1"]="部署3x-ui;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/1.sh"
                ["2"]="部署LXC环境并创建存储池;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/2.sh"
                ["3"]="安装被控;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/3.sh"
                ["4"]="开启BBR;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/4.sh"
                ["5"]="开启&关闭SWAP;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/5.sh"
                ["6"]="下载镜像;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/6.sh"
                ["7"]="查看镜像列表;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/7.sh"
                ["8"]="查看被控管理网页登录信息;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/8.sh"
                ["9"]="获取魔方对接端口与对接密钥;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/9.sh"
                ["10"]="设置未传递镜像时的默认镜像;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/10.sh"
                ["11"]="开启zram;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/11.sh"
                ["12"]="如提示lxc: command not found,执行此项获取手动安装指令;https://raw.githubusercontent.com/StarVM-OpenSource/zjmf-lxd-server-fix/refs/heads/main/shell/12.sh"
            )
            ;;
        alpine)
            SCRIPTS=(
                ["1"]="Alpine 初始化;https://example.com/alpine/init.sh"
                ["2"]="Alpine 安装 LXC;https://example.com/alpine/lxc.sh"
            )
            ;;
    esac
}

execute_remote_script() {
    local url="$1"
    local description="$2"
    msg_info "准备执行: ${description}"

    local temp_script
    temp_script=$(mktemp)
    trap "rm -f '$temp_script'" EXIT HUP INT QUIT TERM

    msg_info "正在从 $url 下载脚本..."
    local script_content
    script_content=$(curl -fsS "$url" || true)

    if [[ -z "$script_content" ]]; then
        msg_error "从 $url 下载脚本失败或脚本内容为空。"
        return 1
    fi
    msg_ok "脚本下载成功。"

    echo "$script_content" > "$temp_script"
    chmod +x "$temp_script"

    msg_warn "您即将从网络执行一个脚本，请确认您信任来源: ${url}"
    read -p "是否继续执行? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        msg_info "操作已由用户取消。"
        return 0
    fi

    msg_info "开始执行子脚本..."
    echo -e "-------------------- 开始执行子脚本 --------------------\n"
    bash "$temp_script"
    local exit_code=$?
    echo -e "\n-------------------- 子脚本执行完毕 --------------------"

    if [[ $exit_code -eq 0 ]]; then
        msg_ok "'${description}' 执行成功。"
    else
        msg_error "'${description}' 执行时返回了错误码: $exit_code"
    fi
}

show_main_menu() {
    clear_screen
    echo -e "${COLOR_GREEN}========================================="
    echo -e "        LXD 工具箱 (系统: ${OS_TYPE})        "
    echo -e "=========================================${COLOR_NC}"

    for key in $(printf '%s\n' "${!SCRIPTS[@]}" | sort -n); do
        local item="${SCRIPTS[$key]}"
        local description="${item%%;*}"
        printf "  %-2s) %s\n" "$key" "$description"
    done

    echo "  ---------------------------------------"
    echo -e "  ${COLOR_RED}0) 退出脚本${COLOR_NC}"
    echo -e "${COLOR_GREEN}=========================================${COLOR_NC}"
    read -p "请输入您的选择: " choice
}

main() {
    check_root
    check_dependencies
    detect_os
    initialize_scripts

    while true; do
        show_main_menu
        if [[ -n "${SCRIPTS[$choice]:-}" ]]; then
            local item="${SCRIPTS[$choice]}"
            local description="${item%%;*}"
            local url="${item##*;}"
            execute_remote_script "$url" "$description"
        elif [[ "$choice" == "0" ]]; then
            msg_info "感谢使用，再见！"
            exit 0
        else
            msg_error "无效的选择 '$choice'，请重新输入。"
        fi
        echo
        read -n 1 -s -r -p "按任意键返回主菜单..."
    done
}

# --- 脚本执行入口 ---
main "$@"
