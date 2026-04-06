#!/bin/sh

#
# (c) 2025 Cezary Jackiewicz <cezary@eko.one.pl>
#

# 通过 ModemManager 的 mmcli 查询指定蜂窝模块（modem）的当前小区信息与信号参数，
# 计算一个 0–100 的“信号百分比”，并输出一段固定格式的 JSON（包含运营商、国家、制式、是否在本地网注册、CID/TAC/PCI/EARFCN 以及 RSSI/RSRP/RSRQ/SNR 等扩展指标）

# ModemManager 中的 modem 标识（通常是数字 0/1/...，也可以是 DBus 对象路径）
DEVICE=$1
if [ -z "$DEVICE" ]; then
	echo '{"error":"Device not found"}'
	exit 0
fi

# 是否强制用 MCCMNC 本地数据库解析运营商名称（仅当值为 1 时启用）
FORCE_PLMN=$2
[ "x$FORCE_PLMN" = "x1" ] || FORCE_PLMN=""

# 引入json库
. /usr/share/libubox/jshn.sh

# 让 ModemManager 开始/配置周期性信号采集（间隔参数=3；具体语义依赖 ModemManager）
mmcli -m "$DEVICE" --signal-setup=3 >/dev/null 2>&1

# 调用 mmcli 获取 cell info(JSON，-J)，并用 jsonfilter 提取 @.modem.* 这部分
json_load "$(mmcli -m "$DEVICE" -J --get-cell-info 2>/dev/null | jsonfilter -q -e '@.modem.*')" 2>/dev/null

# 如果存在 cell-info 字段且它是一个数组
if json_is_a "cell-info" array; then
	json_select "cell-info"
	idx=1
	# 逐个检查数组元素
	while json_is_a ${idx} string; do
		json_get_var line $idx								# 取出第 idx 个元素内容到变量 line

		# 当前驻留/服务小区
		if echo "$line" | grep -q "serving: yes"; then
			IFS=','
			for F in $line; do
				KEY=""
				VAL=""
				# 将该字符串按逗号拆成若干段，每段类似 "key: value"
				eval $(echo "$F" | awk -F: '{gsub(" ", "");printf "KEY=%s, VAL=%s\n", $1, $2}')
				case "$KEY" in
					# 小区制式类型（例如 lte/umts）
					"celltype")
						MODE=$VAL
						_MODE=$(echo "$VAL" | tr 'a-z' 'A-Z')
						case "$_MODE" in
							"LTE")
								MODE_NUM=7
								;;
							"UMTS")
								MODE_NUM=2
								;;
						esac
						;;
					# 运营商标识（PLMN，MCC+MNC），例如 46000/310260 等
					"operatorid")
						COPS_NUM=$VAL
						_plmn_mcc=${COPS_NUM:0:3}
						_plmn_mnc=${COPS_NUM:3:3}
						_plmn_mnc=$(printf "%02d" $_plmn_mnc)
						;;
					# LTE 的 TAC（Tracking Area Code），通常以十六进制形式给出
					"tac")
						_TAC=$VAL
						_TAC_DEC=$(printf "%d" "0x$_TAC")
						;;
					# 小区标识（Cell ID / E-UTRAN Cell Identifier 的一部分等），这里按十六进制处理
					"ci")
						_CELLID=$VAL
						_CELLID_DEC=$(printf "%d" "0x$_CELLID")
						;;
					# PCI（Physical Cell ID），这里按十六进制处理并转十进制
					"physicalci")
						_pci=$(printf "%d" "0x$VAL")
						;;
					# EARFCN（频点号）
					"earfcn")
						_earfcn=$VAL
						;;
					# 参考信号接收功率
					"rsrp")
						_rsrp=$VAL
						;;
					# 参考信号接收质量
					"rsrq")
						_rsrq=$VAL
						;;
				esac
			done
			break
		fi
		idx=$((idx + 1))
	done
fi

_SIGNAL=0
# 获取信号测量详情（--signal-get），从 JSON 中提取 @.modem.signal.<MODE> 段
T=$(mmcli -m "$DEVICE" -J --signal-get 2>/dev/null | jsonfilter -q -e '@.modem.signal.'$MODE)
if [ -n "$T" ]; then
	_rsrp=""
	_rsrq=""
	_rssi=""
	_snr=""
	_rscp=""
	_ecio=""
	# 从该信号段提取常见字段
	eval $(echo "$T" | jsonfilter -q -e "_rsrp=@.rsrp" -e "_rsrq=@.rsrq" -e "_rssi=@.rssi" -e "_snr=@.snr" -e "_rscp=@.rscp" -e "_ecio=@.ecio")
	if [ -n "$_rssi" ] && [ "$_rssi" != "--" ]; then
		_rssi=$(echo "$_rssi" | awk '{printf "%d\n", $1}')
		[ "$_rssi" -ge -51 ] && _rssi=-51			# 将 RSSI 上限钳制到 -51 dBm（更强的信号也按 -51 计算）
		_SIGNAL=$(((_rssi+113)*100/62))				# 把 RSSI 从 [-113, -51] 线性映射到 [0, 100]
	fi
