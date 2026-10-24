# usque (OpenWrt package)

把 `usque`（Cloudflare WARP / MASQUE 客户端）及其 procd 服务、路由钩子、
UCI 配置打包成 OpenWrt 25.x 的 `.apk`。配套的 Web/API 包是
`luci-app-usque`。

## 包内容

```
/usr/bin/usque                    预编译二进制（按目标架构选择）
/etc/init.d/usque                 procd 服务，UCI 优先，兼容 options.sh
/etc/config/usque                 UCI 默认配置（段 main）
/etc/usque/up.sh                  on-connect：端点例外路由 + 默认路由指向隧道
/etc/usque/down.sh                on-disconnect：保持 fail-closed
/etc/usque/options.sh             旧式参数覆盖（可选）
/etc/sysctl.d/90-usque.conf       UDP 缓冲/软中断排队调优
/usr/libexec/usque-routing        apply/revert 路由、防火墙、DNS（供 LuCI API 调用）
```

依赖：`kmod-tun`、`ip-full`。

## 构建

### buildroot / SDK

1. 把二进制放进 `usque/files/`（文件名必须是 `usque-linux-<goarch>`）：

```sh
cp dist/bin/usque-linux-arm64 usque/files/
```

2. 把 `usque/` 放进 `package/`，然后：

```sh
make package/usque/compile V=s
```

架构自动映射：`aarch64→arm64`、`arm(cortex-a5/7/8/9/15)→armv7`、
`arm1176→armv6`、`arm926/fa526/xscale/mpcore→armv5`、
`i386(+x86_64)→amd64/386`、`mipsel/mips→mipsle/mips`（按 `CONFIG_SOFT_FLOAT`
选 softfloat）、`mips64el→mips64le`、`riscv64`、`loongarch64→loong64`。
不确定时用 `make ... USQUE_GOARCH=armv6` 覆盖，或
`make ... USQUE_BIN=/abs/path/to/usque`。

### 无构建环境（Linux / WSL / 路由器）

```sh
APK_STATIC=/path/to/apk.static sh tools/build-usque-apk.sh arm64
# 指定 APK 架构（推荐与路由器一致）：
APK_STATIC=/path/to/apk.static sh tools/build-usque-apk.sh arm64 aarch64_cortex-a53
```

默认 `arch:all` 只是方便本地安装，生产包请填路由器
`apk info --print-arch` 的输出。脚本会与 `dist/MANIFEST.tsv` 核对 SHA256。

> 无扩展名 ELF 的可执行位在 Windows/NTFS 上无法保留，脚本会拒绝打包；
> 请在 Linux/WSL 或路由器上执行。

## 安装与启用

```sh
apk add --allow-untrusted usque-4.2.1-r8.<arch>.apk
/etc/init.d/usque enable
/etc/init.d/usque start
```

首次使用仍需注册设备：

```sh
usque -c /etc/usque/config.json register -n openwrt-router -a
# 或在 LuCI：服务 → Usque WARP → Registration
```

## UCI 与服务

- 配置：`/etc/config/usque` 段 `main`，字段见 `luci-app-usque/README.md`。
- `enabled=0` 时 init 不启动（即使 procd 自启已 enable）。
- 修改 UCI 后提交会自动触发 procd 重载（`procd_add_reload_trigger usque`）。
- 路由/防火墙/DNS 的批量应用：
  `usque-routing apply` / `usque-routing revert`（参数全部取自 UCI）。
- 钩子从环境变量读取 `USQUE_IFACE`、`USQUE_ENDPOINT`、`USQUE_TUN_METRIC`、
  `USQUE_WAN_METRIC`；init 会把 UCI 的 metric 传给钩子。

## 目录

`root/etc/usque/`、`root/etc/init.d/usque`、`root/etc/sysctl.d/` 是钩子、
init 与 sysctl 的唯一源，打包时直接进 APK。
