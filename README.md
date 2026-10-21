# usque-openwrt

把 [usque](https://github.com/Diniboy1123/usque)（Cloudflare WARP / MASQUE 客户端）
带到 OpenWrt 25.x：procd 服务、路由/防火墙钩子、UCI 配置和 LuCI 界面，打包为 APK。

- `usque/` — 服务端包（预编译二进制 + init + 钩子 + `usque-routing`）
- `luci-app-usque/` — LuCI 包（页面、`luci.usque` ubus API、中文翻译）
- `deploy/` — 无 LuCI 的命令行部署/回滚（含架构探测、arm64 调优）
- `docs/行动指南.md` — 完整部署、排障与回滚

## 安装（发布包）

从 [Releases](../../releases) 按路由器架构下载，然后：

```sh
apk add --allow-untrusted ./usque-*.apk ./luci-app-usque-*.apk
/etc/init.d/rpcd restart
rm -rf /tmp/luci-*
```

包未签名，必须带 `--allow-untrusted`；`SHA256SUMS` 随发布提供。

## 从源码构建

```sh
sh tools/build-usque-bin.sh arm64     # 或 amd64 / mipsle
APK_STATIC=/path/to/apk.static sh tools/build-usque-apk.sh arm64 aarch64_cortex-a53
APK_STATIC=/path/to/apk.static sh tools/build-luci-apk.sh all
```

CI（`.github/workflows/build.yml`）在 `v*` 标签上构建三个架构并发布 Release。

## 说明

- usque 上游为 MIT；`usque-src/` 仅用于构建二进制。
- 隧道靠公钥 pin 校验，不依赖系统 CA；`ca-bundle` 只用于注册/账户 HTTPS。
- ARM64 二进制固定 `GOARM64=v8.0`，兼容 Cortex-A53/A72，不会因 LSE 指令 SIGILL。
