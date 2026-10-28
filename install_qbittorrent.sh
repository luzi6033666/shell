#!/usr/bin/env bash
#
# qBittorrent 一键管理脚本（经典版 4.6.7 + libtorrent 2.0.10，静态编译）
#
#   默认 WebUI 端口 8080、中文界面、上传限速 50 MiB/s、下载不限速、
#   随机 16 位复杂密码、自动禁用 IPv6、数据盘预留空间改为 1%。
#   重复执行 install 不会重装、不会换密码（幂等），需重装用 install --force。
#
# 用法: bash install_qbittorrent.sh <命令> [选项]
#
#   install [--force] [--up=N] [--down=N]  安装（已装则跳过；N 单位 MiB/s，0=不限）
#   uninstall [--purge]      卸载服务与程序（--purge 连配置/凭据/下载目录一起删）
#   start | stop | restart   启动 / 停止 / 重启服务
#   status                   服务状态、版本、端口、资源占用
#   info                     登录地址、用户名、密码、限速、语言
#   password                 重新生成随机 16 位复杂密码
#   limit --up=N [--down=N]  调整全局限速（MiB/s，down 填 0 = 不限速）
#   port <端口号>            修改 WebUI 端口
#   reserve [百分比]         调整数据盘预留空间（默认 1%，ext 系列默认 5%）
#   log                      查看最近日志
#
set -euo pipefail

QB_VERSION="4.6.7"
LT_VERSION="2.0.10"
RELEASE_TAG="release-${QB_VERSION}_v${LT_VERSION}"
DL_URL="https://github.com/userdocs/qbittorrent-nox-static/releases/download/${RELEASE_TAG}/x86_64-qbittorrent-nox"

DEFAULT_PORT=8080
DEFAULT_USER="admin"
DEFAULT_UP_MIB=50
DEFAULT_DOWN_MIB=0
DEFAULT_RESERVE_PCT=1     # 数据盘预留空间百分比（ext 默认 5%，改 1% 可省出约 40G/TB）

BIN="/usr/local/bin/qbittorrent-nox"
CONF_DIR="/root/.config/qBittorrent"
CONF_FILE="${CONF_DIR}/qBittorrent.conf"
DOWNLOAD_DIR="/root/Downloads"
SERVICE="/etc/systemd/system/qbittorrent.service"
CRED_FILE="/root/qbittorrent_credentials.txt"
SYSCTL_IPV6="/etc/sysctl.d/99-disable-ipv6.conf"

COOKIE_JAR=""
trap 'rm -f "${COOKIE_JAR}" 2>/dev/null || true' EXIT

log() { printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[*]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[!]\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; }

# ============================================================ 基础工具
need_root() { [ "$(id -u)" -eq 0 ] || die "请用 root 运行"; }
need_systemd() { command -v systemctl >/dev/null 2>&1 || die "本机没有 systemd，脚本不适用"; }

# 注意: 不能用 `list-unit-files | grep -q`（grep -q 提前退出会让 systemctl 收到 SIGPIPE，
# 在 set -o pipefail 下整条管道判为失败）
unit_exists() { [ -f "${SERVICE}" ] || systemctl cat qbittorrent.service >/dev/null 2>&1; }
is_active()   { systemctl is-active --quiet qbittorrent 2>/dev/null; }
is_installed(){ [ -x "${BIN}" ] && unit_exists; }

load_creds() {
    [ -f "${CRED_FILE}" ] || die "找不到凭据文件 ${CRED_FILE}，请先执行: $0 install"
    QBT_VERSION="$(grep -m1 '^QBT_VERSION=' "${CRED_FILE}" | cut -d= -f2-)"
    QBT_PORT="$(grep -m1 '^QBT_PORT=' "${CRED_FILE}" | cut -d= -f2-)"
    QBT_USER="$(grep -m1 '^QBT_USER=' "${CRED_FILE}" | cut -d= -f2-)"
    QBT_PASS="$(grep -m1 '^QBT_PASSWORD=' "${CRED_FILE}" | cut -d= -f2-)"
    QBT_UP_MIB="$(grep -m1 '^QBT_UP_LIMIT_MIB=' "${CRED_FILE}" | cut -d= -f2-)"
    QBT_DOWN_MIB="$(grep -m1 '^QBT_DOWN_LIMIT_MIB=' "${CRED_FILE}" | cut -d= -f2-)"
    : "${QBT_PORT:=${DEFAULT_PORT}}"; : "${QBT_USER:=${DEFAULT_USER}}"
}

