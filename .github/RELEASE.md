# usque-openwrt release

OpenWrt 25.x 的 usque（Cloudflare WARP / MASQUE）客户端与 LuCI 界面，预编译为 APK。

## 文件

- `usque-<ver>.r<rel>.<arch>.apk` — 服务端：二进制、procd 服务、路由钩子、UCI 配置
- `luci-app-usque-<ver>.r<rel>.noarch.apk` — LuCI 页面、`luci.usque` ubus API、中文翻译
- `SHA256SUMS`

`<arch>` 与路由器 `apk info --print-arch` 一致；LuCI 包为 `noarch`。包未签名，安装需 `--allow-untrusted`。

## 本次变更（r3）

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
