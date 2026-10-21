# usque-openwrt release

OpenWrt 25.x 的 usque（Cloudflare WARP / MASQUE）客户端与 LuCI 界面，预编译为 APK。

## 文件

- `usque-<ver>.r<rel>.<arch>.apk` — 服务端：二进制、procd 服务、路由钩子、UCI 配置
- `luci-app-usque-<ver>.r<rel>.all.apk` — LuCI 页面、`luci.usque` ubus API、中文翻译
- `SHA256SUMS`

`<arch>` 与路由器 `apk info --print-arch` 一致；LuCI 包为 `all`。包未签名，安装需 `--allow-untrusted`。

## 安装

```sh
apk add --allow-untrusted ./usque-*.apk ./luci-app-usque-*.apk
/etc/init.d/rpcd restart
rm -rf /tmp/luci-*
```

然后打开 LuCI「网络 → usque」注册设备并启用服务。命令行部署方式见仓库 `deploy/` 与 `docs/行动指南.md`。

## 校验

```sh
sha256sum -c SHA256SUMS
```
