#!/bin/sh

#
# (c) 2010-2025 Cezary Jackiewicz <cezary@eko.one.pl>
#

# 作用：
# - 通过串口/AT 命令从蜂窝模块读取：SIM 状态、信号强度(CSQ)、运营商(PLMN)、注册状态(CREG)、LAC/CID、制式(2G/3G/4G)
# - 可选：强制用本地 mccmnc.dat 解析运营商名称/国家（FORCE_PLMN=1）
# - 可选：按 USB VID:PID 加载厂商/机型特定 addon 脚本，补充更多指标
# - 最终输出一段 JSON，供 OpenWrt/LuCI 状态页等调用显示

# LTE Band -> 频段文本
band4g() {
# see https://en.wikipedia.org/wiki/LTE_frequency_bands
	echo -n "B${1}"
	case "${1}" in
		"1") echo " (2100 MHz)";;
		"2") echo " (1900 MHz)";;
		"3") echo " (1800 MHz)";;
		"4") echo " (1700 MHz)";;
		"5") echo " (850 MHz)";;
		"7") echo " (2600 MHz)";;
		"8") echo " (900 MHz)";;
		"11") echo " (1500 MHz)";;
		"12") echo " (700 MHz)";;
		"13") echo " (700 MHz)";;
		"14") echo " (700 MHz)";;
		"17") echo " (700 MHz)";;
		"18") echo " (850 MHz)";;
		"19") echo " (850 MHz)";;
		"20") echo " (800 MHz)";;
		"21") echo " (1500 MHz)";;
		"24") echo " (1600 MHz)";;
		"25") echo " (1900 MHz)";;
		"26") echo " (850 MHz)";;
		"28") echo " (700 MHz)";;
		"29") echo " (700 MHz)";;
		"30") echo " (2300 MHz)";;
		"31") echo " (450 MHz)";;
		"32") echo " (1500 MHz)";;
		"34") echo " (2000 MHz)";;
		"37") echo " (1900 MHz)";;
		"38") echo " (2600 MHz)";;
		"39") echo " (1900 MHz)";;
		"40") echo " (2300 MHz)";;
		"41") echo " (2500 MHz)";;
		"42") echo " (3500 MHz)";;
		"43") echo " (3700 MHz)";;
		"46") echo " (5200 MHz)";;
		"47") echo " (5900 MHz)";;
		"48") echo " (3500 MHz)";;
		"50") echo " (1500 MHz)";;
		"51") echo " (1500 MHz)";;
		"53") echo " (2400 MHz)";;
		"54") echo " (1600 MHz)";;
		"65") echo " (2100 MHz)";;
		"66") echo " (1700 MHz)";;
		"67") echo " (700 MHz)";;
		"69") echo " (2600 MHz)";;
		"70") echo " (1700 MHz)";;
		"71") echo " (600 MHz)";;
		"72") echo " (450 MHz)";;
		"73") echo " (450 MHz)";;
		"74") echo " (1500 MHz)";;
		"75") echo " (1500 MHz)";;
		"76") echo " (1500 MHz)";;
		"85") echo " (700 MHz)";;
		"87") echo " (410 MHz)";;
		"88") echo " (410 MHz)";;
		"103") echo " (700 MHz)";;
		"106") echo " (900 MHz)";;
		"*") echo "";;
	esac
}

# 5G NR band -> 频段文本
band5g() {
# see https://en.wikipedia.org/wiki/5G_NR_frequency_bands
	echo -n "n${1}"
	case "${1}" in
		"1") echo " (2100 MHz)";;
		"2") echo " (1900 MHz)";;
		"3") echo " (1800 MHz)";;
		"5") echo " (850 MHz)";;
		"7") echo " (2600 MHz)";;
		"8") echo " (900 MHz)";;
		"12") echo " (700 MHz)";;
		"13") echo " (700 MHz)";;
		"14") echo " (700 MHz)";;
		"18") echo " (850 MHz)";;
		"20") echo " (800 MHz)";;
		"24") echo " (1600 MHz)";;
		"25") echo " (1900 MHz)";;
		"26") echo " (850 MHz)";;
		"28") echo " (700 MHz)";;
		"29") echo " (700 MHz)";;
		"30") echo " (2300 MHz)";;
		"34") echo " (2100 MHz)";;
		"38") echo " (2600 MHz)";;
		"39") echo " (1900 MHz)";;
		"40") echo " (2300 MHz)";;
		"41") echo " (2500 MHz)";;
		"46") echo " (5200 MHz)";;
		"47") echo " (5900 MHz)";;
		"48") echo " (3500 MHz)";;
		"50") echo " (1500 MHz)";;
		"51") echo " (1500 MHz)";;
		"53") echo " (2400 MHz)";;
		"54") echo " (1600 MHz)";;
		"65") echo " (2100 MHz)";;
		"66") echo " (1700/2100 MHz)";;
		"67") echo " (700 MHz)";;
		"70") echo " (2000 MHz)";;
		"71") echo " (600 MHz)";;
		"74") echo " (1500 MHz)";;
		"75") echo " (1500 MHz)";;
		"76") echo " (1500 MHz)";;
		"77") echo " (3700 MHz)";;
		"78") echo " (3500 MHz)";;
		"79") echo " (4700 MHz)";;
		"80") echo " (1800 MHz)";;
		"81") echo " (900 MHz)";;
		"82") echo " (800 MHz)";;
		"83") echo " (700 MHz)";;
		"84") echo " (2100 MHz)";;
		"85") echo " (700 MHz)";;
		"86") echo " (1700 MHz)";;
		"89") echo " (850 MHz)";;
		"90") echo " (2500 MHz)";;
		"91") echo " (800/1500 MHz)";;
		"92") echo " (800/1500 MHz)";;
		"93") echo " (900/1500 MHz)";;
		"94") echo " (900/1500 MHz)";;
		"95") echo " (2100 MHz)";;
		"96") echo " (6000 MHz)";;
		"97") echo " (2300 MHz)";;
		"98") echo " (1900 MHz)";;
		"99") echo " (1600 MHz)";;
		"100") echo " (900 MHz)";;
		"101") echo " (1900 MHz)";;
		"102") echo " (6200 MHz)";;
		"104") echo " (6700 MHz)";;
		"105") echo " (600 MHz)";;
		"106") echo " (900 MHz)";;
		"109") echo " (700/1500 MHz)";;
		"257") echo " (28 GHz)";;
		"258") echo " (26 GHz)";;
		"259") echo " (41 GHz)";;
		"260") echo " (39 GHz)";;
		"261") echo " (28 GHz)";;
		"262") echo " (47 GHz)";;
		"263") echo " (60 GHz)";;
		"*") echo "";;
	esac
}

