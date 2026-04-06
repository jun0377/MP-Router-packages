#!/bin/sh

#
# (c) 2024-2025 Cezary Jackiewicz <cezary@eko.one.pl>
#

# 根据传入的 OpenWrt 网络接口逻辑名（例如 wan、wwan、mobile 等）查询其连接状态与连接时长
# 并（如果已连接且能拿到三层设备名）统计该接口的收发流量（RX/TX 字节），最后以 JSON 格式输出

# OpenWrt 的网络接口逻辑名（/etc/config/network 中的 config interface 名称）
NETWORK=$1

if [ -n "$NETWORK" ]; then
	UP=""				# 接口是否 up
	CT=""				# 连接时长,秒
	IFACE=""			# 三层设备名（l3_device，例如 pppoe-wan、wwan0、eth0.2 等）

	# ifstatus输出示例在此脚本的最后
	eval $(ifstatus ${NETWORK} | jsonfilter -q -e 'UP=@.up' -e 'CT=@.uptime' -e 'IFACE=@.l3_device')
	if [ "x$UP" = "x1" ]; then
		STATUS="CONNECTED"
		if [ -n "$IFACE" ]; then
			RX=$(ifconfig $IFACE | awk -F[\(\)] '/bytes/ {printf "%s",$2}')		# ifconfig eth0 | awk -F[\(\)] '/bytes/ {printf "%s",$2}'
			TX=$(ifconfig $IFACE | awk -F[\(\)] '/bytes/ {printf "%s",$4}')		# ifconfig eth0 | awk -F[\(\)] '/bytes/ {printf "%s",$4}'
		fi
	else
		STATUS="DISCONNECTED"
	fi
fi

# 输出 JSON
cat <<EOF
{
"status": "${STATUS}",
"conn_time_sec": "${CT}",
"rx": "${RX}",
"tx": "${TX}"
}
EOF

exit 0

# ifstatus 示例
# ifstatus wan1
# {
#         "up": true,
#         "pending": false,		# 接口是否处于“正在启动/正在等待结果”的中间状态。例如 DHCP 正在等待租约、PPPoE 正在拨号中时可能为 true。
#         "available": true,	# 该接口依赖的底层设备是否存在且可用, 例如 device 指向的网卡不存在、驱动没加载、USB 网卡没插上时可能为 false
#         "autostart": true,	# 是否允许系统自动启动该接口（一般对应 /etc/config/network 里 option auto '1' 这类行为，或 netifd 内部状态）
#         "dynamic": false,		#  该逻辑接口是否是动态创建的（不是静态写在 UCI 配置里的）。常见：某些临时接口、热插拔生成的接口可能是 true；普通配置接口通常是 false
#         "uptime": 42310,		# 该逻辑接口处于 up=true 状态持续的时间
#         "l3_device": "wan1",	# netifd 认为该接口当前用于三层（IP 层）收发的设备名（Linux netdev 名）
#         "proto": "static",	# 该逻辑接口使用的协议类型（netifd 协议处理器），例如：static、dhcp、pppoe、qmi、mbim
#         "device": "wan1",		# 该逻辑接口绑定的底层设备（通常来自 UCI 的 option device / option ifname，或桥、VLAN 设备）
#         "ip4table": 4,		# 该接口使用的 IPv4 路由表 ID（Linux policy routing table）
#         "ip6table": 64,		# 同上，但针对 IPv6 路由表 ID
#         "metric": 4,			# 接口路由的度量值（route metric）。一般 越小优先级越高, 多 WAN 场景常用它决定默认路由的优先级
#         "dns_metric": 0,		# DNS 的优先级/度量（供 resolvconf、dnsmasq 等使用）。多接口同时提供 DNS 时，用于决定哪个 DNS 更优先（实现上与系统脚本/组件有关）
#         "delegation": false,	# 通常与 IPv6 前缀委派（Prefix Delegation, PD）/下游分
#         "ipv4-address": [

#         ],
#         "ipv6-address": [

#         ],
#         "ipv6-prefix": [

#         ],
#         "ipv6-prefix-assignment": [

#         ],
#         "route": [

#         ],
#         "dns-server": [

#         ],
#         "dns-search": [

#         ],
#         "neighbors": [

#         ],
#         "inactive": {
#                 "ipv4-address": [

#                 ],
#                 "ipv6-address": [

#                 ],
#                 "route": [

#                 ],
#                 "dns-server": [

#                 ],
#                 "dns-search": [

#                 ],
#                 "neighbors": [

#                 ]
#         },
#         "data": {

#         }
# }
