# shell

自用 Linux 运维脚本集合（AI 改良版）。所有脚本均需 **root** 权限，主要在 Debian / Ubuntu / CentOS 上验证过。

---

## 脚本一览

| 脚本 | 用途 | 典型用法 |
|------|------|----------|
| `install_qbittorrent.sh` | qBittorrent 4.6.7 一键部署 + 全生命周期管理 | `bash install_qbittorrent.sh install` |
| `AutoTrace.sh` | 三网回程路由测试 + IP 信息/欺诈评分 | `bash AutoTrace.sh` |
| `ssr.sh` | Shadowsocks / SSR 服务端一键安装卸载 | `bash ssr.sh install` |
| `ssr-sync.sh` | 把一台机器的 SSR 整体迁移到另一台 | `bash ssr-sync.sh` |

---

## 1. install_qbittorrent.sh — qBittorrent 一键部署/管理

经典版 **qBittorrent 4.6.7 + libtorrent 2.0.10**（userdocs 静态编译二进制，不依赖系统 Qt/Boost），适用于 Debian / Ubuntu x86_64 + systemd。

**安装后的默认行为**

- WebUI 端口 `8080`，用户名 `admin`，**随机 16 位复杂密码**（安装完自动打印并落盘）
- 界面简体中文，全局上传限速 **50 MiB/s**，下载不限速
- 自动禁用 IPv6（`/etc/sysctl.d/99-disable-ipv6.conf`）
- 数据盘 ext 文件系统预留空间改为 **1%**（默认 5%，1TB 盘可多出约 40G）
- systemd 服务 `qbittorrent.service`，开机自启
- 凭据明文保存在 `/root/qbittorrent_credentials.txt`（0600），随时可用 `info` 查看

**子命令**

```bash
bash install_qbittorrent.sh install [--force] [--up=N] [--down=N]  # 安装；已装则跳过（幂等），--force 才重装
bash install_qbittorrent.sh uninstall [--purge]   # 卸载；--purge 连配置/凭据/下载目录一起删并恢复 IPv6
bash install_qbittorrent.sh start|stop|restart
bash install_qbittorrent.sh status                # 状态/PID/端口/BT监听/内存/磁盘/预留空间
bash install_qbittorrent.sh info                  # 登录地址、用户名、密码、限速、语言
bash install_qbittorrent.sh password              # 重新生成随机 16 位密码
bash install_qbittorrent.sh limit --up=N --down=N # MiB/s，down 填 0 = 不限速
bash install_qbittorrent.sh port <端口号>
bash install_qbittorrent.sh reserve [百分比]      # 数据盘预留空间，默认 1%
bash install_qbittorrent.sh log
```

**注意事项**

- 只有 `install --force` 和 `password` 会更换密码，其余命令不会动凭据
- 路径：程序 `/usr/local/bin/qbittorrent-nox`、配置 `/root/.config/qBittorrent/qBittorrent.conf`、下载目录 `/root/Downloads`
- 4.x 的 CLI 没有 `--webui-password`，密码哈希由脚本自己写入：`PBKDF2-HMAC-SHA512 / 100000 轮 / 64 字节`，存储格式为 `base64(salt):base64(key)`（顺序写反会登录失败）
- 一分钟上手：

```bash
curl -fsSL https://raw.githubusercontent.com/luzi6033666/shell/main/install_qbittorrent.sh -o qbt.sh && bash qbt.sh install
```

---

## 2. AutoTrace.sh — 三网回程路由测试

源自 ChennHaoo 的 AutoTrace（`v2026.04.11_02`），实测三网（电信/联通/移动）回程路由，并输出本机 IP 画像。

**能做什么**

- 显示 ISP、ASN、服务商、国家/地址、IPv4/IPv6、IP 性质（家宽/机房/广播等）
- **IP 危险性评分（0-100，建议 < 60）**，通过 curl-impersonate 伪装 Chrome 绕过 Cloudflare 探测
- 三网回程路由测试（TCP 模式，9 个测试点，含广东、上海、北京），中/英文输出
- 本机到指定 IPv4/IPv6 的路由测试（可指定端口）

**用法**

```bash
bash AutoTrace.sh               # 交互式主菜单（默认 Stand）
bash AutoTrace.sh Specify_IP    # 直达"指定 IP 路由测试"菜单
```

主菜单选项：`1` IPv4 中文 / `2` IPv4 英文 / `3` IPv6 中文 / `4` IPv6 英文 / `5` 指定 IP / `6` 退出。

**依赖与产物**

- 需要 root，仅支持 Debian / Ubuntu / CentOS
- 依赖二进制会自动从**本仓库** main 分支下载，无需手动准备：
  - `Nexttrace/nexttrace_linux_{amd64,386,arm64,armv7,mips}` → 落到 `./Nexttrace/nexttrace_IP`
  - `curl-impersonate/` 的 chrome 二进制与配置 → 落到 `./Curl_impersonate/`
