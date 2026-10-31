# Receptor

Source-complete, rootful Theos tweak for **MobileSafari on iOS 4.0–6.1, armv7**, using manual reference counting. It targets **iPhoneOS SDK 5.0** with a deployment target of **4.0**. It is not a standalone SpringBoard app. Tap the **Files** button in Safari to open the browser.

**Validation status:** successfully compiled, linked, signed and packaged in Ubuntu WSL using Theos and iPhoneOS5.0.sdk. The Mach-O binary was verified as armv7 with an iOS 4.0 minimum and SDK 5.0, using the legacy `/usr/lib/libsubstrate.dylib` dependency. The package contents and permissions were checked with `dpkg-deb`. The only build warning is that targeting iOS 4.0 is deprecated. No physical iOS device has been tested; Safari's private API and jailbreak sandbox behavior must still be verified on each supported firmware using the checklist below.

## Install with Cydia

Add this source in Cydia → Sources → Edit → Add:

```text
https://jajaengland.github.io/Receptor/
```

Refresh, search for **Receptor**, and install. The [repository page](https://jajaengland.github.io/Receptor/) includes a Cydia shortcut and package details. [GitHub releases](https://github.com/jajaengland/Receptor/releases) provide direct `.deb` downloads. GitHub Pages enforces HTTPS for this site; HTTP redirects to HTTPS. Some legacy iOS/Cydia clients may not support the required TLS or certificate chain. Plain HTTP hosting is deferred until a custom domain or another suitable host is available.

## Build and install

Use a Theos installation with an armv7-capable compiler, iPhoneOS5.0.sdk, and a toolchain/linker that still accepts an iOS 4.0 deployment target. Current toolchains may have removed this support. Obtain the SDK through your licensed Apple development tools and place it under `$THEOS/sdks/iPhoneOS5.0.sdk`.

```sh
export THEOS=/path/to/theos
export THEOS_DEVICE_IP=192.168.1.20
make clean
make package FINALPACKAGE=1
make install
```

The device needs a rootful jailbreak with Cydia Substrate. Installation restarts MobileSafari through `INSTALL_TARGET_PROCESSES`. Close Safari before upgrading if a download is active. The filter injects only into `com.apple.mobilesafari`. No entitlement or sandbox bypass is installed: the jailbreak must permit Safari to write `/var/mobile/Media/Receptor/`. Storage errors are reported if it does not. Directory creation occurs as Safari's mobile user; do not create a root-owned, unwritable storage directory.

For this Windows checkout, run the included helper from WSL:

```sh
cd /mnt/d/Receptor
export THEOS=/home/archi/theos
bash scripts/build-wsl.sh
```

The helper builds in a temporary native Linux directory and copies the package to `packages/com.receptor.downloadmanager_1.0.0_iphoneos-arm.deb`, the signed binary to `build/Receptor.dylib`, and the build log to `build/wsl-build.log`. This avoids Debian's rejection of the mode-0777 permissions reported by this Windows-mounted drive. Run `make install` from a native Linux checkout when installing through Theos, or transfer the `.deb` to the device and install it with its package manager. The helper builds only; it does not install or restart Safari.

The local `lib/libLegacySubstrate.tbd` file is a link-time interface stub, not a bundled implementation. It declares only the Substrate entry point Receptor uses and the legacy runtime install name. This prevents modern Theos vendor stubs from introducing a dependency on the newer CydiaSubstrate.framework path. The SDK-specific `MobileCoreServices/UTType.h` import likewise avoids modern private umbrella headers shadowing the iOS 5.0 public API.

## Files

| File | Responsibility |
| --- | --- |
| `Makefile`, `control`, `Receptor.plist` | SDK, architecture, dependency metadata and injection filter |
| `Tweak.x` | Guarded legacy WebView policy-delegate hook and startup |
| `ReceptorPolicyProxy.h/.m` | Delegate forwarding, link/MIME/attachment interception |
| `DownloadManager.h/.m` | Async network transfers, disk writes, cancellation and background execution |
| `ReceptorPaths.h/.m` | Storage checks, filename sanitization and request eligibility |
| `ReceptorUI.h/.m` | Consent queue, completion notifications, Safari Files button and browser window |
| `FileBrowserViewController.h/.m` | Active/saved lists, deletion, Quick Look and document interaction |
| `tests/fixture_server.py` | HTTP fixtures for device integration testing |
| `tests/check_project.py` | Packaging-input and in-memory fixture checks |
| `scripts/build-wsl.sh`, `lib/libLegacySubstrate.tbd` | WSL packaging helper and legacy Substrate link interface |

All Objective-C objects use `retain`, `release`, `autorelease` and `super dealloc`. DownloadManager, ReceptorUI and the immutable file-extension set intentionally live for the process lifetime. There is no ARC or dependency on NSURLSession, WKWebView, modern alert controllers, Auto Layout or iOS 5-only presentation APIs.

## Interception and UI

The tweak hooks `WebView -setPolicyDelegate:` rather than guessing Safari's version-dependent `BrowserController`/`TabDocument` method layouts. A retained associated proxy forwards optional callbacks to the original, assign-owned delegate. The private setter's signature and implemented policy method signatures are checked before wrapping. The original delegate's assign lifetime contract is preserved: WebView must be detached before its delegate is destroyed, as with unmodified Safari. Unsupported ABIs leave Safari's original delegate in place and log a message. Legacy WebKit is loaded if UIKit has not loaded it yet.

Explicit clicked links with known file extensions are offered for download, including text/source files Safari would ordinarily render. Top-level MIME policy callbacks catch formats `WebView +canShowMIMEType:` cannot display, and attachments when the provisional response exposes `Content-Disposition`. New-window file links are also handled. Ordinary page/subframe loads pass through; extensionless renderable content without an attachment header retains Safari's behavior. The extension allowlist is in `ReceptorPolicyProxy.m`.

Only HTTP(S) GET requests without bodies are eligible. POST submissions, non-HTTP schemes, JavaScript/blob-generated downloads and HTML `download` attributes are not replayed or emulated. Receptor resolves the policy listener immediately with `ignore` on WebKit's calling thread, copies the request, and queues consent on the main thread. **Cancel stops the navigation.** Choosing Download starts a separate GET; it does not reuse the original response body. Single-use URLs or sites requiring a POST will need site-specific support.

The main thread owns UIKit and the manager. Requests preserve original headers and use the process's shared cookie storage; verify authenticated sites on-device because Safari's private cookie behavior can vary. Cross-origin redirects remove Cookie, Authorization, Proxy-Authorization and Referer headers; the URL loading system can supply cookies appropriate to the new destination. HTTPS-to-HTTP redirects are rejected. Default Foundation certificate validation is preserved; no trust bypass is implemented. Legacy iOS TLS/certificate support limits which current servers can be reached.

The Files button floats near Safari's lower right corner. The browser uses its own normal-level window just above Safari, avoiding reliance on Safari's private root controller. Done restores Safari's previous key window. Lists use standard iOS 4 table/navigation controls; iPad document interaction is anchored to the selected row.

## Downloads and storage

Up to three asynchronous NSURLConnection transfers run concurrently. Received chunks are written directly to an exclusive, mode-0600 hidden `.part` file. Disk usage grows with file size; memory does not hold an entire download. Writes, close and flush failures become visible errors. HTTP errors and unsolicited partial responses (206) fail instead of publishing an error page or partial file.

Response-suggested names are sanitized; names cannot introduce subdirectories or hidden files. Missing extensions can be inferred using MobileCoreServices. Completion uses an atomic, no-overwrite hard link within the same directory, then removes the hidden partial file. Existing names receive ` (1)`, ` (2)`, etc. Saved files remain mode 0600 and readable by mobile. The browser lists regular files only and ignores symlinks and hidden partials. It does not execute or automatically unpack downloads.

Cancellation and handled failures remove the task's partial file. A kill, crash or reboot can leave hidden `.part` files; they are ignored, not resumed. With Safari fully closed, an administrator can inspect and remove these files if space needs reclaiming. Completed user files are preserved on uninstall and upgrade. The fixed shared Media directory is user-accessible storage, not Safari's application sandbox.

`beginBackgroundTaskWithExpirationHandler:` provides **finite** background execution on iOS 4–6. It cannot provide a daemon or iOS 7 background NSURLSession service. When background time expires the transfer is cancelled with an explanation. There is no persistent queue, automatic retry or resume. Foreground completion/failure uses a queued alert; background completion/failure uses UILocalNotification attributed to Safari. Device notification settings determine delivery. Keep Safari open for long downloads.

## Device integration checklist

Run `python3 tests/check_project.py` for packaging-input checks and in-memory fixture-response checks. These require no network access or iOS toolchain and passed in the authoring environment. Live socket checks were blocked by the environment's local network restrictions.

Run the fixtures on a computer reachable from a test device:

```sh
python3 tests/fixture_server.py --bind 0.0.0.0 --port 8080
```

Open `http://COMPUTER_LAN_IP:8080/` in Safari. Permit that port through the computer's firewall for the test network. The default server bind is localhost if `--bind` is omitted.

Validate on physical armv7 devices for iOS **4.0, 4.3, 5.0, 5.1.1, 6.0 and 6.1**, including iPhone and iPad where available:

1. Install and launch Safari. Check the system log for `[Receptor]` diagnostics. Confirm the Files button and Safari's normal browsing, back/forward, forms, tabs and new windows work.
2. Click ZIP, text, extensionless attachment, unknown MIME, redirect and new-window links. Each should offer one consent dialog. Cancel creates no download. Download saves the expected bytes. Files opens the browser without starting the pending request.
3. Download the same ZIP twice; verify `archive.zip` and `archive (1).zip` and compare bytes with the fixture ZIP. Test attachment filenames and the unsafe-name endpoint; no file may escape the Receptor directory. Place a same-named symlink in the directory and verify publication chooses a fresh name instead of replacing/following it.
4. Set the cookie and download the protected ZIP. Confirm success; if not, inspect that firmware's Safari cookie integration. Test a real authenticated site and same-/cross-origin redirects. Verify HTTPS certificate failures and HTTPS-to-HTTP downgrade rejection using controlled test servers.
5. Download a supported PDF/image/document from a controlled server, preview, return, rotate, use Done, reopen, and delete. Test an unsupported file with and without an installed document handler. Check iPad popover anchoring. Empty/error storage states must remain usable.
6. Start the slow fixture. Check progress, cancellation, multiple concurrent transfers and the three-transfer limit. Background Safari briefly, return, and then test expiration by leaving it backgrounded. Expiration must remove the partial and report failure. Notification settings affect alerts.
7. HTTP 503 and truncated-body endpoints must fail without a saved file. Test disconnects, disk-full storage and unwritable storage on a disposable test filesystem/device; existing files must survive. Restore permissions/space after the test.
8. Kill Safari during a slow transfer and reopen. Previously saved files must remain visible; a leftover hidden partial must not appear as completed. No automatic resume is expected.
9. Run Instruments Leaks/Allocations through repeated prompt, cancel, preview, delete, Files open/close and background-expiration cycles. Confirm tasks, connections, windows and preview controllers are released after use.

The fixture server supports these checks but does not test or certify the Objective-C implementation by itself. It deliberately serves the slow endpoint as synthetic bytes with a `.zip` URL; it is for transfer testing, not ZIP preview.

## Reference contracts

- [Apple: legacy WebKit policy decisions](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DisplayWebContent/Tasks/PolicyDecisions.html)
- [Apple: incremental NSURLConnection data callbacks](https://developer.apple.com/documentation/foundation/nsurlconnectiondatadelegate/connection%28_%3Adidreceive%3A%29-8p5vg?language=objc)
- [Theos: project configuration](https://theos.dev/docs/configuration)

The WebKit policy contract documents the callback structure; it does not establish private MobileSafari compatibility across all iOS firmware. That compatibility remains subject to the runtime guards and device validation above.
