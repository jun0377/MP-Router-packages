#!/bin/sh

#
# (c) 2023-2025 Cezary Jackiewicz <cezary@eko.one.pl>
#

# 从 QMI/MBIM 蜂窝数据模块读取当前网络/信号/小区与载波聚合信息，并以 JSON 形式输出

# QMI/MBIM 设备节点路径（例如 /dev/cdc-wdm0）
DEVICE=$1
if [ -z "$DEVICE" ] || [ ! -e "$DEVICE" ]; then
	echo '{"error":"Device not found"}'
	exit 0
fi

# 如果系统里已有 uqmi 进程在跑，认为设备正忙（避免并发访问导致 uqmi 失败/阻塞）
if [ -n "$(pidof uqmi)" ]; then
	echo '{"error":"Device is busy"}'
	exit 0
fi

# 是否强制用本地 MCC/MNC 库解析运营商信息（仅当值为 1 时启用）
FORCE_PLMN=$2
[ "x$FORCE_PLMN" = "x1" ] || FORCE_PLMN=""

# 是否走 MBIM 模式（仅当值为 1 时启用）
MBIM=$3
[ "x$MBIM" = "x1" ] && MBIM="-m" || MBIM=""

type=""
rssi=""
rsrq=""
rsrp=""
snr=""
ecio=""
fgtype=""
fgrsrq=""
fgrsrp=""
fgsnr=""

# 使用 uqmi 查询信号信息
T=$(uqmi -t 3000 -s -d $DEVICE $MBIM --get-signal-info 2>/dev/null)
#  如果 JSON 顶层存在 .type，说明返回的是单一制式格式
if [ -n "$(echo "$T" | jsonfilter -q -e '@.type')" ]; then
	eval $(echo "$T" | jsonfilter -q -e 'type=@.type' -e 'rssi=@.rssi' -e 'rsrq=@.rsrq' -e 'rsrp=@.rsrp' -e 'snr=@.snr' -e 'ecio=@.ecio')
# 否则认为返回的是“数组”格式：@[0] 为主（LTE/WCDMA），@[1] 为辅（5G NR 等）
else
	eval $(echo "$T" | jsonfilter -q \
		-e 'type=@[0].type' -e 'rssi=@[0].rssi' -e 'rsrq=@[0].rsrq' -e 'rsrp=@[0].rsrp' -e 'snr=@[0].snr' \
		-e 'fgtype=@[1].type' -e 'fgrsrq=@[1].rsrq' -e 'fgrsrp=@[1].rsrp' -e 'fgsnr=@[1].snr')
fi

registration=""
plmn_mcc=""
plmn_mnc=""
plmn_description=""
roaming=""

# 获取驻网/服务系统信息
eval $(uqmi -t 3000 -s -d $DEVICE $MBIM --get-serving-system | jsonfilter -q -e 'registration=@.registration' -e 'plmn_mcc=@.plmn_mcc' -e 'plmn_mnc=@.plmn_mnc' -e 'plmn_description=@.plmn_description' -e 'roaming=@.roaming')
[ -n "$plmn_mnc" ] && plmn_mnc=$(printf %02d $plmn_mnc)

# 将 type 转为大写，得到 LTE/WCDMA/...
MODE=$(echo $type | tr 'a-z' 'A-Z')
case "$MODE" in
	"LTE") MODE_NUM=7;;
	"WCDMA") MODE_NUM=2;;
	*) MODE_NUM=0;;
esac
if [ "$MODE_NUM" = "7" ] && [ "x$fgtype" = "x5gnr" ]; then
	MODE="5G NSA"
fi

# 组合 MCC+MNC 得到 PLMN 数字串（例如 46000）
COPS_NUM="${plmn_mcc}${plmn_mnc}"

# 若 PLMN 非空，则尝试从本地库/usr/share/modemdata/libs/mccmnc.dat查国家/运营商信息
if [ -n "$COPS_NUM" ]; then
	COUNTRY=$(awk -F[\;] '/^'$COPS_NUM';/ {print $2}' /usr/share/modemdata/libs/mccmnc.dat)
	# 如果没查到国家，尝试把 MNC 改为 3 位形式再查（兼容 3 位 MNC）
	if [ -z "$COUNTRY" ]; then
		T=$(printf %03d $plmn_mnc)
		COUNTRY=$(awk -F[\;] '/^'${plmn_mcc}${T}';/ {print $2}' /usr/share/modemdata/libs/mccmnc.dat)
		if [ -n "$COUNTRY" ]; then
			plmn_mnc="$T"
			COPS_NUM="${plmn_mcc}${plmn_mnc}"
		fi
	fi

	# 如果启用强制查表，则用本地库的运营商名称覆盖 uqmi 返回的 plmn_description
	if [ -n "$FORCE_PLMN" ]; then
		plmn_description=$(awk -F[\;] '/^'$COPS_NUM';/ {print $3}' /usr/share/modemdata/libs/mccmnc.dat)
		[ -z "$plmn_description" ] && plmn_description="$COPS_NUM"
	fi