- 已在最新版本时会跳过重复下载；日志写入 `./AutoTrace_Mtr.log`
- 机器需能访问 `raw.githubusercontent.com`，否则二进制拉取失败（x86 32 位无 curl-impersonate，欺诈分显示未知）

---

## 3. ssr.sh — Shadowsocks / SSR 一键安装卸载

源自 Teddysun 的 Shadowsocks 一键脚本，已把下载源改为本仓库镜像（`ssr_assets/`），避免上游失效。

支持四种服务端：`Shadowsocks-Python`、`ShadowsocksR`、`Shadowsocks-Go`、`Shadowsocks-libev`。

**用法**

```bash
bash ssr.sh install      # 交互式选择版本 → 设置密码/端口/加密/协议/混淆 → 自动装依赖并配置防火墙
bash ssr.sh uninstall    # 交互式选择要卸载的版本
```

**说明**

- 系统要求：CentOS 6+ / Debian 7+ / Ubuntu 12+，需 root
- 安装过程交互项为英文，依次选择：服务端类型 → 密码 → 端口 → 加密方式 → 协议 → 混淆
- 装完会在当前目录生成二维码 PNG：`shadowsocks_python_qr.png` / `shadowsocks_r_qr.png` / `shadowsocks_go_qr.png` / `shadowsocks_libev_qr.png`
- 配置与启动脚本位置：`/etc/shadowsocks-python|shadowsocks-r|shadowsocks-go|shadowsocks-libev/config.json`、`/etc/init.d/shadowsocks-*`
- 依赖包（源码 tarball + SysV 启动脚本）从本仓库 `ssr_assets/dist`、`ssr_assets/init` 下载；**本地若已存在同名文件会直接使用**，可提前放进脚本同目录实现离线安装
- `ssr_assets/init` 中带 `-debian` 后缀的是 Debian/Ubuntu 用启动脚本，无后缀的是 CentOS 用

---

## 4. ssr-sync.sh — SSR 整机迁移同步

把一台机器上已经装好的 **ShadowsocksR** 整体搬到另一台（适合换机/重装）。全程交互式，本地中转。

**同步内容**

- `/usr/local/shadowsocks`（SSR 程序本体）
- `/etc/init.d/shadowsocks-r`（启动脚本）
- `/etc/shadowsocks-r/config.json`（配置）

**流程**

1. 输入源机与目标机的 IP、SSH 端口、root 密码（检测到 `sshpass` 则免交互，否则走 ssh/scp 交互认证或已配密钥）
2. 在源机打包 → scp 到本地 `/tmp` → 上传到目标机 `/tmp`
3. 目标机解包并自动做兼容修补：
   - `collections.MutableMapping` → `collections.abc.MutableMapping`（Python 3.10+）
   - `ctypes.util.find_library` 加异常兜底（Python 3.11/3.12）
   - `server.py` shebang 改 `python3`
   - `config.json` 补齐/修正 `pid-file`（兼容 `/var/run` 不存在的容器环境）
   - 检测 chacha/salsa/poly1305 是否缺 libsodium 并告警
   - `update-rc.d` 注册开机启动
4. 询问是否立即重启目标机 SSR 服务，最后清理两端临时文件

**前提**

- 源机与目标机架构相同（如都是 x86_64），建议 Debian/Ubuntu 主版本一致
- 目标机需已安装 `python3`，否则 SSR 无法运行
- 本机需要 `ssh`、`scp`、`tar`、`sed`、`awk`、`grep`

---

## 二进制资产目录

| 目录 | 内容 | 当前版本 |
|------|------|----------|
| `Nexttrace/` | NextTrace 各架构二进制（amd64/386/arm64/armv7/mips）+ `version.txt` | v1.7.5 |
| `curl-impersonate/` | curl-impersonate chrome 二进制（x86_64/aarch64/arm）+ 配置 `curl_chrome116` + `version.txt` | v0.6.1 |
| `BestTrace/` | BestTrace 老版二进制（`besttrace`、`besttrace32`、`besttracearm`），可单独使用，AutoTrace 不引用它 | — |
| `ssr_assets/dist/` | SSR 安装所需的源码/二进制包（libsodium、mbedtls、shadowsocks、shadowsocksr、simple-obfs 等） | — |
| `ssr_assets/init/` | SysV 启动脚本（CentOS 版与 `-debian` 版各一套） | — |

## 自动同步（GitHub Actions）

`.github/workflows/sync-binaries.yml`：**每天 UTC 02:00**（也可在 Actions 页面手动 `workflow_dispatch` 触发）比对上游最新版本，有更新就下载并自动 commit 回仓库：

- `sjlleo/nexttrace` → `Nexttrace/`
- `lwthiker/curl-impersonate` → `curl-impersonate/`

版本号写在各自的 `version.txt`，`AutoTrace.sh` 会读取该文件判断是否已最新。

---

## 免责声明

仓库脚本仅用于自有服务器的运维管理，请遵守所在地区法律法规与服务商条款。使用前建议先看清交互提示，涉及卸载、清库类的操作（`uninstall --purge` 等）会直接删除数据。
