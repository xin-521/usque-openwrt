## TCP and HTTP/2 Support

While `usque` was originally designed with a focus on **QUIC** and **HTTP/3**, Cloudflare has since introduced TCP fallback support in their official clients. To meet frequent user requests, `usque` now supports this connection method.

### Architectural Philosophy
As noted in the [README](https://github.com/Diniboy1123/usque/blob/main/README.md#known-issues), `usque` is intended to be a **lightweight research client** rather than a comprehensive Cloudflare API interaction layer. 

Because the tool uses a minimal implementation of the Cloudflare API (`register` and `enroll`), dynamically fetching HTTP/2 endpoint details is not currently feasible. To bridge this gap without bloating the codebase, we have introduced manual configuration options.

---

### Configuration & Usage

To connect via TCP/HTTP/2, use the `--http2` CLI flag. Because endpoints cannot be reliably pulled from the API, you can manage connections using the following configuration parameters:

* **`endpoint_h2_v4`**: The IPv4 address for the HTTP/2 endpoint.
* **`endpoint_h2_v6`**: The IPv6 address for the HTTP/2 endpoint.

#### Default Behavior
If no specific address is provided, `usque` uses a hardcoded, known-working IPv4 address: `162.159.198.2`. 
> [!NOTE]
> IPv6 is not included by default and must be configured manually if required.

#### Finding Alternative Endpoints
If you wish to use different addresses, you can discover them by:
1. Running the official Cloudflare client.
2. Inspecting the traffic via [Wireshark](https://www.wireshark.org/) OR by checking the official client logs.

---

### TLS and Security

In some cases, a tunnel may use a different TLS public key than the one used for QUIC. If you encounter connection issues:
1. Try the `--insecure` flag to skip the certificate check.
2. If the connection succeeds using `--insecure`, please **open an Issue** on GitHub. This helps us identify which keys we should support natively in future updates.

**Be aware that this is insecure though** and means that any rogue endpoint that understands the protocol can [MiTM](https://en.wikipedia.org/wiki/Man-in-the-middle_attack) your traffic. Only do this on networks you trust.

---

### Why use hardcoded IPs?

The decision to use a hardcoded IP rather than dynamic discovery is intentional. This project is focused on exploring the **underlying technology** of these protocols. To avoid potential legal or ethical issues associated with reverse-engineering internal, closed-source Cloudflare APIs, we prefer manual configuration for specific metadata.