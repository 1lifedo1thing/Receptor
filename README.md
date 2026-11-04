# Receptor

Safari downloads, a standalone file browser and IPA/DEB installation for **jailbroken 32-bit iOS 4.0–8.x** (iOS 7–8 support is experimental). Built with **SDK 5.0**, targeting **iOS 4.0**, using manual reference counting.

## Install

Add this source in Cydia → Sources → Edit → Add:

```text
https://jajaengland.github.io/repo/
```

Install or upgrade **Receptor**, then open its **Home screen app**. If the icon does not appear after installation, respring. [Package details](https://jajaengland.github.io/repo/depictions/receptor.html) and [release downloads](https://github.com/jajaengland/Receptor/releases) are available on GitHub. The [JajaEngland repository](https://github.com/jajaengland/jajaengland.github.io) hosts Receptor and future tweaks. Previous root and `/Receptor/` sources remain available for existing users; `/repo/` is the canonical source.

1.2.2 removes the separate **JajaEngland Repository Icons** dependency. Receptor's Cydia listing uses the icon already installed at `/Applications/Receptor.app/Icon.png`. After upgrading, the old icons package can be removed through Cydia. On legacy Cydia, this local listing icon is available once Receptor itself is installed. The repository's purple emblem is separate from Receptor's app/package artwork.

GitHub Pages enforces HTTPS. Some legacy Cydia clients may not support its TLS/certificate requirements. The bundled HTTPS transport described below applies to Receptor downloads; it does not replace the networking stack used by Cydia or Safari webpages. Plain HTTP repository hosting is deferred until a suitable domain or alternative host is available.

Requires a rootful jailbreak and Cydia Substrate. The jailbreak must permit access to `/var/mobile/Media/Receptor/`. No global sandbox patch or certificate-validation bypass is installed. A compatible AppSync setup may be needed for IPAs that are not validly signed for the device; it is not installed automatically.

## Desktop management and background access (1.8.0b3)

Update Receptor to **1.8.0b3** using the [beta 3 release](https://github.com/jajaengland/Receptor/releases/tag/v1.8.0-beta3); keep **Receptor Desktop 1.8.0 beta 1** on Windows. On Windows, enable **Allow background device access**, start sharing and open **Manage device…**. On the iPad, connect/refresh in **Desktop**, open **Background desktop access…**, compare the PC key and enable it once. Existing foreground pairings remain compatible.

Beta 3 fixes beta 2's misleading **launchctl 0** failure: service queries now fall back from XML to legacy dictionary/table formats, and successful load/start commands are not rejected solely because listing is unavailable. An unavailable status is distinguished from a failed command; actual device startup still needs confirmation. **Forget saved connection** now asks Cancel/Forget before removing the pairing and revoking background access. Cancel preserves it; a confirmation dismissed while the app is inactive cannot delete the pairing.

Beta 2 explicitly loads/starts the background service when access is enabled, instead of relying only on a filesystem trigger. For an existing beta 1 grant, tap **Restart service / Retry connection** once after updating. This starts a missing/stopped service without stopping a running one. The screen now distinguishes saved permission from connection state, refreshes diagnostics automatically and reports launchctl, network and authentication failures. This addresses a startup gap; the exact cause of the first reported device connection failure is not yet confirmed.

The PC can then search/list/install/remove packages, manage sources, review APT dependency plans, inspect the operation log, request a confirmed respring and browse/upload/download files in **Receptor's download folder**, even after leaving the iPad app. The separate device Filesystem tab is not remotely exposed. Close Cydia before package changes. Source refresh uses system APT/TLS, so legacy repository/certificate limitations still apply.

Background access is opt-in and persists across app closure/reboot. Its root service makes outgoing encrypted, authenticated requests to the pinned PC; it opens no listening port on the iPad. Files run through a non-setuid helper as mobile. Disable it on-device or Forget saved connection to revoke it; Reset pairing on Windows replaces the PC key and revokes old grants. The grant permits unattended root package changes while locked. Already dispatched operations may finish after disconnection or revocation; inspect the operation log before retrying an uncertain install.

Keep Windows running and sharing enabled, and the iPad powered and reachable on private Wi-Fi. Locked/sleeping Wi-Fi behavior depends on iOS and power state; continuous reachability is not guaranteed. Host integration/build checks pass; **physical-device background/launchd/APT testing is pending**. See [setup and device checklist](docs/REMOTE-TESTING.md) and [protocol details](Desktop/README.md#background-management-protocol-v3).

## Packages: sources and tweaks (1.7.0b1)

The [1.7.0 beta 1 release](https://github.com/jajaengland/Receptor/releases/tag/v1.7.0-beta1) adds a **Packages** tab with **Sources**, **Search packages**, **Installed packages**, **Refresh repository indexes** and **Operation log**. This is an experimental native APT frontend: **real device package/source operations are not yet validated**. Install through Cydia so its compatible `apt7` or `apt` command-line dependency and both authenticated helpers are installed correctly. Windows stays at 1.6.0 beta 2; saved pairing is unchanged.

Fully close Cydia in the app switcher before making changes. In Sources, use **+** to add a flat HTTP(S) Cydia URL. Refresh repository indexes, search by package name, open a result and choose **Install / Upgrade**. Receptor shows the APT dependency plan; review every change before confirming. Installed packages have **Remove** with the same preview flow. Removal keeps configuration files and does not run autoremove. Core/Essential packages and package-manager components are protected from removal here. Individual upgrades are supported; bulk upgrades, purge, repair and commercial-repository account login are not included.

Authentication is enabled by default. Legacy unsigned repositories can be used only by choosing **Allow unsigned…** in the install confirmation and accepting a second warning for that installation. The setting is not saved and does not change global APT trust configuration. Repository metadata without authenticated signatures can be modified by an untrusted source or network attacker; package hashes from that metadata do not establish the author’s identity. No force-yes or forced dependency-removal options are used. Modified conffiles are kept using dpkg’s `--force-confold` setting.

Repo/package networking uses **the device’s APT transport**, not Receptor’s bundled curl/Mbed TLS downloader. A source that works in Receptor’s URL downloader can still fail in APT because of missing HTTPS methods, old TLS, certificates, date/time, a server error or repository layout. Those errors remain visible in the operation log; TLS verification is not disabled. Refresh can partially fail, so read warnings even when APT returns success.

Sources added here live in `/etc/apt/sources.list.d/receptor.list`, which Cydia’s APT loader also reads. Cydia may display these entries as read-only; remove them through Receptor. Existing conventional `.list` entries can also be removed. Removing a Cydia-managed URI synchronizes recognized legacy metadata and root/mobile Cydia preferences, including all distributions for that URI. Unknown metadata/symlink layouts are refused. Cydia must stay closed during these edits. Changes keep unrelated source lines/preferences and save a private pre-removal backup; source removal never uninstalls packages. See [backend and device testing notes](docs/PACKAGES-TESTING.md).

The new `/usr/libexec/receptor-package-helper` uses the existing installed-app code-hash authorization, fixed command paths, validated identifiers and a shared operation lock. It re-simulates before applying and rejects a changed plan, installed database or source list. Install targets include the exact candidate version. Neither helper exposes an arbitrary root shell or executable path. A durable operation journal survives UI termination; use Packages → Operation log. Keep Receptor in the foreground and do not run another package manager concurrently. A failed/interrupted package install can require repair in Cydia. Respring remains manual after installation.

## Manual Respring button (1.6.0b3)

Upgrade Receptor to **1.6.0b3** from Cydia or the [beta 3 release](https://github.com/jajaengland/Receptor/releases/tag/v1.6.0-beta3). The **Files** toolbar now has **Respring**, also available while viewing **Install Log**. Confirm to restart the Home/lock-screen interface; Cancel leaves it running. Finish transfers and close Cydia first. Receptor blocks the action during its IPA/DEB installations and active downloads; its root helper checks the dpkg lock before requesting the restart. The **Cydia** shortcut is now in the Install Log toolbar to keep the Files toolbar usable on narrow screens.

Respringing is always explicit. Receptor does not automatically respring after installing a DEB, on launch or at boot, and it does not claim to detect whether a package requires one. Cydia uses its own explicit finish-request channel; plain dpkg output alone does not reproduce that behavior. Follow a package author’s respring/reboot instructions. This button does not reboot the device or replace a required reboot.

The existing caller-authenticated helper has two fixed restart operations: `/bin/launchctl stop com.apple.SpringBoard` on iOS 4–5 and `stop com.apple.backboardd` on iOS 6–8, matching the version split in [Cydia’s reload implementation](https://github.com/autopear/Cydia/blob/master/MobileCydia.mm). It accepts no arbitrary job label, PID, signal or executable path. Host tests use a fake launchctl and never restart host services. Actual device behavior still needs testing. Windows remains **1.6.0 beta 2**; its binary and saved pairing are unchanged.

## Device-to-PC transfers and filesystem browser (1.6.0b2)

Upgrade Receptor in Cydia and download **ReceptorDesktop.exe 1.6.0 beta 2** from the [1.6.0 beta 2 release](https://github.com/jajaengland/Receptor/releases/tag/v1.6.0-beta2). Saved pairing is retained. On Windows, enable **Receive files sent from the device**, choose a destination folder, and keep **Start sharing** active. Receiving can be enabled and its folder changed while sharing is running; no stop or re-pair is needed. The address and pairing code stay visible when paused, but connections require sharing to be running. In Receptor’s **Files** tab, hold a file or tap **••• → Send to PC**, then tap **Send to PC** on the confirmation screen. Use **Manage pairing** there if this PC has not been paired. Keep both apps open until delivery is verified. **Open folder** in the Windows companion shows received files. It does not automatically open or install them.

The separate **Filesystem** tab starts at `/`, includes hidden entries and navigates folders and symbolic links. Select a regular file for **Preview** (Quick Look) or **Send to PC**. This tab is read-only: there are no system-file delete, move, edit or install actions. It uses the app’s existing permissions; protected paths can be unavailable, and special files such as devices/sockets are excluded. Filesystem browsing/export does not use the root helper. Since 1.6.0b3, that helper also supports the fixed, confirmed manual respring operation. The existing Files tab retains its grid/list, download management, sharing and confirmed installation actions.

Sending creates an anonymous private snapshot on the device, requiring free space approximately equal to the selected file’s size. Files changing during preparation are rejected. The PC verifies the declared length and SHA-256, publishes without overwriting existing files, and signs its receipt. Cancelling or leaving the sender stops the transfer and removes incomplete snapshots; a fully delivered copy may remain if its receipt was interrupted. Receiving is opt-in and its folder/preference is saved encrypted for the current Windows user. Preference changes apply to new requests; active transfers finish in their original folder. Stop sharing cancels active transfers. Up to 32 incoming files per sharing session, each at most 2,147,483,647 bytes. Restart sharing for a new session. Authentication does not encrypt filenames or contents: use a trusted private LAN. This legacy transfer flow cannot remotely browse the device; optional 1.8.0 background access exposes only the download folder.

The armv7 SDK 5.0 build and Windows integration tests pass. The new iOS tab/preview/send flow needs physical-device testing. **iOS 7–8 support remains experimental; arm64 Safari is not included.** See [new-feature test steps](docs/TRANSFER-TESTING.md).

Cydia beta labels are now **1.5.0b1**, **1.6.0b1** and **1.6.0b2**. The two beta-1 packages only change package metadata: their original signed app payloads retain the original bundle versions. Old numeric package files and GitHub release assets remain unchanged but the numeric betas are hidden from Cydia indexes. These b-suffix versions sort above the previous numeric versions, so existing installations can upgrade; a later stable release should use a higher numeric version.

## Experimental iOS 7–8 support (introduced in 1.5.0)

The first 32-bit iOS 7–8 test build was published in the [1.5.0 beta release](https://github.com/jajaengland/Receptor/releases/tag/v1.5.0-beta1); these adapters remain in 1.6.0. Existing 1.4.1 files remain unchanged and available for iOS 4–6. **No iOS 7/8 physical-device result is claimed yet, and arm64 Safari injection is not included.** Pairing is unchanged.

iOS 7 retains the guarded legacy WebView adapter. iOS 8 has a new guarded WKWebView navigation delegate, forwarding Safari's optional callbacks and authentication handling while leaving profile/certificate and native Passbook responses to Safari. On iOS 7–8, choose **Open Receptor** at the Safari prompt and confirm **Download** inside the app. This avoids relying on Safari's storage sandbox/background lifetime. The handoff carries the HTTP(S) GET URL only, with fresh in-app consent; private Safari cookies, headers, POST bodies, one-time responses and blob URLs are not replayed. Start with public file URLs.

IPA installation retains MobileInstallationInstall through iOS 7 and uses the checked LSApplicationWorkspace interface on iOS 8. A bounded reader obtains the IPA bundle identifier without extracting an archive; the native installer still checks compatibility, signing and authorization. iOS 8 also requests notification permission for completion alerts. New classes and zeroing-weak functions are dynamically resolved so the binaries retain their iOS 4 startup compatibility. See the [runtime matrix and device test checklist](docs/IOS78-TESTING.md).

## Profiles, Catbox and Photos (1.4.1)

Safari configuration profiles and certificates are left to the native system installer, including `.mobileconfig`, `.cer`, `.crt`, `.der`, `.p12` and `.pfx`, their recognized installer MIME types, and response-suggested installer filenames. Receptor no longer consumes those responses as generic unsupported downloads. The system installer retains review/confirmation; Receptor does not install profiles or trust roots itself. After updating, fully close/reopen Safari before retrying a profile link. If a profile was already downloaded into Receptor, revisit its original link in Safari. This follows Apple's documented [Safari certificate/identity installation path](https://developer.apple.com/library/archive/qa/qa1745/_index.html).

Direct app downloads now supply a default `Receptor/1.4.1 (iOS)` User-Agent when the request has none. This fixes a reproduced Catbox connection close (`curl 56`, `ssl_read returned: (-0x0000)`). Existing browser User-Agent headers are preserved. Certificate-chain and hostname checks remain enabled. The reported direct PNG succeeded in a full-body test with the pinned curl/Mbed TLS stack; the URL/content is not included in the source or release notes.

Use **Save to Photos** from a file's actions or the image preview's bottom toolbar. Supported images and `.mov`/`.mp4`/`.m4v` videos use AssetsLibrary and show success or the system's error. iOS 4.1 and later receives original encoded image data, preserving source resolution/metadata rather than saving the reduced preview. Images have a 64 MB import limit. iOS 4.0 uses its older decoded-image API with a 6-megapixel limit. Codec support and Photos permissions still apply.

**Share…** is separate from **Open In…**. On iOS 6 and later it presents the public system activity sheet, in a popover on iPad. On iOS 4–5 it presents a legacy menu with Save to Photos for supported media and Open In. Open In is an app picker: if no installed app registers support for the file type, an explanatory message appears. The image preview includes direct Save to Photos and Open In buttons as well as Share.

The 1.4.1 update only changed iOS; Windows remained at 1.4.0 until the 1.6.0 two-way transfer update.

## Browse, preview and share files (1.4.0)

The file browser now opens in an adaptive grid inspired by the iOS Files app, with image thumbnails, file-type icons and filename search. Use **Grid / List** to switch layouts; Receptor remembers your choice. Tap a supported image for a full-screen preview with pinch/double-tap zoom. Documents use Quick Look where supported. Hold a file, tap its **•••** button (grid) or detail button (list), then choose **Open In…** to send it to a compatible installed app. The image viewer has Share, Save to Photos and Open In controls. Package menus retain their explicit Install action. Use Edit and tap a grid tile, or swipe a list row, to delete with confirmation.

The grid uses reusable table rows on iOS 4–6. Image thumbnails are generated off the main thread with a bounded cache. Previews use an orientation-correct image capped at 1600 pixels; images larger than 25 megapixels or unsupported by legacy ImageIO show a fallback message and remain available to Open In. Animated images preview their first frame. This Files-inspired grid covers the Receptor download directory; 1.6.0 adds a separate read-only filesystem tab.

## Send any file from Windows (1.4.0)

Download **ReceptorDesktop.exe** from the [1.4.0 release](https://github.com/jajaengland/Receptor/releases/tag/v1.4.0) and upgrade Receptor in Cydia. On the PC, choose your Wi-Fi address, click **Start sharing**, then **Add files…**. On the iPad/iPhone, open Receptor → **Desktop**, enter the displayed address and **8-character code**, and tap **Connect / Refresh** once. The connection is saved; Desktop reconnects automatically when reopened or brought back to the foreground. Tap any file to receive it, then return to **Browse** to preview, share or manage it. Images, documents, archives, IPAs, DEBs, unknown formats, extensionless files and empty files can all be transferred. Each session supports up to 32 files, each no larger than 2,147,483,647 bytes. Duplicate filenames receive a numbered suffix without changing the extension or overwriting an existing file.

Both devices must be on the same private IPv4 network. Keep both apps open and permit the desktop app through Windows Firewall on the private network if asked. No Safari access to the original download website, SSH setup or device password is required. Receptor must already be installed. Windows 10/11 includes the .NET Framework 4.x runtime used by the portable, unsigned EXE; no desktop installation is needed.

Update both apps to 1.4.0 for all-file transfers. Saved pairings from 1.3.1 continue working. Windows saves the pairing using DPAPI and uses the same port (49176); the iOS app keeps its credential in Keychain. The short code stays off the network and is stretched with salted PBKDF2. HMAC-SHA256 authenticates lists/transfers, and Receptor checks file size and SHA-256 before offering installation. Local HTTP transfers are **not encrypted**. Only explicitly selected files are shared, and the PC cannot initiate installation without confirmation on the device. Stop sharing pauses access while preserving pairing. To revoke remembered devices, stop sharing and use **Reset pairing** on the PC. **Forget saved connection** removes the local iOS record. Closing the PC app while sharing preserves its preference and resumes sharing on reopening. If the PC IP changes, edit the address and connect with the code blank. The PC's “Sent” message is a transfer result; use Receptor's **Install Log** for the actual installation result. See [desktop usage, protocol and build instructions](Desktop/README.md).

## Using Receptor

- **Safari:** tap a downloadable link and choose Download. Completion alerts offer **Open Receptor**. The floating Files window from 1.0.0 has been removed.
- **Receptor app:** browse completed files, see transfers started in Safari or Receptor, swipe a transfer to cancel, and use Edit or the file menu to delete saved files. Tap **+** to paste an HTTP(S) file URL and download directly in the app. This is also useful if Safari's own TLS stack cannot reach a page before Receptor receives a policy callback.
- **Preview and sharing:** tap an image for zoomable preview, or a document for Quick Look. Use the file actions → Share or Open In to send any file to a compatible installed app. Legacy OS codecs and the receiving app determine supported formats.
- **Install IPA:** tap a saved `.ipa`, select **Install IPA**, and confirm. Installation may replace an existing app version. iOS's native installer checks package/device compatibility and signing; Receptor does not decrypt FairPlay-protected apps, forge signatures or force incompatible apps onto the device. Installations run off the UI thread and report progress and the native return code on failure.
- **Install DEB (1.2.0):** close Cydia, tap a saved `.deb`, choose **Install DEB**, and confirm. Receptor invokes the device's `dpkg`, so successfully installed packages appear in Cydia's **Installed** list after reopening Cydia. **Install Log** shows the last package-manager output, and **Install Log → Cydia** opens Cydia. A DEB can run maintainer scripts as root; install only packages you intend to trust. If dependencies are missing, install them through Cydia and retry. A failed install may leave an unpacked/unconfigured package; use Cydia's reported repair/configuration steps. The local-DEB installer does not force installation, delete lock files, automatically remove packages, or fetch dependencies. The separate Packages tab in 1.7.0b1 uses APT for dependency resolution. Keep Receptor open and wait for the result; respring afterward if the package requires it.

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
| `Tweak.x`, `ReceptorPolicyProxy.*`, `RCWKNavigationProxy.*` | Guarded WebView (iOS 4–7) / WKWebView (iOS 8) interception in 32-bit Safari |
| `RCCurlTransfer.*` | Worker-thread HTTP(S), portable TLS, response/filename parsing, redirect rules |
| `DownloadManager.*` | Streamed disk writes, active transfers, background tasks, cancellation and status snapshots |
| `App/`, `FileBrowserViewController.*`, `RCFileArtwork.*`, `RCFileSharing.*` | Home screen app, grid/list browser, search, image thumbnails/zoom, Photos saving, Share/Open In, URL downloads and install UI |
| `RCIPAInstaller.*`, `RCIPAArchive.*` | Guarded legacy/workspace installation and bounded ZIP Info.plist reading for iOS 8 |
| `RCDEBInstaller.*`, `Tools/receptor-deb-helper.c` | Confirmed local DEB installation, bounded output/logging and fixed-operation root helper |
| `Desktop/`, `RCCompanionClient.*`, `RCCompanionViewController.*` | Windows Wi-Fi file sharing, authenticated transfer and on-device installation consent |
| `ReceptorUI.*`, `ReceptorPaths.*` | Consent/notifications, app launching, storage and filename handling |
| `vendor/tls/`, `layout/` | Armv7 TLS libraries, CA roots, licenses and package scripts |
| `docs/`, `scripts/update-repository.py` | Flat Cydia repository and deterministic compressed indexes |

On iOS 4–7 the tweak wraps `WebView -setPolicyDelegate:` and forwards optional callbacks to Safari's original assign-owned delegate. Signatures are checked before wrapping. Policy listeners are resolved on WebKit's calling thread; consent and download management run on the main thread. curl runs on worker threads and hands each response/data chunk to the main thread synchronously, bounding queued data and preserving file/UI ownership. MRC ownership is explicit throughout.

Files stream into exclusive, mode-0600 hidden partials. Sanitized names cannot create subdirectories or hidden user files. Completed transfers are flushed and atomically published without overwriting existing files; duplicate names receive a numbered suffix. The browser ignores hidden files and symlinks. Handled failures/cancellation remove owned partials; a crash or kill can leave an ignored hidden `.part` file. No archives are unpacked automatically.

### DEB helper

1.2.0 installs `/usr/libexec/receptor-deb-helper` as root:wheel, mode **4755**, because a mobile-user app cannot modify dpkg's system database. The helper accepts one staged basename under the fixed Receptor download directory, verifies owner/type/permissions and rejects symlinks and hardlinks. Non-root callers must be the mobile user and have a kernel-reported caller code-directory hash matching the signed, root-owned installed Receptor app. Failure to verify that identity denies the request. Already-root callers retain their existing privilege.

The helper creates a private root-owned snapshot and runs only `/usr/bin/dpkg --no-act --install SNAPSHOT`, followed by `/usr/bin/dpkg --install SNAPSHOT` if the preflight succeeds. It uses fixed argument vectors and a clean environment, with no command shell or user-provided executable/options. dpkg retains responsibility for architecture/dependency checks, locking and maintainer scripts. The original saved DEB is preserved. The app's staged copy and helper's private files are cleaned after the operation. dpkg writes a regular log file so losing the UI's pipe does not terminate a package transaction; the helper returns a bounded tail of that output. The app stores the last log in a hidden mode-0600 file in the Receptor directory.

The root helper is limited to package installation and two fixed respring operations; it is not a general privileged command runner. It never executes an arbitrary path supplied by the caller. IPA, DEB, APT and respring operations cannot overlap within Receptor. The two privileged helpers also share a root-owned transaction lock. Initial installation of 1.2.0 must be done through Cydia (or an existing root package manager) so the helper's ownership and setuid permissions are established.

## Validation

1.2.0 compiles, links, signs and packages for armv7 with SDK 5.0 and an iOS 4.0 minimum. Package checks validate the app manifest, executable headers, icon resources, CA bundle, tweak, root helper and repository checksums. Native Linux tests of the same curl/Mbed TLS versions pass TLS 1.2 downloads and redirects and reject untrusted issuers and wrong hostnames. The transport also successfully retrieved response bodies from Archive.org and GitHub Pages. An Obscura-linked VLC IPA endpoint reached its storage host but returned HTTP 500 during testing; successful TLS does not guarantee an archive file is available.

**Physical-device validation of each new feature is still required**. User-reported versions now include iOS 5.1.1 and iOS 6.1.3. Compilation and native transport tests cannot certify private Safari hooks, Home screen registration or installation/signing behavior on the device.

1.4.0 adds arbitrary file transfers, a grid/list browser, filename search, bounded image previews and Open In for every file. Eight-character codes and saved pairing from 1.3.1 are retained. It compiles the iOS pairing client against SDK 5.0 for armv7/iOS 4. Protocol integration tests exercise the actual Windows server, authentication/replay rejection, streamed immutable file contents, malformed requests and shutdown. The desktop form has been rendered for layout inspection. Updated tests verify PNG/text/ZIP/IPA/DEB/binary/extensionless/empty-file transfers, DPAPI persistence, remembered pairing after a server restart, stale-session rejection, reset and the production C key-derivation loop against independent vectors. The new iOS grid, preview/rotation/zoom and Open In flows require physical-device testing. Pairing, receiving and installation through the new iOS screen still need testing on the physical device.

User also reports Receptor works on **iOS 6.1.3**, without specifying the device or complete feature coverage. iOS 6.x patch releases are included by the package requirement `firmware (>= 4.0), firmware (<< 9.0)`.

Earlier user-reported iPad 1 / iOS 5.1.1 results: three IPA downloads completed and one installed app launched. Two other app launch failures remain unexplained; compatibility, signing and other app-specific causes have not been established. DEB installation appearing in Cydia has not yet been confirmed on-device. Treat the current release as experimental and the full iOS 4–8 range as intended targets rather than a validated support matrix.

1.4.1 compiles/signs for the same legacy target. Native tests exercise the production installer-content classifier, including extension/MIME lookalikes, and a TLS regression endpoint that closes requests lacking the User-Agent. Valid downloads still pass, and untrusted/hostname-mismatched certificates still fail. The new native installer handoff, Photos import and iOS 6/legacy sharing UI need on-device validation.

1.5.0 adds experimental 32-bit iOS 7/8 adapters. ZIP-reader tests and 1000 malformed-archive mutations pass; built-binary import checks verify that no iOS 8 class/weak-function startup dependency was added. Safari delegate lifecycle, app handoff, iOS 8 notifications and native IPA/DEB installation need physical-device validation.

```sh
python3 tests/check_legacy_linkage.py
python3 tests/test_ipa_archive.py
python3 tests/test_system_content.py
python3 tests/check_project.py
python3 scripts/update-repository.py
python3 tests/check_repository.py
python3 tests/test_deb_helper.py
bash scripts/build-host-tls-probe.sh
python3 tests/test_tls_transport.py
```

For device HTTP fixtures, run `python3 tests/fixture_server.py --bind 0.0.0.0 --port 8080` on a reachable computer and open its LAN URL in Safari. Check link/MIME interception, cancellation, duplicate/unsafe names, empty/error/truncated responses, cookies, background expiration and stored byte integrity. The slow `.zip` endpoint contains synthetic bytes for transfer tests, not a real archive.

The DEB-helper tests compile an unprivileged Linux-only test build and a fake package manager in a temporary directory. They check preflight/install sequencing, argument/environment isolation, private snapshot preservation, dependency/install failures, symlinks, hardlinks, traversal, permissions, shell metacharacters and bounded log output. Respring tests verify fixed job labels, clean environment, failure status, package-lock contention and unsafe lock rejection using a fake launchctl. They never invoke the host’s real dpkg, install a package or restart a host service. Test mode is rejected at compile time on Apple targets. Packaged-helper checks verify root ownership, mode 4755, caller-authentication markers, armv7 and the iOS 4.0/SDK 5.0 load command.

On-device, also verify: the Receptor icon after upgrade; direct URL downloads with +; Safari-to-app transfer status and cancellation; file preview/deletion; IPA Install confirmation/progress/error reporting; DEB confirmation, caller authorization, a harmless compatible DEB appearing in Cydia, Install Log, missing dependencies, an already-held Cydia/dpkg lock and failed maintainer scripts; rotation/iPad menus; failed certificates and incorrect date/time; no saved HTML error pages; process kill/relaunch; and MRC behavior with Instruments. The setuid/caller-code-hash gate and actual iOS dpkg execution cannot be certified by the Linux mock tests. Keep a backup before testing package/app upgrades that replace installed software.

## References

- [Apple: legacy WebKit policy decisions](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DisplayWebContent/Tasks/PolicyDecisions.html)
- [Apple: HTTPS server trust evaluation and error codes](https://developer.apple.com/library/archive/technotes/tn2232/)
- [Theos configuration](https://theos.dev/docs/configuration)
- [Mbed TLS supported branches](https://github.com/Mbed-TLS/mbedtls/blob/development/BRANCHES.md)

The installed file browser and private installer are independent of the website used to find an IPA. Receptor does not guarantee that a third-party archive is available or that an archived app will run on a particular device.
