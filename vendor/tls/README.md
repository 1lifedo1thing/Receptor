# Bundled HTTPS transport

Receptor statically links curl **8.23.0** and Mbed TLS **3.6.7 LTS**, compiled for armv7 with iPhoneOS5.0.sdk and an iOS 4.0 deployment target. Certificate-chain and hostname verification remain enabled. The application does not depend on Apple's legacy TLS implementation for its downloads.

Rebuild the static archives with `bash scripts/build-tls.sh`. Official upstream source archives are downloaded into ignored `build/tls-cache/` and SHA256-checked before compilation:

The vendored public Mbed TLS/PSA headers come from that same pinned archive and are copied by the build script alongside the libraries. Receptor 1.8.0 uses the existing RSA implementation for background enrollment, with the same threading/platform configuration flags used to build the archives. CommonCrypto supplies device AES/HMAC; the host-test adapter uses OpenSSL instead and cannot be compiled in Apple production builds.

| Archive | SHA256 |
| --- | --- |
| `curl-8.23.0.tar.xz` | `8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5` |
| `mbedtls-3.6.7.tar.bz2` | `a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6` |

Sources: [curl 8.23.0](https://github.com/curl/curl/releases/tag/curl-8_23_0), [Mbed TLS 3.6.7](https://github.com/Mbed-TLS/mbedtls/releases/tag/mbedtls-3.6.7). Mbed TLS is used under its Apache-2.0 option; curl uses its curl license. Copies are in `licenses/` and installed with Receptor. No Apple SDK files are redistributed.

`scripts/tls-clock.c` supplies Mbed TLS's documented alternate millisecond clock using `mach_absolute_time`, because iOS 4–6 lack `clock_gettime`. Pthread locking is enabled consistently in Mbed TLS and curl for concurrent transfers. The other TLS-library sources are unmodified. Only HTTP(S) is enabled in the downloader. System HTTP proxies, HTTP/2, HTTP/3, compressed-content decoding and a public-suffix database are omitted. Requests advertise `Accept-Encoding: identity`; server-forced unsupported encodings fail. The in-memory cookie jar is cleared on cross-origin redirects so cookies cannot cross origins without public-suffix validation.

The CA bundle under `layout/Library/Application Support/Receptor/cacert.pem` comes from [curl's Mozilla CA extraction](https://curl.se/docs/caextract.html), dated **2026-10-20**, SHA256 `796f1389bfea13c0ed78f663b765baaff54a508e5483786bd6ece73c5e3e3cbe`. It is covered by MPL-2.0; the license is installed under Receptor's `licenses/` directory. Keep this bundle current. Incorrect device date/time can still cause valid certificates to fail.

Portable transport tests can be run in Linux with `bash scripts/build-host-tls-probe.sh` followed by `python3 tests/test_tls_transport.py`. These compile the same upstream TLS versions for Linux and test TLS 1.2 body transfer, redirects, untrusted certificates and wrong-host rejection. They do not execute the Objective-C integration on an iOS device.

1.4.1 adds a default `Receptor/1.4.1 (iOS)` User-Agent to direct app requests while retaining browser-provided values. A Catbox direct image reproduced curl 56 with an absent agent and succeeded with the agent (HTTP 200, full body). No TLS libraries, certificate checks or trusted roots were weakened. The test probe supports optional environment-only diagnostics (`RC_PROBE_NO_USER_AGENT`, `RC_PROBE_USER_AGENT`, `RC_PROBE_TLS12`, `RC_PROBE_VERBOSE`, `RC_PROBE_NO_RANGE`); defaults use the production User-Agent. The native tests include a server that closes anonymous-client connections and continue checking certificate failures.