fi

# 再获取一次 modem 总体信息（JSON），用于取运营商名称与注册状态等字段
T=$(mmcli -m "$DEVICE" -J 2>/dev/null)

# 如果启用 FORCE_PLMN：不用 mmcli 返回的 operator-name，而是根据 operatorid 查本地库
if [ -n "$FORCE_PLMN" ]; then
	# 在 mccmnc.dat 中查找以 "<MCCMNC>;" 开头的行，取第3列作为运营商名称
	_plmn_description=$(awk -F[\;] '/^'$COPS_NUM';/ {print $3}' /usr/share/modemdata/libs/mccmnc.dat)
	# 若查不到则回退为直接输出 MCCMNC 数字串
	[ -z "$_plmn_description" ] && _plmn_description="$COPS_NUM"
# 否则：直接从 mmcli 输出的 @.modem.3gpp.operator-name 取运营商名
else
	_plmn_description=$(echo "$T" | jsonfilter -q -e "@.modem['3gpp']['operator-name']")
fi

# 从总体信息中取 3GPP 注册状态（home/roaming/searching/denied/...）
T=$(echo "$T" | jsonfilter -q -e "@.modem['3gpp']['registration-state']")
# # 只有 "home" 才算已注册（本地网）, 其它状态一律算未注册（这里把 roaming 也算 0）
case "$T" in
	"home")
		_registration=1
		;;
	*)
		_registration=0
		;;
esac

echo "{"
echo "\"signal\":\"$_SIGNAL\","
echo "\"operator_name\":\"$_plmn_description\","
echo "\"operator_mcc\":\"$_plmn_mcc\","
echo "\"operator_mnc\":\"$_plmn_mnc\","
[ -n "$COPS_NUM" ] && COUNTRY=$(awk -F[\;] '/^'$COPS_NUM';/ {print $2}' /usr/share/modemdata/libs/mccmnc.dat)
echo "\"country\":\"$COUNTRY\","
echo "\"mode\":\"$_MODE\","
echo "\"registration\":\"$_registration\","
echo "\"lac_dec\":\"\",\"lac_hex\":\"\",\"cid_dec\":\"${_CELLID_DEC}\",\"cid_hex\":\"${_CELLID}\",\"addon\":["
ADDON=""
[ -n "$_rssi" ] && [ "$_rssi" != "--" ] && ADDON="${ADDON}{\"idx\":35,\"key\":\"RSSI\",\"value\":\"$(printf "%.1f" $_rssi) dBm\"},"

# LTE 入网
if [ "$MODE_NUM" = "7" ]; then
	[ -n "$_rsrp" ] && [ "$_rsrp" != "--" ] && ADDON="${ADDON}{\"idx\":36,\"key\":\"RSRP\",\"value\":\"$(printf "%.1f" $_rsrp) dBm\"},"
	[ -n "$_rsrq" ] && [ "$_rsrq" != "--" ] && ADDON="${ADDON}{\"idx\":37,\"key\":\"RSRQ\",\"value\":\"$(printf "%.1f" $_rsrq) dB\"},"
	[ -n "$_snr" ] && [ "$_snr" != "--" ] && ADDON="${ADDON}{\"idx\":38,\"key\":\"SNR\",\"value\":\"$(printf "%.1f" $_snr) dB\"},"
	[ -n "$_TAC" ] && ADDON="${ADDON}{\"idx\":23,\"key\":\"TAC\",\"value\":\"${_TAC_DEC} (${_TAC})\"},"
fi
# UMTS 入网
if [ "$MODE_NUM" = "2" ]; then
	[ -n "$_ecio" ] && ADDON="${ADDON}{\"idx\":36,\"key\":\"ECIO\",\"value\":\"$_ecio dB\"},"
fi

# pci小区
[ -n "$_pci" ] && ADDON="${ADDON}{\"idx\":33,\"key\":\"PCI\",\"value\":\"$_pci\"},"
# 频点号
[ -n "$_earfcn" ] && ADDON="${ADDON}{\"idx\":34,\"key\":\"EARFCN\",\"value\":\"$_earfcn\"},"
[ -n "$ADDON" ] && echo "${ADDON%,*}"
echo "]}"

exit 0