save_creds() { # save_creds <up_mib> <down_mib>
    cat >"${CRED_FILE}" <<EOF
# qBittorrent 凭据（自动生成，勿手动改；运行 $0 info 查看）
QBT_VERSION=${QB_VERSION}
QBT_LT_VERSION=${LT_VERSION}
QBT_PORT=${QBT_PORT}
QBT_USER=${QBT_USER}
QBT_PASSWORD=${QBT_PASS}
QBT_UP_LIMIT_MIB=$1
QBT_DOWN_LIMIT_MIB=$2
QBT_DOWNLOAD_DIR=${DOWNLOAD_DIR}
QBT_CONF=${CONF_FILE}
QBT_UPDATED=$(date '+%Y-%m-%d %H:%M:%S %Z')
EOF
    chmod 0600 "${CRED_FILE}"
}

# 生成随机 16 位复杂密码 + qBittorrent 密码哈希（salt:key）
gen_credential() {
    python3 - <<'PY'
import base64, hashlib, secrets, string

symbols = "@#%*+-_="
charset = string.ascii_letters + string.digits + symbols
while True:
    pw = ''.join(secrets.choice(charset) for _ in range(16))
    if (any(c.islower() for c in pw) and any(c.isupper() for c in pw)
            and any(c.isdigit() for c in pw) and any(c in symbols for c in pw)):
        break

salt = secrets.token_bytes(32)
# qBittorrent 存储格式: base64(salt):base64(key)，PBKDF2-HMAC-SHA512 / 100000 轮 / 64 字节
key = hashlib.pbkdf2_hmac('sha512', pw.encode(), salt, 100000, 64)
print(pw)
print('@ByteArray(' + base64.b64encode(salt).decode() + ':' + base64.b64encode(key).decode() + ')')
PY
}

write_conf() { # write_conf <user> <hash> <port>
    mkdir -p "${CONF_DIR}" "${DOWNLOAD_DIR}"
    cat >"${CONF_FILE}" <<EOF
[Preferences]
WebUI\\Username=$1
WebUI\\Password_PBKDF2="$2"
WebUI\\Port=$3
WebUI\\Address=*
WebUI\\ServerDomains=*
WebUI\\HostHeaderValidation=false
WebUI\\CSRFProtection=true
WebUI\\ClickjackingProtection=false
WebUI\\LocalHostAuth=true
WebUI\\AuthSubnetWhitelistEnabled=false
WebUI\\SessionTimeout=3600
WebUI\\UseUPnP=false
General\\Locale=zh_CN
LegalNotice\\Accepted=true
EOF
    chmod 0600 "${CONF_FILE}"
}

set_conf_key() { # set_conf_key <key(含反斜杠)> <value>
    local key="$1" value="$2"
    python3 - "${CONF_FILE}" "${key}" "${value}" <<'PY'
import sys
path, key, value = sys.argv[1:4]
line = f'{key}={value}'
lines = open(path, encoding='utf-8').read().splitlines()
out, found, in_pref = [], False, False
for l in lines:
    if l.startswith(key + '='):
        out.append(line); found = True
    else:
        out.append(l)
if not found:
    for i, l in enumerate(out):
        if l.strip() == '[Preferences]':
            out.insert(i + 1, line); found = True; break
    if not found:
        out += ['[Preferences]', line]
open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PY
}

