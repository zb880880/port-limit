#!/bin/bash

# 入站端口限速管理脚本
# 依赖：tc (iproute2 工具包)
# 需要 root 权限运行

DEV="eth0"
BURST="20k"

# 颜色
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
PLAIN="\033[0m"

ok()   { echo -e " ${GREEN}[√]${PLAIN} $*"; }
err()  { echo -e " ${RED}[✗]${PLAIN} $*" >&2; }
warn() { echo -e " ${YELLOW}[!]${PLAIN} $*"; }
info() { echo -e " ${CYAN}[-]${PLAIN} $*"; }

# 检查 root
if [[ $EUID -ne 0 ]]; then
    err "请使用 root 权限运行此脚本"
    exit 1
fi

# 检查 tc
if ! command -v tc &>/dev/null; then
    err "未找到 tc 命令，请安装 iproute2"
    exit 1
fi

# 确保 ingress qdisc 存在
ensure_ingress() {
    if ! tc qdisc show dev "$DEV" | grep -q "ingress"; then
        tc qdisc add dev "$DEV" ingress 2>/dev/null
        if [[ $? -ne 0 ]]; then
            err "创建 ingress qdisc 失败，请检查网卡 $DEV 是否存在"
            exit 1
        fi
    fi
}

# 获取所有规则，每行格式：句柄|端口|速率
get_rules() {
    if ! tc qdisc show dev "$DEV" 2>/dev/null | grep -q "ingress"; then
        return
    fi
    local output
    output=$(tc filter show dev "$DEV" ingress 2>/dev/null) || return
    local handles=() ports=() rates=()
    local current_handle="" current_port=""
    while IFS= read -r line; do
        if [[ $line =~ fh[[:space:]]+([0-9a-fA-F]+::[0-9a-fA-F]+) ]]; then
            current_handle="${BASH_REMATCH[1]}"
            current_port=""
        fi
        if [[ $line =~ match[[:space:]]+([0-9a-fA-F]{8})/([0-9a-fA-F]{8}) ]]; then
            current_port=$((16#${BASH_REMATCH[1]}))
        fi
        if [[ -n $current_handle && -n $current_port && $line =~ police.*rate[[:space:]]+([0-9]+[kKmMgG]?[bB]it) ]]; then
            handles+=("$current_handle")
            ports+=("$current_port")
            rates+=("${BASH_REMATCH[1]}")
            current_handle=""
            current_port=""
        fi
    done <<< "$output"
    local count=${#ports[@]}
    for ((i=0; i<count; i++)); do
        echo "${handles[$i]}|${ports[$i]}|${rates[$i]}"
    done
}

rule_handle() { echo "${1%%|*}"; }
rule_port()   { local t="${1#*|}"; echo "${t%%|*}"; }
rule_rate()   { echo "${1##*|}"; }

# 分隔线
sep() { echo -e " ${CYAN}--------------------------------------------${PLAIN}"; }

# 显示规则列表
show_rules() {
    local rules=()
    mapfile -t rules < <(get_rules)
    sep
    printf " ${CYAN}%-6s %-10s %-12s${PLAIN}\n" "序号" "端口" "限速"
    sep
    if [[ ${#rules[@]} -eq 0 ]]; then
        echo "  暂无限速规则"
    else
        local idx=1
        for rule in "${rules[@]}"; do
            printf " %-6s %-10s %-12s\n" "$idx" "$(rule_port "$rule")" "$(rule_rate "$rule")"
            ((idx++))
        done
    fi
    sep
}

# 新增规则
add_rule() {
    local port rate
    echo ""
    read -p " 请输入目标端口（1-65535）：" port
    if ! [[ $port =~ ^[0-9]+$ ]] || [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
        err "无效的端口号"
        return 1
    fi
    local existing
    existing=$(get_rules | awk -F'|' -v p="$port" '$2==p{print $3}')
    if [[ -n $existing ]]; then
        warn "端口 $port 已存在限速规则（$existing），请先删除或修改"
        return 1
    fi
    read -p " 请输入限速（Mbit，仅数字，例如 10）：" rate
    if ! [[ $rate =~ ^[0-9]+$ ]]; then
        err "无效的速率，请输入正整数"
        return 1
    fi
    rate="${rate}mbit"
    ensure_ingress
    tc filter add dev "$DEV" parent ffff: protocol ip prio 1 u32 \
        match ip dport "$port" 0xffff \
        police rate "$rate" burst "$BURST" drop flowid :1 2>/dev/null
    if [[ $? -eq 0 ]]; then
        ok "端口 $port 限速规则已添加，速率：$rate"
    else
        err "添加规则失败"
        return 1
    fi
}

# 删除规则
delete_rule() {
    local rules=()
    mapfile -t rules < <(get_rules)
    if [[ ${#rules[@]} -eq 0 ]]; then
        warn "当前没有可删除的规则"
        return
    fi
    show_rules
    read -p " 请输入要删除的序号（0 取消）：" choice
    [[ $choice -eq 0 ]] && return
    if ! [[ $choice =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#rules[@]} ]]; then
        err "无效的序号"
        return 1
    fi
    local selected="${rules[$((choice-1))]}"
    local handle port
    handle=$(rule_handle "$selected")
    port=$(rule_port "$selected")
    tc filter del dev "$DEV" parent ffff: protocol ip prio 1 handle "$handle" u32 2>/dev/null
    if [[ $? -eq 0 ]]; then
        ok "端口 $port 的限速规则已删除"
    else
        err "删除失败，请检查规则是否存在"
        return 1
    fi
}

# 修改规则
modify_rule() {
    local rules=()
    mapfile -t rules < <(get_rules)
    if [[ ${#rules[@]} -eq 0 ]]; then
        warn "当前没有可修改的规则"
        return
    fi
    show_rules
    read -p " 请输入要修改的序号（0 取消）：" choice
    [[ $choice -eq 0 ]] && return
    if ! [[ $choice =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#rules[@]} ]]; then
        err "无效的序号"
        return 1
    fi
    local selected="${rules[$((choice-1))]}"
    local old_handle old_port old_rate new_rate
    old_handle=$(rule_handle "$selected")
    old_port=$(rule_port "$selected")
    old_rate=$(rule_rate "$selected")
    info "当前：端口 $old_port  限速 $old_rate"
    read -p " 请输入新的限速（Mbit，仅数字，例如 10）：" new_rate
    if ! [[ $new_rate =~ ^[0-9]+$ ]]; then
        err "无效的速率，请输入正整数"
        return 1
    fi
    new_rate="${new_rate}mbit"
    tc filter del dev "$DEV" parent ffff: protocol ip prio 1 handle "$old_handle" u32 2>/dev/null
    if [[ $? -ne 0 ]]; then
        err "删除旧规则失败"
        return 1
    fi
    ensure_ingress
    tc filter add dev "$DEV" parent ffff: protocol ip prio 1 u32 \
        match ip dport "$old_port" 0xffff \
        police rate "$new_rate" burst "$BURST" drop flowid :1 2>/dev/null
    if [[ $? -eq 0 ]]; then
        ok "端口 $old_port 限速已更新：$old_rate → $new_rate"
    else
        err "添加新规则失败"
        return 1
    fi
}

# 主菜单
while true; do
    echo ""
    echo -e " ${CYAN}============================================${PLAIN}"
    echo -e " ${CYAN}      入站端口限速管理   网卡：$DEV${PLAIN}"
    echo -e " ${CYAN}============================================${PLAIN}"
    echo "  1. 查看规则列表"
    echo "  2. 新增限速规则"
    echo "  3. 删除限速规则"
    echo "  4. 修改限速规则"
    echo "  0. 退出"
    echo -e " ${CYAN}============================================${PLAIN}"
    read -p " 请输入操作序号：" opt
    case "$opt" in
        1) show_rules ;;
        2) add_rule ;;
        3) delete_rule ;;
        4) modify_rule ;;
        0) echo ""; ok "已退出"; echo ""; exit 0 ;;
        *) warn "无效选项，请输入 0-4" ;;
    esac
done
