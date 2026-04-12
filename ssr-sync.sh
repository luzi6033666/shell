#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Interactive SSR sync script
# Scope: ShadowsocksR only
# Sync payload: executable files + config files
#   - /usr/local/shadowsocks
#   - /etc/init.d/shadowsocks-r
#   - /etc/shadowsocks-r/config.json

USE_SSHPASS=0
SSH_COMMON_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

log() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARN] $*" >&2
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_root() {
    [ "${EUID}" -eq 0 ] || die "请使用 root 运行。"
}

need_cmd() {
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "Command not found: $c"
    done
}

read_required() {
    local prompt="$1"
    local var
    while true; do
        read -r -p "$prompt" var
        if [ -n "$var" ]; then
            echo "$var"
            return
        fi
        echo "不能为空，请重新输入。"
    done
}

read_with_default() {
    local prompt="$1"
    local def="$2"
    local var
    read -r -p "$prompt (默认: $def): " var
    if [ -z "$var" ]; then
        echo "$def"
    else
        echo "$var"
    fi
}

read_password() {
    local prompt="$1"
    local var
    while true; do
        read -r -s -p "$prompt" var
        echo
        if [ -n "$var" ]; then
            echo "$var"
            return
        fi
        echo "密码不能为空，请重新输入。"
    done
}

init_auth_mode() {
    if command -v sshpass >/dev/null 2>&1; then
        USE_SSHPASS=1
        log "检测到 sshpass，使用免交互密码模式。"
    else
        USE_SSHPASS=0
        warn "未检测到 sshpass，切换为 ssh/scp 交互认证模式（会手动输入密码，或使用已配置密钥）。"
    fi
}

src_ssh() {
    if [ "$USE_SSHPASS" -eq 1 ]; then
        sshpass -p "$SRC_PASS" ssh "${SSH_COMMON_OPTS[@]}" -p "$SRC_PORT" "root@${SRC_IP}" "$@"
    else
        ssh "${SSH_COMMON_OPTS[@]}" -p "$SRC_PORT" "root@${SRC_IP}" "$@"
    fi
}

dst_ssh() {
    if [ "$USE_SSHPASS" -eq 1 ]; then
        sshpass -p "$DST_PASS" ssh "${SSH_COMMON_OPTS[@]}" -p "$DST_PORT" "root@${DST_IP}" "$@"
    else
        ssh "${SSH_COMMON_OPTS[@]}" -p "$DST_PORT" "root@${DST_IP}" "$@"
    fi
}

src_scp_from() {
    local remote_path="$1"
    local local_path="$2"
    if [ "$USE_SSHPASS" -eq 1 ]; then
        sshpass -p "$SRC_PASS" scp "${SSH_COMMON_OPTS[@]}" -P "$SRC_PORT" "root@${SRC_IP}:${remote_path}" "$local_path"
    else
        scp "${SSH_COMMON_OPTS[@]}" -P "$SRC_PORT" "root@${SRC_IP}:${remote_path}" "$local_path"
    fi
}

dst_scp_to() {
    local local_path="$1"
    local remote_path="$2"
    if [ "$USE_SSHPASS" -eq 1 ]; then
        sshpass -p "$DST_PASS" scp "${SSH_COMMON_OPTS[@]}" -P "$DST_PORT" "$local_path" "root@${DST_IP}:${remote_path}"
    else
        scp "${SSH_COMMON_OPTS[@]}" -P "$DST_PORT" "$local_path" "root@${DST_IP}:${remote_path}"
    fi
}

print_banner() {
    cat <<'BANNER'
========================================
 SSR 交互式同步脚本（仅 SSR 场景）
========================================
会同步以下内容：
1) /usr/local/shadowsocks
2) /etc/init.d/shadowsocks-r
3) /etc/shadowsocks-r/config.json

注意：
- 源机和目标机需同架构（例如都为 x86_64）
- 建议 Debian/Ubuntu 主版本一致
- 目标机需已安装 python3（SSR 运行需要）
BANNER
}

collect_input() {
    SRC_IP=$(read_required "源机器 IP: ")
    SRC_PORT=$(read_with_default "源机器 SSH 端口" "22")
    if [ "$USE_SSHPASS" -eq 1 ]; then
        SRC_PASS=$(read_password "源机器 root 密码: ")
    fi

    echo
    DST_IP=$(read_required "目标机器 IP: ")
    DST_PORT=$(read_with_default "目标机器 SSH 端口" "22")
    if [ "$USE_SSHPASS" -eq 1 ]; then
        DST_PASS=$(read_password "目标机器 root 密码: ")
    else
        echo "将通过 ssh/scp 在连接时交互输入密码。"
    fi

    echo
    echo "------ 确认信息 ------"
    echo "源机器: root@${SRC_IP}:${SRC_PORT}"
    echo "目标机器: root@${DST_IP}:${DST_PORT}"
    echo "----------------------"
    read -r -p "确认开始同步? [Y/n]: " CONFIRM
    CONFIRM=${CONFIRM:-Y}
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || die "已取消。"
}

build_source_package() {
    log "在源机器打包 SSR 可执行文件与配置..."
    local output
    output=$(src_ssh 'bash -s' <<'EOS'
set -e
for p in /usr/local/shadowsocks /etc/init.d/shadowsocks-r /etc/shadowsocks-r/config.json; do
    [ -e "$p" ] || { echo "[ERROR] 源机器缺少: $p" >&2; exit 1; }
done
pkg="/tmp/ssr-sync-ssr-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czpf "$pkg" /usr/local/shadowsocks /etc/init.d/shadowsocks-r /etc/shadowsocks-r/config.json
echo "$pkg"
EOS
)
    SRC_PKG=$(echo "$output" | tail -n1)
    [ -n "$SRC_PKG" ] || die "获取源机打包文件路径失败。"
    log "源机器打包完成: $SRC_PKG"
}