fi

SIGNAL=0
if [ -n "$rssi" ]; then
	rssi=$(echo "$rssi" | awk '{printf "%d\n", $1}')		# 取 RSSI 的数值部分并转整数（例如 "-72 dBm" -> -72）
	[ $rssi -ge -51 ] && rssi=-51							# 将 RSSI 上限钳制到 -51 dBm（更强也按 -51 计算）
	SIGNAL=$(((rssi+113)*100/62))							# 将 RSSI 从 [-113, -51] 线性映射到 [0, 100]
fi

# 附网状态
case "$registration" in
	# 未注册
	"not_registered")
		registration="0"
		;;
	# 已注册（非漫游）
	"registered")
		registration="1"
		[ "x$roaming" = "x1" ] && registration="5"
		;;
	# 正在搜索网络
	"searching")
		registration="2"
		;;
	# 注册被拒
	"registering_denied")
		registration="3"
		;;
	# 其它未知状态，输出为空
	*)
		registration=""
		;;
esac

PB=""
PF=""
PBW=""
PPCI=""
PEARFCN=""
S1B=""
S1F=""
S1BW=""
S1STATE=""
S1PCI=""
S1EARFCN=""
S2B=""
S2F=""
S2BW=""
S2STATE=""
S2PCI=""
S2EARFCN=""
S3B=""
S3F=""
S3BW=""
S3STATE=""
S3PCI=""
S3EARFCN=""
S4B=""
S4F=""
S4BW=""
S4STATE=""
S4PCI=""
S4EARFCN=""

# 仅在 LTE（或后续显示为 LTE-A/5G NSA 的 LTE 基座）时查询 CA 信息
if [ "$MODE_NUM" = "7" ]; then
	# 获取 LTE 物理层载波聚合（CA）信息
	T=$(uqmi -t 3000 -s -d $DEVICE $MBIM --get-lte-cphy-ca-info 2>/dev/null)
	# 提取主载波 band/frequency/bandwidth/cell_id/channel
	eval $(echo "$T" | jsonfilter -q -e 'PB=@.primary.band' -e 'PF=@.primary.frequency' -e 'PBW=@.primary.bandwidth' -e 'PPCI=@.primary.cell_id' -e 'PEARFCN=@.primary.channel')
	IDX=1
	# uqmi 可能暴露 secondary_1..secondary_10，这里最多扫描 10 个槽位
	for i in 1 2 3 4 5 6 7 8 9 10; do
		# 判断该 secondary_i 是否存在 band 字段
		T1=$(echo "$T" | jsonfilter -q -e "@.secondary_${i}.band")
		# 若存在，则抽取该 secondary 的信息写入 S${IDX}* 变量
		if [ -n "$T1" ]; then
			eval $(echo "$T" | jsonfilter -q -e "S${IDX}B=@.secondary_${i}.band" -e "S${IDX}F=@.secondary_${i}.frequency" -e "S${IDX}BW=@.secondary_${i}.bandwidth" -e "S${IDX}STATE=@.secondary_${i}.state" -e "S${IDX}PCI=@.secondary_${i}.cell_id" -e "S${IDX}EARFCN=@.secondary_${i}.channel")
			# 只保留最多 4 个 secondary（S1..S4）
			[ $IDX = "4" ] && break
			IDX=$((IDX + 1))
		fi
	done
	# 如果有主 band，则把模式字符串拼上 “Bxx (freq MHz)”
	[ -n "$PB" ] && MODE="${MODE} B${PB} (${PF} MHz)"
	# secondary 1 若激活，追加到模式字符串
	[ -n "$S1B" ] && [ "x$S1STATE" = "xactivated" ] && MODE="${MODE} / B${S1B} (${S1F} MHz)"
	# secondary 2 若激活，追加
	[ -n "$S2B" ] && [ "x$S2STATE" = "xactivated" ] && MODE="${MODE} / B${S2B} (${S2F} MHz)"
	# secondary 3 若激活，追加
	[ -n "$S3B" ] && [ "x$S3STATE" = "xactivated" ] && MODE="${MODE} / B${S3B} (${S3F} MHz)"
	# secondary 4 若激活，追加
	[ -n "$S4B" ] && [ "x$S4STATE" = "xactivated" ] && MODE="${MODE} / B${S4B} (${S4F} MHz)"
	# 如果存在 5G NR 辅链路类型（NSA）, 模式字符串末尾加 “/ ?” 表示还有 NR 部分
	if [ -n "$fgtype" ]; then
		MODE="${MODE} / ?"
	# 如果没有 NR 辅链路，则判断是否发生 CA：有 “ / B” 就认为是 LTE-A, 将字符串中的 LTE 替换为 LTE-A（仅替换第一次出现）
	else
		echo "$MODE" | grep -q " / B" && MODE=${MODE/LTE/LTE-A}
	fi