write_service() {
    cat >"${SERVICE}" <<EOF
[Unit]
Description=qBittorrent-nox ${QB_VERSION} (libtorrent ${LT_VERSION})
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment=HOME=/root
ExecStart=${BIN} --webui-port=${QBT_PORT}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

disable_ipv6() {
    log "禁用 IPv6 (sysctl, 永久生效) ..."
    cat >"${SYSCTL_IPV6}" <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl -q -p "${SYSCTL_IPV6}" 2>/dev/null || \
        sysctl -q -w net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1 net.ipv6.conf.lo.disable_ipv6=1
    for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do echo 1 >"${f}" 2>/dev/null || true; done
}

enable_ipv6() {
    log "恢复 IPv6 ..."
    rm -f "${SYSCTL_IPV6}"
    sysctl -q -w net.ipv6.conf.all.disable_ipv6=0 net.ipv6.conf.default.disable_ipv6=0 net.ipv6.conf.lo.disable_ipv6=0 2>/dev/null || true
    for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do echo 0 >"${f}" 2>/dev/null || true; done
}

# 预留空间百分比（tune2fs -l 只给块数，百分比自己算）
reserved_pct() { # reserved_pct <设备>
    # 注意两行的字段数不同（"Block count:" 2 个词 / "Reserved block count:" 3 个词），统一取 $NF
    tune2fs -l "$1" 2>/dev/null | awk '
        /^Block count:/          {b=$NF}
        /^Reserved block count:/ {r=$NF}
        END { if (b > 0) printf "%.0f%%\n", (r * 100 / b) }'
}

# 数据盘预留空间（ext 系列默认 5%，1TB 盘即约 50G，改成 1% 可省出约 40G）
tune_reserved() { # tune_reserved <百分比>
    local pct="$1" src fstype cur
    command -v tune2fs >/dev/null 2>&1 || { warn "系统没有 tune2fs，跳过预留空间调整"; return 0; }
    src="$(findmnt -no SOURCE --target "${DOWNLOAD_DIR}" 2>/dev/null || true)"
    [ -n "${src}" ] || { warn "无法定位 ${DOWNLOAD_DIR} 所在设备，跳过预留空间调整"; return 0; }
    fstype="$(findmnt -no FSTYPE --target "${DOWNLOAD_DIR}" 2>/dev/null || true)"
    case "${fstype}" in
        ext2|ext3|ext4) ;;
        *) warn "${DOWNLOAD_DIR} 所在文件系统为 ${fstype:-未知}，不支持预留空间调整，跳过"; return 0 ;;
    esac
    cur="$(reserved_pct "${src}")"
    if [ "${cur}" = "${pct}%" ]; then
        log "预留空间已是 ${pct}%（${src}），无需调整"
        return 0
    fi
    log "调整 ${src} (${fstype}) 预留空间: ${cur:-未知} -> ${pct}% ..."
    tune2fs -m "${pct}" "${src}" >/dev/null
    log "完成，可用空间: $(df -h --output=avail "${DOWNLOAD_DIR}" | tail -1 | tr -s ' ')"
}

wait_webui() {
    local i
    for i in $(seq 1 60); do
        curl -sf -o /dev/null "http://127.0.0.1:${QBT_PORT}/" && return 0
        sleep 1
    done
    return 1
}

# ============================================================ Web API
api_login() {
    [ -n "${COOKIE_JAR}" ] && rm -f "${COOKIE_JAR}"
    COOKIE_JAR="$(mktemp)"
    local res
    res="$(curl -sf -c "${COOKIE_JAR}" \
            -H "Referer: http://127.0.0.1:${QBT_PORT}/" \
            --data-urlencode "username=${QBT_USER}" \
            --data-urlencode "password=${QBT_PASS}" \
            "http://127.0.0.1:${QBT_PORT}/api/v2/auth/login" || true)"
    [ "${res}" = "Ok." ] || return 1
    grep -q 'SID' "${COOKIE_JAR}" || return 1
}

api() { # api <path> [curl 额外参数...]
    local path="$1"; shift
    curl -sS -b "${COOKIE_JAR}" -H "Referer: http://127.0.0.1:${QBT_PORT}/" \
        "$@" "http://127.0.0.1:${QBT_PORT}${path}"
}

api_set_prefs() { api /api/v2/app/setPreferences -X POST --data-urlencode "json=$1" >/dev/null; }

api_pref() { # api_pref <key>
    api /api/v2/app/preferences | python3 -c "import sys,json;print(json.load(sys.stdin).get('$1',''))"
}

# 写入运行时偏好（限速 / 语言 / 保存路径）
apply_runtime_prefs() { # apply_runtime_prefs <up_bytes> <down_bytes>
    api_set_prefs "{\"up_limit\":$1,\"dl_limit\":$2,\"save_path\":\"${DOWNLOAD_DIR}\",\"temp_path_enabled\":false,\"locale\":\"zh_CN\"}"
}

