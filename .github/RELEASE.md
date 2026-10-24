# usque-openwrt release

OpenWrt 25.x 的 usque（Cloudflare WARP / MASQUE）客户端与 LuCI 界面，预编译为 APK。

## 文件

- `usque-<ver>.r<rel>.<arch>.apk` — 服务端：二进制、procd 服务、路由钩子、UCI 配置
- `luci-app-usque-<ver>.r<rel>.noarch.apk` — LuCI 页面、`luci.usque` ubus API、中文翻译
- `SHA256SUMS`

`<arch>` 与路由器 `apk info --print-arch` 一致；LuCI 包为 `noarch`。包未签名，安装需 `--allow-untrusted`。

## 本次变更（r9）

- 修复受管 DNS 的 `warp_dns` 第二 dnsmasq 实例争抢 53 端口并反复崩溃：
  r7/r8 生成的实例没有独立端口，会与主实例同时绑定 `192.168.1.1:53`
  与 `127.0.0.1:53`，最终进入 procd crash loop
- Manage DNS 现在只设置主 dnsmasq 的 WAN 上游；Apply/Revert 会删除遗留的
  `warp_dns` 配置、旧的实例标记和 DHCP `instance` 绑定
- usque **4.2.1-r9**；LuCI **1.2.0-r5**

## 上一版（r8）

- 修复状态页 uptime 仍显示 0：ucode 的 `int()` 不接受 `/proc/uptime`
  的小数文本，现在先截取整数部分再计算
- 修复 Strict mode 下显式 `network.@route6[0]` 在 `network reload` 后被
  重新添加的问题；应用配置、服务启动和连接钩子都会清理非隧道接口的
  IPv4/IPv6 默认路由
- 修复路由 helper 在 `set -u` 下无法识别逻辑接口的问题；端点 host route
  现在会正确写入 `interface wan`，Strict 模式重连后可正常恢复
- usque **4.2.1-r8**；LuCI **1.2.0-r5**

## 上一版（r7）

- 修复 Strict mode 开局断网：Apply 时先为当前 WARP 端点写入仅走 WAN 的
  host route（`network.usque_warp_ep4/6`），再移除 WAN 默认路由；`up.sh`
  在没有默认路由时会从该端点路由反推 WAN 设备和网关。退出 Strict 或
  Revert 时会删除 helper route 及 `wan6.defaultroute=0`
- 修复 dnsmasq `warp_dns` 实例继承 DHCP range 并重复监听 UDP 67：将现有
  DHCP/relay 段绑定到主 dnsmasq 实例，让 `warp_dns` 只负责 DNS
- 关闭 Manage firewall / Manage DNS 后再 Apply 会主动删除旧 zone、
  forwarding、`warp_dns` 实例并恢复 WAN 自动 DNS，不再残留配置
- 状态页 uptime 改由 `/proc/<pid>/stat` 与 `/proc/uptime` 计算；
  procd 不返回 uptime 时不再永远显示 0
- 首次安装 `luci-app-usque` 自动执行一次 `usque enable`；标记文件避免升级
  覆盖用户之后手动关闭的自启
- 新增 `endpoint_h2_v4` / `endpoint_h2_v6` 设置及 nativetun 覆盖参数，
  HTTP/2 日志会明确指出端点/账户被 `tls: access denied` 拒绝。该错误来自
  Cloudflare 服务端策略，不是界面开关失效
- 账户 API 返回 `Not Found` 时，Devices 操作显示明确的不支持提示
- usque **4.2.1-r7**；LuCI **1.2.0-r4**

## 上一版（r6）

- 修复 LuCI 所有页面报 `TypeError: "usque.common" factory yields invalid constructor`：LuCI 客户端 `require()` 只接受返回 `L.Class` 子类的模块工厂（加载时用 `Class.isSubclass` 校验，失败即抛此错），而共享模块 `usque/common.js` 之前 `return {...}` 返回的是普通对象。状态、服务控制、出口检测、注册账户、日志等页面都会 `'require usque.common as usque'`，因此全部在加载该模块时中断。现改为 `return L.Class.extend({...})`，与官方共享模块 `tools/widgets.js`、`tools/views.js` 写法一致
- LuCI 包版本 **1.2.0-r3**；usque 二进制与 r5 相同（本版仅含 LuCI 修复）

## 上一版（r5）

- LuCI 界面拆成 6 个独立页面（与「设置」同级）：**状态 / 服务控制 / 出口检测 / 注册账户 / 日志 / 设置**。启停与开机自启集中在「服务控制」页；日志独立成页，带行数选择（100/200/500/1000）与 10 秒自动刷新；注册与账户合并为一页
- 修复「日志页永远空白」：后端 `logs` 的 ubus 参数类型声明错误（写成字符串 `'int'`，rpcd 会按 String 注册），浏览器发来的 `{"lines":200}` 在进入函数前就被 `UBUS_STATUS_INVALID_ARGUMENT` 拒掉，前端又把错误吞成「暂无日志」。改为 int32 后日志正常显示，出错也会显示明确提示而不是留白
- 修复升级后后端不生效：apk 只在全新安装时执行 `post-install`，替换已装包走 `post-upgrade`；此前只注册了前者，`apk add <新包>` 之后 rpcd 仍使用旧版 `luci.usque`（表现同样是日志页空白）。现在两个脚本名都注册，升级会自动重启 rpcd
- 中文翻译 138 条（含菜单标题）；LuCI 包版本 **1.2.0-r2**
- 提示：服务不会随开机自启，需要在「服务控制」页点一次 **Enable on boot**

## 上一版（r4）

- LuCI 注册使用团队令牌时不再卡在 `Do you want to overwrite it? (y/n)`：注册前自动把旧配置改名为 `config.json.bak`，失败自动还原；命令 stdin 接 `/dev/null`，rpcd 下不会等待交互输入
- 团队令牌支持直接粘贴裸 JWT、`.../auth?token=...` 登录链接或整段 `<meta http-equiv="refresh" ...>` 片段，后端自动提取其中的 token
- 移除界面上的 Overwrite 勾选；LuCI 包版本 1.1.3

## 上一版（r3）

- 修复 usque 服务始终不启动：`/etc/init.d/usque` 首行缺少 `/etc/rc.common`，procd 从未注册实例，`start`/`enable` 静默返回 0、不生成 `S95usque` 软链、`warp0` 不出现。升级后 `usque status` 应为 running

## 上一版（r2）

- 修复安装后 LuCI 一直显示「未找到 usque 可执行文件」：ubus 对象 `luci.usque` 只在 rpcd 启动时加载，新增 post-install 自动重启 rpcd
- 修复固件缺少 `timeout` 命令时后端全部失效（版本、启停、注册、路由都返回 127）：改为按需探测，无 `timeout` 也能运行

## 安装

```sh
apk add --allow-untrusted ./usque-*.apk ./luci-app-usque-*.apk
/etc/init.d/rpcd restart
rm -rf /tmp/luci-*
```

然后打开 LuCI「服务 → Usque WARP」注册设备，并按 `docs/LuCI使用指南.md` 配置。

## 校验

```sh
sha256sum -c SHA256SUMS
```
