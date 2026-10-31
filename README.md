# Receptor

Safari downloads, a standalone file browser and IPA installation for **jailbroken iOS 4.0–6.1, armv7**. Built with **SDK 5.0**, targeting **iOS 4.0**, using manual reference counting.

## Install

Add this source in Cydia → Sources → Edit → Add:

```text
https://jajaengland.github.io/Receptor/
```

Install or upgrade **Receptor**, then open its **Home screen app**. If the icon does not appear after installation, respring. [Package details](https://jajaengland.github.io/Receptor/depictions/receptor.html) and [release downloads](https://github.com/jajaengland/Receptor/releases) are available on GitHub.

GitHub Pages enforces HTTPS. Some legacy Cydia clients may not support its TLS/certificate requirements. The bundled HTTPS transport described below applies to Receptor downloads; it does not replace the networking stack used by Cydia or Safari webpages. Plain HTTP repository hosting is deferred until a suitable domain or alternative host is available.

Requires a rootful jailbreak and Cydia Substrate. The jailbreak must permit access to `/var/mobile/Media/Receptor/`. No global sandbox patch or certificate-validation bypass is installed. A compatible AppSync setup may be needed for IPAs that are not validly signed for the device; it is not installed automatically.

## Using Receptor

- **Safari:** tap a downloadable link and choose Download. Completion alerts offer **Open Receptor**. The floating Files window from 1.0.0 has been removed.
- **Receptor app:** browse completed files, see transfers started in Safari or Receptor, swipe a transfer to cancel, and swipe a saved file to delete. Tap **+** to paste an HTTP(S) file URL and download directly in the app. This is also useful if Safari's own TLS stack cannot reach a page before Receptor receives a policy callback.
- **Preview:** tap a document for Quick Look or document interaction.
- **Install IPA:** tap a saved `.ipa`, select **Install IPA**, and confirm. Installation may replace an existing app version. iOS's native installer checks package/device compatibility and signing; Receptor does not decrypt FairPlay-protected apps, forge signatures or force incompatible apps onto the device. Installations run off the UI thread and report progress and the native return code on failure.

Each process allows up to three transfers. iOS grants finite background execution, not a persistent background service. Keep the process that started a long download in the foreground: Safari for Safari downloads, Receptor for downloads started with +. There is no automatic resume after the process exits. Active transfers are exchanged using small, hidden status snapshots; cancellation requests are checked by the owning process. Completed user files survive upgrades and uninstall.

## HTTPS compatibility in 1.1.0

1.0.0 used NSURLConnection and therefore inherited iOS 5's TLS/certificate limitations. 1.1.0 uses statically bundled **curl 8.23.0 + Mbed TLS 3.6.7** with current Mozilla CA roots, independently of Apple's legacy TLS stack. Hostname and certificate-chain verification remain enabled. The minimum requested TLS version is 1.2. Incorrect device date/time, an invalid certificate, a server error or an unsupported server configuration can still prevent a download.

The Obscura locator's direct IPA links can redirect from `archive.org` to an Archive.org storage host. Receptor follows up to ten HTTP(S) redirects, refuses HTTPS-to-HTTP downgrades, and drops credentials and cookies when the origin changes. A server returning HTTP 403/404/500 is reported as an HTTP failure rather than saved as an IPA.

Only HTTP(S) GET requests without bodies are supported. POST forms, blob downloads and one-time responses that cannot be fetched again are not replayed. Initial request headers and available process cookies are preserved. System proxy settings, HTTP/2, HTTP/3 and compressed-content decoding are not supported by this build; requests ask for identity encoding. See [transport sources and licenses](vendor/tls/README.md).

## Build

Use Theos with an armv7-capable compiler/linker and a licensed `iPhoneOS5.0.sdk` under `$THEOS/sdks`. This repository includes the armv7 TLS static libraries and public curl headers; it does not redistribute the Apple SDK.

```sh
export THEOS=/path/to/theos
make package FINALPACKAGE=1
```

For the Windows checkout in this project, use WSL:

```sh
cd /mnt/d/Receptor
export THEOS=/home/archi/theos
bash scripts/build-wsl.sh
```

The helper copies inputs to a native Linux temporary directory to avoid DrvFS's mode-0777 packaging errors. It copies the `.deb` to `packages/`, the signed tweak to `build/Receptor.dylib`, the app to `build/Receptor.app/`, and the build log to `build/wsl-build.log`. It does not install to a device. To install through Theos, use a native Linux checkout and `make install` with `THEOS_DEVICE_IP` configured; this restarts Safari and ReceptorApp.

To rebuild third-party libraries, run `bash scripts/build-tls.sh`. Source archive hashes are pinned and checked before compilation. Mbed TLS's millisecond clock uses a small `mach_absolute_time` adapter because legacy iOS lacks `clock_gettime`. To regenerate the geometric app icons, install Pillow and run `python3 scripts/make-icons.py`.

The local `lib/libLegacySubstrate.tbd` is a link-time interface pointing to `/usr/lib/libsubstrate.dylib`, avoiding the newer framework install name in current Theos. The app carries the platform-application entitlement for the legacy installation API. Its manifest registers `receptor://files`. Package scripts invoke `uicache` when available.

## Architecture

| Files | Responsibility |
| --- | --- |
| `Tweak.x`, `ReceptorPolicyProxy.*` | Guarded legacy WebKit policy-delegate interception in MobileSafari |
| `RCCurlTransfer.*` | Worker-thread HTTP(S), portable TLS, response/filename parsing, redirect rules |
| `DownloadManager.*` | Streamed disk writes, active transfers, background tasks, cancellation and status snapshots |
| `App/`, `FileBrowserViewController.*` | Home screen app, URL downloads, files, previews and install UI |
| `RCIPAInstaller.*` | Guarded dynamic lookup of `MobileInstallationInstall` on supported legacy firmware |
| `ReceptorUI.*`, `ReceptorPaths.*` | Consent/notifications, app launching, storage and filename handling |
| `vendor/tls/`, `layout/` | Armv7 TLS libraries, CA roots, licenses and package scripts |
| `docs/`, `scripts/update-repository.py` | Flat Cydia repository and deterministic compressed indexes |

The tweak wraps `WebView -setPolicyDelegate:` and forwards optional callbacks to Safari's original assign-owned delegate. Signatures are checked before wrapping. Policy listeners are resolved on WebKit's calling thread; consent and download management run on the main thread. curl runs on worker threads and hands each response/data chunk to the main thread synchronously, bounding queued data and preserving file/UI ownership. MRC ownership is explicit throughout.

Files stream into exclusive, mode-0600 hidden partials. Sanitized names cannot create subdirectories or hidden user files. Completed transfers are flushed and atomically published without overwriting existing files; duplicate names receive a numbered suffix. The browser ignores hidden files and symlinks. Handled failures/cancellation remove owned partials; a crash or kill can leave an ignored hidden `.part` file. No archives are unpacked automatically.

## Validation

1.1.0 compiles, links, signs and packages for armv7 with SDK 5.0 and an iOS 4.0 minimum. Package checks validate the app manifest, executable headers, icon resources, CA bundle, tweak and repository checksums. Native Linux tests of the same curl/Mbed TLS versions pass TLS 1.2 downloads and redirects and reject untrusted issuers and wrong hostnames. The transport also successfully retrieved response bodies from Archive.org and GitHub Pages. An Obscura-linked VLC IPA endpoint reached its storage host but returned HTTP 500 during testing; successful TLS does not guarantee an archive file is available.

**Physical-device validation is still required**, particularly on the reported iPad 1 / iOS 5.1.1. Compilation and native transport tests cannot certify private Safari hooks, Home screen registration or installation/signing behavior on the device.

```sh
python3 tests/check_project.py
python3 scripts/update-repository.py
python3 tests/check_repository.py
bash scripts/build-host-tls-probe.sh
python3 tests/test_tls_transport.py
```

For device HTTP fixtures, run `python3 tests/fixture_server.py --bind 0.0.0.0 --port 8080` on a reachable computer and open its LAN URL in Safari. Check link/MIME interception, cancellation, duplicate/unsafe names, empty/error/truncated responses, cookies, background expiration and stored byte integrity. The slow `.zip` endpoint contains synthetic bytes for transfer tests, not a real archive.

On-device, also verify: the Receptor icon after upgrade; direct URL downloads with +; Safari-to-app transfer status and cancellation; file preview/deletion; IPA Install confirmation, progress and error reporting with a compatible test app; rotation/iPad menus; failed certificates and incorrect date/time; no saved HTML error pages; process kill/relaunch; and MRC behavior with Instruments. Keep a backup before testing an IPA upgrade that replaces an installed app.

## References

- [Apple: legacy WebKit policy decisions](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DisplayWebContent/Tasks/PolicyDecisions.html)
- [Apple: HTTPS server trust evaluation and error codes](https://developer.apple.com/library/archive/technotes/tn2232/)
- [Theos configuration](https://theos.dev/docs/configuration)
- [Mbed TLS supported branches](https://github.com/Mbed-TLS/mbedtls/blob/development/BRANCHES.md)

The installed file browser and private installer are independent of the website used to find an IPA. Receptor does not guarantee that a third-party archive is available or that an archived app will run on a particular device.