# 统一拼接 addon JSON 数组元素的辅助函数：
# - 第1参 idx：前端排序/定位用的编号
# - 第2参 key：展示名称
# - 第3参 value：展示值（会去掉回车）
addon() {
	[ -n "$ADDON" ] && ADDON="$ADDON,"
	ADDON="$ADDON"'{"idx":'$1',"key":"'$2'","value":"'${3//$'\r'/}'"}'
}

# 设备节点（通常是提供 AT 口的 ttyUSBx/ttyACMx/ttyHSx 等）
DEVICE=$1
if [ -z "$DEVICE" ] || [ ! -e "$DEVICE" ]; then
	echo '{"error":"Device not found"}'
	exit 0
fi

# 是否强制用本地库解析运营商名称, 不使用模块返回的长名称
FORCE_PLMN=$2
[ "x$FORCE_PLMN" = "x1" ] || FORCE_PLMN=""

# 数据目录：包含 mccmnc.dat、addon 脚本、VID/PID 探测脚本等
RES="/usr/share/modemdata"

# -------------------------
# COPS：运营商名称 + MCC/MNC + 国家
# -------------------------
COUNTRY=""
COPS=""
COPS_MCC=""
COPS_MNC=""
COPS_NUM=""

# 获取数字格式的运营商信息
O=$(sms_tool -D -d $DEVICE at "AT+COPS=3,2" | tr -d '\r')
O=$(sms_tool -D -d $DEVICE at "AT+COPS?" | tr -d '\r')
COPS_NUM=$(echo "$O" | awk -F[\"] '/^\+COPS:\s*.,2/ {print $2}')
if [ -n "$COPS_NUM" ]; then
	COPS_MCC=${COPS_NUM:0:3}
	COPS_MNC=${COPS_NUM:3:3}
fi

if [ -z "$FORCE_PLMN" ]; then
	O=$(sms_tool -D -d $DEVICE at "AT+COPS=3,0" | tr -d '\r')
	O=$(sms_tool -D -d $DEVICE at "AT+COPS?" | tr -d '\r')
	COPS=$(echo "$O" | awk -F[\"] '/^\+COPS:\s*.,0/ {print $2}' | awk '{if(NF==2 && tolower($1)==tolower($2)){print $1}else{print $0}}')
else
	[ -n "$COPS_NUM" ] && COPS=$(awk -F[\;] '/^'$COPS_NUM';/ {print $3}' $RES/libs/mccmnc.dat)
fi

# 如果运营商名称仍为空，则回退为 MCCMNC 数字串
[ -z "$COPS" ] && COPS=$COPS_NUM
# 国家字段：mccmnc.dat 第2列（依数据文件内容，可能是国家名/代码）
[ -n "$COPS_NUM" ] && COUNTRY=$(awk -F[\;] '/^'$COPS_NUM';/ {print $2}' $RES/libs/mccmnc.dat)

# -------------------------
# 按设备 VID:PID 加载厂商特定脚本
# -------------------------
. $RES/libs/getdevicevendorproduct
VIDPID=$(getdevicevendorproduct $DEVICE)
# 若存在对应的脚本,执行之...
if [ -e "$RES/vendorproduct/$VIDPID" ]; then
	. $RES/vendorproduct/$VIDPID
fi

# -------------------------
# MODE：把 MODE_NUM(AcT) 映射成人类可读制式字符串
# TODO: 要区分 LTE NSA SA三种入网场景
# MT5700M 在SA入网时通过 AT+C5GREG? 命令查看
# -------------------------
if [ -z "$MODE_NUM" ] || [ "x$MODE_NUM" = "x0" ]; then
	MODE_NUM=$(echo "$O" | awk -F[,] '/^\+COPS/ {print $4;exit}' | xargs)
fi

# -------------------------
# 错误/卡状态覆盖：若 AT 返回 CME ERROR 或 CPIN 非 READY，则用更明确文本覆盖 REG
# TODO: 查询SIM卡状态
# -------------------------
T=$(echo "$O" | awk -F[,\ ] '/^\+CME ERROR:/ {print $0;exit}')
if [ -n "$T" ]; then
	case "$T" in
		"+CME ERROR: 10"*) REG="SIM not inserted";;
		"+CME ERROR: 11"*) REG="SIM PIN required";;
		"+CME ERROR: 12"*) REG="SIM PUK required";;
		"+CME ERROR: 13"*) REG="SIM failure";;
		"+CME ERROR: 14"*) REG="SIM busy";;
		"+CME ERROR: 15"*) REG="SIM wrong";;
		"+CME ERROR: 17"*) REG="SIM PIN2 required";;
		"+CME ERROR: 18"*) REG="SIM PUK2 required";;
		*) REG=$(echo "$T" | cut -f2 -d: | xargs);;
	esac
