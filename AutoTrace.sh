#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: CentOS/Debian/Ubuntu
#	Description: 三网回程路由详细测试
#	Author: ChennHaoo
#   参考：https://github.com/zq/shell/blob/master/autoBestTrace.sh  
#         https://github.com/fscarmen/warp_unlock
#         https://github.com/fscarmen/tools/blob/main/return.sh
#         https://github.com/masonr/yet-another-bench-script/blob/master/yabs.sh
#         https://github.com/sjlleo/nexttrace/blob/main/README_zh_CN.md
#         https://github.com/spiritLHLS/ecs
#
#	Blog: https://github.com/Chennhaoo
#
#   重要：若IP失效或提示404，请修改 $IPv4_IP 和 $IPv6_IP 部分IP
#=================================================

#定义参数
sh_ver="2026.01.14_07"
# 当通过管道/进程替换运行时，$0可能是/dev/fd/63，需要回退到/tmp
filepath=$(cd "$(dirname "$0")" 2>/dev/null; pwd)
file=$(echo -e "${filepath}"|awk -F "$0" '{print $1}')
if [[ "$filepath" == /dev/* ]] || [[ "$filepath" == /proc/* ]] || [ ! -d "$filepath" ]; then
    filepath="/tmp"
    file="/tmp/"
fi
BestTrace_dir="${file}/BestTrace"
BestTrace_file="${file}/BestTrace/besttrace_IP"
Nexttrace_dir="${file}/Nexttrace"
Nexttrace_file="${file}/Nexttrace/nexttrace_IP"
Curl_impersonate_dir="${file}/Curl_impersonate"
Curl_impersonate_file="${file}/Curl_impersonate/curl_chrome116"
log="${file}/AutoTrace_Mtr.log"
true > $log
rep_time=$( date -R )

# 检测 /dev/tty 是否可用，用于 read 输入
# 定义 _read_input 函数统一处理输入读取
if [ -c /dev/tty ] 2>/dev/null; then
    _read_input() { read "$@" < /dev/tty; }
else
    _read_input() { read "$@"; }
fi

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Yellow_font_prefix="\033[33m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"


# ======= Nexttrace POW Provider 检测 =======
NT_POW_ARGS=""
nexttrace_detect_pow() {
    local Blue="\033[34m" && local Reset="\033[0m"
    echo -e "${Blue}[检测] 正在检测 NextTrace API 可用性...${Reset}"
    local test_out
    # 优先尝试 leomoeapi（中文数据）
    test_out=$(${Nexttrace_file} --data-provider leomoeapi -q 1 -n -m 3 1.1.1.1 2>&1)
    if ! echo "$test_out" | grep -q "ASAPI Server Error\|pow token fetch failed"; then
        NT_POW_ARGS="--data-provider leomoeapi"
        echo -e "${Blue}[检测] 使用 leomoeapi（中文）${Reset}"
        return
    fi
    # leomoeapi 不可用，尝试 sakura pow 节点
    test_out=$(${Nexttrace_file} --pow-provider sakura --data-provider leomoeapi -q 1 -n -m 3 1.1.1.1 2>&1)
    if ! echo "$test_out" | grep -q "ASAPI Server Error\|pow token fetch failed"; then
        NT_POW_ARGS="--pow-provider sakura --data-provider leomoeapi"
        echo -e "${Blue}[检测] 切换至 sakura 节点（中文）${Reset}"
        return
    fi
    # 均不可用，回退 ipinfo（稳定，英文）
    NT_POW_ARGS="--data-provider ipinfo"
    echo -e "${Blue}[检测] API 受限，使用 ipinfo（英文）${Reset}"
}
# ======= Nexttrace POW Provider 检测结束 =======
# ======= 线路判断函数 =======
ROUTE_SUMMARY=()  # 存储各条路由的判断结果

judge_route() {
    local log=$1
    local title=$2
    local no=$3

    # 读取本段路由内容（从 NT_BLOCK_START 行到文件末尾）
    local block
    if [ -n "${NT_BLOCK_START}" ] && [ "${NT_BLOCK_START}" -gt 0 ] 2>/dev/null; then
        block=$(tail -n +"${NT_BLOCK_START}" "$log")
    fi
    [ -z "$block" ] && block=$(tac "$log" | awk "/^No:[0-9]+\/[0-9]+/{found=1} found{print} found && /^==/{exit}" | tac)

    # ---- 中国三大运营商 ----
    local has_5943=$(echo "$block"    | grep -c "59\.43\.")
    local has_20297=$(echo "$block"   | grep -c "202\.97\.")
    local has_as9929=$(echo "$block"  | grep -ci "AS9929\|210\.51\.")
    local has_as10099=$(echo "$block" | grep -ci "AS10099")
    local has_as4837=$(echo "$block"  | grep -ci "AS4837\|219\.158\.")
    local has_as58453=$(echo "$block" | grep -ci "AS58453")
    local has_as58807=$(echo "$block" | grep -ci "AS58807\|223\.118\.")
    local has_as9808=$(echo "$block"  | grep -ci "AS9808\|211\.136\.")
    local has_as4134=$(echo "$block"  | grep -ci "AS4134\|CHINANET")

    # ---- 中国其他 ----
    local has_drpeng=$(echo "$block"    | grep -ci "AS17964\|drpeng\|Dr\.Peng")
    local has_cernet=$(echo "$block"    | grep -ci "AS4538\|CERNET\|edu\.cn")
    local has_cstnet=$(echo "$block"    | grep -ci "AS7497\|CSTNET")
    local has_gwbn=$(echo "$block"      | grep -ci "AS9801\|gwbn")
    local has_alicloud=$(echo "$block"  | grep -ci "AS45102\|AS37963\|alibaba\|aliyun")
    local has_tencloud=$(echo "$block"  | grep -ci "AS45090\|AS132203\|tencent\|tencentyun")
    local has_baidu=$(echo "$block"     | grep -ci "AS45076\|baidu")
    local has_huaweicloud=$(echo "$block" | grep -ci "AS136907\|huaweicloud")

    # ---- 日本 ----
    local has_softbank=$(echo "$block"  | grep -ci "AS17676\|AS9824\|softbank\|bbtec")
    local has_ntt=$(echo "$block"       | grep -ci "AS2914\|ntt\.net\|gin\.ntt")
    local has_ntt_com=$(echo "$block"   | grep -ci "AS4713\|ntt\.com\|ocn\.ad\.jp")
    local has_kddi=$(echo "$block"      | grep -ci "AS2516\|kddi\|dion\.ne\.jp")
    local has_iij=$(echo "$block"       | grep -ci "AS2497\|iij\.ad\.jp")
    local has_biglobe=$(echo "$block"   | grep -ci "AS2518\|biglobe")
    local has_sonet=$(echo "$block"     | grep -ci "AS2527\|so-net")
    local has_freebit=$(echo "$block"   | grep -ci "AS10013\|freebit")
    local has_jpix=$(echo "$block"      | grep -ci "AS7527\|jpix")
    local has_bbix=$(echo "$block"      | grep -ci "AS23640\|bbix")

    # ---- 香港 ----
    local has_pccw=$(echo "$block"      | grep -ci "AS3491\|pccw\|pccwglobal")
    local has_hgc=$(echo "$block"       | grep -ci "AS9304\|hgc\|hutchison")
    local has_hkbn=$(echo "$block"      | grep -ci "AS9269\|hkbn\|hk broadband")
    local has_hkt=$(echo "$block"       | grep -ci "AS4515\|hkt\.com\|netvigator")
    local has_hkix=$(echo "$block"      | grep -ci "AS4635\|hkix")

    # ---- 台湾 ----
    local has_hinet=$(echo "$block"     | grep -ci "AS3462\|hinet\|cht\.com\.tw")
    local has_seednet=$(echo "$block"   | grep -ci "AS4780\|seednet")
    local has_twm=$(echo "$block"       | grep -ci "AS9924\|taiwanmobile\|台湾大")
    local has_fetnet=$(echo "$block"    | grep -ci "AS4182\|fetnet\|远传")
    local has_aptg=$(echo "$block"      | grep -ci "AS17709\|aptg\|亚太电信")
    local has_tbc=$(echo "$block"       | grep -ci "AS131596\|tbc\|tbcom")

    # ---- 韩国 ----
    local has_kt=$(echo "$block"        | grep -ci "AS4766\|Korea Telecom\|kt\.co\.kr")
    local has_sk=$(echo "$block"        | grep -ci "AS9318\|SK Broadband\|skbroadband")
    local has_lg=$(echo "$block"        | grep -ci "AS17858\|LG U+\|LG DACOM\|lgdacom")
    local has_kinx=$(echo "$block"      | grep -ci "AS9286\|kinx\.net")

    # ---- 东南亚 ----
    local has_singtel=$(echo "$block"   | grep -ci "AS7473\|AS7474\|singtel")
    local has_starhub=$(echo "$block"   | grep -ci "AS4657\|starhub")
    local has_myrepublic=$(echo "$block" | grep -ci "AS56300\|myrepublic")
    local has_vnpt=$(echo "$block"      | grep -ci "AS45899\|vnpt")
    local has_cat=$(echo "$block"       | grep -ci "AS131090\|AS23969\|cat\.net\.th\|catelecom")
    local has_true=$(echo "$block"      | grep -ci "AS7470\|trueidc\|true\.th")
    local has_pldt=$(echo "$block"      | grep -ci "AS9299\|pldt")
    local has_globe=$(echo "$block"     | grep -ci "AS4775\|globe\.com\.ph")
    local has_telkom_id=$(echo "$block" | grep -ci "AS7713\|telkom\.net\.id\|telkomindonesia")

    # ---- 澳大利亚/新西兰 ----
    local has_telstra=$(echo "$block"   | grep -ci "AS1221\|telstra")
    local has_optus=$(echo "$block"     | grep -ci "AS4804\|optus")
    local has_tpg=$(echo "$block"       | grep -ci "AS7545\|AS4764\|tpg\.com\.au\|iinet")
    local has_vocus=$(echo "$block"     | grep -ci "AS4826\|AS9443\|vocus\|nextgen")
    local has_spark_nz=$(echo "$block"  | grep -ci "AS4771\|spark\.co\.nz")

    # ---- 印度 ----
    local has_jio=$(echo "$block"       | grep -ci "AS55836\|AS18101\|jio\|ril\.com")
    local has_airtel_in=$(echo "$block" | grep -ci "AS9498\|AS45609\|airtel\.in\|airtelbroadband")
    local has_bsnl=$(echo "$block"      | grep -ci "AS9829\|bsnl")
    local has_tata_in=$(echo "$block"   | grep -ci "AS4755\|vsnl")
    local has_mtnl=$(echo "$block"      | grep -ci "AS17813\|mtnl")

    # ---- 美国/北美 ----
    local has_gtt=$(echo "$block"       | grep -ci "AS3257\|gtt\.net")
    local has_cogent=$(echo "$block"    | grep -ci "AS174\|cogent")
    local has_he=$(echo "$block"        | grep -ci "AS6939\|he\.net\|hurricane")
    local has_level3=$(echo "$block"    | grep -ci "AS3356\|level3\|lumen\|centurylink")
    local has_zayo=$(echo "$block"      | grep -ci "AS6461\|zayo")
    local has_att=$(echo "$block"       | grep -ci "AS7018\|att\.net")
    local has_verizon=$(echo "$block"   | grep -ci "AS701\|verizon")
    local has_sprint=$(echo "$block"    | grep -ci "AS1239\|sprint\|sprintlink")
    local has_charter=$(echo "$block"   | grep -ci "AS20115\|charter\|spectrum")
    local has_comcast=$(echo "$block"   | grep -ci "AS7922\|comcast")
    local has_rogers=$(echo "$block"    | grep -ci "AS812\|rogers\.com")
    local has_telus=$(echo "$block"     | grep -ci "AS852\|telus")
    local has_windstream=$(echo "$block" | grep -ci "AS7029\|windstream")

    # ---- 欧洲 ----
    local has_telia=$(echo "$block"     | grep -ci "AS1299\|telia\|arelion")
    local has_dtag=$(echo "$block"      | grep -ci "AS3320\|dtag\|telekom\.de")
    local has_orange=$(echo "$block"    | grep -ci "AS5511\|opentransit")
    local has_vodafone=$(echo "$block"  | grep -ci "AS1273\|vodafone")
    local has_swisscom=$(echo "$block"  | grep -ci "AS3303\|swisscom")
    local has_bt=$(echo "$block"        | grep -ci "AS2856\|bt\.net")
    local has_telefonica=$(echo "$block" | grep -ci "AS12956\|telefonica\|telxius")
    local has_tele2=$(echo "$block"     | grep -ci "AS1257\|tele2")
    local has_liberty=$(echo "$block"   | grep -ci "AS6830\|liberty\|libertyglobal")
    local has_retn=$(echo "$block"      | grep -ci "AS9002\|retn")
    local has_turktelekom=$(echo "$block" | grep -ci "AS9121\|turk.*telekom\|ttnet")
    local has_colt=$(echo "$block"      | grep -ci "AS8220\|colt\.net")
    local has_eunetworks=$(echo "$block" | grep -ci "AS13237\|eunetworks")
    local has_telenor=$(echo "$block"   | grep -ci "AS2119\|telenor")
    local has_kpn=$(echo "$block"       | grep -ci "AS1136\|AS286\|kpn\.net")
    local has_proximus=$(echo "$block"  | grep -ci "AS5432\|proximus\|belgacom")
    local has_a1=$(echo "$block"        | grep -ci "AS8447\|a1\.net\|aon\.at")
    local has_init7=$(echo "$block"     | grep -ci "AS13030\|init7")
    local has_ovh=$(echo "$block"       | grep -ci "AS16276\|ovh\.net")
    local has_hetzner=$(echo "$block"   | grep -ci "AS24940\|hetzner\|your-server\.de")
    local has_scaleway=$(echo "$block"  | grep -ci "AS12876\|scaleway\|online\.net")
    local has_turkcell=$(echo "$block"  | grep -ci "AS34984\|turkcell")

    # ---- 全球骨干/Transit ----
    local has_tata=$(echo "$block"      | grep -ci "AS6453\|tatacommunications")
    local has_seabone=$(echo "$block"   | grep -ci "AS6762\|seabone\|sparkle\|tisparkle")
    local has_ixreach=$(echo "$block"   | grep -ci "AS43531\|ix-reach\|ixreach")
    local has_telxius=$(echo "$block"   | grep -ci "AS12956\|telxius")
    local has_hibernia=$(echo "$block"  | grep -ci "AS5765\|hibernia")
    local has_packetfabric=$(echo "$block" | grep -ci "AS4556\|packetfabric")

    # ---- IX 交换中心 ----
    local has_decix=$(echo "$block"     | grep -ci "AS6695\|de-cix")
    local has_amsix=$(echo "$block"     | grep -ci "AS1200\|ams-ix")
    local has_linx=$(echo "$block"      | grep -ci "AS5459\|linx\.net")
    local has_equinix_ix=$(echo "$block" | grep -ci "AS24115\|equinix.*ix\|eqix")
    local has_megaport=$(echo "$block"  | grep -ci "AS132863\|megaport")

    # ---- 云/CDN ----
    local has_zenlayer=$(echo "$block"  | grep -ci "AS21859\|zenlayer")
    local has_aws=$(echo "$block"       | grep -ci "AS16509\|AS14618\|amazonaws\|amazon\.com")
    local has_gcp=$(echo "$block"       | grep -ci "AS15169\|AS396982\|1e100\.net\|google")
    local has_azure=$(echo "$block"     | grep -ci "AS8075\|AS8068\|msn\.net\|microsoft")
    local has_cloudflare=$(echo "$block" | grep -ci "AS13335\|cloudflare")
    local has_akamai=$(echo "$block"    | grep -ci "AS20940\|AS16625\|akamai")
    local has_fastly=$(echo "$block"    | grep -ci "AS54113\|fastly")
    local has_edgecast=$(echo "$block"  | grep -ci "AS15133\|edgecast\|edgio")
    local has_oracle=$(echo "$block"    | grep -ci "AS31898\|oraclecloud")
    local has_digitalocean=$(echo "$block" | grep -ci "AS14061\|digitalocean")
    local has_vultr=$(echo "$block"     | grep -ci "AS20473\|vultr\|choopa")
    local has_linode=$(echo "$block"    | grep -ci "AS63949\|linode")

    # ---- 俄罗斯 ----
    local has_rostelecom=$(echo "$block" | grep -ci "AS12389\|rostelecom")
    local has_ttk=$(echo "$block"       | grep -ci "AS20485\|ttk\.ru\|transtelecom")

    # ---- 中东 ----
    local has_stc=$(echo "$block"       | grep -ci "AS39891\|AS25019\|stc\.com\.sa")
    local has_etisalat=$(echo "$block"  | grep -ci "AS8966\|etisalat")
    local has_du=$(echo "$block"        | grep -ci "AS15802\|du\.ae\|emirates.*integrated")
    local has_zain=$(echo "$block"      | grep -ci "AS42961\|zain")
    local has_ooredoo=$(echo "$block"   | grep -ci "AS8781\|AS21050\|ooredoo")
    local has_bezeq=$(echo "$block"     | grep -ci "AS8551\|bezeqint")
    local has_telecom_eg=$(echo "$block" | grep -ci "AS8452\|tedata\|te\.eg")

    # ---- 非洲 ----
    local has_mtn=$(echo "$block"       | grep -ci "AS16637\|mtn\.co\|mtn\.com")
    local has_liquid=$(echo "$block"    | grep -ci "AS30844\|liquid.*telecom")
    local has_safaricom=$(echo "$block" | grep -ci "AS33771\|safaricom")
    local has_seacom=$(echo "$block"    | grep -ci "AS37100\|seacom")
    local has_vodacom=$(echo "$block"   | grep -ci "AS36994\|vodacom")
    local has_maroc=$(echo "$block"     | grep -ci "AS6713\|iam\.net\.ma\|maroc")

    # ---- 拉美 ----
    local has_telmex=$(echo "$block"    | grep -ci "AS8151\|telmex")
    local has_claro=$(echo "$block"     | grep -ci "AS4230\|AS28573\|claro")
    local has_vivo=$(echo "$block"      | grep -ci "AS26599\|AS27699\|vivo\.com\.br")
    local has_oi=$(echo "$block"        | grep -ci "AS7738\|oi\.com\.br\|telemar")
    local has_embratel=$(echo "$block"  | grep -ci "AS4230\|embratel")
    local has_tim_br=$(echo "$block"    | grep -ci "AS26615\|timbrasil")

    local result
    local transit=""

    # ========== 中国三大运营商线路（优先判断） ==========
    # 电信
    if [ "$has_5943" -gt 0 ] && [ "$has_20297" -eq 0 ]; then
        result="电信 CN2 GIA"
    elif [ "$has_5943" -gt 0 ] && [ "$has_20297" -gt 0 ]; then
        result="电信 CN2 GT"
    elif [ "$has_as4134" -gt 0 ] && [ "$has_5943" -eq 0 ]; then
        result="电信 163"
    # 联通
    elif [ "$has_as10099" -gt 0 ]; then
        result="联通 AS10099 精品网"
    elif [ "$has_as9929" -gt 0 ]; then
        result="联通 AS9929 精品网"
    elif [ "$has_as4837" -gt 0 ]; then
        result="联通 169"
    # 移动
    elif [ "$has_as58807" -gt 0 ]; then
        result="移动 CMIN2"
    elif [ "$has_as58453" -gt 0 ] || [ "$has_as9808" -gt 0 ]; then
        result="移动 CMI"
    # 中国其他
    elif [ "$has_drpeng" -gt 0 ]; then
        result="鹏博士 Dr.Peng"
    elif [ "$has_cernet" -gt 0 ]; then
        result="教育网 CERNET"
    elif [ "$has_cstnet" -gt 0 ]; then
        result="科技网 CSTNET"
    elif [ "$has_gwbn" -gt 0 ]; then
        result="长城宽带 GWBN"
    elif [ "$has_alicloud" -gt 0 ]; then
        result="阿里云"
    elif [ "$has_tencloud" -gt 0 ]; then
        result="腾讯云"
    elif [ "$has_baidu" -gt 0 ]; then
        result="百度云"
    elif [ "$has_huaweicloud" -gt 0 ]; then
        result="华为云"

    # ========== 日本运营商 ==========
    elif [ "$has_softbank" -gt 0 ]; then
        result="日本 软银 SoftBank"
    elif [ "$has_iij" -gt 0 ]; then
        result="日本 IIJ"
    elif [ "$has_kddi" -gt 0 ]; then
        result="日本 KDDI"
    elif [ "$has_ntt_com" -gt 0 ]; then
        result="日本 NTT Communications"
    elif [ "$has_ntt" -gt 0 ]; then
        result="NTT (全球骨干)"
    elif [ "$has_biglobe" -gt 0 ]; then
        result="日本 BIGLOBE"
    elif [ "$has_sonet" -gt 0 ]; then
        result="日本 So-net"
    elif [ "$has_freebit" -gt 0 ]; then
        result="日本 FreeBit"
    elif [ "$has_jpix" -gt 0 ]; then
        result="日本 JPIX"
    elif [ "$has_bbix" -gt 0 ]; then
        result="日本 BBIX"

    # ========== 香港运营商 ==========
    elif [ "$has_pccw" -gt 0 ]; then
        result="香港 PCCW"
    elif [ "$has_hgc" -gt 0 ]; then
        result="香港 HGC 环球全域"
    elif [ "$has_hkbn" -gt 0 ]; then
        result="香港 HKBN 香港宽频"
    elif [ "$has_hkt" -gt 0 ]; then
        result="香港 HKT"
    elif [ "$has_hkix" -gt 0 ]; then
        result="香港 HKIX"

    # ========== 台湾运营商 ==========
    elif [ "$has_hinet" -gt 0 ]; then
        result="台湾 HiNet (中华电信)"
    elif [ "$has_seednet" -gt 0 ] || [ "$has_fetnet" -gt 0 ]; then
        result="台湾 远传电信/Seednet"
    elif [ "$has_twm" -gt 0 ]; then
        result="台湾 TWM (台湾大哥大)"
    elif [ "$has_aptg" -gt 0 ]; then
        result="台湾 APTG (亚太电信)"
    elif [ "$has_tbc" -gt 0 ]; then
        result="台湾 TBC (台湾宽频)"

    # ========== 韩国运营商 ==========
    elif [ "$has_kt" -gt 0 ]; then
        result="韩国 KT"
    elif [ "$has_sk" -gt 0 ]; then
        result="韩国 SK Broadband"
    elif [ "$has_lg" -gt 0 ]; then
        result="韩国 LG U+"
    elif [ "$has_kinx" -gt 0 ]; then
        result="韩国 KINX"

    # ========== 东南亚 ==========
    elif [ "$has_singtel" -gt 0 ]; then
        result="新加坡 Singtel"
    elif [ "$has_starhub" -gt 0 ]; then
        result="新加坡 StarHub"
    elif [ "$has_myrepublic" -gt 0 ]; then
        result="新加坡 MyRepublic"
    elif [ "$has_vnpt" -gt 0 ]; then
        result="越南 VNPT"
    elif [ "$has_cat" -gt 0 ]; then
        result="泰国 CAT Telecom"
    elif [ "$has_true" -gt 0 ]; then
        result="泰国 True"
    elif [ "$has_pldt" -gt 0 ]; then
        result="菲律宾 PLDT"
    elif [ "$has_globe" -gt 0 ]; then
        result="菲律宾 Globe"
    elif [ "$has_telkom_id" -gt 0 ]; then
        result="印尼 Telkom Indonesia"

    # ========== 澳大利亚/新西兰 ==========
    elif [ "$has_telstra" -gt 0 ]; then
        result="澳洲 Telstra"
    elif [ "$has_optus" -gt 0 ]; then
        result="澳洲 Optus"
    elif [ "$has_tpg" -gt 0 ]; then
        result="澳洲 TPG/iiNet"
    elif [ "$has_vocus" -gt 0 ]; then
        result="澳洲 Vocus/NextGen"
    elif [ "$has_spark_nz" -gt 0 ]; then
        result="新西兰 Spark"

    # ========== 印度运营商 ==========
    elif [ "$has_jio" -gt 0 ]; then
        result="印度 Jio (Reliance)"
    elif [ "$has_airtel_in" -gt 0 ]; then
        result="印度 Airtel"
    elif [ "$has_bsnl" -gt 0 ]; then
        result="印度 BSNL"
    elif [ "$has_tata_in" -gt 0 ]; then
        result="印度 Tata/VSNL"
    elif [ "$has_mtnl" -gt 0 ]; then
        result="印度 MTNL"

    # ========== 全球骨干/Transit ==========
    elif [ "$has_gtt" -gt 0 ]; then
        result="GTT (全球骨干)"
    elif [ "$has_cogent" -gt 0 ]; then
        result="Cogent (全球骨干)"
    elif [ "$has_he" -gt 0 ]; then
        result="HE 飓风电气 (全球骨干)"
    elif [ "$has_level3" -gt 0 ]; then
        result="Level3/Lumen (全球骨干)"
    elif [ "$has_telia" -gt 0 ]; then
        result="Telia/Arelion (欧洲骨干)"
    elif [ "$has_zayo" -gt 0 ]; then
        result="Zayo (北美骨干)"
    elif [ "$has_tata" -gt 0 ]; then
        result="Tata Communications (全球骨干)"
    elif [ "$has_seabone" -gt 0 ]; then
        result="Seabone/TI Sparkle (全球骨干)"
    elif [ "$has_colt" -gt 0 ]; then
        result="Colt (欧洲骨干)"
    elif [ "$has_eunetworks" -gt 0 ]; then
        result="euNetworks (欧洲骨干)"
    elif [ "$has_ixreach" -gt 0 ]; then
        result="IX Reach (全球骨干)"
    elif [ "$has_retn" -gt 0 ]; then
        result="RETN (欧亚骨干)"
    elif [ "$has_hibernia" -gt 0 ]; then
        result="Hibernia (跨大西洋骨干)"
    elif [ "$has_packetfabric" -gt 0 ]; then
        result="PacketFabric (北美骨干)"

    # ========== IX 交换中心 ==========
    elif [ "$has_decix" -gt 0 ]; then
        result="DE-CIX (德国IX)"
    elif [ "$has_amsix" -gt 0 ]; then
        result="AMS-IX (荷兰IX)"
    elif [ "$has_linx" -gt 0 ]; then
        result="LINX (英国IX)"
    elif [ "$has_equinix_ix" -gt 0 ]; then
        result="Equinix IX (全球IX)"
    elif [ "$has_megaport" -gt 0 ]; then
        result="Megaport (全球IX)"

    # ========== 云/CDN ==========
    elif [ "$has_zenlayer" -gt 0 ]; then
        result="Zenlayer (全球CDN/云)"
    elif [ "$has_aws" -gt 0 ]; then
        result="AWS (亚马逊云)"
    elif [ "$has_gcp" -gt 0 ]; then
        result="GCP (谷歌云)"
    elif [ "$has_azure" -gt 0 ]; then
        result="Azure (微软云)"
    elif [ "$has_cloudflare" -gt 0 ]; then
        result="Cloudflare"
    elif [ "$has_akamai" -gt 0 ]; then
        result="Akamai (CDN)"
    elif [ "$has_fastly" -gt 0 ]; then
        result="Fastly (CDN)"
    elif [ "$has_edgecast" -gt 0 ]; then
        result="Edgecast/Edgio (CDN)"
    elif [ "$has_oracle" -gt 0 ]; then
        result="Oracle Cloud"
    elif [ "$has_digitalocean" -gt 0 ]; then
        result="DigitalOcean"
    elif [ "$has_vultr" -gt 0 ]; then
        result="Vultr/Choopa"
    elif [ "$has_linode" -gt 0 ]; then
        result="Linode"
    elif [ "$has_ovh" -gt 0 ]; then
        result="OVHcloud"
    elif [ "$has_hetzner" -gt 0 ]; then
        result="Hetzner"
    elif [ "$has_scaleway" -gt 0 ]; then
        result="Scaleway"

    # ========== 美国/加拿大运营商 ==========
    elif [ "$has_att" -gt 0 ]; then
        result="美国 AT&T"
    elif [ "$has_verizon" -gt 0 ]; then
        result="美国 Verizon"
    elif [ "$has_sprint" -gt 0 ]; then
        result="美国 Sprint"
    elif [ "$has_charter" -gt 0 ]; then
        result="美国 Charter/Spectrum"
    elif [ "$has_comcast" -gt 0 ]; then
        result="美国 Comcast"
    elif [ "$has_windstream" -gt 0 ]; then
        result="美国 Windstream"
    elif [ "$has_rogers" -gt 0 ]; then
        result="加拿大 Rogers"
    elif [ "$has_telus" -gt 0 ]; then
        result="加拿大 Telus"

    # ========== 欧洲运营商 ==========
    elif [ "$has_dtag" -gt 0 ]; then
        result="德国 DTAG (德国电信)"
    elif [ "$has_orange" -gt 0 ]; then
        result="法国 Orange"
    elif [ "$has_vodafone" -gt 0 ]; then
        result="欧洲 Vodafone"
    elif [ "$has_swisscom" -gt 0 ]; then
        result="瑞士 Swisscom"
    elif [ "$has_bt" -gt 0 ]; then
        result="英国 BT (英国电信)"
    elif [ "$has_telefonica" -gt 0 ]; then
        result="西班牙 Telefonica"
    elif [ "$has_tele2" -gt 0 ]; then
        result="欧洲 Tele2"
    elif [ "$has_liberty" -gt 0 ]; then
        result="欧洲 Liberty Global"
    elif [ "$has_turktelekom" -gt 0 ]; then
        result="土耳其 Turk Telekom"
    elif [ "$has_turkcell" -gt 0 ]; then
        result="土耳其 Turkcell"
    elif [ "$has_telenor" -gt 0 ]; then
        result="北欧 Telenor"
    elif [ "$has_kpn" -gt 0 ]; then
        result="荷兰 KPN"
    elif [ "$has_proximus" -gt 0 ]; then
        result="比利时 Proximus"
    elif [ "$has_a1" -gt 0 ]; then
        result="奥地利 A1 Telekom"
    elif [ "$has_init7" -gt 0 ]; then
        result="瑞士 Init7"

    # ========== 俄罗斯运营商 ==========
    elif [ "$has_rostelecom" -gt 0 ]; then
        result="俄罗斯 Rostelecom"
    elif [ "$has_ttk" -gt 0 ]; then
        result="俄罗斯 TTK (TransTeleCom)"

    # ========== 中东运营商 ==========
    elif [ "$has_stc" -gt 0 ]; then
        result="沙特 STC"
    elif [ "$has_etisalat" -gt 0 ]; then
        result="阿联酋 Etisalat"
    elif [ "$has_du" -gt 0 ]; then
        result="阿联酋 du"
    elif [ "$has_zain" -gt 0 ]; then
        result="中东 Zain"
    elif [ "$has_ooredoo" -gt 0 ]; then
        result="中东 Ooredoo"
    elif [ "$has_bezeq" -gt 0 ]; then
        result="以色列 Bezeq"
    elif [ "$has_telecom_eg" -gt 0 ]; then
        result="埃及 Telecom Egypt"

    # ========== 非洲运营商 ==========
    elif [ "$has_mtn" -gt 0 ]; then
        result="非洲 MTN"
    elif [ "$has_liquid" -gt 0 ]; then
        result="非洲 Liquid Telecom"
    elif [ "$has_safaricom" -gt 0 ]; then
        result="肯尼亚 Safaricom"
    elif [ "$has_seacom" -gt 0 ]; then
        result="非洲 SEACOM"
    elif [ "$has_vodacom" -gt 0 ]; then
        result="南非 Vodacom"
    elif [ "$has_maroc" -gt 0 ]; then
        result="摩洛哥 Maroc Telecom"

    # ========== 拉美运营商 ==========
    elif [ "$has_telmex" -gt 0 ]; then
        result="墨西哥 Telmex"
    elif [ "$has_claro" -gt 0 ]; then
        result="拉美 Claro"
    elif [ "$has_vivo" -gt 0 ]; then
        result="巴西 Vivo"
    elif [ "$has_oi" -gt 0 ]; then
        result="巴西 Oi"
    elif [ "$has_embratel" -gt 0 ]; then
        result="巴西 Embratel"
    elif [ "$has_tim_br" -gt 0 ]; then
        result="巴西 TIM"

    else
        result="未识别"
    fi

    # 检测经过的骨干网路径
    # 注意：只检测真正的骨干网/Transit，不包括机房自身网络（VPS/云/CDN提供商）
    if [ "$result" != "未识别" ]; then
        if echo "$result" | grep -qE "电信|联通|移动|鹏博士|教育网|科技网|长城|阿里云|腾讯云|百度云|华为云"; then
            [ "$has_ntt" -gt 0 ] && transit="${transit}NTT → "
            [ "$has_gtt" -gt 0 ] && transit="${transit}GTT → "
            [ "$has_cogent" -gt 0 ] && transit="${transit}Cogent → "
            [ "$has_telia" -gt 0 ] && transit="${transit}Telia → "
            [ "$has_he" -gt 0 ] && transit="${transit}HE → "
            [ "$has_level3" -gt 0 ] && transit="${transit}Level3 → "
            [ "$has_pccw" -gt 0 ] && transit="${transit}PCCW → "
            [ "$has_softbank" -gt 0 ] && transit="${transit}软银 → "
            [ "$has_zayo" -gt 0 ] && transit="${transit}Zayo → "
            [ "$has_tata" -gt 0 ] && transit="${transit}Tata → "
            [ "$has_seabone" -gt 0 ] && transit="${transit}Seabone → "
            [ "$has_kddi" -gt 0 ] && transit="${transit}KDDI → "
            [ "$has_hgc" -gt 0 ] && transit="${transit}HGC → "
            [ "$has_colt" -gt 0 ] && transit="${transit}Colt → "
            [ "$has_retn" -gt 0 ] && transit="${transit}RETN → "
            [ "$has_telxius" -gt 0 ] && transit="${transit}Telxius → "
            [ "$has_hibernia" -gt 0 ] && transit="${transit}Hibernia → "
        fi
    fi

    if [ -n "$transit" ]; then
        result="${transit}${result}"
    fi

    # 提取最后一跳的延迟（目标延迟）
    local latency
    latency=$(echo "$block" | grep -oE '[0-9]+\.[0-9]+ ms' | tail -1 | sed 's/ ms//')
    if [ -n "$latency" ]; then
        result="${result} (${latency}ms)"
    fi

    ROUTE_SUMMARY+=("${no} ${title}: ${result}")
}

print_route_summary() {
    local log=$1
    local Yellow="\033[33m" && local Green="\033[32m" && local Blue="\033[34m"
    local Cyan="\033[36m" && local Magenta="\033[35m" && local Red="\033[31m" && local White="\033[37m"
    local Reset="\033[0m" && local Bold="\033[1m"
    echo -e "\n${Bold}================== 线路判断汇总 ==================${Reset}" | tee -a $log
    for item in "${ROUTE_SUMMARY[@]}"; do
        local color="$White"
        # 中国运营商/云
        echo "$item" | grep -qE "电信" && color="$Yellow"
        echo "$item" | grep -qE "联通" && color="$Green"
        echo "$item" | grep -qE "移动" && color="$Blue"
        echo "$item" | grep -qiE "鹏博士|教育网|科技网|长城|阿里云|腾讯云|百度云|华为云" && color="$Yellow"
        # 日本运营商
        echo "$item" | grep -qiE "软银|SoftBank|NTT|IIJ|KDDI|BIGLOBE|So-net|FreeBit|JPIX|BBIX" && color="$Magenta"
        # 香港运营商
        echo "$item" | grep -qiE "PCCW|HGC|HKBN|HKT|HKIX" && color="$Cyan"
        # 台湾运营商
        echo "$item" | grep -qiE "HiNet|Seednet|远传|TWM|FETnet|APTG|TBC" && color="$Cyan"
        # 韩国
        echo "$item" | grep -qiE "韩国|KINX" && color="$Cyan"
        # 东南亚/大洋洲/新西兰
        echo "$item" | grep -qiE "Singtel|StarHub|MyRepublic|Telstra|Optus|TPG|Vocus|Spark|越南|泰国|菲律宾|印尼|新加坡|澳洲|新西兰" && color="$Cyan"
        # 印度
        echo "$item" | grep -qiE "印度|Jio|Airtel|BSNL|VSNL|MTNL" && color="$Cyan"
        # 全球骨干
        echo "$item" | grep -qiE "GTT|Cogent|HE |Level3|Lumen|Telia|Arelion|Zayo|Tata Comm|Seabone|Sparkle|Colt|euNetworks|IX Reach|RETN|Hibernia|PacketFabric" && color="$Red"
        # IX 交换中心
        echo "$item" | grep -qiE "DE-CIX|AMS-IX|LINX|Equinix IX|Megaport" && color="$Red"
        # 云/CDN
        echo "$item" | grep -qiE "Zenlayer|AWS|GCP|Azure|Cloudflare|Akamai|Fastly|Edgecast|Edgio|Oracle Cloud|DigitalOcean|Vultr|Choopa|Linode|OVH|Hetzner|Scaleway" && color="$Magenta"
        # 美国/加拿大运营商
        echo "$item" | grep -qiE "AT&T|Verizon|Sprint|Charter|Spectrum|Comcast|Windstream|Rogers|Telus" && color="$Red"
        # 欧洲运营商
        echo "$item" | grep -qiE "DTAG|Orange|Vodafone|Swisscom|BT |Telefonica|Tele2|Liberty|Turk|Turkcell|Telenor|KPN|Proximus|A1 Telekom|Init7" && color="$Magenta"
        # 俄罗斯/中东/非洲/拉美
        echo "$item" | grep -qiE "Rostelecom|TTK|STC|Etisalat|du |Zain|Ooredoo|Bezeq|Egypt|MTN|Liquid|Safaricom|SEACOM|Vodacom|Maroc|Telmex|Claro|Vivo|Oi |Embratel|TIM" && color="$Cyan"
        # 未识别
        echo "$item" | grep -q "未识别" && color="$White"
        echo -e "${color}  $item${Reset}" | tee -a $log
    done
    echo -e "${Bold}==================================================${Reset}" | tee -a $log
    echo -e "${Bold}颜色说明: ${Yellow}中国${Reset} ${Green}联通${Reset} ${Blue}移动${Reset} ${Magenta}日本/欧洲/云CDN${Reset} ${Cyan}亚太/其他${Reset} ${Red}骨干/IX/北美${Reset}" | tee -a $log
    echo "" | tee -a $log
    ROUTE_SUMMARY=()
}
# ======= 线路判断函数结束 =======
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"

#检查当前账号是否为root，主要是后面要装软件
check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）。" && exit 1
}

#检查系统
check_sys(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"	
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
    fi
	[ -z "${release}" ] && echo -e "${Error} 未安装操作系统 !" && exit 1
	bit=`uname -m`

	# 主机架构判断
	ARCH=$(uname -m)
	if [[ $ARCH = *x86_64* ]]; then
		# 64-bit kernel
		bit="x64"
	elif [[ $ARCH = *i386* ]]; then
		# 32-bit kernel
		bit="x86"
	elif [[ $ARCH = *aarch* || $ARCH = *arm* ]]; then
		KERNEL_BIT=`getconf LONG_BIT`
		if [[ $KERNEL_BIT = *64* ]]; then
			# ARM 64-bit kernel
			bit="aarch64"
		else
			# ARM 32-bit kernel
			bit="arm"
		fi
		echo -e "\nARM 实验性质平台"
    elif [[ $ARCH = *mips* ]]; then
		# MIPS kernel
		bit="mips"
	else
		# 未知内核 
		echo -e "${Error} 无法受支持的系统 !" && exit 1
	fi

    #软件安装检查
	if  [[ "$(command -v wget)" == "" ]]; then
		echo -e "${Info} 开始安装 Wget ...."
		if [[ ${release} == "centos" ]]; then
			yum -y install Wget
		elif [[ ${release} == "debian" ]]; then	
			apt-get -y install Wget
		elif [[ ${release} == "ubuntu" ]]; then	
			apt-get -y install Wget	
		else
		 	echo -e "${Error} 无法判断您的系统 " && exit 1	
		fi
    elif  [[ "$(command -v curl)" == "" ]]; then
		echo -e "${Info} 开始安装 Curl ...."
		if [[ ${release} == "centos" ]]; then
			yum -y install curl
		elif [[ ${release} == "debian" ]]; then	
			apt-get -y install curl
		elif [[ ${release} == "ubuntu" ]]; then	
			apt-get -y install curl	
		else
		 	echo -e "${Error} 无法判断您的系统 " && exit 1	
		fi
    elif  [[ "$(command -v ping)" == "" ]]; then
		echo -e "${Info} 开始安装 Ping ...."
		if [[ ${release} == "centos" ]]; then
			yum -y install ping
		elif [[ ${release} == "debian" ]]; then	
			apt-get -y install ping
		elif [[ ${release} == "ubuntu" ]]; then	
			apt-get -y install ping	
		else
		 	echo -e "${Error} 无法判断您的系统 " && exit 1	
		fi
	fi    
}

#使用计数
statistics_of_run-times() {
    COUNT=$(
        curl -4 -ksm10 "https://hits.assd276080758.workers.dev/CESU?action=hit&title=hits&title_bg=%23555555&count_bg=%233aebee&edge_flat=false" 2>&1 ||
            curl -6 -ksm10 "https://hits.assd276080758.workers.dev/CESU?action=hit&title=hits&title_bg=%23555555&count_bg=%233aebee&edge_flat=false" 2>&1
    )
    if [ -z "$COUNT" ]; then
        TODAY="N/A"
        TOTAL="N/A"
    else
        #当天
        TODAY=$(echo "$COUNT" | grep -oP '"daily":\s*[0-9]+' | sed 's/"daily":\s*\([0-9]*\)/\1/')
        #累计
        TOTAL=$(echo "$COUNT" | grep -oP '"total":\s*[0-9]+' | sed 's/"total":\s*\([0-9]*\)/\1/')
        [ -z "$TODAY" ] && TODAY="N/A"
        [ -z "$TOTAL" ] && TOTAL="N/A"
    fi
}

#脚本版本更新（已改为从自有仓库管理，跳过原作者仓库的版本检查）
checkver() {
    echo -e "${Info} 本地脚本版本为：${sh_ver} "
    echo -e "${Info} 脚本由自有仓库管理，跳过自动更新检查 ！"
}

#检测IPv4、IPv6状态
IP_Check(){
    #通过ping ip.sb这个网站，如果ping通了没有报错，再和后面比较，如果都有输出，则代表网络通的。这个主要用来测试只有IPV4或IPV6的机器是不是有网
    IPV4_CHECK=$((ping -4 -c 1 -W 4 ip.sb >/dev/null 2>&1 && echo true) || curl -s -m 4 -4 ip-api.com 2> /dev/null)
    IPV6_CHECK=$((ping -6 -c 1 -W 4 ip.sb >/dev/null 2>&1 && echo true) || curl -s -m 4 -6 ip.sb 2> /dev/null)
    if [[ -z "$IPV4_CHECK" && -z "$IPV6_CHECK" ]]; then
        echo -e
        echo -e "${Error} 未检测到 IPv4 和 IPv6 连接，请检查 DNS 问题..." && exit 1 
    fi

    #开始检测IPv4、IPv6前的参数配置
    API_URL=("http://ip-api.com/json")
    
    #IPv4网络探测
    WAN_4=$(echo $(curl -s4 http://ip4.me/api/) | cut -d, -f2)
    IP_4=$(curl -s4m5 -A Mozilla $API_URL/$WAN_4)
    #如果IPv4不为空，就执行里面的
    if [ -n "$WAN_4" ]; then
      #输出IP的ISP
      ISP_4=$(expr "${IP_4}" : '.*isp\":[ ]*\"\([^"]*\).*')
      #输出IP的ASN
      ASN_4_Temp=$(echo $(curl -s4 http://ip-api.com/json/$WAN_4) | grep -Po '"as": *\K"[^"]*"')
      ASN_4=${ASN_4_Temp//\"}
      #输出IP的服务商
      Host_4_Temp=$(echo $(curl -s4 http://ip-api.com/json/$WAN_4) | grep -Po '"org": *\K"[^"]*"')
      Host_4=${Host_4_Temp//\"}
      #输出IP的国家，英文
      COUNTRY_4E=$(expr "${IP_4}" : '.*country\":[ ]*\"\([^"]*\).*')
      #输出IP的地址，英文
      City_4E=$(expr "${IP_4}" : '.*city\":[ ]*\"\([^"]*\).*')
      Region_4E=$(expr "${IP_4}" : '.*regionName\":[ ]*\"\([^"]*\).*')
      Region_code_4E=$(expr "${IP_4}" : '.*region\":[ ]*\"\([^"]*\).*')
      Location_4E="$City_4E, $Region_4E ($Region_code_4E)"
      
      #IP欺诈分数，使用https://github.com/lwthiker/curl-impersonate绕过CF
      #检测当下目录Curl-impersonate文件夹，如有则删除
      Curl_impersonate_Dle
        if [[ ${bit} == "mips" ]]; then
            FRAUD_SCORE_4="未知"
        else
            Curl_impersonate_Ver
            FRAUD_SCORE_4_TEMP=$(${Curl_impersonate_file} -m10 -sL -H "Referer: https://scamalytics.com" \
            "https://scamalytics.com/ip/$WAN_4" | awk -F : '/Fraud Score/ {gsub(/[^0-9]/,"",$2); print $2}')
            if [[ -z "$FRAUD_SCORE_4_TEMP" ]]; then
                FRAUD_SCORE_4="未知"
            else
                FRAUD_SCORE_4="$FRAUD_SCORE_4_TEMP"
            fi
        fi
        #删除Curl-impersonate文件夹
       Curl_impersonate_Dle

      #输出IP的类型：数据中心/家庭宽带/商业宽带/移动流量/内容分发网络/搜索引擎蜘蛛/教育网/未知
      #使用abuseipdb.com的API进行探测，每日1000次请求
      TYPE_4_Temp=$(curl -sG https://api.abuseipdb.com/api/v2/check \
      --data-urlencode "ipAddress=$WAN_4" \
      -d maxAgeInDays=90 \
      -d verbose \
      -H "Key: c97ab9480e282182aeac0408b788fad9e41d3ef5aa12d294b3fe8b50cfeb4edf43351bbe4870b066" \
      -H "Accept: application/json" | grep -Po '"usageType": *\K"[^"]*"' | sed "s#\\\##g" | sed 's/"//g')
        if [[ ${TYPE_4_Temp} == "Data Center/Web Hosting/Transit" ]]; then
            TYPE_4="数据中心"
        elif [[ ${TYPE_4_Temp} == "Fixed Line ISP" ]]; then
            TYPE_4="家庭宽带"
        elif [[ ${TYPE_4_Temp} == "Commercial" ]]; then
            TYPE_4="商业宽带"
        elif [[ ${TYPE_4_Temp} == "Mobile ISP" ]]; then
            TYPE_4="移动流量"
        elif [[ ${TYPE_4_Temp} == "Content Delivery Network" ]]; then
            TYPE_4="内容分发网络(CDN)"
        elif [[ ${TYPE_4_Temp} == "Search Engine Spider" ]]; then
            TYPE_4="搜索引擎蜘蛛"
        elif [[ ${TYPE_4_Temp} == "University/College/School" ]]; then
            TYPE_4="教育网"
        elif [[ ${TYPE_4_Temp} == "" ]]; then
            TYPE_4="未知 IP 网络类型"             
        fi           
    fi  

    #IPv6网络探测
    WAN_6=$(echo $(curl -s6 http://ip6.me/api/) | cut -d, -f2)
    IP_6=$(curl -s6m5 -A Mozilla $API_URL/$WAN_6) &&
    #如果IPv6不为空，就执行里面的
    if [ -n "$WAN_6" ]; then
      #输出IP的ISP
      ISP_6=$(expr "${IP_6}" : '.*isp\":[ ]*\"\([^"]*\).*')
      #输出IP的ASN
      ASN_6_Temp=$(echo $(curl -s6 http://ip-api.com/json/$WAN_6) | grep -Po '"as": *\K"[^"]*"')
      ASN_6=${ASN_6_Temp//\"}
      #输出IP的服务商
      Host_6_Temp=$(echo $(curl -s6 http://ip-api.com/json/$WAN_6) | grep -Po '"org": *\K"[^"]*"')
      Host_6=${Host_6_Temp//\"}
      #输出IP的国家，英文
      COUNTRY_6E=$(expr "${IP_6}" : '.*country\":[ ]*\"\([^"]*\).*')
      #输出IP的地址，英文
      City_6E=$(expr "${IP_6}" : '.*city\":[ ]*\"\([^"]*\).*')
      Region_6E=$(expr "${IP_6}" : '.*regionName\":[ ]*\"\([^"]*\).*')
      Region_code_6E=$(expr "${IP_6}" : '.*region\":[ ]*\"\([^"]*\).*')
      Location_6E="$City_6E, $Region_6E ($Region_code_6E)"

      #IP欺诈分数，使用https://github.com/lwthiker/curl-impersonate绕过CF
      #检测当下目录Curl-impersonate文件夹，如有则删除
      Curl_impersonate_Dle
        if [[ ${bit} == "mips" ]]; then
            FRAUD_SCORE_6="未知"
        else
            Curl_impersonate_Ver
            FRAUD_SCORE_6_TEMP=$(${Curl_impersonate_file} -m10 -sL -H "Referer: https://scamalytics.com" \
            "https://scamalytics.com/ip/$WAN_6" | awk -F : '/Fraud Score/ {gsub(/[^0-9]/,"",$2); print $2}')
            if [[ -z "$FRAUD_SCORE_6_TEMP" ]]; then
                FRAUD_SCORE_6="未知"
            else
                FRAUD_SCORE_6="$FRAUD_SCORE_6_TEMP"
            fi
        fi
        #删除Curl-impersonate文件夹
       Curl_impersonate_Dle

      #输出IP的类型：数据中心/家庭宽带/商业宽带/移动流量/内容分发网络/搜索引擎蜘蛛/教育网/未知
      #使用abuseipdb.com的API进行探测，每日1000次请求
      TYPE_6_Temp=$(curl -sG https://api.abuseipdb.com/api/v2/check \
      --data-urlencode "ipAddress=$WAN_6" \
      -d maxAgeInDays=90 \
      -d verbose \
      -H "Key: c97ab9480e282182aeac0408b788fad9e41d3ef5aa12d294b3fe8b50cfeb4edf43351bbe4870b066" \
      -H "Accept: application/json" | grep -Po '"usageType": *\K"[^"]*"' | sed "s#\\\##g" | sed 's/"//g')

      	if [[ ${TYPE_6_Temp} == "Data Center/Web Hosting/Transit" ]]; then
            TYPE_6="数据中心"
        elif [[ ${TYPE_6_Temp} == "Fixed Line ISP" ]]; then
            TYPE_6="家庭宽带"
        elif [[ ${TYPE_6_Temp} == "Commercial" ]]; then
            TYPE_6="商业宽带"
        elif [[ ${TYPE_6_Temp} == "Mobile ISP" ]]; then
            TYPE_6="移动流量"
        elif [[ ${TYPE_6_Temp} == "Content Delivery Network" ]]; then
            TYPE_6="内容分发网络(CDN)"
        elif [[ ${TYPE_6_Temp} == "Search Engine Spider" ]]; then
            TYPE_6="搜索引擎蜘蛛"
        elif [[ ${TYPE_6_Temp} == "University/College/School" ]]; then
            TYPE_6="教育网"
        elif [[ ${TYPE_6_Temp} == "" ]]; then
            TYPE_6="未知 IP 网络类型"               
        fi          
    fi

    #菜单栏统一输出参数
    if [[ -n ${WAN_4} ]]; then 
        IPv4_Print="${WAN_4}"
    else 
        IPv4_Print="无 IPv4"
    fi
    if [[ -n ${WAN_6} ]]; then 
        IPv6_Print="${WAN_6}"
    else 
        IPv6_Print="无 IPv6"
    fi
    #优先输出IPv4的ISP、ASN、IP服务商、国家、地址、网络信息
    if [[ -n ${WAN_4} ]]; then 
        ISP_Print="${ISP_4}"
        ASN_Print="${ASN_4}"
        Host_Print="${Host_4}"
        COUNTRY_Print="${COUNTRY_4E}"
        Location_Print="${Location_4E}"
        FRAUD_SCORE="${FRAUD_SCORE_4}"
        TYPE_Print="${TYPE_4}"
    elif [[ -n ${WAN_6} ]]; then 
        ISP_Print="${ISP_6}"
        ASN_Print="${ASN_6}"
        Host_Print="${Host_6}"
        COUNTRY_Print="${COUNTRY_6E}"
        Location_Print="${Location_6E}"
        FRAUD_SCORE="${FRAUD_SCORE_6}"
        TYPE_Print="${TYPE_6}"
    else
        ISP_Print="网络连接出错，无法探测"
        ASN_Print="网络连接出错，无法探测"
        Host_Print="网络连接出错，无法探测"
        COUNTRY_Print="网络连接出错，无法探测"
        Location_Print="网络连接出错，无法探测"
        FRAUD_SCORE="网络连接出错，无法探测"
        TYPE_Print="网络连接出错，无法探测"   
    fi    
}

#BestTrace IPv4 回程代码 中文输出 
BT_Ipv4_mtr_CN(){
    if [ "$2" = "tcp" ] || [ "$2" = "TCP" ]; then
        echo -e "\n$5 Traceroute to $4 (TCP Mode, Max $3 Hop, IPv4)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${BestTrace_file} -g cn -q 1 -n -T -m $3 $1 | tee -a $log
    elif [ "$2" = "icmp" ] || [ "$2" = "ICMP" ]; then
        echo -e "\n$5 Tracecroute to $4 (ICMP Mode, Max $3 Hop, IPv4)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${BestTrace_file} -g cn -q 1 -n -m $3 $1 | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi
}

#BestTrace IPv4 IP库三网回程路由测试 中文输出  (若需修改IP，可修改IPv4_IP代码段；若需修改TCP/ICMP，可修改BestTrace_Mode代码段)
BT_IPv4_IP_CN_Mtr(){
    #检测是否存在 IPv4
    if  [[ "${WAN_4}" == "" ]]; then
        echo -e "${Error} 本机没有 IPv4 地址" && exit 1
    fi
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载BestTrace主程序
    BestTrace_Ver
    #载入IPv4库     
    IPv4_IP
    #载入BestTrace参数
    BestTrace_Mode
    #开始测试IPv4库回程路由，第5个块是表示节点序号的，增删节点都要修改
    clear  
 	BT_Ipv4_mtr_CN "${IPv4_1}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_1_name}" "No:1/9"
    BT_Ipv4_mtr_CN "${IPv4_2}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_2_name}" "No:2/9"
    BT_Ipv4_mtr_CN "${IPv4_3}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_3_name}" "No:3/9"
    BT_Ipv4_mtr_CN "${IPv4_4}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_4_name}" "No:4/9"
    BT_Ipv4_mtr_CN "${IPv4_5}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_5_name}" "No:5/9"
    BT_Ipv4_mtr_CN "${IPv4_6}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_6_name}" "No:6/9"
    BT_Ipv4_mtr_CN "${IPv4_7}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_7_name}" "No:7/9"
    BT_Ipv4_mtr_CN "${IPv4_8}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_8_name}" "No:8/9"
    BT_Ipv4_mtr_CN "${IPv4_9}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_9_name}" "No:9/9"
    #保留IPv4回程路由日志
    echo -e "${Info} 回程路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除BestTrace执行文件
    BestTrace_Dle     
}

#BestTrace IPv4 回程代码 英文输出 
BT_Ipv4_mtr_EN(){
    if [ "$2" = "tcp" ] || [ "$2" = "TCP" ]; then
        echo -e "\n$5 Traceroute to $4 (TCP Mode, Max $3 Hop, IPv4)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${BestTrace_file} -g en -q 1 -n -T -m $3 $1 | tee -a $log
    elif [ "$2" = "icmp" ] || [ "$2" = "ICMP" ]; then
        echo -e "\n$5 Tracecroute to $4 (ICMP Mode, Max $3 Hop, IPv4)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${BestTrace_file} -g en -q 1 -n -m $3 $1 | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi     
}

#BestTrace IPv4 IP库三网回程路由测试 英文输出  (若需修改IP，可修改IPv4_IP代码段；若需修改TCP/ICMP，可修改BestTrace_Mode代码段)
BT_IPv4_IP_EN_Mtr(){
    #检测是否存在 IPv4
    if  [[ "${WAN_4}" == "" ]]; then
        echo -e "${Error} 本机没有 IPv4 地址" && exit 1
    fi     
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载BestTrace主程序
    BestTrace_Ver
    #载入IPv4库     
    IPv4_IP
    #载入BestTrace参数
    BestTrace_Mode
    #开始测试IPv4库回程路由，第5个块是表示节点序号的，增删节点都要修改
    clear  
 	BT_Ipv4_mtr_EN "${IPv4_1}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_1_name}" "No:1/9"
    BT_Ipv4_mtr_EN "${IPv4_2}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_2_name}" "No:2/9"
    BT_Ipv4_mtr_EN "${IPv4_3}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_3_name}" "No:3/9"
    BT_Ipv4_mtr_EN "${IPv4_4}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_4_name}" "No:4/9"
    BT_Ipv4_mtr_EN "${IPv4_5}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_5_name}" "No:5/9"
    BT_Ipv4_mtr_EN "${IPv4_6}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_6_name}" "No:6/9"
    BT_Ipv4_mtr_EN "${IPv4_7}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_7_name}" "No:7/9"
    BT_Ipv4_mtr_EN "${IPv4_8}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_8_name}" "No:8/9"
    BT_Ipv4_mtr_EN "${IPv4_9}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_9_name}" "No:9/9"
    #保留IPv4回程路由日志
    echo -e "${Info} 回程路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除BestTrace执行文件
    BestTrace_Dle      
}

#Nexttrace IPv4 回程代码 中文输出 
NT_Ipv4_mtr_CN(){
    # 记录本段开始行号
    NT_BLOCK_START=$(( $(wc -l < "$log") + 1 ))
    if [ "$2" = "tcp" ] || [ "$2" = "TCP" ]; then
        echo -e "\n$5 Traceroute to $4 (TCP Mode, Max $3 Hop, IPv4)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g cn -q 1 -n -T -m $3 $1 | tee -a $log
    elif [ "$2" = "icmp" ] || [ "$2" = "ICMP" ]; then
        echo -e "\n$5 Tracecroute to $4 (ICMP Mode, Max $3 Hop, IPv4)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g cn -q 1 -n -m $3 $1 | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi   
}

#Nexttrace IPv4 IP库三网回程路由测试 中文输出  (若需修改IP，可修改IPv4_IP代码段；若需修改TCP/ICMP，可修改Nexttrace_Mode代码段)
NT_IPv4_IP_CN_Mtr(){
    #检测是否存在 IPv4
    if  [[ "${WAN_4}" == "" ]]; then
        echo -e "${Error} 本机没有 IPv4 地址" && exit 1
    fi     
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载Nexttrace主程序
    Nexttrace_Ver
    #载入IPv4库     
    IPv4_IP
    #载入Nexttrace参数
    Nexttrace_Mode
    #检测 POW 节点
    nexttrace_detect_pow
    #开始测试IPv4库回程路由，第5个块是表示节点序号的，增删节点都要修改
    clear    
 	NT_Ipv4_mtr_CN "${IPv4_1}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_1_name}" "No:1/9"
    judge_route "$log" "${IPv4_1_name}" "No:1/9"
    NT_Ipv4_mtr_CN "${IPv4_2}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_2_name}" "No:2/9"
    judge_route "$log" "${IPv4_2_name}" "No:2/9"
    NT_Ipv4_mtr_CN "${IPv4_3}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_3_name}" "No:3/9"
    judge_route "$log" "${IPv4_3_name}" "No:3/9"
    NT_Ipv4_mtr_CN "${IPv4_4}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_4_name}" "No:4/9"
    judge_route "$log" "${IPv4_4_name}" "No:4/9"
    NT_Ipv4_mtr_CN "${IPv4_5}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_5_name}" "No:5/9"
    judge_route "$log" "${IPv4_5_name}" "No:5/9"
    NT_Ipv4_mtr_CN "${IPv4_6}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_6_name}" "No:6/9"
    judge_route "$log" "${IPv4_6_name}" "No:6/9"
    NT_Ipv4_mtr_CN "${IPv4_7}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_7_name}" "No:7/9"
    judge_route "$log" "${IPv4_7_name}" "No:7/9"
    NT_Ipv4_mtr_CN "${IPv4_8}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_8_name}" "No:8/9"
    judge_route "$log" "${IPv4_8_name}" "No:8/9"
    NT_Ipv4_mtr_CN "${IPv4_9}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_9_name}" "No:9/9"
    judge_route "$log" "${IPv4_9_name}" "No:9/9"
    #输出线路判断汇总
    print_route_summary "$log"
    #保留IPv4回程路由日志
    echo -e "${Info} 回程路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除Nexttrace执行文件
    Nexttrace_Dle       
}

#Nexttrace IPv4 回程代码 英文输出 
NT_Ipv4_mtr_EN(){
    if [ "$2" = "tcp" ] || [ "$2" = "TCP" ]; then
        echo -e "\n$5 Traceroute to $4 (TCP Mode, Max $3 Hop, IPv4)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g en -q 1 -n -T -m $3 $1 | tee -a $log
    elif [ "$2" = "icmp" ] || [ "$2" = "ICMP" ]; then
        echo -e "\n$5 Tracecroute to $4 (ICMP Mode, Max $3 Hop, IPv4)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g en -q 1 -n -m $3 $1 | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi   
}

#Nexttrace IPv4 IP库三网回程路由测试 英文输出  (若需修改IP，可修改IPv4_IP代码段；若需修改TCP/ICMP，可修改Nexttrace_Mode代码段)
NT_IPv4_IP_EN_Mtr(){
    #检测是否存在 IPv4
    if  [[ "${WAN_4}" == "" ]]; then
        echo -e "${Error} 本机没有 IPv4 地址" && exit 1
    fi     
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载Nexttrace主程序
    Nexttrace_Ver
    #载入IPv4库     
    IPv4_IP
    #载入Nexttrace参数
    Nexttrace_Mode
    #检测 POW 节点
    nexttrace_detect_pow
    #开始测试IPv4库回程路由，第5个块是表示节点序号的，增删节点都要修改
    clear    
 	NT_Ipv4_mtr_EN "${IPv4_1}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_1_name}" "No:1/9"
    NT_Ipv4_mtr_EN "${IPv4_2}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_2_name}" "No:2/9"
    NT_Ipv4_mtr_EN "${IPv4_3}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_3_name}" "No:3/9"
    NT_Ipv4_mtr_EN "${IPv4_4}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_4_name}" "No:4/9"
    NT_Ipv4_mtr_EN "${IPv4_5}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_5_name}" "No:5/9"
    NT_Ipv4_mtr_EN "${IPv4_6}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_6_name}" "No:6/9"
    NT_Ipv4_mtr_EN "${IPv4_7}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_7_name}" "No:7/9"
    NT_Ipv4_mtr_EN "${IPv4_8}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_8_name}" "No:8/9"
    NT_Ipv4_mtr_EN "${IPv4_9}" "${Net_Mode}" "${Hop_Mode}" "${IPv4_9_name}" "No:9/9"
    #保留IPv4回程路由日志
    echo -e "${Info} 回程路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除Nexttrace执行文件
    Nexttrace_Dle       
}

#IP v4 库（可以是IP，也可以是域名）
IPv4_IP(){
    #电信
    IPv4_1="gd-ct-v4.ip.zstaticcdn.com:80"
    IPv4_1_name="中国 广东 电信"
    
    IPv4_2="sh-ct-v4.ip.zstaticcdn.com:80"
    IPv4_2_name="中国 上海 电信"
    
    IPv4_3="bj-ct-v4.ip.zstaticcdn.com:80"
    IPv4_3_name="中国 北京 电信"   
    #联通
    IPv4_4="gd-cu-v4.ip.zstaticcdn.com:80"
    IPv4_4_name="中国 广东 联通"
    
    IPv4_5="sh-cu-v4.ip.zstaticcdn.com:80"
    IPv4_5_name="中国 上海 联通"
    
    IPv4_6="bj-cu-v4.ip.zstaticcdn.com:80"
    IPv4_6_name="中国 北京 联通"
    #移动
    IPv4_7="gd-cm-v4.ip.zstaticcdn.com:80"
    IPv4_7_name="中国 广东 移动"
    
    IPv4_8="sh-cm-v4.ip.zstaticcdn.com:80"
    IPv4_8_name="中国 上海 移动"
    
    IPv4_9="bj-cm-v4.ip.zstaticcdn.com:80"
    IPv4_9_name="中国 北京 移动"
}

#Nexttrace IPv6 回程代码 中文输出 
NT_Ipv6_mtr_CN(){
    if [ "$2" = "tcp" ] || [ "$2" = "TCP" ]; then
        echo -e "\n$5 Traceroute to $4 (TCP Mode, Max $3 Hop, IPv6)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g cn -q 1 -n -T -m $3 $1 | tee -a $log
    elif [ "$2" = "icmp" ] || [ "$2" = "ICMP" ]; then
        echo -e "\n$5 Tracecroute to $4 (ICMP Mode, Max $3 Hop, IPv6)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g cn -q 1 -n -m $3 $1 | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi   
}

#Nexttrace IPv6 IP库三网回程路由测试 中文输出  (若需修改IP，可修改IPv6_IP代码段；若需修改TCP/ICMP，可修改Nexttrace_Mode代码段)
NT_IPv6_IP_CN_Mtr(){
    #检测是否存在 IPv6
    if  [[ "${WAN_6}" == "" ]]; then
        echo -e "${Error} 本机没有 IPv6 地址" && exit 1
    fi     
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载Nexttrace主程序
    Nexttrace_Ver
    #载入IPv4库     
    IPv6_IP
    #载入Nexttrace参数
    Nexttrace_Mode
    #检测 POW 节点
    nexttrace_detect_pow
    #开始测试IPv6库回程路由，第5个块是表示节点序号的，增删节点都要修改
    clear    
 	NT_Ipv6_mtr_CN "${IPv6_1}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_1_name}" "No:1/9"
    NT_Ipv6_mtr_CN "${IPv6_2}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_2_name}" "No:2/9"
    NT_Ipv6_mtr_CN "${IPv6_3}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_3_name}" "No:3/9" 
    NT_Ipv6_mtr_CN "${IPv6_4}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_4_name}" "No:4/9" 
    NT_Ipv6_mtr_CN "${IPv6_5}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_5_name}" "No:5/9" 
    NT_Ipv6_mtr_CN "${IPv6_6}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_6_name}" "No:6/9" 
    NT_Ipv6_mtr_CN "${IPv6_7}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_7_name}" "No:7/9" 
    NT_Ipv6_mtr_CN "${IPv6_8}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_8_name}" "No:8/9" 
    NT_Ipv6_mtr_CN "${IPv6_9}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_9_name}" "No:9/9" 
    #保留IPv6回程路由日志
    echo -e "${Info} 回程路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除Nexttrace执行文件
    Nexttrace_Dle       
}

#Nexttrace IPv6 回程代码 英文输出 
NT_Ipv6_mtr_EN(){
    if [ "$2" = "tcp" ] || [ "$2" = "TCP" ]; then
        echo -e "\n$5 Traceroute to $4 (TCP Mode, Max $3 Hop, IPv6)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g en -q 1 -n -T -m $3 $1 | tee -a $log
    elif [ "$2" = "icmp" ] || [ "$2" = "ICMP" ]; then
        echo -e "\n$5 Tracecroute to $4 (ICMP Mode, Max $3 Hop, IPv6)" | tee -a $log
        echo -e "===================================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g en -q 1 -n -m $3 $1 | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi     
}

#IPv6 IP库三网回程路由测试 英文输出  (若需修改IP，可修改IPv6_IP代码段；若需修改TCP/ICMP，可修改Nexttrace_Mode代码段)
NT_IPv6_IP_EN_Mtr(){
    #检测是否存在 IPv6
    if  [[ "${WAN_6}" == "" ]]; then
        echo -e "${Error} 本机没有 IPv6 地址" && exit 1
    fi     
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载Nexttrace主程序
    Nexttrace_Ver
    #载入IPv4库     
    IPv6_IP
    #载入Nexttrace参数
    Nexttrace_Mode
    #检测 POW 节点
    nexttrace_detect_pow
    #开始测试IPv6库回程路由，第5个块是表示节点序号的，增删节点都要修改
    clear  
 	NT_Ipv6_mtr_EN "${IPv6_1}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_1_name}" "No:1/9"
    NT_Ipv6_mtr_EN "${IPv6_2}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_2_name}" "No:2/9"
    NT_Ipv6_mtr_EN "${IPv6_3}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_3_name}" "No:3/9"  
    NT_Ipv6_mtr_EN "${IPv6_4}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_4_name}" "No:4/9" 
    NT_Ipv6_mtr_EN "${IPv6_5}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_5_name}" "No:5/9" 
    NT_Ipv6_mtr_EN "${IPv6_6}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_6_name}" "No:6/9" 
    NT_Ipv6_mtr_EN "${IPv6_7}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_7_name}" "No:7/9" 
    NT_Ipv6_mtr_EN "${IPv6_8}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_8_name}" "No:8/9" 
    NT_Ipv6_mtr_EN "${IPv6_9}" "${Net_Mode}" "${Hop_Mode}" "${IPv6_9_name}" "No:9/9" 
    #保留IPv6回程路由日志
    echo -e "${Info} 回程路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除Nexttrace执行文件
    Nexttrace_Dle  
}

#IP v6 库（可以是IP，也可以是域名）
IPv6_IP(){
    #电信
    IPv6_1="bj-ct-v6.ip.zstaticcdn.com:80"
    IPv6_1_name="中国 北京 电信"
    
    IPv6_2="sh-ct-v6.ip.zstaticcdn.com:80"
    IPv6_2_name="中国 上海 电信"
    
    IPv6_3="gd-ct-v6.ip.zstaticcdn.com:80"
    IPv6_3_name="中国 广东 电信" 

    #联通
    IPv6_4="bj-cu-v6.ip.zstaticcdn.com:80"
    IPv6_4_name="中国 北京 联通" 

    IPv6_5="sh-cu-v6.ip.zstaticcdn.com:80"
    IPv6_5_name="中国 上海 联通"   

    IPv6_6="gd-cu-v6.ip.zstaticcdn.com:80"
    IPv6_6_name="中国 广东 联通" 
    
    #移动
    IPv6_7="bj-cm-v6.ip.zstaticcdn.com:80"
    IPv6_7_name="中国 北京 移动" 

    IPv6_8="sh-cm-v6.ip.zstaticcdn.com:80"
    IPv6_8_name="中国 上海 移动"   

    IPv6_9="gd-cm-v6.ip.zstaticcdn.com:80"
    IPv6_9_name="中国 广东 移动"    
}


#参数配置区域
#==========================================================================================
#BestTrace 参数设置
BestTrace_Mode(){
    #使用TCP SYN进行探测，如需ICMP，直接改为ICMP即可
    Net_Mode="TCP"
    #最大跳数（最大生存时间值），默认 30
    Hop_Mode="30"
}

#Nexttrace 参数设置
Nexttrace_Mode(){
    #使用TCP SYN进行探测，如需ICMP，直接改为ICMP即可
    Net_Mode="TCP"
    #最大跳数（最大生存时间值），默认 30
    Hop_Mode="30"
}

#当下目录BestTrace主程序文件删除
BestTrace_Dle(){
    rm -rf "${BestTrace_dir}"
	if [[ -e ${BestTrace_dir} ]]; then
		echo -e "${Error} 删除 BestTrace 文件失败，请手动删除 ${BestTrace_file}"
	else	
		echo -e "${Info} 已删除 BestTrace 文件"
	fi   
}

#当下目录Nexttrace主程序文件删除
Nexttrace_Dle(){
    rm -rf "${Nexttrace_dir}"
	if [[ -e ${Nexttrace_dir} ]]; then
		echo -e "${Error} 删除 Nexttrace 文件失败，请手动删除 ${Nexttrace_dir}"
	else	
		echo -e "${Info} 已删除 Nexttrace 文件"
	fi  
}

#当下目录Curl-impersonate主程序文件删除
Curl_impersonate_Dle(){
    rm -rf "${Curl_impersonate_dir}"
	if [[ -e ${Curl_impersonate_dir} ]]; then
		echo -e "${Error} 删除 Curl-impersonate 文件失败，请手动删除 ${Curl_impersonate_dir}"
	else	
		echo -e "${Info} 已删除 Curl-impersonate 文件"
	fi  
}

#删除当前目录下的路由路径文件，共用
Log_Dle(){
    rm -rf "${log}"
	if [[ -e ${log} ]]; then
		echo -e "${Error} 删除 路由路径 文件失败，请手动删除 ${log}"
	else	
		echo -e "${Info} 已删除 路由路径 文件"
	fi  
}

#前置参数启动
AutoTrace_Start(){
    #检测当下目录BestTrace文件夹，如有则删除
    BestTrace_Dle
    #检测当下目录Nexttrace文件夹，如有则删除
    Nexttrace_Dle
    #删除当前目录下的路由路径文件
    Log_Dle
    #开始生成本次报告的时间
    echo -e "${Info} 本报告生成时间：${rep_time}" | tee -a $log  
}

#BestTrace版本下载
BestTrace_Ver(){
    if [[ ${release} == "centos" ]]; then
        BestTrace_bit
        echo -e "${Info} CentOS BestTrace 检测已下载 !" | tee -a $log
    elif [[ ${release} == "debian" ]]; then 
        BestTrace_bit
        echo -e "${Info} Debian BestTrace 检测已下载 !" | tee -a $log      
    elif [[ ${release} == "ubuntu" ]]; then 
        BestTrace_bit
        echo -e "${Info} Ubuntu BestTrace 检测已下载 !" | tee -a $log 
    else
        echo -e "${Error} 无法受支持的系统 !" && exit 1
    fi
}

#BestTrace 系统位数版本下载
BestTrace_bit(){
    echo -e "${Info} 开始根据系统位数下载 BestTrace !"
    mkdir "${BestTrace_dir}"
    echo -e "${Info} 当前目录建立 BestTrace 文件夹 !"
    if [[ ${bit} == "x64" ]]; then 
        if ! wget --no-check-certificate -O ${BestTrace_dir}/besttrace_IP https://raw.githubusercontent.com/luzi6033666/shell/main/BestTrace/besttrace; then
            echo -e "${Error} BestTrace_x64 下载失败 !" && exit 1
        else
            echo -e "${Info} BestTrace_x64 下载完成 !" | tee -a $log
        fi
    elif [[ ${bit} == "x86" ]]; then
            if ! wget --no-check-certificate -O ${BestTrace_dir}/besttrace_IP https://raw.githubusercontent.com/luzi6033666/shell/main/BestTrace/besttrace32; then
            echo -e "${Error} BestTrace_x32 下载失败 !" && exit 1
        else
            echo -e "${Info} BestTrace_x32 下载完成 !" | tee -a $log
        fi 
    elif [[ ${bit} == "aarch64" ]]; then
            if ! wget --no-check-certificate -O ${BestTrace_dir}/besttrace_IP https://raw.githubusercontent.com/luzi6033666/shell/main/BestTrace/besttracearm; then
            echo -e "${Error} BestTrace_ARM 下载失败 !" && exit 1
        else
            echo -e "${Info} BestTrace_ARM 下载完成 !" | tee -a $log
        fi
    elif [[ ${bit} == "arm" ]]; then
            if ! wget --no-check-certificate -O ${BestTrace_dir}/besttrace_IP https://raw.githubusercontent.com/luzi6033666/shell/main/BestTrace/besttracearm; then
            echo -e "${Error} BestTrace_ARM 下载失败 !" && exit 1
        else
            echo -e "${Info} BestTrace_ARM 下载完成 !" | tee -a $log
        fi
    else
        echo -e "${Error} 无法受支持的系统 !" && exit 1
    fi
    #检查BestTrace文件是否存在
    if [[ -e ${BestTrace_file} ]]; then
        echo -e "${Info} BestTrace 已下载 !"
        chmod +x "${BestTrace_file}"
    else
        echo -e "${Error} 未检测到 BestTrace 文件，请查看 ${BestTrace_dir} 目录文件是否存在!" && exit 1       
    fi
}

#Nexttrace版本下载
Nexttrace_Ver(){
    if [[ ${release} == "centos" ]]; then
        Nexttrace_bit
        echo -e "${Info} CentOS Nexttrace 检测已下载 !" | tee -a $log
    elif [[ ${release} == "debian" ]]; then 
        Nexttrace_bit
        echo -e "${Info} Debian Nexttrace 检测已下载 !" | tee -a $log      
    elif [[ ${release} == "ubuntu" ]]; then 
        Nexttrace_bit
        echo -e "${Info} Ubuntu Nexttrace 检测已下载 !" | tee -a $log 
    else
        echo -e "${Error} 无法受支持的系统 !" && exit 1
    fi
}

#Nexttrace 系统位数版本下载
Nexttrace_bit(){
    echo -e "${Info} 开始根据系统位数下载 Nexttrace !"
    mkdir "${Nexttrace_dir}"
    echo -e "${Info} 当前目录建立 Nexttrace 文件夹 !"
    #网址直接获取特定文件最终版
    #https://github.com/sjlleo/nexttrace/releases/latest/download/nexttrace_linux_386 
    #通过Github API获取最新版本号
    local NT_Ver=$(curl -sL https://raw.githubusercontent.com/luzi6033666/shell/main/Nexttrace/version.txt | tr -d '[:space:]')
    echo -e "${Info} Nexttrace最新版本为 $NT_Ver" | tee -a $log 
    #开始分版本下载
    if [[ ${bit} == "x64" ]]; then 
        if ! wget --no-check-certificate -O ${Nexttrace_dir}/nexttrace_IP https://raw.githubusercontent.com/luzi6033666/shell/main/Nexttrace/nexttrace_linux_amd64; then
            echo -e "${Error} Nexttrace_x64 下载失败 !" && exit 1
        else
            echo -e "${Info} Nexttrace_x64 下载完成 !" | tee -a $log
        fi
    elif [[ ${bit} == "x86" ]]; then
            if ! wget --no-check-certificate -O ${Nexttrace_dir}/nexttrace_IP https://raw.githubusercontent.com/luzi6033666/shell/main/Nexttrace/nexttrace_linux_386; then
            echo -e "${Error} Nexttrace_x32 下载失败 !" && exit 1
        else
            echo -e "${Info} Nexttrace_x32 下载完成 !" | tee -a $log
        fi 
    elif [[ ${bit} == "aarch64" ]]; then
            if ! wget --no-check-certificate -O ${Nexttrace_dir}/nexttrace_IP https://raw.githubusercontent.com/luzi6033666/shell/main/Nexttrace/nexttrace_linux_arm64; then
            echo -e "${Error} Nexttrace_ARM_X64 下载失败 !" && exit 1
        else
            echo -e "${Info} Nexttrace_ARM_X64 下载完成 !" | tee -a $log
        fi
    elif [[ ${bit} == "arm" ]]; then
            if ! wget --no-check-certificate -O ${Nexttrace_dir}/nexttrace_IP https://raw.githubusercontent.com/luzi6033666/shell/main/Nexttrace/nexttrace_linux_armv7; then
            echo -e "${Error} Nexttrace_ARM_X32 下载失败 !" && exit 1
        else
            echo -e "${Info} Nexttrace_ARM_X32 下载完成 !" | tee -a $log
        fi
    elif [[ ${bit} == "mips" ]]; then
            if ! wget --no-check-certificate -O ${Nexttrace_dir}/nexttrace_IP https://raw.githubusercontent.com/luzi6033666/shell/main/Nexttrace/nexttrace_linux_mips; then
            echo -e "${Error} Nexttrace_MIPS 下载失败 !" && exit 1
        else
            echo -e "${Info} Nexttrace_MIPS 下载完成 !" | tee -a $log
        fi
    else
        echo -e "${Error} 无法受支持的系统 !" && exit 1
    fi
    #检查Nexttrace文件是否存在
    if [[ -e ${Nexttrace_file} ]]; then
        echo -e "${Info} Nexttrace 已下载 !"
        chmod +x "${Nexttrace_file}"
    else
        echo -e "${Error} 未检测到 Nexttrace 文件，请查看 ${Nexttrace_dir} 目录文件是否存在!" && exit 1       
    fi
}

#Curl-impersonate版本下载
Curl_impersonate_Ver(){
    if [[ ${release} == "centos" ]]; then
        Curl_impersonate_bit
        echo -e "${Info} CentOS Curl-impersonate 检测已下载 !" | tee -a $log
    elif [[ ${release} == "debian" ]]; then 
        Curl_impersonate_bit
        echo -e "${Info} Debian Curl-impersonate 检测已下载 !" | tee -a $log      
    elif [[ ${release} == "ubuntu" ]]; then 
        Curl_impersonate_bit
        echo -e "${Info} Ubuntu Curl-impersonate 检测已下载 !" | tee -a $log 
    else
        echo -e "${Error} 无法受支持的系统 !" && exit 1
    fi
}

#Curl-impersonate系统位数版本下载
Curl_impersonate_bit(){
    echo -e "${Info} 开始根据系统位数下载 Curl-impersonate !"
    mkdir "${Curl_impersonate_dir}"
    echo -e "${Info} 当前目录建立 Curl-impersonate 文件夹 !"
    #开始配置文件下载
    if ! wget --no-check-certificate -O ${Curl_impersonate_dir}/curl_chrome116 https://raw.githubusercontent.com/luzi6033666/shell/main/curl-impersonate/curl_chrome116; then
        echo -e "${Error} Curl-impersonate 配置文件下载失败 !" && exit 1
    else
        echo -e "${Info} Curl-impersonate 配置文件下载完成 !" | tee -a $log
    fi
    #检查Curl-impersonate配置文件是否存在
    if [[ -e ${Curl_impersonate_file} ]]; then
        echo -e "${Info} Curl-impersonate 配置文件已下载 !"
        chmod +x "${Curl_impersonate_file}"
    else
        echo -e "${Error} 未检测到 Curl-impersonate 配置文件，请查看 ${Curl_impersonate_file} 目录文件是否存在!" && exit 1       
    fi
    #开始二进制CURL文件下载
    if [[ ${bit} == "x64" ]]; then 
        if ! wget --no-check-certificate -O ${Curl_impersonate_dir}/curl-impersonate-chrome https://raw.githubusercontent.com/luzi6033666/shell/main/curl-impersonate/curl-impersonate-chrome_x86_64-linux; then
            echo -e "${Error} Curl-impersonate_x64 下载失败 !" && exit 1
        else
            echo -e "${Info} Curl-impersonate_x64 下载完成 !" | tee -a $log
        fi
    elif [[ ${bit} == "x86" ]]; then
            if ! wget --no-check-certificate -O ${Curl_impersonate_dir}/curl-impersonate-chrome https://raw.githubusercontent.com/luzi6033666/shell/main/curl-impersonate/curl-impersonate-chrome_x86_64-linux; then
            echo -e "${Error} Curl-impersonate_x32 下载失败 !" && exit 1
        else
            echo -e "${Info} Curl-impersonate_x32 下载完成 !" | tee -a $log
        fi 
    elif [[ ${bit} == "aarch64" ]]; then
            if ! wget --no-check-certificate -O ${Curl_impersonate_dir}/curl-impersonate-chrome https://raw.githubusercontent.com/luzi6033666/shell/main/curl-impersonate/curl-impersonate-chrome_aarch64-linux; then
            echo -e "${Error} Curl-impersonate_ARM_X64 下载失败 !" && exit 1
        else
            echo -e "${Info} Curl-impersonate_ARM_X64 下载完成 !" | tee -a $log
        fi
    elif [[ ${bit} == "arm" ]]; then
            if ! wget --no-check-certificate -O ${Curl_impersonate_dir}/curl-impersonate-chrome https://raw.githubusercontent.com/luzi6033666/shell/main/curl-impersonate/curl-impersonate-chrome_arm-linux; then
            echo -e "${Error} Curl-impersonate_ARM_X32 下载失败 !" && exit 1
        else
            echo -e "${Info} Curl-impersonate_ARM_X32 下载完成 !" | tee -a $log
        fi
    else
        echo -e "${Error} 无法受支持的系统 !" && exit 1
    fi
    #检查Curl-impersonate二进制文件是否存在
    if [[ -e ${Curl_impersonate_dir}/curl-impersonate-chrome ]]; then
        echo -e "${Info} Curl-impersonate二进制文件已下载 !"
        chmod +x "${Curl_impersonate_dir}/curl-impersonate-chrome"
    else
        echo -e "${Error} 未检测到 Curl-impersonate二进制文件，请查看 ${Curl_impersonate_dir}/curl-impersonate-chrome 目录文件是否存在!" && exit 1       
    fi
}
###到指定IP路由测试部分    开始========================================================

#到指定IP路由测试 主菜单
Specify_IP(){
	clear
echo -e " 请选择需要的测试项（TCP Mode）
————————————————————————————————————
${Green_font_prefix} 1. ${Font_color_suffix}本机到指定 IPv4 路由 中文 输出 Nexttrace库（可指定端口）
${Green_font_prefix} 2. ${Font_color_suffix}本机到指定 IPv4 路由 英文 输出 Nexttrace库（可指定端口）
${Green_font_prefix} 3. ${Font_color_suffix}本机到指定 IPv6 路由 中文 输出 Nexttrace库（可指定端口）
${Green_font_prefix} 4. ${Font_color_suffix}本机到指定 IPv6 路由 英文 输出 Nexttrace库（可指定端口）
    "
    stty erase '^H' 2>/dev/null; _read_input -p " 请输入数字 [1-4] (默认: 取消):" Specify_IP_num
    [[ -z ${Specify_IP_num} ]] && echo "已取消..." && exit 1 
	if [[ ${Specify_IP_num} == "1" ]]; then
		echo -e "${Info} 您选择的是：本机到指定 IPv4 路由 中文 输出 Nexttrace库（可指定端口），即将开始测试!
		"
        sleep 3s
        NT_Specify_IPv4_CN_Mtr
    elif [[ ${Specify_IP_num} == "2" ]]; then
		echo -e "${Info} 您选择的是：本机到指定 IPv4 路由 英文 输出 Nexttrace库（可指定端口），即将开始测试!
		"
        sleep 3s	
        NT_Specify_IPv4_EN_Mtr
    elif [[ ${Specify_IP_num} == "3" ]]; then
		echo -e "${Info} 您选择的是：本机到指定 IPv6 路由 中文 输出 Nexttrace库（可指定端口），即将开始测试!
		"
        sleep 3s	
        NT_Specify_IPv6_CN_Mtr
    elif [[ ${Specify_IP_num} == "4" ]]; then
		echo -e "${Info} 您选择的是：本机到指定 IPv6 路由 英文 输出 Nexttrace库（可指定端口），即将开始测试!
		"
        sleep 3s
        NT_Specify_IPv6_EN_Mtr
	else
		echo -e "${Error} 请输入正确的数字 [1-4]" && exit 1
	fi
}


#IPv4输入模块 IP检查
Int_IPV4(){
    _read_input -e -p "请输入目标 IPv4：" Int_IPV4_IP
    [[ -z "${Int_IPV4_IP}" ]] && echo -e "${Error} 未输入 IP，已退出" && exit 1 
    #检查IP
    Check_Int_IPV4
}

#IPv4输入模块 端口检查  //因为BestTrace不支持指定端口
Int_IPV4_P(){
    _read_input -e -p "请输入指定的端口（默认 80）：" Int_IPV4_Prot
    [[ -z "${Int_IPV4_Prot}" ]] && Int_IPV4_Prot="80"
    echo -e "${Info} 正在检测输入 端口 合法性"
    #判断端口是否为数字
    echo "${Int_IPV4_Prot}" |grep -Eq '[^0-9]' && echo -e "${Error} 请输入有效端口" && exit 1
    #判断端口是否在 1-65535 之间，-ge 1是指大于等于1，-le 65535是指小于等于65535，本段话是指输入端口如果大于等于1，小于等于65535时，则为真
#   if [ [ ${Int_IPV4_Prot} -ge 1 ] && [ ${Int_IPV4_Prot} -le 65535 ] ]; then
#       echo -e "${Info} 端口有效"
#   else
#       echo "${Error} 请输入 1-65535 之间的端口" && exit 1
#   fi
    #判断端口是否在 1-65535 之间，-lt 1是指小于1，-gt 65535是指大于65535，本段话是指输入端口如果小于1，大于65535时，则为真
    if [[ "${Int_IPV4_Prot}" -lt 1 || "${Int_IPV4_Prot}" -gt 65535 ]]; then
        echo -e "${Error} 输入的端口${Green_font_prefix}${Int_IPV4_Prot}${Font_color_suffix}有误，请输入 1-65535 之间的端口" && exit 1  
    fi
}

#IPv6输入模块
Int_IPV6(){
    _read_input -e -p "请输入目标 IPv6：" Int_IPV6_IP
     [[ -z "${Int_IPV6_IP}" ]] && echo -e "${Error} 未输入 IP，已退出" && exit 1 
    #检查IP
    Check_Int_IPV6
    _read_input -e -p "请输入指定的端口（默认 80）：" Int_IPV6_Prot
    [[ -z "${Int_IPV6_Prot}" ]] && Int_IPV6_Prot="80"
    #判断端口是否为数字
    echo -e "${Info} 正在检测输入 端口 合法性"
    echo "${Int_IPV6_Prot}" |grep -Eq '[^0-9]' && echo -e "${Error} 请输入有效端口" && exit 1
    #判断端口是否在 1-65535 之间，-lt 1是指小于1，-gt 65535是指大于65535，本段话是指输入端口如果小于1，大于65535时，则为真 
    if [[ "${Int_IPV6_Prot}" -lt 1 || "${Int_IPV6_Prot}" -gt 65535 ]]; then
        echo -e "${Error} 输入的端口${Green_font_prefix}${Int_IPV6_Prot}${Font_color_suffix}有误，请输入 1-65535 之间的端口" && exit 1  
    fi
}

#检测输入的IP是否为IPv4
Check_Int_IPV4(){
    echo -e "${Info} 正在检测输入 IP 连通性"
    #检测本机是否存在 IPv4
    if  [[ "${WAN_4}" == "" ]]; then
        echo -e "${Error} 本机没有 IPv4 地址，无法测试到指定 IPv4 路由" && exit 1
    fi
    #检测输入IP是否为IPV4，PING得通就输出true，后面判断不为空就表示是IPV4
    PING_IPV4_CHECK=$(ping -4 -c 4 -W 4 "${Int_IPV4_IP}" >/dev/null 2>&1 && echo true) 
    if [[ -z "${PING_IPV4_CHECK}" ]]; then
        echo -e
        echo -e "${Error} 输入的${Green_font_prefix}${Int_IPV4_IP}${Font_color_suffix}不是有效的 IPv4 地址，或无法 Ping 通，是否忽略错误继续？[y/N]" && echo
        stty erase '^H' 2>/dev/null; _read_input -p "(默认: y):" unyn
        if [[ ${unyn} == [Nn] ]]; then
            echo && echo -e "${Info} 已取消..." && exit 1
        fi
    fi     
}

#检测输入的IP是否为IPv6
Check_Int_IPV6(){
    echo -e "${Info} 正在检测输入 IP 连通性"
    #检测本机是否存在 IPv6
    if  [[ "${WAN_6}" == "" ]]; then
        echo -e "${Error} 本机没有 IPv6 地址，无法测试到指定 IPv6 路由" && exit 1
    fi
    #检测输入IP是否为IPV6，PING得通就输出true，后面判断不为空就表示是IPV6
    PING_IPV6_CHECK=$(ping -6 -c 4 -W 4 "${Int_IPV6_IP}" >/dev/null 2>&1 && echo true) 
    if [[ -z "${PING_IPV6_CHECK}" ]]; then
        echo -e
        echo -e "${Error} 输入的${Green_font_prefix}${Int_IPV6_IP}${Font_color_suffix}不是有效的 IPv6 地址，或无法 Ping 通，是否忽略错误继续？[y/N]" && echo
        stty erase '^H' 2>/dev/null; _read_input -p "(默认: y):" unyn
        if [[ ${unyn} == [Nn] ]]; then
            echo && echo -e "${Info} 已取消..." && exit 1
        fi
    fi     
}

#BestTrace IPv4 到指定IP路由测试 中文输出  (若需修改TCP/ICMP，可修改BestTrace_Mode代码段)
BT_Specify_IPv4_CN_Mtr(){
    #IP输入
    Int_IPV4    
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载BestTrace主程序
    BestTrace_Ver
    #载入BestTrace参数
    BestTrace_Mode
    clear
    #开始测试到指定IPv4路由
    if [ "${Net_Mode}" = "tcp" ] || [ "${Net_Mode}" = "TCP" ]; then
        echo -e "\nTraceroute to "${Int_IPV4_IP}" (TCP Mode, Max "${Hop_Mode}" Hop, IPv4)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${BestTrace_file} -g cn -q 1 -n -T -m "${Hop_Mode}" "${Int_IPV4_IP}" | tee -a $log
    elif [ "${Net_Mode}" = "icmp" ] || [ "${Net_Mode}" = "ICMP" ]; then
        echo -e "\nTracecroute to "${Int_IPV4_IP}" (ICMP Mode, Max "${Hop_Mode}" Hop, IPv4)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${BestTrace_file} -g cn -q 1 -n -m "${Hop_Mode}" "${Int_IPV4_IP}" | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi 
    #保留IPv4路由日志
    echo -e "${Info} 路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除BestTrace执行文件
    BestTrace_Dle  
}

#BestTrace IPv4 到指定IP路由测试 英文输出  (若需修改TCP/ICMP，可修改BestTrace_Mode代码段)
BT_Specify_IPv4_EN_Mtr(){
    #IP输入
    Int_IPV4
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载BestTrace主程序
    BestTrace_Ver
    #载入BestTrace参数
    BestTrace_Mode
    clear
    #开始测试到指定IPv4路由
    if [ "${Net_Mode}" = "tcp" ] || [ "${Net_Mode}" = "TCP" ]; then
        echo -e "\nTraceroute to "${Int_IPV4_IP}" (TCP Mode, Max "${Hop_Mode}" Hop, IPv4)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${BestTrace_file} -g en -q 1 -n -T -m "${Hop_Mode}" "${Int_IPV4_IP}" | tee -a $log
    elif [ "${Net_Mode}" = "icmp" ] || [ "${Net_Mode}" = "ICMP" ]; then
        echo -e "\nTracecroute to "${Int_IPV4_IP}" (ICMP Mode, Max "${Hop_Mode}" Hop, IPv4)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${BestTrace_file} -g en -q 1 -n -m "${Hop_Mode}" "${Int_IPV4_IP}" | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi 
    #保留IPv4路由日志
    echo -e "${Info} 路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除BestTrace执行文件
    BestTrace_Dle  
}

#Nexttrace IPv4 到指定IP路由测试 中文输出，可指定端口(若需修改TCP/ICMP，可修改Nexttrace_Mode代码段)
NT_Specify_IPv4_CN_Mtr(){   
    #IP输入 端口输入
    Int_IPV4
    Int_IPV4_P
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载Nexttrace主程序
    Nexttrace_Ver
    #载入Nexttrace参数
    Nexttrace_Mode
    #检测 POW 节点
    nexttrace_detect_pow
    clear
    #开始测试到指定IPv4路由  
    if [ "${Net_Mode}" = "tcp" ] || [ "${Net_Mode}" = "TCP" ]; then
        echo -e "\nTraceroute to "${Int_IPV4_IP}", Port:"${Int_IPV4_Prot}" (TCP Mode, Max "${Hop_Mode}" Hop, IPv4)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g cn -q 1 -n -T -p "${Int_IPV4_Prot}" -m "${Hop_Mode}" "${Int_IPV4_IP}" | tee -a $log
    elif [ "$2" = "icmp" ] || [ "$2" = "ICMP" ]; then
        echo -e "\nTracecroute to "${Int_IPV4_IP}", Port:"${Int_IPV4_Prot}" (ICMP Mode, Max "${Hop_Mode}" Hop, IPv4)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g cn -q 1 -n -p "${Int_IPV4_Prot}" -m "${Hop_Mode}" "${Int_IPV4_IP}" | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi  
    #保留IPv4路由日志
    echo -e "${Info} 路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除Nexttrace执行文件
    Nexttrace_Dle       
}

#Nexttrace IPv4 到指定IP路由测试 英文输出，可指定端口(若需修改TCP/ICMP，可修改Nexttrace_Mode代码段)
NT_Specify_IPv4_EN_Mtr(){   
    #IP输入 端口输入
    Int_IPV4
    Int_IPV4_P
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载Nexttrace主程序
    Nexttrace_Ver
    #载入Nexttrace参数
    Nexttrace_Mode
    #检测 POW 节点
    nexttrace_detect_pow
    clear
    #开始测试到指定IPv4路由  
    if [ "${Net_Mode}" = "tcp" ] || [ "${Net_Mode}" = "TCP" ]; then
        echo -e "\nTraceroute to "${Int_IPV4_IP}", Port:"${Int_IPV4_Prot}" (TCP Mode, Max "${Hop_Mode}" Hop, IPv4)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g en -q 1 -n -T -p "${Int_IPV4_Prot}" -m "${Hop_Mode}" "${Int_IPV4_IP}" | tee -a $log
    elif [ "$2" = "icmp" ] || [ "$2" = "ICMP" ]; then
        echo -e "\nTracecroute to "${Int_IPV4_IP}", Port:"${Int_IPV4_Prot}" (ICMP Mode, Max "${Hop_Mode}" Hop, IPv4)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g en -q 1 -n -p "${Int_IPV4_Prot}" -m "${Hop_Mode}" "${Int_IPV4_IP}" | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi  
    #保留IPv4路由日志
    echo -e "${Info} 路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除Nexttrace执行文件
    Nexttrace_Dle       
}

#Nexttrace IPv6 到指定IP路由测试 中文输出，可指定端口(若需修改TCP/ICMP，可修改Nexttrace_Mode代码段)
NT_Specify_IPv6_CN_Mtr(){   
    #IP输入 端口输入
    Int_IPV6
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载Nexttrace主程序
    Nexttrace_Ver
    #载入Nexttrace参数
    Nexttrace_Mode
    #检测 POW 节点
    nexttrace_detect_pow
    clear
    #开始测试到指定IPv4路由  
    if [ "${Net_Mode}" = "tcp" ] || [ "${Net_Mode}" = "TCP" ]; then
        echo -e "\nTraceroute to "${Int_IPV6_IP}", Port:"${Int_IPV6_Prot}" (TCP Mode, Max "${Hop_Mode}" Hop, IPv6)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g cn -q 1 -n -T -p "${Int_IPV6_Prot}" -m "${Hop_Mode}" "${Int_IPV6_IP}" | tee -a $log
    elif [ "$2" = "icmp" ] || [ "$2" = "ICMP" ]; then
        echo -e "\nTracecroute to "${Int_IPV6_IP}", Port:"${Int_IPV6_Prot}" (ICMP Mode, Max "${Hop_Mode}" Hop, IPv6)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g cn -q 1 -n -p "${Int_IPV6_Prot}" -m "${Hop_Mode}" "${Int_IPV6_IP}" | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi  
    #保留IPv6路由日志
    echo -e "${Info} 路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除Nexttrace执行文件
    Nexttrace_Dle       
}

#Nexttrace IPv6 到指定IP路由测试 英文输出，可指定端口(若需修改TCP/ICMP，可修改Nexttrace_Mode代码段)
NT_Specify_IPv6_EN_Mtr(){   
    #IP输入 端口输入
    Int_IPV6
    #删除之前的日志及执行文件 
    AutoTrace_Start
    #下载Nexttrace主程序
    Nexttrace_Ver
    #载入Nexttrace参数
    Nexttrace_Mode
    #检测 POW 节点
    nexttrace_detect_pow
    clear
    #开始测试到指定IPv4路由  
    if [ "${Net_Mode}" = "tcp" ] || [ "${Net_Mode}" = "TCP" ]; then
        echo -e "\nTraceroute to "${Int_IPV6_IP}", Port:"${Int_IPV6_Prot}" (TCP Mode, Max "${Hop_Mode}" Hop, IPv6)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g en -q 1 -n -T -p "${Int_IPV6_Prot}" -m "${Hop_Mode}" "${Int_IPV6_IP}" | tee -a $log
    elif [ "$2" = "icmp" ] || [ "$2" = "ICMP" ]; then
        echo -e "\nTracecroute to "${Int_IPV6_IP}", Port:"${Int_IPV6_Prot}" (ICMP Mode, Max "${Hop_Mode}" Hop, IPv6)" | tee -a $log
        echo -e "============================================================" | tee -a $log
        ${Nexttrace_file} ${NT_POW_ARGS} -M -g en -q 1 -n -p "${Int_IPV6_Prot}" -m "${Hop_Mode}" "${Int_IPV6_IP}" | tee -a $log
    else
        echo -e "${Error} 参数错误，请输入 TCP 或 ICMP" && exit 1
    fi  
    #保留IPv6路由日志
    echo -e "${Info} 路由路径已保存在${Green_font_prefix} ${log} ${Font_color_suffix}中，如不需要请自行删除 !" 	
    #删除Nexttrace执行文件
    Nexttrace_Dle       
}

###到指定IP路由测试部分    结束========================================================

#启动菜单区===============================================
#脚本不加参数时的启动菜单
Stand_AutoTrace(){
echo -e " -- AutoTrace 三网回程测试脚本 ${Green_font_prefix}[v${sh_ver}]${Font_color_suffix}  当天运行：$TODAY 次 / 累计运行：$TOTAL 次 --

服务器信息（优先显示IPv4，仅供参考）：
—————————————————————————————————————————————————————————————————————
 ISP      : $ISP_Print
 ASN      : $ASN_Print
 服务商   : $Host_Print
 国家     : $COUNTRY_Print
 地址     : $Location_Print
 IPv4地址 : $IPv4_Print
 IPv6地址 : $IPv6_Print
 IP 性质  : $TYPE_Print
 IP 危险性: $FRAUD_SCORE/100（建议小于60分，分数越高说明 IP 可能存在滥用欺诈行为）

 测试项（TCP Mode，三网回程测试点均为 9 个，包含广东、上海、北京）：
—————————————————————————————————————————————————————————————————————
 ${Yellow_font_prefix}1. 本机 IPv4 三网回程路由 中文 输出 Nexttrace 库（默认）${Font_color_suffix} 
 2. 本机 IPv4 三网回程路由 英文 输出 Nexttrace 库
 ${Yellow_font_prefix}3. 本机 IPv6 三网回程路由 中文 输出 Nexttrace 库${Font_color_suffix} 
 4. 本机 IPv6 三网回程路由 英文 输出 Nexttrace 库
 ${Yellow_font_prefix}5. 本机到指定 IPv4/IPv6 路由 Nexttrace库${Font_color_suffix} 
 6. 退出测试

    " 
    _read_input -e -p " 请输入需要的测试项 [1-6] ( 默认：1 ）：" Stand_AutoTrace_num
    [[ -z "${Stand_AutoTrace_num}" ]] && Stand_AutoTrace_num="1"
    if [[ ${Stand_AutoTrace_num} == "1" ]]; then        
        echo -e "${Info} 您选择的是：本机 IPv4 三网回程路由 中文 输出 Nexttrace库，即将开始测试!  Ctrl+C 取消！
        "
        sleep 4s
        NT_IPv4_IP_CN_Mtr 
    elif [[ ${Stand_AutoTrace_num} == "2" ]]; then 
        echo -e "${Info} 您选择的是：本机 IPv4 三网回程路由 英文 输出 Nexttrace库，即将开始测试!  Ctrl+C 取消！
        "
        sleep 4s
        NT_IPv4_IP_EN_Mtr        
    elif [[ ${Stand_AutoTrace_num} == "3" ]]; then 
        echo -e "${Info} 您选择的是：本机 IPv6 三网回程路由 中文 输出 Nexttrace库，即将开始测试!  Ctrl+C 取消！
        "
        sleep 4s
        NT_IPv6_IP_CN_Mtr
    elif [[ ${Stand_AutoTrace_num} == "4" ]]; then 
        echo -e "${Info} 您选择的是：本机 IPv6 三网回程路由 英文 输出 Nexttrace库，即将开始测试!  Ctrl+C 取消！
        "
        sleep 4s
        NT_IPv6_IP_EN_Mtr 
    elif [[ ${Stand_AutoTrace_num} == "5" ]]; then 
        echo -e "${Info} 您选择的是：本机到指定 IPv4/IPv6 路由 Nexttrace库，即将开始测试!  Ctrl+C 取消！
        "
        sleep 3s
        Specify_IP
    elif [[ ${Stand_AutoTrace_num} == "6" ]]; then 
        echo -e "${Info} 已取消测试 ！" && exit 1
    else
		echo -e "${Error} 请输入正确的数字 [1-6]" && exit 1
	fi
}

#通过脚本参数启动的传递区域
Specify_IP_AutoTrace(){
    Specify_IP
}
#启动菜单区===============================================



#脚本运行区
clear
echo -e "${Info} 脚本正在初始化，请稍等 ！"
check_sys
checkver
IP_Check
check_root
statistics_of_run-times
clear 
[[ ${release} != "debian" ]] && [[ ${release} != "ubuntu" ]] && [[ ${release} != "centos" ]] && echo -e "${Error} 本脚本不支持当前系统 ${release} !" && exit 1


#脚本启动入口，通过判断是否传入参数，来判断启动类型,这个代码块放到所有代码之下
Action=$1
[[ -z $1 ]] && Action=Stand
case "$Action" in
	Stand|Specify_IP)
	${Action}_AutoTrace
	;;
	*)
	echo "输入错误 !"
	echo "用法: AutoTrace.sh { Stand | Specify_IP }"
	;;
esac
