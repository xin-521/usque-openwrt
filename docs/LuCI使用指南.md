# luci-app-usque 使用指南

本文只讲 **LuCI 界面**用法。安装包、构建与 ubus API 详见
[`luci-app-usque/README.md`](../luci-app-usque/README.md)。

菜单入口：**服务 → Usque WARP**（`/cgi-bin/luci/admin/services/usque`），
下分 6 个页面：状态 / 服务控制 / 出口检测 / 注册账户 / 日志 / 设置。

> usque 把整机流量经 MASQUE 送进 Cloudflare WARP。启用前先确认路由器能上网，
> 并且你接受流量经过 Cloudflare。

## 1. 安装

在路由器上按架构安装两个包（顺序不能反）：

```sh
cd /tmp
apk add --allow-untrusted ./usque-4.2.1-r4.<你的架构>.apk
apk add --allow-untrusted ./luci-app-usque-1.2.0-r1.noarch.apk
/etc/init.d/rpcd restart
rm -rf /tmp/luci-*
```

- 架构用 `apk info --print-arch` 查；两个包必须匹配。
- 包未签名，`--allow-untrusted` 不能省；校验值见 Release 的 `SHA256SUMS`。
- 装完刷新浏览器，LuCI 才会加载新菜单。

## 2. 首次使用顺序

1. 打开 **服务 → Usque WARP**，首屏是 **状态**（只读），每 10 秒自动刷新。
2. 到 **注册账户** 填设备名（默认 `openwrt-router`），点 **Register**。
3. 回到 **状态**，确认 **Configuration file** 显示 `present`。
4. 打开 **设置**，确认接口名、metric 等，点 **Save & Apply**。
5. 还在 **设置** 页点 **Apply routing**，安装接口、路由、防火墙和 DNS。
6. 到 **服务控制** 点 **Start**，状态页确认 **Service = Running**、**Interface = Up**。
7. 用 **出口检测** 验证出口 IP 已变成 Cloudflare；有异常就到 **日志** 看输出。

免费 WARP 账户可直接注册；Zero Trust 团队在注册时填 Team token（JWT）。

## 3. 状态页（Status）

每 10 秒自动刷新，只读，只调用 `stat`（不发网络请求）。

| 字段 | 含义 |
|------|------|
| Service | `Running` 且显示 PID/运行时长；`Stopped` 表示进程不在 |
| Start on boot | procd 自启是否已 enable（与总开关 `enabled` 无关） |
| Version | `/usr/bin/usque` 的版本；缺失时红字提示 |
| Configuration file | 凭证文件是否存在、大小；`missing` 需先注册 |
| Interface | TUN 接口是否存在/Up；需配合下方路由判断 |
| MTU / Tunnel address | 实际 MTU 与隧道内地址 |
| IPv4/IPv6 default route | 当前默认路由；应指向隧道接口 |
| Physical (WAN) default route | 物理 WAN 后备路由；严格模式下为空 |
| Egress self-test | `ip route get` 结果，`through tunnel` 才正常 |

状态页本身不带操作按钮，启停与自启在 **服务控制** 页。

## 4. 服务控制页（Service control）

页面顶部同样显示 Service / Start on boot / Interface，点按钮后立即刷新。

| 按钮 | 等价命令 | 说明 |
|------|----------|------|
| Start | `/etc/init.d/usque start` | `enabled=0` 时拒绝，提示去设置页启用 |
| Stop | `/etc/init.d/usque stop` | 会二次确认；隧道路由被撤掉，流量按 metric 回落到 WAN（严格模式除外） |
| Restart | `/etc/init.d/usque restart` | 改完设置后重建连接 |
| Enable on boot | `/etc/init.d/usque enable` | 生成 `/etc/rc.d/S95usque`，重启后自启 |
| Disable on boot | `/etc/init.d/usque disable` | 取消自启（不影响当前运行） |

> 服务不会随开机自启，除非至少点过一次 **Enable on boot**；重装包也不会自动自启。

## 5. 出口检测页（Egress check）

- 默认填当前隧道接口，可手改（接口名白名单 `[A-Za-z0-9._-]`，≤15 字符）。
- 请求 `https://www.cloudflare.com/cdn-cgi/trace`，显示 `ip / warp / loc / colo`。
- `warp=on` 且 IP 不是本地公网才算成功；依赖 `curl` 或 `uclient-fetch`。

## 6. 注册与账户页（Registration & Account）

### Registration

- 设备名只允许字母、数字、`.`、`-`、`_`，最长 64。
- Team token（可选）可以粘贴三种形式，程序会自动提取其中的 JWT：
  1. 裸 token：`eyJhbGciOi...`；
  2. 完整登录链接：`com.cloudflare.warp://<team>.cloudflareaccess.com/auth?token=...`；
  3. 控制台给的整段 `<meta http-equiv="refresh" content="0;url=...token=...">`。
- 已有配置会自动改名为 `config.json.bak`，然后重新注册；注册失败自动还原。
  不再需要勾选“覆盖”，也不会再卡在 `(y/n)` 提示上。
- 注册要访问 `api.cloudflareclient.com`，可能耗时一分钟。

### Account

需要已有配置和网络：

- **Account info / Devices**：查看账户与已注册设备。
- **Set license**：填入许可密钥（`xxxxxxxx-xxxxxxxx-xxxxxxxx`）。
- **Reset license**：清除密钥。

