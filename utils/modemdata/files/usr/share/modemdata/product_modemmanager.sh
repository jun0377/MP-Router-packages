#!/bin/sh

#
# (c) 2025 Cezary Jackiewicz <cezary@eko.one.pl>
#

# 通过 ModemManager 的 mmcli 查询指定 modem（-m DEVICE）的设备信息：厂商、型号、固件版本（revision）、IMEI
# 如果该 modem 检测到  SIM（返回 SIM 对象路径/编号），继续查询 SIM 信息：ICCID、IMSI

VENDOR=""
PRODUCT=""
REVISION=""
IMEI=""
ICCID=""
IMSI=""
SIM=""

# ModemManager 里的 modem 标识（mmcli -m <id>），通常是 0/1/... 或对象路径
DEVICE=$1
if [ -n "$DEVICE" ]; then
	# 调用 mmcli 获取该 modem 的 JSON 信息
	eval $(mmcli -m "$DEVICE" -J 2>/dev/null | jsonfilter -q -e 'IMEI=@.modem.generic["equipment-identifier"]' -e 'VENDOR=@.modem.generic.manufacturer' -e 'PRODUCT=@.modem.generic.model' -e 'REVISION=@.modem.generic.revision' -e 'SIM=@.modem.generic.sim')
	# 如果 SIM 标识非空，则进一步查询 SIM 信息
	[ -n "$SIM" ] && eval $(mmcli -m "$DEVICE" -J --sim $SIM 2>/dev/null | jsonfilter -q -e 'ICCID=@.sim.properties.iccid' -e 'IMSI=@.sim.properties.imsi')
fi

cat <<EOF
{
"vendor":"${VENDOR}",
"product":"${PRODUCT}",
"revision":"${REVISION}",
"imei":"${IMEI}",
"iccid":"${ICCID}",
"imsi":"${IMSI}"
}
EOF

exit 0