fi

echo "{"
echo "\"signal\":\"$SIGNAL\","
echo "\"operator_name\":\"$plmn_description\","
echo "\"operator_mcc\":\"$plmn_mcc\","
echo "\"operator_mnc\":\"$plmn_mnc\","
echo "\"country\":\"$COUNTRY\","
echo "\"mode\":\"$MODE\","
echo "\"registration\":\"$registration\","
TAC=""
CELLID=""

# 仅 LTE 读取系统信息来拼 TAC 和 CELLID
if [ "$MODE_NUM" = "7" ]; then
	SCELLID=""
	ENODEBID=""
	# 从 system-info 取 lte.tracking_area_code / lte.cell_id / lte.enodeb_id
	eval $(uqmi -t 3000 -s -d $DEVICE $MBIM --get-system-info 2>/dev/null | jsonfilter -q -e 'TAC=@.lte.tracking_area_code' -e 'SCELLID=@.lte.cell_id' -e 'ENODEBID=@.lte.enodeb_id')
	# 如果 cell_id 和 enodeb_id 都存在，则把它们拼成 E-UTRAN Cell Identifier（ECI）
	if [ -n "$SCELLID" ] && [ -n "$ENODEBID" ]; then
		CELLID=$(printf "%X%X" $ENODEBID $SCELLID )
		CELLID_DEC=$(printf "%d" "0x$CELLID")
	fi
	[ -n "$TAC" ] && TAC_HEX=$(printf "%X" $TAC)
fi
echo "\"lac_dec\":\"\",\"lac_hex\":\"\",\"cid_dec\":\"$CELLID_DEC\",\"cid_hex\":\"$CELLID\",\"addon\":["
ADDON=""

# 如果 RSSI 存在，加入 RSSI 项（idx=35 为前端约定）
[ -n "$rssi" ] && ADDON="${ADDON}{\"idx\":35,\"key\":\"RSSI\",\"value\":\"$rssi dBm\"},"