# ============================================================ 显示
print_info() {
    local ip up dl loc ver
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)"
    : "${ip:=127.0.0.1}"
    up="-"; dl="-"; loc="-"; ver="-"
    if is_active && api_login 2>/dev/null; then
        up="$(api_pref up_limit)"; dl="$(api_pref dl_limit)"; loc="$(api_pref locale)"
        ver="$(api /api/v2/app/version)"
    fi
    printf '\n'
    printf '%s\n' '============================================================'
    printf ' qBittorrent %s (libtorrent %s)\n' "${QBT_VERSION:-${QB_VERSION}}" "${LT_VERSION}"
    printf '%s\n' '============================================================'
    printf '  登录地址 : http://%s:%s\n' "${ip}" "${QBT_PORT}"
    printf '  用户名   : %s\n' "${QBT_USER}"
    printf '  密码     : %s\n' "${QBT_PASS}"
    printf '%s\n' '------------------------------------------------------------'
    printf '  上传限速 : %s MiB/s (%s B/s)\n' "${QBT_UP_MIB}" "${up}"
    printf '  下载限速 : %s\n' "$( [ "${QBT_DOWN_MIB}" = "0" ] && echo "不限速 (${dl})" || echo "${QBT_DOWN_MIB} MiB/s (${dl})" )"
    printf '  界面语言 : %s\n' "${loc}"
    printf '  程序版本 : %s\n' "${ver}"
    printf '  下载目录 : %s\n' "${DOWNLOAD_DIR}"
    printf '  配置文件 : %s\n' "${CONF_FILE}"
    printf '  凭据文件 : %s\n' "${CRED_FILE}"
    printf '%s\n' '============================================================'
    printf '\n'
}

# ============================================================ 命令
cmd_install() {
    need_root; need_systemd
    local force=0 up="${DEFAULT_UP_MIB}" down="${DEFAULT_DOWN_MIB}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1 ;;
            --up=*) up="${1#*=}" ;;
            --down=*) down="${1#*=}" ;;
            *) die "未知参数: $1（用法见 $0 help）" ;;
        esac
        shift
    done

    if is_installed && [ "${force}" -eq 0 ]; then
        warn "qBittorrent 已安装（$(api_version 2>/dev/null || echo "${QB_VERSION}")），跳过安装以避免重复改动。"
        is_active || { log "服务未在运行，启动之 ..."; systemctl start qbittorrent; wait_webui || true; }
        load_creds
        print_info
        printf '如需重装（会重新生成密码）: %s install --force\n' "$0"
        printf '如需只改密码: %s password\n\n' "$0"
        return 0
    fi

    export DEBIAN_FRONTEND=noninteractive
    log "安装依赖 (curl / python3) ..."
    apt-get update -qq
    apt-get install -y -qq curl python3 ca-certificates

    if is_active; then
        log "停止已运行的 qbittorrent 服务 ..."
        systemctl stop qbittorrent
    fi

    log "生成随机 16 位复杂密码 ..."
    { read -r QBT_PASS; read -r QBT_HASH; } < <(gen_credential)
    QBT_USER="${DEFAULT_USER}"

    log "下载 qBittorrent ${QB_VERSION} (libtorrent ${LT_VERSION}) 静态二进制 ..."
    curl -fL --retry 3 --retry-delay 2 -o "${BIN}" "${DL_URL}"
    chmod 0755 "${BIN}"

    disable_ipv6

        tune_reserved "${DEFAULT_RESERVE_PCT}"

    log "写入配置文件 ${CONF_FILE} ..."
    write_conf "${QBT_USER}" "${QBT_HASH}" "${DEFAULT_PORT}"

    QBT_PORT="${DEFAULT_PORT}"
    log "创建 systemd 服务 (端口 ${QBT_PORT}) ..."
    write_service
    systemctl enable --now qbittorrent

    log "等待 WebUI 就绪 ..."
    wait_webui || die "WebUI 未能在 60 秒内启动，检查: journalctl -u qbittorrent -n 50"

    log "登录 WebUI 并写入限速 / 语言设置 ..."
    api_login || die "WebUI 登录失败，密码哈希可能不匹配"
    apply_runtime_prefs $((up * 1024 * 1024)) $((down * 1024 * 1024))

    local real_up real_dl
    real_up="$(api_pref up_limit)"; real_dl="$(api_pref dl_limit)"
    [ "${real_up}" = "$((up * 1024 * 1024))" ] || die "上传限速写入失败（实际: ${real_up}）"
    { [ "${real_dl}" = "$((down * 1024 * 1024))" ] || [ "${real_dl}" = "0" ]; } || die "下载限速写入失败（实际: ${real_dl}）"

    log "重启服务让配置落盘 ..."
    systemctl restart qbittorrent
    wait_webui || die "重启后 WebUI 未就绪"

    QBT_VERSION="${QB_VERSION}"
    QBT_UP_MIB="${up}"; QBT_DOWN_MIB="${down}"
    save_creds "${up}" "${down}"

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
        log "放行 ufw ${QBT_PORT}/tcp ..."
        ufw allow "${QBT_PORT}/tcp" >/dev/null
    fi

    print_info
}

