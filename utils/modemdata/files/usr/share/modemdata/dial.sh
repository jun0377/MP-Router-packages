#!/bin/sh

#
# (c) 2024-2025 Cezary Jackiewicz <cezary@eko.one.pl>
#


# 输入一个设备节点路径（如 /dev/ttyUSB2、/dev/cdc-wdm0 等）。
# 通过 /usr/share/modemdata/libs/getdevicevendorproduct 计算该设备对应的 USB VID:PID 标识。
# 再根据 VID:PID 去加载 /usr/share/modemdata/vendorproduct/<VIDPID> 的“设备识别脚本”（若没有则加载 generic），由被加载脚本负责设置 VENDOR/PRODUCT/REVISION/IMEI/ICCID/IMSI 等变量

# DIAL_PARAMS='{"rat":"sa+nsa",
# "apn":"ctnet",
# "auth":"none",
# "passwd":"passwd", 
# "username":"username",
# "nrfreqlock":{
# 	"operatetype":0,
# 	"band":[78,78,78],
# 	"arfcn":[633888,633888,633888],
# 	"scstype": [1,1,1],
# 	"pci": [100, 102, 103]
# },
# "ltefreqlock":{
# 	"operatetype":3,
# 	"forbidFlag":0,
# 	"band":[1,1],
# 	"arfcn":[100, 300],
# 	"pci": [420,420]
# }
# }'

DEVICE=$1
DIAL_PARAMS=$2
[ -n $DIAL_PARAMS ] && logger -t "NCM" "dial params: ${DIAL_PARAMS}"

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

exit 0