# LTE/LTE-A/5G NSA（LTE 基座）下输出 LTE 相关扩展项
if [ "$MODE_NUM" = "7" ]; then
	[ -n "$TAC" ] && ADDON="${ADDON}{\"idx\":23,\"key\":\"TAC\",\"value\":\"$TAC (${TAC_HEX})\"},"
	[ -n "$PB" ] && ADDON="${ADDON}{\"idx\":30,\"key\":\"Primary band\",\"value\":\"B${PB} (${PF} MHz) @${PBW} MHz\"},"
	[ -n "$rsrp" ] && ADDON="${ADDON}{\"idx\":36,\"key\":\"RSRP\",\"value\":\"$rsrp dBm\"},"
	[ -n "$rsrq" ] && ADDON="${ADDON}{\"idx\":37,\"key\":\"RSRQ\",\"value\":\"$rsrq dB\"},"
	[ -n "$snr" ] && ADDON="${ADDON}{\"idx\":38,\"key\":\"SNR\",\"value\":\"$(printf "%.1f" $snr) dB\"},"
	[ -n "$PPCI" ] && ADDON="${ADDON}{\"idx\":33,\"key\":\"PCI\",\"value\":\"$PPCI\"},"
	[ -n "$PEARFCN" ] && ADDON="${ADDON}{\"idx\":34,\"key\":\"EARFCN\",\"value\":\"$PEARFCN\"},"
	IDX=50
	SCC=1
	if [ -n "$S1B" ] && [ "x$S1STATE" = "xactivated" ]; then
		ADDON="${ADDON}{\"idx\":${IDX} ,\"key\":\"(S${SCC}) band\",\"value\":\"B${S1B} (${S1F} MHz) @${S1BW} MHz\"},"
		[ -n "$S1PCI" ] && ADDON="${ADDON}{\"idx\":$((IDX + 3)),\"key\":\"(S${SCC}) PCI\",\"value\":\"$S1PCI\"},"
		[ -n "$S1EARFCN" ] && ADDON="${ADDON}{\"idx\":$((IDX + 4)),\"key\":\"(S${SCC}) EARFCN\",\"value\":\"$S1EARFCN\"},"
		IDX=$((IDX + 10))
		SCC=$((SCC + 1))
	fi
	if [ -n "$S2B" ] && [ "x$S2STATE" = "xactivated" ]; then
		ADDON="${ADDON}{\"idx\":${IDX},\"key\":\"(S${SCC}) band\",\"value\":\"B${S2B} (${S2F} MHz) @${S2BW} MHz\"},"
		[ -n "$S2PCI" ] && ADDON="${ADDON}{\"idx\":$((IDX + 3)),\"key\":\"(S${SCC}) PCI\",\"value\":\"$S2PCI\"},"
		[ -n "$S2EARFCN" ] && ADDON="${ADDON}{\"idx\":$((IDX + 4)),\"key\":\"(S${SCC}) EARFCN\",\"value\":\"$S2EARFCN\"},"
		IDX=$((IDX + 10))
		SCC=$((SCC + 1))
	fi
	if [ -n "$S3B" ] && [ "x$S3STATE" = "xactivated" ]; then
		ADDON="${ADDON}{\"idx\":${IDX},\"key\":\"(S${SCC}) band\",\"value\":\"B${S3B} (${S3F} MHz) @${S3BW} MHz\"},"
		[ -n "$S3PCI" ] && ADDON="${ADDON}{\"idx\":$((IDX + 3)),\"key\":\"(S${SCC}) PCI\",\"value\":\"$S3PCI\"},"
		[ -n "$S3EARFCN" ] && ADDON="${ADDON}{\"idx\":$((IDX + 4)),\"key\":\"(S${SCC}) EARFCN\",\"value\":\"$S3EARFCN\"},"
		IDX=$((IDX + 10))
		SCC=$((SCC + 1))
	fi
	if [ -n "$S4B" ] && [ "x$S4STATE" = "xactivated" ]; then
		ADDON="${ADDON}{\"idx\":${IDX},\"key\":\"(S${SCC}) band\",\"value\":\"B${S4B} (${S4F} MHz) @${S4BW} MHz\"},"
		[ -n "$S4PCI" ] && ADDON="${ADDON}{\"idx\":$((IDX + 3)),\"key\":\"(S${SCC}) PCI\",\"value\":\"$S4PCI\"},"
		[ -n "$S4EARFCN" ] && ADDON="${ADDON}{\"idx\":$((IDX + 4)),\"key\":\"(S${SCC}) EARFCN\",\"value\":\"$S4EARFCN\"},"
		IDX=$((IDX + 10))
		SCC=$((SCC + 1))
	fi

	# 如果存在 5G NR 辅链路，则把它当作“最后一个 Sx”输出（band 直接写 5G）
	if [ -n "$fgtype" ]; then
		ADDON="${ADDON}{\"idx\":${IDX},\"key\":\"(S${SCC}) band\",\"value\":\"5G\"},"
		[ -n "$fgrsrp" ] && ADDON="${ADDON}{\"idx\":$((IDX + 6)),\"key\":\"(S${SCC}) RSRP\",\"value\":\"$fgrsrp dBm\"},"
		[ -n "$fgrsrq" ] && ADDON="${ADDON}{\"idx\":$((IDX + 7)),\"key\":\"(S${SCC}) RSRQ\",\"value\":\"$fgrsrq dB\"},"
		[ -n "$fgsnr" ] && ADDON="${ADDON}{\"idx\":$((IDX + 8)),\"key\":\"(S${SCC}) SNR\",\"value\":\"$(printf "%.1f" $fgsnr) dB\"},"
	fi
fi

# WCDMA 下输出 ECIO
if [ "$MODE_NUM" = "2" ]; then
	[ -n "$ecio" ] && ADDON="${ADDON}{\"idx\":36,\"key\":\"ECIO\",\"value\":\"$ecio dB\"},"
fi
# 若 ADDON 非空：输出并去掉最后一个逗号（${var%,*} 去掉末尾最短匹配 ",*"）
[ -n "$ADDON" ] && echo "${ADDON%,*}"
echo "]}"

exit 0
