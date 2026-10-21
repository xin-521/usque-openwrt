# L4 proxies

`usque` has shipped with a `socks` mode since the very beginning. Historically, both `usque` and the official client implemented proxying using a userspace TCP/IP stack. In `usque`'s case this was [gVisor](https://github.com/google/gvisor), while the official client used [smoltcp](https://github.com/smoltcp-rs/smoltcp). This was necessary because Cloudflare's MASQUE endpoints operated on L3 traffic and therefore required IP packets.

Cloudflare has since moved away from this approach, replacing it with a more efficient L4 design that avoids the overhead and complexity of a full TCP/IP stack. AFAIK, smoltcp has now been removed entirely from the official client. The linked article is worth a read if you'd like a better understanding of the change:

https://blog.cloudflare.com/faster-sase-proxy-mode-quic/

Due to popular demand, this is now coming to `usque` as well.

## Limitations

L4 proxies currently only work with HTTP/3 (QUIC), which means they require UDP. Corporate networks or heavily censored environments may therefore be out of luck. Unfortunately, HTTP/2 support (and therefore TCP-based transport) is not available yet.

Custom SNI does not appear to work, as the backend rejects requests with an unexpected SNI. The official client uses `consumer-masque-proxy.cloudflareclient.com`, and so does `usque`. Because of this limitation, the `-s` flag is not exposed for these modes.

For example, SOCKS supports UDP via UDP ASSOCIATE (and this works with the legacy `usque socks` mode, which uses gVisor). However, based on my testing, Cloudflare does not appear to support this on their end. As a result, attempts to connect to UDP targets through L4 modes will fail.

If any of these limitations affect your use case, I recommend sticking with the legacy `usque socks` mode. It has higher overhead, but avoids all of the above restrictions.

There are also minor differences between how the official client and `usque` communicate with the backend servers. These could be eliminated by patching quic-go, but doing so would increase the maintenance burden for very little practical benefit. As long as the current implementation continues to work reliably, I do not intend to fully emulate the official client's behavior.

## SOCKS5 mode

Simply run:

```console
$ usque l4-socks
2026/06/16 20:56:16 CEST L4 SOCKS proxy listening on 0.0.0.0:1080
```

This will expose a SOCKS5-compatible proxy server.

## HTTP Proxy mode

This mode is not available in the official client, but it can be implemented using the same underlying mechanism, so I decided to include it. `usque` already provides an `http-proxy` mode, making this a natural addition.

Run:

```console
$ usque l4-http-proxy
2026/06/16 21:01:59 CEST L4 HTTP proxy listening on 0.0.0.0:8000
```

## Usage in 3rd-party projects

Use [`api.NewL4Proxy`](api/l4proxy.go) with [`api.L4ProxyConfig`](api/l4proxy.go) and call `DialContext` for each TCP target you want to reach through MASQUE. A minimal setup looks like this:

```go
proxy, err := api.NewL4Proxy(api.L4ProxyConfig{
    TLSConfig:      tlsConfig,
    QUICConfig:     quicConfig,
    Endpoint:       endpoint,
    DNSResolver:    resolver,
    ResolveLocally: true,
})
if err != nil {
    return err
}

conn, err := proxy.DialContext(ctx, "example.com:443")
```

If you want local hostname resolution, implement [`api.DNSResolver`](api/l4proxy.go) and pass it in the configuration. The `cmd/` package contains concrete examples showing how to integrate the proxy with SOCKS5, HTTP proxy, and hook-based workflows.

## How does it work?

It uses the same approach as the official client. `usque` exposes a proxy, a client makes a request through that proxy, and `usque` forwards it. For each individual connection, quic-go is used to issue an HTTP [CONNECT](https://pkg.go.dev/net/http#MethodConnect) request containing the desired target.

Authentication is handled using the same TLS-based mechanism that should already be familiar from the older modes. Once the connection has been established, a bidirectional stream is created, allowing the client and server to communicate directly over raw TCP without involving an L3 IP networking stack.