cmd_uninstall() {
    need_root; need_systemd
    local purge=0
    while [ $# -gt 0 ]; do
        case "$1" in --purge) purge=1 ;; *) die "未知参数: $1" ;; esac
        shift
    done
    is_installed || { warn "qBittorrent 未安装，无需卸载"; return 0; }

    if is_active; then
        log "停止服务 ..."
        systemctl stop qbittorrent
    fi
    log "禁用并删除 systemd 服务 ..."
    systemctl disable --now qbittorrent 2>/dev/null || true
    rm -f "${SERVICE}"
    systemctl daemon-reload

    log "删除主程序 ${BIN} ..."
    rm -f "${BIN}"

    log "删除配置与凭据 ..."
    rm -rf "${CONF_DIR}" "${CRED_FILE}"

    enable_ipv6

    if [ "${purge}" -eq 1 ]; then
        log "清空下载目录 ${DOWNLOAD_DIR} ..."
        rm -rf "${DOWNLOAD_DIR}"
    else
        warn "已保留下载目录 ${DOWNLOAD_DIR}（要一起删用: $0 uninstall --purge）"
    fi
    log "卸载完成"
}

cmd_start()   { need_root; systemctl start qbittorrent;   log "服务已启动: $(systemctl is-active qbittorrent)"; }
cmd_stop()    { need_root; systemctl stop qbittorrent;    log "服务已停止"; }
cmd_restart() { need_root; systemctl restart qbittorrent; log "服务已重启: $(systemctl is-active qbittorrent)"; }

cmd_status() {
    need_root
    if ! is_installed; then warn "qBittorrent 未安装"; return 1; fi
    load_creds
    printf '服务      : %s (开机自启: %s)\n' "$(systemctl is-active qbittorrent)" "$(systemctl is-enabled qbittorrent 2>/dev/null || echo unknown)"
    printf 'PID       : %s\n' "$(systemctl show -p MainPID --value qbittorrent)"
    printf 'WebUI     : http://%s:%s\n' "$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)" "${QBT_PORT}"
    printf '配置版本  : %s (libtorrent %s)\n' "${QBT_VERSION}" "${LT_VERSION}"
    printf 'BT 监听   : %s\n' "$(ss -lntp 2>/dev/null | awk '/qbittorrent-nox/ && !/:8080/ {print $4}' | tr '\n' ' ')"
    printf '内存/CPU  : %s\n' "$(systemctl show -p MemoryCurrent -p CPUUsageNSec --value qbittorrent | tr '\n' ' ')"
    printf 'IPv6      : 已禁用 (disable_ipv6=%s)\n' "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo '?')"
    printf '下载目录  : %s (已用 %s)\n' "${DOWNLOAD_DIR}" "$(du -sh "${DOWNLOAD_DIR}" 2>/dev/null | cut -f1)"
    printf '数据盘预留: %s (设备 %s)\n' \
        "$(reserved_pct "$(findmnt -no SOURCE --target "${DOWNLOAD_DIR}" 2>/dev/null)" 2>/dev/null || echo '?')" \
        "$(findmnt -no SOURCE --target "${DOWNLOAD_DIR}" 2>/dev/null || echo '?')"
    printf '运行时长  : %s\n' "$(systemctl show -p ActiveEnterTimestamp --value qbittorrent)"
}

cmd_info() { need_root; is_installed || die "qBittorrent 未安装"; load_creds; print_info; }

