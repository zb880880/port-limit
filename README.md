# port-limit

入站端口限速管理脚本 | Inbound Port Rate Limiting Manager

---

## 简介

`port_limit.sh` 是一个基于 `tc`（Traffic Control）的交互式 Shell 脚本，用于管理服务器入站端口的带宽限速。支持添加、查看、修改和删除限速规则，适合需要对特定端口流量进行精细控制的场景。

## Introduction

`port_limit.sh` is an interactive shell script based on `tc` (Traffic Control) for managing inbound bandwidth rate limits per port. It supports adding, viewing, modifying, and deleting rate limit rules — ideal for scenarios requiring fine-grained control over traffic on specific ports.

---

## 依赖 | Requirements

- Linux 系统 / Linux OS
- `iproute2`（提供 `tc` 命令 / provides the `tc` command）
- Root 权限 / Root privileges

安装依赖 / Install dependencies:

```bash
# Debian / Ubuntu
apt install iproute2

# CentOS / RHEL
yum install iproute
```

---

## 使用方法 | Usage

```bash
chmod +x port_limit.sh
sudo ./port_limit.sh
```

---

## 功能菜单 | Menu

```
============================================
      入站端口限速管理   网卡：eth0
============================================
  1. 查看规则列表   / List rules
  2. 新增限速规则   / Add rule
  3. 删除限速规则   / Delete rule
  4. 修改限速规则   / Modify rule
  0. 退出           / Exit
============================================
```

### 新增规则 | Add a rule

选择 `2`，按提示输入端口号（1-65535）和限速值（单位 Mbit），例如限制端口 8080 为 10 Mbit：

Select `2`, then enter the port number (1–65535) and rate limit in Mbit. Example: limit port 8080 to 10 Mbit:

```
请输入目标端口（1-65535）：8080
请输入限速（Mbit，仅数字，例如 10）：10
```

### 查看规则 | List rules

选择 `1` 查看当前所有限速规则：

Select `1` to view all active rules:

```
--------------------------------------------
序号   端口       限速
--------------------------------------------
1      8080       10mbit
--------------------------------------------
```

### 删除 / 修改规则 | Delete / Modify rules

选择 `3` 或 `4`，按序号操作对应规则。

Select `3` or `4`, then choose the rule by index number.

---

## 实现原理 | How It Works

脚本使用 `tc ingress qdisc` + `u32` 过滤器 + `police` 动作对匹配目标端口的入站 IP 数据包进行限速，超出速率的报文直接丢弃（`drop`）。

The script uses `tc ingress qdisc` with `u32` filters and `police` actions to rate-limit inbound IP packets matching the specified destination port. Packets exceeding the configured rate are dropped.

---

## 注意事项 | Notes

- 仅限速**入站**流量（`ingress`），不影响出站。/ Only limits **inbound** traffic; outbound is unaffected.
- 规则在重启后不持久，如需持久化请结合 `rc.local` 或 systemd 服务使用。/ Rules do not persist across reboots. Use `rc.local` or a systemd service for persistence.
- 脚本自动识别默认网卡，多网卡环境请确认 `DEV` 变量是否正确。/ The script auto-detects the default NIC. Verify the `DEV` variable in multi-NIC environments.

---

## License

MIT
