# Prebuilt binaries

Buildroot needs the target binary here before compiling:

```sh
cp ../dist/bin/usque-linux-<goarch> .
```

Expected file names (from `dist/bin/`):

`usque-linux-amd64`, `usque-linux-386`, `usque-linux-arm64`,
`usque-linux-armv7`, `usque-linux-armv6`, `usque-linux-armv5`,
`usque-linux-mipsle`, `usque-linux-mipsle-softfloat`, `usque-linux-mips`,
`usque-linux-mips-softfloat`, `usque-linux-mips64le`, `usque-linux-mips64`,
`usque-linux-riscv64`, `usque-linux-loong64`.

The standalone packager (`tools/build-usque-apk.sh`) reads `dist/bin/` directly
and does not need this directory.
