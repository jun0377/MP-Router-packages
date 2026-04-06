#!/bin/sh

#
# (c) 2024-2025 Cezary Jackiewicz <cezary@eko.one.pl>
#


# 输入一个设备节点路径（如 /dev/ttyUSB2、/dev/cdc-wdm0 等）。
# 通过 /usr/share/modemdata/libs/getdevicevendorproduct 计算该设备对应的 USB VID:PID 标识。
# 再根据 VID:PID 去加载 /usr/share/modemdata/vendorproduct/<VIDPID> 的“设备识别脚本”（若没有则加载 generic），由被加载脚本负责设置 VENDOR/PRODUCT/REVISION/IMEI/ICCID/IMSI 等变量

DEVICE=$1
if [ -n "$DEVICE" ] && [ -e "$DEVICE" ]; then
	# 脚本资源目录
	RES="/usr/share/modemdata"
	. $RES/libs/getdevicevendorproduct
	# 从设备节点推导 USB VendorID+ProductID
	VIDPID=$(getdevicevendorproduct $DEVICE)

	# 若存在针对该 VIDPID 的专用脚本，则加载它, 否则加载通用脚本（generic）
	if [ -e "$RES/vendorproduct/$VIDPID" ]; then
		. "$RES/vendorproduct/$VIDPID"
	else
		. "$RES/vendorproduct/generic"
	fi
fi

# rat: Radio Access Technology无线接入技术
# pdp: Packet Data Protocol分组数据协议,终端要通过运营商分组网络上网时，需要建立的一组参数/状态
# auth: 鉴权设置,数据业务（PDP/PDN）建立时对 APN 的认证，常见于企业专网卡/物联网卡
# freqlock: 锁频/锁pci小区设置
cat <<EOF
{
"rat": "${SETTINGS_NET}",
"pdp": ${PDP_JSON:-null},
"auth": ${AUTH_JSON:-null},
"nrfreqlock":${NR_FREQLOCK_JSON:-null},
"ltefreqlock":${LTE_FREQLOCK_JSON:-null}
}
EOF

exit 0