cmd_password() {
    need_root; is_installed || die "qBittorrent 未安装"
    load_creds
    local newpass newhash
    { read -r newpass; read -r newhash; } < <(gen_credential)
    log "生成新的随机 16 位密码 ..."
    log "停止服务并写入新密码 ..."
    systemctl stop qbittorrent
    set_conf_key 'WebUI\Password_PBKDF2' "\"${newhash}\""
    systemctl start qbittorrent
    wait_webui || die "服务重启后 WebUI 未就绪"
    QBT_PASS="${newpass}"
    api_login || die "新密码登录失败"
    save_creds "${QBT_UP_MIB}" "${QBT_DOWN_MIB}"
    log "密码已更新"
    print_info
}

cmd_limit() {
    need_root; is_installed || die "qBittorrent 未安装"
    load_creds
    local up="${QBT_UP_MIB}" down="${QBT_DOWN_MIB}"
    while [ $# -gt 0 ]; do
        case "$1" in --up=*) up="${1#*=}" ;; --down=*) down="${1#*=}" ;; *) die "未知参数: $1" ;; esac
        shift
    done
    [[ "${up}" =~ ^[0-9]+$ ]] || die "--up 必须是非负整数（MiB/s）"
    [[ "${down}" =~ ^[0-9]+$ ]] || die "--down 必须是非负整数（MiB/s，0 = 不限速）"

    is_active || die "服务未在运行，先执行: $0 start"
    api_login || die "WebUI 登录失败"
    apply_runtime_prefs $((up * 1024 * 1024)) $((down * 1024 * 1024))
    local real_up real_dl
    real_up="$(api_pref up_limit)"; real_dl="$(api_pref dl_limit)"
    [ "${real_up}" = "$((up * 1024 * 1024))" ] || die "上传限速写入失败（实际: ${real_up}）"
    QBT_UP_MIB="${up}"; QBT_DOWN_MIB="${down}"
    save_creds "${up}" "${down}"
    log "限速已更新: 上传 ${up} MiB/s，下载 $( [ "${down}" = "0" ] && echo 不限速 || echo "${down} MiB/s" )"
    print_info
}

cmd_port() {
    need_root; is_installed || die "qBittorrent 未安装"
    load_creds
    local newport="${1:-}"
    [[ "${newport}" =~ ^[0-9]+$ ]] || die "用法: $0 port <端口号>"
    [ "${newport}" = "${QBT_PORT}" ] && { warn "端口已经是 ${newport}，无需修改"; return 0; }
    log "修改 WebUI 端口: ${QBT_PORT} -> ${newport} ..."
    systemctl stop qbittorrent
    set_conf_key 'WebUI\Port' "${newport}"
    QBT_PORT="${newport}"
    write_service
    systemctl start qbittorrent
    wait_webui || die "服务重启后 WebUI 未就绪"
    api_login || die "WebUI 登录失败"
    save_creds "${QBT_UP_MIB}" "${QBT_DOWN_MIB}"
    log "端口已更新"
    print_info
}

cmd_log() { need_root; journalctl -u qbittorrent -n "${1:-100}" --no-pager; }

cmd_reserve() { # cmd_reserve [百分比]
    need_root
    local pct="${1:-${DEFAULT_RESERVE_PCT}}"
    [[ "${pct}" =~ ^[0-9]+$ ]] || die "用法: $0 reserve [百分比]（默认 ${DEFAULT_RESERVE_PCT}）"
    tune_reserved "${pct}"
}

api_version() {
    is_active || return 1
    load_creds || return 1
    api_login || return 1
    api /api/v2/app/version
}

# ============================================================ 入口
main() {
    local cmd="${1:-install}"; [ $# -gt 0 ] && shift || true
    case "${cmd}" in
        install)   cmd_install "$@" ;;
        uninstall) cmd_uninstall "$@" ;;
        start)     cmd_start ;;
        stop)      cmd_stop ;;
        restart)   cmd_restart ;;
        status)    cmd_status ;;
        info)      cmd_info ;;
        password)  cmd_password ;;
        limit)     cmd_limit "$@" ;;
        port)      cmd_port "$@" ;;
        reserve)   cmd_reserve "$@" ;;
        log)       cmd_log "$@" ;;
        help|-h|--help) usage ;;
        *)         usage; die "未知命令: ${cmd}" ;;
    esac
}

main "$@"