## 7. 日志页（Logs）

- 内容：`logread -e usque`，即所有提到 usque 的 syslog 行（含 procd 与
  `usque-hook` 的连接/断开钩子输出）。
- **Lines**：100 / 200 / 500 / 1000，默认 200，改完自动重拉。
- 每 10 秒自动刷新，也可点 **Refresh** 手动拉。
- 日志为空只有两种可能：服务没在跑（`/etc/init.d/usque status`），或日志缓冲
  （`logd`）里确实还没有相关行。后端出错时会显示明确的错误文字，不会静默留白。

## 8. 设置页（Settings）

保存会提交 `/etc/config/usque` 并由 procd 重载服务。

### 基本

| 选项 | 说明 |
|------|------|
| Enable service | 总开关；关掉后即使自启已 enable 也不会启动 |
| Interface name | TUN 名，默认 `warp0`，冲突时才改 |
| Configuration file | 凭证路径，默认 `/etc/usque/config.json` |
| Always reconnect | 断线后持续重连 |
| Use HTTP/2 over TCP | UDP/443 被封时改走 TCP+TLS |
| Use IPv6 endpoint | 用 IPv6 连 WARP 端点 |
| TLS SNI | 可选伪装 SNI，对抗 DPI |
| Connect port | 默认 443 |
| Keepalive period / Reconnect delay | 秒；NAT 掉线频繁时缩短 keepalive |
| MTU | 固定 1280 |
| Disable certificate pinning | 仅排障用，会失去中间人防护 |
| Disable IPv4/IPv6 inside the tunnel | 只跑单栈时勾选 |

### 路由与 DNS

| 选项 | 说明 |
|------|------|
| Tunnel route metric | 隧道路由 metric，默认 10，必须小于 WAN |
| WAN fallback metric | WAN 路由 metric，默认 250；隧道断了才轮到它 |
| Strict mode | 删掉 WAN 默认路由，断线即断网、不回落 |
| Manage firewall | 创建 `warp` 区域、LAN→warp 转发与 NAT |
| Manage DNS | 把 dnsmasq 上游指向 `dns`，防 DNS 泄漏 |
| DNS server | 默认 `1.1.1.1` |

**Apply routing** 才真正写入 network/firewall/dhcp 并重载；只保存不点不会生效。
**Revert routing** 会先停 usque，再删除上述 UCI 条目并重载。

## 9. 命令行等价操作

| 界面动作 | 命令 |
|----------|------|
| Start / Stop / Restart | `/etc/init.d/usque start\|stop\|restart` |
| Enable / Disable on boot | `/etc/init.d/usque enable\|disable` |
| Apply / Revert routing | `/usr/libexec/usque-routing apply\|revert` |
| 改设置 | `uci set usque.main.<key>=<value>; uci commit usque` |
| 注册 | `usque -c /etc/usque/config.json register -n <name> -a` |
| 看日志 | `logread -e usque` |

ubus 调用见 [`luci-app-usque/README.md`](../luci-app-usque/README.md#ubus-apiluciusque)。

## 10. 排障

| 现象 | 处理 |
|------|------|
| 菜单不出现 | 两个包都装了吗；`/etc/init.d/rpcd restart` 并强刷浏览器 |
| `usque binary not found` | 先 `which usque`：存在则 `/etc/init.d/rpcd restart`（rpcd 只在启动时加载 `/usr/share/rpcd/ucode/luci.usque`，不重启时 ubus 对象 `luci.usque` 不存在，界面任何状态都取不到）；不存在再重装 `usque` 包并确认 `/usr/bin/usque` 可执行 |
| 注册失败 `invalid-jwt` | 确认粘贴内容里有 `token=` 或直接粘贴裸 JWT；整段 `<meta>` 也可以 |
| 服务启动即退 | 看 Logs；确认已注册、`kmod-tun` 已加载（`lsmod \| grep tun`） |
| Logs 页空白 | 升级到 `luci-app-usque ≥ 1.2.0`：1.2.0 之前后端把 `logs` 的参数类型写成字符串 `'int'`，rpcd 注册成 String，浏览器发来的数字 `{"lines":200}` 会被 `UBUS_STATUS_INVALID_ARGUMENT` 拒掉；升级后仍空白说明服务没在跑（`/etc/init.d/usque status`），没跑就没有日志 |
| 有接口但无法上网 | 查 IPv4 default route 是否指向隧道；先关 Strict 再试 |
| 出口仍是本地 IP | 重新 Apply routing；确认 Egress self-test 为 through tunnel |
| UDP/443 被封 | 设置里开 **Use HTTP/2 over TCP** |
| DNS 泄漏 | 开 Manage DNS，或手动把 dnsmasq 上游指到隧道内 DNS |
| 想临时恢复直连 | Stop 服务；或 Apply 后点 Revert routing |

改完路由相关选项务必重新 **Apply routing**。`Save & Apply` 只提交 UCI。

## 11. 卸载与还原

```sh
/etc/init.d/usque stop
/etc/init.d/usque disable
/usr/libexec/usque-routing revert
apk del luci-app-usque usque
rm -f /etc/usque/config.json /etc/usque/config.json.bak
```

`apk del` 不会删 `/etc/config/usque` 和凭证；需要彻底清理时手动删除。