fi

# 读取 +CPIN: READY / SIM PIN / ...
T=$(echo "$O" | awk -F[,\ ] '/^\+CPIN:/ {print $0;exit}' | xargs)
if [ -n "$T" ]; then
	[ "$T" = "+CPIN: READY" ] || REG=$(echo "$T" | cut -f2 -d: | xargs)
fi

# -------------------------
# addon 扩展：按设备 VID:PID 加载厂商特定脚本，补充 ADDON JSON 数组
# -------------------------
REGOK=0
# REGOK：是否“看起来已注册/可用”的标记，供 addon 脚本参考
[ "x$REG" = "x1" ] || [ "x$REG" = "x5" ] || [ "x$REG" = "x6" ] || [ "x$REG" = "x7" ] && REGOK=1
# 引入函数 getdevicevendorproduct，用于从设备节点推导 USB VID:PID
. $RES/libs/getdevicevendorproduct
# 得到类似 "12d1156b"（仅示例）的 VIDPID 标识
VIDPID=$(getdevicevendorproduct $DEVICE)
# 若存在对应设备的 addon 脚本，执行之以生成更多 ADDON 字段
if [ -e "$RES/addon/$VIDPID" ]; then
	ADDON=""
	case $(cat /tmp/sysinfo/board_name) in
		# 对特定 board_name 做特殊映射加载（覆盖/替代常规 VIDPID）
		"zte,mf289f")
			. "$RES/addon/usb/19d21485"
			;;
		# 默认加载对应 VIDPID 的 addon 脚本
		*)
			. "$RES/addon/$VIDPID"
			;;
	esac
fi

# 4G Core (EPS) 注册状态查询
C4GCORE=""
if type eps_readtime >/dev/null 2>&1; then
	C4GCORE_OUTPUT=$(eps_readtime)
	C4GCORE=$(echo "$C4GCORE_OUTPUT" | sed 's/.*"cereg":\(.*\)}$/\1/')
fi

# monsc: monitor serving cell驻留小区信息
# monnc: monitor neighbor cells相邻小区信息
cat <<EOF
{
"timestamp": "$(date '+%H:%M:%S')",
"sim": "${CPIN_TEXT}",
"country":"${COUNTRY}",
"mcc":"${MCC}", "mnc":"${MNC}",
"operator_name":"$COPS",
"freqInfo":${HFREQINFO_JSON:-null},
"C5GCore":${C5GREG_JSON:-null},
"C4GCore":${CEREG_JSON:-null},
"monsc":{
  "rat":"$RAT",
  "nr":{"cell_id":"$NR_CELL_ID","arfcn":"$NR_ARFCN","scs":"$NR_SCS","pci":"$NR_PCI","tac":"$NR_TAC","rsrp":"$NR_RSRP","rsrq":"$NR_RSRQ","sinr":"$NR_SINR"},
  "lte":{"cell_id":"$LTE_CELL_ID","arfcn":"$LTE_ARFCN","pci":"$LTE_PCI","tac":"$LTE_TAC","rsrp":"$LTE_RSRP","rsrq":"$LTE_RSRQ","rssi":"$LTE_RSSI"},
  "wcdma":{"arfcn":"$WCDMA_ARFCN","pcs":"$WCDMA_PCS","cell_id":"$WCDMA_CELL_ID","lac":"$WCDMA_LAC","rscp":"$WCDMA_RSCP","rxlev":"$WCDMA_RXLEV","ecno":"$WCDMA_ECNO"}
},
"monnc":{"gsm":${NC_GSM_JSON:-[]},"wcdma":${NC_WCDMA_JSON:-[]},"lte":${NC_LTE_JSON:-[]},"nr":${NC_NR_JSON:-[]}},
"addon":[$ADDON]
}
EOF

exit 0
