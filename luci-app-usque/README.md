# luci-app-usque

OpenWrt 25.x（apk + LuCI 客户端 JS 视图）上管理 `usque`
（Cloudflare WARP / MASQUE）的 Web 界面与 **ubus API**。

服务端文件（二进制、procd 服务、路由钩子、UCI 默认配置、路由助手）由同仓的
`usque` 包提供；本包只包含：

- LuCI 视图：状态页、设置页
- ubus 对象 `luci.usque`（ucode 后端）
- 菜单、ACL、首次安装时启用服务
- 中文翻译

依赖：`luci-base`、`rpcd-mod-ucode`、`ucode-mod-fs`、`usque`。

## 目录

```
luci-app-usque/
├── Makefile
├── htdocs/luci-static/resources/view/usque/{overview,settings}.js
├── po/{templates/usque.pot,zh_Hans/usque.po}
└── root/
    ├── etc/uci-defaults/95-luci-app-usque
    └── usr/share/
        ├── luci/menu.d/luci-app-usque.json
        └── rpcd/
            ├── acl.d/luci-app-usque.json
            └── ucode/luci.usque
```

## 构建与安装

### 1) buildroot / SDK

`usque/` 放进 `package/`，`luci-app-usque/` 放进 `feeds/luci/applications/`：

```sh
cp -r usque openwrt/package/
cp -r luci-app-usque openwrt/feeds/luci/applications/
cd openwrt
make package/usque/compile V=s
make package/feeds/luci/luci-app-usque/compile V=s
```

安装顺序：先 `usque`，后 `luci-app-usque`（或一次 `apk add` 两个包）。

### 2) 无构建环境（Linux / WSL / 路由器）

```sh
APK_STATIC=/path/to/apk.static sh tools/build-usque-apk.sh arm64
APK_STATIC=/path/to/apk.static sh tools/build-luci-apk.sh all
```

路由器上：

```sh
apk add --allow-untrusted usque-4.2.1-r1.<arch>.apk \
                       luci-app-usque-1.1.0-r1.all.apk
/etc/init.d/rpcd restart
rm -rf /tmp/luci-*
```

> Windows 原生 Git Bash 无法保留无扩展名 ELF 的可执行位，打包脚本会报错；
> 这是刻意保护，避免装出 `Permission denied` 的服务。

## 安装顺序与冲突

1. 安装 `usque` 包（二进制 + `/etc/init.d/usque` + 钩子 + `/etc/config/usque`）。
2. 安装 `luci-app-usque`，首次启动会执行 `/etc/uci-defaults/95-luci-app-usque`，
   在二进制存在时 `enable` 服务。
3. 旧的 `deploy/install-on-router.sh` 仍可用于纯命令行部署，但它会覆盖
   `/etc/init.d/usque`；之后请重新安装 `usque` 包（或从包内拷贝 init）。

## ubus API（`luci.usque`）

```sh
ubus -v list luci.usque
ubus call luci.usque stat '{}'
```

| 方法 | 参数 | 返回 | ACL |
|------|------|------|-----|
| `stat` | – | `binary{exists,version}`, `config{path,exists,size,mtime}`, `service{running,pid,uptime,autostart}`, `tunnel{iface,present,up,mtu,ipv4[],ipv6[]}`, `routes{default4,default6,wan4,selftest4}`, `uci{...}` | read |
| `logs` | `lines:int` | `{lines, count}`，取自 `logread -e usque` | read |
| `check_egress` | `iface:string` | `{ok, ip, warp, loc, colo, output}`，请求 Cloudflare trace | read |
| `control` | `action`: `start\|stop\|restart\|reload\|enable\|disable` | `{ok, code, output, stat}`；`enabled=0` 时启动类动作返回 `service-disabled` | write |
| `register` | `name:string`, `jwt:string`, `overwrite:bool` | `{ok, code, output, config, backup}` | write |
| `account` | `action`: `info\|devices\|set\|reset`, `key:string` | `{ok, code, output}` | write |
| `routing` | `action`: `apply\|revert` | `{ok, code, output, stat}` | write |

说明：

- `stat` 不做网络请求，前端每 10 秒轮询一次。
- `register` 在 `overwrite=false` 且配置已存在时返回 `config-exists`；覆盖时先把
  旧文件改名为 `config.json.bak`，失败自动还原；没有旧配置时失败会删除半成品。
- 设备名白名单 `[A-Za-z0-9._-]`（≤64）；JWT 只允许 `[A-Za-z0-9._-]`；
  许可密钥 `[A-Za-z0-9-]`（8–64）；接口名、配置路径均做白名单校验。
- `routing apply` 与 `deploy/install-on-router.sh` 第 2–4 步等价，并额外重载
  dnsmasq；参数全部来自 UCI，浏览器不传命令。
- `routing revert` 先停 usque，再删除 warp 接口、防火墙、DNS 的 UCI 条目并
  重载 network/firewall/dnsmasq。

## UCI 选项（`/etc/config/usque`，段 `main`）

| 选项 | 默认 | 作用 |
|------|------|------|
| `enabled` | `1` | 服务总开关；0 时 procd 不启动 |
| `iface` | `warp0` | TUN 接口名 |
| `config` | `/etc/usque/config.json` | 设备凭证路径 |
| `always_reconnect` | `1` | `--always-reconnect` |
| `http2` | `0` | `--http2`（TCP+TLS） |
| `ipv6` | `0` | `-6`（IPv6 端点） |
| `sni` | 空 | `-s` |
| `port` | `443` | `-P` |
| `keepalive` | `30` | `--keepalive-period`（秒） |
| `reconnect_delay` | `1` | `--reconnect-delay`（秒） |
| `mtu` | `1280` | `--mtu` |
| `insecure` | `0` | `--insecure`（仅排障） |
| `no_tunnel_ipv4` / `no_tunnel_ipv6` | `0` | `--no-tunnel-ipv4/6` |
| `tun_metric` | `10` | 钩子安装的隧道路由 metric |
| `wan_metric` | `250` | WAN 后备路由 metric |
| `strict` | `0` | 严格模式（WAN 不产生默认路由） |
| `manage_firewall` | `1` | 应用路由时创建 warp 区域/转发/NAT |
| `manage_dns` | `1` | 应用路由时改 dnsmasq 上游 |
| `dns` | `1.1.1.1` | 上游 DNS |

## 与旧 options.sh 的兼容

`usque` 包的 init 取值优先级为 **UCI > `/etc/usque/options.sh` > 内置默认值**：

- `iface`、`tun_metric`、`wan_metric` 在 UCI 未设置时回退到 `USQUE_IFACE` /
  `USQUE_TUN_METRIC` / `USQUE_WAN_METRIC`。
- `USQUE_EXTRA_ARGS` 若不是默认的 `--always-reconnect`，会在 UCI 参数之后
  按空格分词追加。
- 同一个参数不要既写 UCI 又写 `USQUE_EXTRA_ARGS`，否则会重复。

## 安全边界

- 后端只执行固定路径：`/usr/bin/usque`、`/etc/init.d/usque`、
  `/usr/libexec/usque-routing`；动作是枚举值，不接受任意命令。
- 进入 shell 的变量都经过单引号转义；输入先做白名单校验。
- ACL 读写分离：`stat/logs/check_egress` 只读，`control/register/account/routing`
  需要写权限。
- `config.json` 含私钥；本包不读取其内容，只读元数据。