transfer_package() {
    LOCAL_PKG="/tmp/ssr-sync-${SRC_IP//./_}-to-${DST_IP//./_}-$(date +%Y%m%d-%H%M%S).tar.gz"
    DST_PKG="/tmp/$(basename "$LOCAL_PKG")"

    log "从源机器下载包到本地: $LOCAL_PKG"
    src_scp_from "$SRC_PKG" "$LOCAL_PKG"

    log "上传包到目标机器: $DST_PKG"
    dst_scp_to "$LOCAL_PKG" "$DST_PKG"
}

apply_target_fixes() {
    log "在目标机器解包并应用兼容修补..."
    dst_ssh "bash -s -- '$DST_PKG'" <<'EOS'
set -e
pkg="$1"
[ -f "$pkg" ] || { echo "[ERROR] 目标机器未找到包: $pkg" >&2; exit 1; }

tar -xzpf "$pkg" -C /

# Debian 12/13 + Python 3.11/3.12 兼容
[ -f /usr/local/shadowsocks/lru_cache.py ] && sed -i 's/collections\.MutableMapping/collections.abc.MutableMapping/g' /usr/local/shadowsocks/lru_cache.py
[ -f /usr/local/shadowsocks/ordereddict.py ] && sed -i 's/collections\.MutableMapping/collections.abc.MutableMapping/g' /usr/local/shadowsocks/ordereddict.py
if command -v python3 >/dev/null 2>&1 && [ -f /usr/local/shadowsocks/crypto/util.py ]; then
python3 - <<'PY'
from pathlib import Path
p = Path("/usr/local/shadowsocks/crypto/util.py")
s = p.read_text(encoding="utf-8")
old = """        else:
            path = ctypes.util.find_library(name)
            if path:
                paths.append(path)
"""
new = """        else:
            try:
                path = ctypes.util.find_library(name)
            except Exception:
                path = None
            if path:
                paths.append(path)
"""
if old in s:
    p.write_text(s.replace(old, new), encoding="utf-8")
PY
fi

if command -v python3 >/dev/null 2>&1 && [ -f /usr/local/shadowsocks/server.py ]; then
    sed -i '1s@^#!.*python.*$@#!/usr/bin/env python3@' /usr/local/shadowsocks/server.py
fi

# pid-file 适配 /var/run 不存在的容器环境
cfg="/etc/shadowsocks-r/config.json"
if [ -f "$cfg" ]; then
    if [ -d /var/run ]; then
        pid_file="/var/run/shadowsocksr.pid"
    else
        pid_file="/run/shadowsocksr.pid"
    fi

    if grep -q '"pid-file"' "$cfg"; then
        sed -i "s#\"pid-file\"[[:space:]]*:[[:space:]]*\"[^\"]*\"#\"pid-file\":\"${pid_file}\"#g" "$cfg"
    else
        sed -i "/\"workers\"[[:space:]]*:/i\    \"pid-file\":\"${pid_file}\"," "$cfg"
    fi

    # 如果使用 chacha/salsa/poly1305 系列，加密依赖 libsodium。
    if command -v python3 >/dev/null 2>&1; then
        method=$(python3 - <<'PY'
import json
try:
    with open('/etc/shadowsocks-r/config.json', 'r', encoding='utf-8') as f:
        print(str(json.load(f).get('method', '')).lower())
except Exception:
    print('')
PY
)
        if echo "$method" | grep -Eqi 'chacha|salsa|poly1305'; then
            if ! ldconfig -p 2>/dev/null | grep -qi 'libsodium'; then
                echo "[WARN] 当前 method=${method} 可能需要 libsodium，但目标机未检测到 libsodium。"
            fi
        fi
    fi
fi

chmod +x /etc/init.d/shadowsocks-r || true
[ -f /usr/local/shadowsocks/server.py ] && chmod +x /usr/local/shadowsocks/server.py || true

if command -v update-rc.d >/dev/null 2>&1; then
    update-rc.d -f shadowsocks-r defaults >/dev/null 2>&1 || true
fi

# 轻量检查
if ! command -v python3 >/dev/null 2>&1; then
    echo "[WARN] 目标机器未安装 python3，SSR 无法运行。"
fi
EOS
}

restart_service_if_needed() {
    read -r -p "是否在目标机器立即重启 SSR 服务? [Y/n]: " START_NOW
    START_NOW=${START_NOW:-Y}

    if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
        log "重启目标机器 SSR 服务..."
        dst_ssh '/etc/init.d/shadowsocks-r restart || true; sleep 1; /etc/init.d/shadowsocks-r status || true'
    else
        log "已跳过重启。可在目标机手动执行: /etc/init.d/shadowsocks-r restart"
    fi
}

cleanup() {
    log "清理临时文件..."
    [ -n "${LOCAL_PKG:-}" ] && [ -f "$LOCAL_PKG" ] && rm -f "$LOCAL_PKG" || true
    [ -n "${SRC_PKG:-}" ] && src_ssh "rm -f '$SRC_PKG'" || true
    [ -n "${DST_PKG:-}" ] && dst_ssh "rm -f '$DST_PKG'" || true
}

main() {
    require_root
    need_cmd ssh scp tar sed awk grep
    init_auth_mode

    print_banner
    collect_input
    build_source_package
    transfer_package
    apply_target_fixes
    restart_service_if_needed
    cleanup

    echo
    echo "同步完成。"
}

main "$@"
