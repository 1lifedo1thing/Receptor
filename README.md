# Receptor

Safari downloads, a standalone file browser and IPA/DEB installation for **jailbroken iOS 4.0–6.1, armv7**. Built with **SDK 5.0**, targeting **iOS 4.0**, using manual reference counting.

## Install

Add this source in Cydia → Sources → Edit → Add:

```text
https://jajaengland.github.io/repo/
```

Install or upgrade **Receptor**, then open its **Home screen app**. If the icon does not appear after installation, respring. [Package details](https://jajaengland.github.io/repo/depictions/receptor.html) and [release downloads](https://github.com/jajaengland/Receptor/releases) are available on GitHub. The [JajaEngland repository](https://github.com/jajaengland/jajaengland.github.io) hosts Receptor and future tweaks. Previous root and `/Receptor/` sources remain available for existing users; `/repo/` is the canonical source.

1.2.2 removes the separate **JajaEngland Repository Icons** dependency. Receptor's Cydia listing uses the icon already installed at `/Applications/Receptor.app/Icon.png`. After upgrading, the old icons package can be removed through Cydia. On legacy Cydia, this local listing icon is available once Receptor itself is installed. The repository's purple emblem is separate from Receptor's app/package artwork.

GitHub Pages enforces HTTPS. Some legacy Cydia clients may not support its TLS/certificate requirements. The bundled HTTPS transport described below applies to Receptor downloads; it does not replace the networking stack used by Cydia or Safari webpages. Plain HTTP repository hosting is deferred until a suitable domain or alternative host is available.

Requires a rootful jailbreak and Cydia Substrate. The jailbreak must permit access to `/var/mobile/Media/Receptor/`. No global sandbox patch or certificate-validation bypass is installed. A compatible AppSync setup may be needed for IPAs that are not validly signed for the device; it is not installed automatically.

## Browse, preview and share files (1.4.0)

The file browser now opens in an adaptive grid inspired by the iOS Files app, with image thumbnails, file-type icons and filename search. Use **Grid / List** to switch layouts; Receptor remembers your choice. Tap a supported image for a full-screen preview with pinch/double-tap zoom. Documents use Quick Look where supported. Hold a file, tap its **•••** button (grid) or detail button (list), then choose **Open In…** to send it to a compatible installed app. The image viewer also has an action button for Open In. Package menus retain their explicit Install action. Use Edit and tap a grid tile, or swipe a list row, to delete with confirmation.

The grid uses reusable table rows on iOS 4–6. Image thumbnails are generated off the main thread with a bounded cache. Previews use an orientation-correct image capped at 1600 pixels; images larger than 25 megapixels or unsupported by legacy ImageIO show a fallback message and remain available to Open In. Animated images preview their first frame. This is a Files-inspired browser for the Receptor download directory, rather than the full iOS 11 Files app or a whole-filesystem explorer.

## Send any file from Windows (1.4.0)

Download **ReceptorDesktop.exe** from the [1.4.0 release](https://github.com/jajaengland/Receptor/releases/tag/v1.4.0) and upgrade Receptor in Cydia. On the PC, choose your Wi-Fi address, click **Start sharing**, then **Add files…**. On the iPad/iPhone, open Receptor → **Desktop**, enter the displayed address and **8-character code**, and tap **Connect / Refresh** once. The connection is saved; Desktop reconnects automatically when reopened or brought back to the foreground. Tap any file to receive it, then return to **Browse** to preview, share or manage it. Images, documents, archives, IPAs, DEBs, unknown formats, extensionless files and empty files can all be transferred. Each session supports up to 32 files, each no larger than 2,147,483,647 bytes. Duplicate filenames receive a numbered suffix without changing the extension or overwriting an existing file.

Both devices must be on the same private IPv4 network. Keep both apps open and permit the desktop app through Windows Firewall on the private network if asked. No Safari access to the original download website, SSH setup or device password is required. Receptor must already be installed. Windows 10/11 includes the .NET Framework 4.x runtime used by the portable, unsigned EXE; no desktop installation is needed.

Update both apps to 1.4.0 for all-file transfers. Saved pairings from 1.3.1 continue working. Windows saves the pairing using DPAPI and uses the same port (49176); the iOS app keeps its credential in Keychain. The short code stays off the network and is stretched with salted PBKDF2. HMAC-SHA256 authenticates lists/transfers, and Receptor checks file size and SHA-256 before offering installation. Local HTTP transfers are **not encrypted**. Only explicitly selected files are shared, and the PC cannot initiate installation without confirmation on the device. Stop sharing pauses access while preserving pairing. To revoke remembered devices, stop sharing and use **Reset pairing** on the PC. **Forget saved connection** removes the local iOS record. Closing the PC app while sharing preserves its preference and resumes sharing on reopening. If the PC IP changes, edit the address and connect with the code blank. The PC's “Sent” message is a transfer result; use Receptor's **Install Log** for the actual installation result. See [desktop usage, protocol and build instructions](Desktop/README.md).

## Using Receptor

- **Safari:** tap a downloadable link and choose Download. Completion alerts offer **Open Receptor**. The floating Files window from 1.0.0 has been removed.
- **Receptor app:** browse completed files, see transfers started in Safari or Receptor, swipe a transfer to cancel, and use Edit or the file menu to delete saved files. Tap **+** to paste an HTTP(S) file URL and download directly in the app. This is also useful if Safari's own TLS stack cannot reach a page before Receptor receives a policy callback.
- **Preview and sharing:** tap an image for zoomable preview, or a document for Quick Look. Use the file actions → Open In to send any file to a compatible installed app. Legacy OS codecs and the receiving app determine supported formats.
- **Install IPA:** tap a saved `.ipa`, select **Install IPA**, and confirm. Installation may replace an existing app version. iOS's native installer checks package/device compatibility and signing; Receptor does not decrypt FairPlay-protected apps, forge signatures or force incompatible apps onto the device. Installations run off the UI thread and report progress and the native return code on failure.
- **Install DEB (1.2.0):** close Cydia, tap a saved `.deb`, choose **Install DEB**, and confirm. Receptor invokes the device's `dpkg`, so successfully installed packages appear in Cydia's **Installed** list after reopening Cydia. **Install Log** shows the last package-manager output, and the toolbar's **Cydia** button opens Cydia. A DEB can run maintainer scripts as root; install only packages you intend to trust. If dependencies are missing, install them through Cydia and retry. A failed install may leave an unpacked/unconfigured package; use Cydia's reported repair/configuration steps. Receptor does not force installation, delete lock files, automatically remove packages, or fetch dependencies. Keep Receptor open and wait for the result; respring afterward if the package requires it.

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

To rebuild third-party libraries, run `bash scripts/build-tls.sh`. Source archive hashes are pinned and checked before compilation. Mbed TLS's millisecond clock uses a small `mach_absolute_time` adapter because legacy iOS lacks `clock_gettime`. Version 1.1.1 uses the owner's custom blue download artwork with transparent rounded corners. The original and rounded master are preserved in `App/Artwork/`. To resize the rounded master into the app and Cydia icon sizes, install Pillow and run `python3 scripts/make-icons.py`. `UIPrerenderedIcon` prevents iOS from applying additional shine to the already glossy artwork.

The local `lib/libLegacySubstrate.tbd` is a link-time interface pointing to `/usr/lib/libsubstrate.dylib`, avoiding the newer framework install name in current Theos. The app carries the platform-application entitlement for the legacy installation API. Its manifest registers `receptor://files`. Package scripts invoke `uicache` when available.

## Architecture

| Files | Responsibility |
| --- | --- |
| `Tweak.x`, `ReceptorPolicyProxy.*` | Guarded legacy WebKit policy-delegate interception in MobileSafari |
| `RCCurlTransfer.*` | Worker-thread HTTP(S), portable TLS, response/filename parsing, redirect rules |
| `DownloadManager.*` | Streamed disk writes, active transfers, background tasks, cancellation and status snapshots |
| `App/`, `FileBrowserViewController.*`, `RCFileArtwork.*` | Home screen app, grid/list browser, search, image thumbnails/zoom, Open In, URL downloads and install UI |
| `RCIPAInstaller.*` | Guarded dynamic lookup of `MobileInstallationInstall` on supported legacy firmware |
| `RCDEBInstaller.*`, `Tools/receptor-deb-helper.c` | Confirmed local DEB installation, bounded output/logging and fixed-operation root helper |
| `Desktop/`, `RCCompanionClient.*`, `RCCompanionViewController.*` | Windows Wi-Fi file sharing, authenticated transfer and on-device installation consent |
| `ReceptorUI.*`, `ReceptorPaths.*` | Consent/notifications, app launching, storage and filename handling |
| `vendor/tls/`, `layout/` | Armv7 TLS libraries, CA roots, licenses and package scripts |
| `docs/`, `scripts/update-repository.py` | Flat Cydia repository and deterministic compressed indexes |

The tweak wraps `WebView -setPolicyDelegate:` and forwards optional callbacks to Safari's original assign-owned delegate. Signatures are checked before wrapping. Policy listeners are resolved on WebKit's calling thread; consent and download management run on the main thread. curl runs on worker threads and hands each response/data chunk to the main thread synchronously, bounding queued data and preserving file/UI ownership. MRC ownership is explicit throughout.

Files stream into exclusive, mode-0600 hidden partials. Sanitized names cannot create subdirectories or hidden user files. Completed transfers are flushed and atomically published without overwriting existing files; duplicate names receive a numbered suffix. The browser ignores hidden files and symlinks. Handled failures/cancellation remove owned partials; a crash or kill can leave an ignored hidden `.part` file. No archives are unpacked automatically.

### DEB helper

1.2.0 installs `/usr/libexec/receptor-deb-helper` as root:wheel, mode **4755**, because a mobile-user app cannot modify dpkg's system database. The helper accepts one staged basename under the fixed Receptor download directory, verifies owner/type/permissions and rejects symlinks and hardlinks. Non-root callers must be the mobile user and have a kernel-reported caller code-directory hash matching the signed, root-owned installed Receptor app. Failure to verify that identity denies the request. Already-root callers retain their existing privilege.

The helper creates a private root-owned snapshot and runs only `/usr/bin/dpkg --no-act --install SNAPSHOT`, followed by `/usr/bin/dpkg --install SNAPSHOT` if the preflight succeeds. It uses fixed argument vectors and a clean environment, with no command shell or user-provided executable/options. dpkg retains responsibility for architecture/dependency checks, locking and maintainer scripts. The original saved DEB is preserved. The app's staged copy and helper's private files are cleaned after the operation. dpkg writes a regular log file so losing the UI's pipe does not terminate a package transaction; the helper returns a bounded tail of that output. The app stores the last log in a hidden mode-0600 file in the Receptor directory.

The root helper is limited to package installation and is not a general privileged command runner. It never executes an arbitrary path supplied by the caller. IPA and DEB installs cannot overlap within Receptor. Initial installation of 1.2.0 must be done through Cydia (or an existing root package manager) so the helper's ownership and setuid permissions are established.

## Validation

1.2.0 compiles, links, signs and packages for armv7 with SDK 5.0 and an iOS 4.0 minimum. Package checks validate the app manifest, executable headers, icon resources, CA bundle, tweak, root helper and repository checksums. Native Linux tests of the same curl/Mbed TLS versions pass TLS 1.2 downloads and redirects and reject untrusted issuers and wrong hostnames. The transport also successfully retrieved response bodies from Archive.org and GitHub Pages. An Obscura-linked VLC IPA endpoint reached its storage host but returned HTTP 500 during testing; successful TLS does not guarantee an archive file is available.

**Physical-device validation is still required**, particularly on the reported iPad 1 / iOS 5.1.1. Compilation and native transport tests cannot certify private Safari hooks, Home screen registration or installation/signing behavior on the device.

1.4.0 adds arbitrary file transfers, a grid/list browser, filename search, bounded image previews and Open In for every file. Eight-character codes and saved pairing from 1.3.1 are retained. It compiles the iOS pairing client against SDK 5.0 for armv7/iOS 4. Protocol integration tests exercise the actual Windows server, authentication/replay rejection, streamed immutable file contents, malformed requests and shutdown. The desktop form has been rendered for layout inspection. Updated tests verify PNG/text/ZIP/IPA/DEB/binary/extensionless/empty-file transfers, DPAPI persistence, remembered pairing after a server restart, stale-session rejection, reset and the production C key-derivation loop against independent vectors. The new iOS grid, preview/rotation/zoom and Open In flows require physical-device testing. Pairing, receiving and installation through the new iOS screen still need testing on the physical device.

Latest user-reported iPad 1 / iOS 5.1.1 results: three IPA downloads completed and one installed app launched. Two other app launch failures remain unexplained; compatibility, signing and other app-specific causes have not been established. DEB installation appearing in Cydia has not yet been confirmed on-device. Treat the current release as experimental and the full iOS 4–6 range as intended targets rather than a validated support matrix.

```sh
python3 tests/check_project.py
python3 scripts/update-repository.py
python3 tests/check_repository.py
python3 tests/test_deb_helper.py
bash scripts/build-host-tls-probe.sh
python3 tests/test_tls_transport.py
```

For device HTTP fixtures, run `python3 tests/fixture_server.py --bind 0.0.0.0 --port 8080` on a reachable computer and open its LAN URL in Safari. Check link/MIME interception, cancellation, duplicate/unsafe names, empty/error/truncated responses, cookies, background expiration and stored byte integrity. The slow `.zip` endpoint contains synthetic bytes for transfer tests, not a real archive.

The DEB-helper tests compile an unprivileged Linux-only test build and a fake package manager in a temporary directory. They check preflight/install sequencing, argument/environment isolation, private snapshot preservation, dependency/install failures, symlinks, hardlinks, traversal, permissions, shell metacharacters and bounded log output. They never invoke the host's real dpkg or install a package. Test mode is rejected at compile time on Apple targets. Packaged-helper checks verify root ownership, mode 4755, caller-authentication markers, armv7 and the iOS 4.0/SDK 5.0 load command.

On-device, also verify: the Receptor icon after upgrade; direct URL downloads with +; Safari-to-app transfer status and cancellation; file preview/deletion; IPA Install confirmation/progress/error reporting; DEB confirmation, caller authorization, a harmless compatible DEB appearing in Cydia, Install Log, missing dependencies, an already-held Cydia/dpkg lock and failed maintainer scripts; rotation/iPad menus; failed certificates and incorrect date/time; no saved HTML error pages; process kill/relaunch; and MRC behavior with Instruments. The setuid/caller-code-hash gate and actual iOS dpkg execution cannot be certified by the Linux mock tests. Keep a backup before testing package/app upgrades that replace installed software.

## References

- [Apple: legacy WebKit policy decisions](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DisplayWebContent/Tasks/PolicyDecisions.html)
- [Apple: HTTPS server trust evaluation and error codes](https://developer.apple.com/library/archive/technotes/tn2232/)
- [Theos configuration](https://theos.dev/docs/configuration)
- [Mbed TLS supported branches](https://github.com/Mbed-TLS/mbedtls/blob/development/BRANCHES.md)

The installed file browser and private installer are independent of the website used to find an IPA. Receptor does not guarantee that a third-party archive is available or that an archived app will run on a particular device.
